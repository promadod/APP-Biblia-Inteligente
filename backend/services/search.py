"""Busca: icontains, FTS (PostgreSQL) e trigram em entidades."""
from __future__ import annotations

from typing import Any

from django.conf import settings
from django.db.models import Q, QuerySet
from django.db.models.expressions import RawSQL

from core.models import Book, Chapter, Entity, Verse


def search_entities(q: str, limit: int = 20) -> QuerySet[Entity]:
    if settings.DATABASES["default"]["ENGINE"].endswith("postgresql"):
        from django.contrib.postgres.search import TrigramSimilarity

        return (
            Entity.objects.annotate(sim=TrigramSimilarity("name", q))
            .filter(sim__gt=0.15)
            .order_by("-sim")[:limit]
        )
    return Entity.objects.filter(name__icontains=q)[:limit]


def search_verses_fts(q: str, limit: int = 50, version_code: str | None = None) -> QuerySet[Verse]:
    if not getattr(settings, "USE_POSTGRES_SEARCH", False):
        return Verse.objects.none()
    qs = (
        Verse.objects.annotate(
            rank=RawSQL(
                "ts_rank(to_tsvector('portuguese', core_verse.text), plainto_tsquery('portuguese', %s))",
                (q,),
            )
        )
        .filter(rank__gt=0.01)
        .select_related("chapter__book")
        .order_by("-rank")
    )
    if version_code:
        qs = qs.filter(chapter__book__version__code=version_code)
    return qs[:limit]


def search_verses_icontains(q: str, limit: int = 50, version_code: str | None = None) -> QuerySet[Verse]:
    qs = Verse.objects.filter(text__icontains=q).select_related("chapter__book").order_by("id")
    if version_code:
        qs = qs.filter(chapter__book__version__code=version_code)
    return qs[:limit]


def search_books(q: str, version_code: str | None) -> QuerySet[Book]:
    qs = Book.objects.select_related("version").filter(
        Q(name__icontains=q) | Q(abbreviation__icontains=q)
    )
    if version_code:
        qs = qs.filter(version__code=version_code)
    return qs[:20]


def search_chapters(q: str, version_code: str | None) -> QuerySet[Chapter]:
    qs = Chapter.objects.select_related("book", "book__version").filter(
        Q(book__name__icontains=q) | Q(book__abbreviation__icontains=q)
    )
    if version_code:
        qs = qs.filter(book__version__code=version_code)
    return qs.distinct()[:30]


def unified_search(q: str, version_code: str | None, limit: int = 50) -> dict[str, Any]:
    q = (q or "").strip()
    if not q:
        return {"verses": [], "books": [], "chapters": [], "entities": []}

    verses = list(search_verses_fts(q, limit, version_code=version_code))
    if not verses:
        verses = list(search_verses_icontains(q, limit, version_code=version_code))

    return {
        "verses": verses,
        "books": list(search_books(q, version_code)),
        "chapters": list(search_chapters(q, version_code)),
        "entities": list(search_entities(q, 20)),
    }
