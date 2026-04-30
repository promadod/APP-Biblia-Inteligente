from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Q

from core.models import Verse
from embeddings.services import batch_generate_embeddings


class Command(BaseCommand):
    help = "Gera embeddings via API OpenAI (text-embedding-3-small). Requer OPENAI_API_KEY. Use --force para recalcular tudo após mudar de modelo."

    def add_arguments(self, parser):
        parser.add_argument(
            "--batch-size",
            type=int,
            default=100,
            help="Máx. de textos por pedido à API (≤2048; predefinido 100 para quotas/rate limit).",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Recalcula mesmo quando embedding já existe",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=None,
            help="Processar no máximo N versículos (debug)",
        )

    def handle(self, *args, **options):
        batch_size = options["batch_size"]
        force = options["force"]
        limit = options["limit"]

        if not (getattr(settings, "OPENAI_API_KEY", "") or "").strip():
            self.stdout.write(
                self.style.ERROR(
                    "OPENAI_API_KEY não definida. Configure no PythonAnywhere (Web → Environment) ou no .env na raiz do projeto."
                )
            )
            return

        if force:
            qs = Verse.objects.all().order_by("id")
        else:
            qs = Verse.objects.filter(
                Q(embedding__isnull=True) | Q(embedding__exact=[])
            ).order_by("id")

        ids = list(qs.values_list("id", flat=True))
        if limit:
            ids = ids[:limit]

        if not ids:
            self.stdout.write(self.style.WARNING("Nada a processar."))
            return

        total = len(ids)
        done = 0
        chunk = 500
        for i in range(0, total, chunk):
            batch_ids = ids[i : i + chunk]
            verses = list(
                Verse.objects.filter(id__in=batch_ids).select_related("chapter__book").order_by("id")
            )
            texts = [v.text for v in verses]
            vectors = batch_generate_embeddings(texts, batch_size=batch_size)
            for v, emb in zip(verses, vectors, strict=True):
                if len(emb) != settings.EMBEDDING_DIMENSION:
                    self.stderr.write(f"Dimensão inesperada para versículo {v.id}")
                    continue
                v.embedding = emb
            with transaction.atomic():
                Verse.objects.bulk_update(verses, ["embedding"], batch_size=batch_size)
            done += len(verses)
            self.stdout.write(f"Atualizados {done}/{total} versículos…")

        self.stdout.write(self.style.SUCCESS(f"Concluído: {done} versículos com embedding."))
