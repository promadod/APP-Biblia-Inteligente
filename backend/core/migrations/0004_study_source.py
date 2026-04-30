from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0003_verse_embedding"),
    ]

    operations = [
        migrations.AddField(
            model_name="study",
            name="source",
            field=models.CharField(
                choices=[
                    ("manual", "Manual"),
                    ("search", "Busca"),
                    ("chat", "Perguntas"),
                ],
                db_index=True,
                default="manual",
                max_length=16,
            ),
        ),
    ]
