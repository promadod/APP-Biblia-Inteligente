# Generated manually for AskSemanticCache

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("rag", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="AskSemanticCache",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "question_text",
                    models.TextField(help_text="Texto normalizado usado no embedding"),
                ),
                (
                    "question_embedding",
                    models.JSONField(help_text="Vetor float[E] (ex.: 384d)"),
                ),
                ("version_code", models.CharField(blank=True, db_index=True, max_length=32)),
                ("intent", models.CharField(blank=True, db_index=True, max_length=64)),
                ("response_body", models.JSONField(help_text="Corpo JSON devolvido ao cliente")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddIndex(
            model_name="asksemanticcache",
            index=models.Index(fields=["version_code", "intent", "created_at"], name="rag_asksem_version_a835bc_idx"),
        ),
    ]
