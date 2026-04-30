"""Cache semântico para POST /api/ask — evita RAG+OpenAI em perguntas muito parecidas."""
from __future__ import annotations

import copy
import logging
import math
import re
from typing import Any

from django.conf import settings

from embeddings.services import generate_embedding
from rag.models import AskSemanticCache

logger = logging.getLogger(__name__)


def normalize_question(text: str) -> str:
    t = (text or "").strip().lower()
    t = re.sub(r"\s+", " ", t)
    return t


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(a[i] * b[i] for i in range(len(a)))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    if na < 1e-12 or nb < 1e-12:
        return 0.0
    return dot / (na * nb)


def lookup_similar_response(
    question: str,
    version_code: str | None,
    intent: str,
) -> dict[str, Any] | None:
    """
    Devolve uma cópia do response_body guardado se existir entrada recente com
    similaridade de cosseno >= limiar (versão + intent iguais).
    """
    if not getattr(settings, "SEMANTIC_ASK_CACHE_ENABLED", True):
        return None

    qn = normalize_question(question)
    if not qn:
        return None

    min_sim = float(getattr(settings, "SEMANTIC_ASK_CACHE_MIN_SIMILARITY", 0.9))
    lookback = int(getattr(settings, "SEMANTIC_ASK_CACHE_LOOKBACK", 400))
    dim = getattr(settings, "EMBEDDING_DIMENSION", 384)

    try:
        query_vec = generate_embedding(qn)
    except Exception as exc:
        logger.warning("Semantic cache: falha ao gerar embedding da pergunta (%s)", exc)
        return None

    if len(query_vec) != dim:
        return None

    vc = (version_code or "").strip()
    it = (intent or "").strip()

    qs = AskSemanticCache.objects.filter(version_code=vc, intent=it).order_by("-created_at")[:lookback]

    best_sim = -1.0
    best_body: dict[str, Any] | None = None

    for row in qs:
        emb = row.question_embedding
        if not isinstance(emb, list) or len(emb) != dim:
            continue
        sim = _cosine_similarity(query_vec, emb)
        if sim > best_sim:
            best_sim = sim
            best_body = row.response_body

    if best_body is not None and best_sim >= min_sim:
        out = copy.deepcopy(best_body)
        if isinstance(out, dict):
            out["semantic_cache_hit"] = True
            out["semantic_cache_similarity"] = round(best_sim, 4)
        logger.info(
            "Semantic cache HIT sim=%.4f (min=%.4f) intent=%r version=%r",
            best_sim,
            min_sim,
            it,
            vc or "(none)",
        )
        return out

    return None


def store_response(
    question: str,
    version_code: str | None,
    intent: str,
    response_body: dict[str, Any],
) -> None:
    """Persiste embedding + resposta para futuras consultas semânticas."""
    if not getattr(settings, "SEMANTIC_ASK_CACHE_ENABLED", True):
        return

    qn = normalize_question(question)
    if not qn:
        return

    dim = getattr(settings, "EMBEDDING_DIMENSION", 384)

    try:
        vec = generate_embedding(qn)
    except Exception as exc:
        logger.warning("Semantic cache: não guardado — embedding falhou (%s)", exc)
        return

    if len(vec) != dim:
        return

    body_copy = copy.deepcopy(response_body)
    if isinstance(body_copy, dict):
        body_copy.pop("semantic_cache_hit", None)
        body_copy.pop("semantic_cache_similarity", None)

    vc = (version_code or "").strip()
    it = (intent or "").strip()

    try:
        AskSemanticCache.objects.create(
            question_text=qn[:8000],
            question_embedding=vec,
            version_code=vc,
            intent=it,
            response_body=body_copy,
        )
    except Exception as exc:
        logger.warning("Semantic cache: falha ao gravar (%s)", exc)
