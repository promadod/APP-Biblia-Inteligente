"""Ordenação canónica de versículos (ordem dos livros, capítulo, número)."""
from __future__ import annotations

from collections.abc import Iterable

from core.models import Verse


def sort_verses_bible_order(verses: Iterable[Verse]) -> list[Verse]:
    return sorted(
        verses,
        key=lambda v: (
            v.chapter.book.order,
            v.chapter.book_id,
            v.chapter.number,
            v.number,
        ),
    )
