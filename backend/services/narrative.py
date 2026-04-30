"""Narrativa consolidada a partir de resultados de busca (templates; NLP futuro)."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Protocol

from core.models import Entity, Relationship, Verse


class NarrativeBackend(Protocol):
    def build(self, query: str, context: dict[str, Any]) -> str: ...


class TemplateNarrativeBackend:
    """Monta parágrafos a partir de versículos, entidades e relações."""

    def build(self, query: str, context: dict[str, Any]) -> str:
        verses: list[Verse] = context.get("verses") or []
        entities: list[Entity] = context.get("entities") or []
        relations: list[Relationship] = context.get("relationships") or []

        parts: list[str] = []
        parts.append(
            f"Resumo temático para «{query}». "
            f"Texto gerado automaticamente a partir de trechos da Bíblia e do grafo semântico."
        )
        if entities:
            names = ", ".join(e.name for e in entities[:8])
            parts.append(f"Entidades relacionadas: {names}.")
        if relations:
            bits = []
            for r in relations[:10]:
                bits.append(f"{r.source_entity.name} ({r.relation_type}) {r.target_entity.name}")
            parts.append("Relações: " + "; ".join(bits) + ".")
        if verses:
            parts.append("Trechos destacados:")
            for v in verses[:12]:
                ref = f"{v.chapter.book.name} {v.chapter.number}:{v.number}"
                parts.append(f"• {ref} — {v.text[:280]}{'…' if len(v.text) > 280 else ''}")
        if not verses and not entities:
            parts.append("Nenhum resultado encontrado para enriquecer a narrativa.")
        return "\n\n".join(parts)


class TransformersNarrativeBackend(ABC):
    """Reservado para integração futura com modelos transformers."""

    @abstractmethod
    def build(self, query: str, context: dict[str, Any]) -> str:
        raise NotImplementedError("Configure um modelo e tokenizer para usar este backend.")


def relationships_for_entities(entities: list[Entity]) -> list[Relationship]:
    if not entities:
        return []
    ids = [e.id for e in entities if e.id]
    return list(
        Relationship.objects.filter(source_entity_id__in=ids)
        .select_related("source_entity", "target_entity")[:30]
    )


class NarrativeService:
    def __init__(self, backend: NarrativeBackend | None = None):
        self.backend = backend or TemplateNarrativeBackend()

    def build(self, query: str, verses: list, entities: list) -> str:
        rels = relationships_for_entities(entities)
        ctx = {"verses": verses, "entities": entities, "relationships": rels}
        return self.backend.build(query, ctx)
