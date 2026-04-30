import json
from collections import defaultdict
from pathlib import Path

import yaml
from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction

from core.models import BibleVersion, Book, Chapter, Verse


class Command(BaseCommand):
    help = "Importa versículos de JSON (data/bible_kjv.json) para o banco."

    def add_arguments(self, parser):
        parser.add_argument(
            "--json",
            type=str,
            default=None,
            help="Caminho do JSON (default: <repo>/data/bible_kjv.json)",
        )
        parser.add_argument(
            "--books-yaml",
            type=str,
            default=None,
            help="YAML com livros e abreviações (default: ../ingestion/kjv_books_pt.yaml)",
        )
        parser.add_argument(
            "--version-code",
            type=str,
            default="BKJ_PT",
            help="Código BibleVersion (slug)",
        )
        parser.add_argument(
            "--version-name",
            type=str,
            default="Bíblia King James 1611 (BKJ)",
        )
        parser.add_argument(
            "--language",
            type=str,
            default="pt",
        )
        parser.add_argument(
            "--rebuild-search",
            action="store_true",
            help="Reservado: FTS usa índice to_tsvector em PostgreSQL",
        )

    def handle(self, *args, **options):
        base = Path(settings.BASE_DIR).resolve()
        repo_root = base.parent
        json_path = Path(options["json"] or repo_root / "data" / "bible_kjv.json")
        yaml_path = Path(
            options["books_yaml"] or repo_root / "ingestion" / "kjv_books_pt.yaml"
        )

        if not json_path.is_file():
            self.stderr.write(f"Arquivo não encontrado: {json_path}")
            return

        raw = json.loads(json_path.read_text(encoding="utf-8"))
        book_meta = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
        book_order = {b["name"]: i for i, b in enumerate(book_meta["books"], start=1)}
        abbrev = {b["name"]: b["abbreviation"] for b in book_meta["books"]}

        version, _ = BibleVersion.objects.get_or_create(
            code=options["version_code"],
            defaults={
                "name": options["version_name"],
                "language": options["language"],
            },
        )

        # Última ocorrência vence (PDF pode repetir cabeçalhos de capítulo como versículo)
        dedup: dict[tuple[str, int, int], str] = {}
        for row in raw:
            key = (row["book"], int(row["chapter"]), int(row["verse"]))
            dedup[key] = row["text"].strip()

        by_book: dict[str, list[tuple[int, int, str]]] = defaultdict(list)
        for (book_name, ch_num, v_num), text in dedup.items():
            by_book[book_name].append((ch_num, v_num, text))

        with transaction.atomic():
            Book.objects.filter(version=version).delete()

            books_to_create = []
            for name in book_order:
                if name not in by_book:
                    continue
                books_to_create.append(
                    Book(
                        version=version,
                        name=name,
                        abbreviation=abbrev.get(name, "")[:16],
                        order=book_order[name],
                    )
                )
            Book.objects.bulk_create(books_to_create)
            book_map = {
                b.name: b for b in Book.objects.filter(version=version).select_related("version")
            }

            chapters_to_create: list[Chapter] = []
            chapter_key: dict[tuple[str, int], Chapter] = {}
            for book_name, verses in by_book.items():
                book = book_map.get(book_name)
                if not book:
                    continue
                chapter_nums = sorted({v[0] for v in verses})
                for cn in chapter_nums:
                    ch = Chapter(book=book, number=cn)
                    chapters_to_create.append(ch)
            Chapter.objects.bulk_create(chapters_to_create)

            for ch in Chapter.objects.filter(book__version=version).select_related("book"):
                chapter_key[(ch.book.name, ch.number)] = ch

            verse_objs: list[Verse] = []
            for book_name, tuples in by_book.items():
                for ch_num, v_num, text in tuples:
                    ch = chapter_key.get((book_name, ch_num))
                    if not ch:
                        continue
                    verse_objs.append(Verse(chapter=ch, number=v_num, text=text))

            batch = 2000
            for i in range(0, len(verse_objs), batch):
                Verse.objects.bulk_create(verse_objs[i : i + batch])

        n = Verse.objects.filter(chapter__book__version=version).count()
        self.stdout.write(self.style.SUCCESS(f"Importação concluída: {n} versículos ({version.code})."))

        if options["rebuild_search"]:
            self.stdout.write(
                "Índice FTS em PostgreSQL: rode migrate com DB_NAME definido; "
                "índice to_tsvector em core_verse é criado na migração 0002."
            )
