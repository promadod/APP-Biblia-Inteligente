"""
Busca semântica (cosine) + híbrido com busca textual (fallback / ranking).
"""
from __future__ import annotations

import logging

import numpy as np
from django.conf import settings
from django.db.models import Q, QuerySet

from core.models import Verse
from embeddings.services import generate_embedding
from services.search import search_verses_icontains, search_verses_fts

logger = logging.getLogger(__name__)


def _norm_rows(matrix: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    norms = np.clip(norms, 1e-12, None)
    return matrix / norms


def _cosine_scores(query_vec: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    """matrix: (n, dim), query_vec: (dim,) — ambos L2-normalizados."""
    q = query_vec / max(np.linalg.norm(query_vec), 1e-12)
    m = _norm_rows(matrix)
    return m @ q


def search_similar_verses(
    query: str,
    top_k: int = 10,
    version_code: str | None = None,
) -> list[tuple[Verse, float]]:
    """
    Versículos mais similares semanticamente (requer embedding preenchido).
    Retorna lista (Verse, score) ordenada por score descendente.
    """
    query = (query or "").strip()
    if not query:
        return []

    top_k = min(max(top_k, 1), getattr(settings, "RAG_TOP_K_SEMANTIC", 24))

    qs = Verse.objects.filter(embedding__isnull=False).exclude(embedding=[]).select_related(
        "chapter__book", "chapter__book__version"
    )
    if version_code:
        qs = qs.filter(chapter__book__version__code=version_code)

    ids = list(qs.values_list("id", flat=True))
    if not ids:
        logger.warning("Nenhum versículo com embedding. Rode: python manage.py generate_embeddings")
        return []

    qvec = np.array(generate_embedding(query), dtype=np.float32)
    if qvec.shape[0] != settings.EMBEDDING_DIMENSION:
        return []

    chunk = 4000
    best: list[tuple[int, float]] = []
    for i in range(0, len(ids), chunk):
        part_ids = ids[i : i + chunk]
        rows = Verse.objects.filter(id__in=part_ids).only("id", "embedding")
        mat_list = []
        id_order = []
        for v in rows:
            emb = v.embedding
            if not emb or len(emb) != settings.EMBEDDING_DIMENSION:
                continue
            mat_list.append(emb)
            id_order.append(v.id)
        if not mat_list:
            continue
        mat = np.array(mat_list, dtype=np.float32)
        scores = _cosine_scores(qvec, mat)
        for vid, sc in zip(id_order, scores.tolist(), strict=True):
            best.append((vid, float(sc)))

    best.sort(key=lambda x: x[1], reverse=True)
    best = best[:top_k]
    id_map = {
        v.id: v for v in Verse.objects.filter(id__in=[x[0] for x in best]).select_related("chapter__book")
    }
    return [(id_map[i], s) for i, s in best if i in id_map]


def search_text_verses(query: str, limit: int, version_code: str | None) -> QuerySet[Verse]:
    """Filtra por versão *antes* do slice — nunca filtrar um QuerySet já fatiado."""
    if getattr(settings, "USE_POSTGRES_SEARCH", False):
        fts = search_verses_fts(query, limit, version_code=version_code)
        if fts.exists():
            return fts
    return search_verses_icontains(query, limit, version_code=version_code)


def hybrid_search(
    query: str,
    version_code: str | None = None,
    top_semantic: int | None = None,
    top_text: int | None = None,
    top_final: int | None = None,
) -> list[tuple[Verse, float, str]]:
    """
    Combina scores semânticos (0–1) e texto (0–1 heurístico).
    Retorna [(Verse, score_híbrido, origem)] origem em {'semantic','text','both'}.
    """
    top_semantic = top_semantic or getattr(settings, "RAG_TOP_K_SEMANTIC", 24)
    top_text = top_text or getattr(settings, "RAG_TOP_K_TEXT", 16)
    top_final = top_final or getattr(settings, "RAG_TOP_K_FINAL", 12)

    sem = search_similar_verses(query, top_k=top_semantic, version_code=version_code)
    sem_map = {v.id: s for v, s in sem}

    # `search_text_verses` já aplica o limite; materializar sem novo slice no QuerySet
    # (evita combinações frágeis com QuerySet fatiado em versões do Django).
    text_qs = search_text_verses(query, top_text * 2, version_code)
    text_list = list(text_qs)
    text_map: dict[int, float] = {}
    for rank, v in enumerate(text_list):
        text_map[v.id] = 1.0 - (rank / max(len(text_list), 1)) * 0.5

    ids = set(sem_map) | set(text_map)
    merged: dict[int, tuple[float, str]] = {}
    for vid in ids:
        s_sem = sem_map.get(vid, 0.0)
        s_txt = text_map.get(vid, 0.0)
        if s_sem > 0 and s_txt > 0:
            score = 0.65 * s_sem + 0.35 * s_txt
            tag = "both"
        elif s_sem > 0:
            score = s_sem
            tag = "semantic"
        else:
            score = s_txt
            tag = "text"
        merged[vid] = (score, tag)

    ranked = sorted(merged.items(), key=lambda x: x[1][0], reverse=True)[:top_final]
    verses = {
        v.id: v
        for v in Verse.objects.filter(id__in=[r[0] for r in ranked]).select_related("chapter__book")
    }
    out: list[tuple[Verse, float, str]] = []
    for vid, (sc, tag) in ranked:
        if vid in verses:
            out.append((verses[vid], sc, tag))
    return out
