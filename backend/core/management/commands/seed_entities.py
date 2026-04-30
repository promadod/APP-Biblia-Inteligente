import json
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand

from core.models import BibleVersion, Entity, EntityType, Relationship


class Command(BaseCommand):
    help = "Carrega entidades e relações de fixtures/entities_kjv_seed.json"

    def add_arguments(self, parser):
        parser.add_argument(
            "--fixture",
            type=str,
            default=None,
            help="Caminho JSON (default: backend/fixtures/entities_kjv_seed.json)",
        )
        parser.add_argument(
            "--version-code",
            type=str,
            default="BKJ_PT",
        )

    def handle(self, *args, **options):
        base = Path(settings.BASE_DIR)
        path = Path(options["fixture"] or base / "fixtures" / "entities_kjv_seed.json")
        data = json.loads(path.read_text(encoding="utf-8"))
        version = BibleVersion.objects.filter(code=options["version_code"]).first()

        name_to_entity: dict[str, Entity] = {}
        for row in data.get("entities", []):
            etype = row.get("type", "person")
            valid = {c[0] for c in EntityType.choices}
            if etype not in valid:
                etype = EntityType.PERSON
            ent, _ = Entity.objects.update_or_create(
                name=row["name"],
                defaults={"type": etype, "version": version},
            )
            name_to_entity[row["name"]] = ent

        for rel in data.get("relationships", []):
            s = name_to_entity.get(rel["source"])
            t = name_to_entity.get(rel["target"])
            if not s or not t:
                continue
            Relationship.objects.get_or_create(
                source_entity=s,
                target_entity=t,
                relation_type=rel.get("relation_type", "related"),
            )

        self.stdout.write(self.style.SUCCESS("Seed de entidades concluído."))
