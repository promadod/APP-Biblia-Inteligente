from django.db import migrations


def create_pg_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return
    schema_editor.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    schema_editor.execute(
        """
        CREATE INDEX IF NOT EXISTS core_verse_text_trgm_idx
        ON core_verse USING gin (lower(text) gin_trgm_ops)
        """
    )
    schema_editor.execute(
        """
        CREATE INDEX IF NOT EXISTS core_entity_name_trgm_idx
        ON core_entity USING gin (lower(name) gin_trgm_ops)
        """
    )
    schema_editor.execute(
        """
        CREATE INDEX IF NOT EXISTS core_verse_text_fts_idx
        ON core_verse USING gin (to_tsvector('portuguese', text))
        """
    )


def drop_pg_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return
    for name in (
        "core_verse_text_trgm_idx",
        "core_entity_name_trgm_idx",
        "core_verse_text_fts_idx",
    ):
        schema_editor.execute(f"DROP INDEX IF EXISTS {name}")


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(create_pg_indexes, drop_pg_indexes),
    ]
