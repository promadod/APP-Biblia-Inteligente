"""Sugere menções de entidades conhecidas nos versículos (regex por nome)."""
from django.conf import settings
from django.core.management.base import BaseCommand

from core.models import Entity, Verse


class Command(BaseCommand):
    help = "Lista contagem de versículos que mencionam cada entidade (sem gravar no BD)"

    def add_arguments(self, parser):
        parser.add_argument("--limit-entities", type=int, default=30)

    def handle(self, *args, **options):
        entities = Entity.objects.all()[: options["limit_entities"]]
        for ent in entities:
            n = Verse.objects.filter(text__icontains=ent.name).count()
            if n:
                self.stdout.write(f"{ent.name}: {n} versículos")
        self.stdout.write("Use spaCy opcionalmente: pip install spacy && python -m spacy download pt_core_news_sm")
