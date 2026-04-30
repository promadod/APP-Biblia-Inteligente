"""Monta texto de contexto para o LLM a partir da busca híbrida e entidades."""
from __future__ import annotations

import re

from django.conf import settings
from django.db.models import Q

from core.models import Entity, Relationship, Verse
from search.semantic_search import hybrid_search

_STOPWORDS_PT = frozenset(
    """
    quem foi que como sobre para uma pelo pela pelo pela dos das neste esse esta esse estas este isto aquilo
    what who was were the are from with when where which there their about into onto
    """.split()
)


def _entities_from_query(query: str, version_code: str | None, limit: int = 15) -> list[Entity]:
    query = (query or "").strip()
    if not query:
        return []
    words = [w.strip("?.!,;:\"'") for w in query.split() if len(w) > 2]
    seen: set[int] = set()
    out: list[Entity] = []
    for w in words[:12]:
        qs = Entity.objects.filter(name__icontains=w)
        if version_code:
            qs = qs.filter(Q(version__code=version_code) | Q(version__isnull=True))
        for e in qs[:6]:
            if e.id not in seen:
                seen.add(e.id)
                out.append(e)
            if len(out) >= limit:
                return out
    if not out:
        qs = Entity.objects.filter(name__icontains=query[:64])
        if version_code:
            qs = qs.filter(Q(version__code=version_code) | Q(version__isnull=True))
        out = list(qs[:limit])
    return out


def _relationship_lines(entities: list[Entity], max_lines: int = 20) -> list[str]:
    lines: list[str] = []
    ids = [e.id for e in entities[:10]]
    if not ids:
        return lines
    rels = (
        Relationship.objects.filter(source_entity_id__in=ids)
        .select_related("source_entity", "target_entity")[:max_lines]
    )
    for r in rels:
        lines.append(f"{r.source_entity.name} —{r.relation_type}→ {r.target_entity.name}")
    return lines


def _biography_augmented_queries(raw: str) -> list[str]:
    """Palavras-chave extraídas para segunda passagem de recuperação (maior cobertura)."""
    raw = (raw or "").strip()
    if not raw:
        return []
    tokens = re.findall(r"[\wáàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]+", raw, flags=re.IGNORECASE)
    out: list[str] = []
    seen: set[str] = set()
    for t in tokens:
        tl = t.lower()
        if len(tl) <= 3 or tl in _STOPWORDS_PT:
            continue
        if tl not in seen:
            seen.add(tl)
            out.append(t)
        if len(out) >= 6:
            break
    return out


def _merge_hybrid_results(
    chunks: list[list[tuple[Verse, float, str]]],
    cap: int,
) -> list[tuple[Verse, float, str]]:
    best: dict[int, tuple[Verse, float, str]] = {}
    for lst in chunks:
        for v, sc, tag in lst:
            prev = best.get(v.id)
            if prev is None or sc > prev[1]:
                best[v.id] = (v, sc, tag)
    merged = sorted(best.values(), key=lambda x: x[1], reverse=True)
    return merged[:cap]


def build_context(
    query: str,
    version_code: str | None = None,
    *,
    biography_mode: bool = False,
) -> tuple[str, list, dict]:
    """
    Retorna (texto_contexto, lista de versículos em ordem de relevância híbrida, meta).

    Em [biography_mode], aumenta top-K e faz buscas auxiliares por palavras-chave para cobrir
    mais versículos do livro/personagem (limitado ao texto importado).
    """
    query = (query or "").strip()

    if biography_mode:
        ts = getattr(settings, "RAG_BIOGRAPHY_TOP_SEMANTIC", 56)
        tt = getattr(settings, "RAG_BIOGRAPHY_TOP_TEXT", 80)
        tf = getattr(settings, "RAG_BIOGRAPHY_TOP_FINAL", 56)
        chunks: list[list[tuple[Verse, float, str]]] = [
            hybrid_search(
                query,
                version_code=version_code,
                top_semantic=ts,
                top_text=tt,
                top_final=tf,
            ),
        ]
        for aug in _biography_augmented_queries(query):
            chunks.append(
                hybrid_search(
                    aug,
                    version_code=version_code,
                    top_semantic=max(ts // 2, 16),
                    top_text=max(tt // 2, 24),
                    top_final=min(32, max(tf // 2, 16)),
                )
            )
        ranked = _merge_hybrid_results(chunks, cap=tf)
    else:
        ranked = hybrid_search(query, version_code=version_code)

    verses = [v for v, _, _ in ranked]

    verse_lines: list[str] = []
    for v, score, origin in ranked:
        ref = f"{v.chapter.book.name} {v.chapter.number}:{v.number}"
        verse_lines.append(f"- [{origin} ~{score:.2f}] {ref}: {v.text}")

    entities = _entities_from_query(query, version_code)
    ent_names = ", ".join(e.name for e in entities[:12])
    rel_lines = _relationship_lines(entities)

    block_verses = "Versículos relevantes:\n" + (
        "\n".join(verse_lines) if verse_lines else "(nenhum trecho recuperado; verifique embeddings ou reformule)."
    )

    block_extra = ["Contexto adicional:"]
    if ent_names:
        block_extra.append(f"Entidades: {ent_names}.")
    else:
        block_extra.append("Entidades: (nenhuma nomeada nos dados semânticos).")
    if rel_lines:
        block_extra.append("Relações:\n" + "\n".join(f"- {x}" for x in rel_lines))
    else:
        block_extra.append("Relações: (nenhuma encontrada para as entidades acima).")

    full = block_verses + "\n\n" + "\n".join(block_extra)
    meta = {
        "ranked": ranked,
        "entities": entities,
        "biography_mode": biography_mode,
    }
    return full, verses, meta
