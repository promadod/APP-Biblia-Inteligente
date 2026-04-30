from django.conf import settings
from django.db import models


class BibleVersion(models.Model):
    code = models.SlugField(max_length=32, unique=True)
    name = models.CharField(max_length=128)
    language = models.CharField(max_length=16, default="pt")

    class Meta:
        ordering = ["code"]

    def __str__(self) -> str:
        return f"{self.code} ({self.name})"


class Book(models.Model):
    version = models.ForeignKey(
        BibleVersion,
        on_delete=models.CASCADE,
        related_name="books",
    )
    name = models.CharField(max_length=64)
    abbreviation = models.CharField(max_length=16, blank=True)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["version", "order", "name"]
        constraints = [
            models.UniqueConstraint(
                fields=["version", "name"],
                name="uniq_book_version_name",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.name} ({self.version.code})"


class Chapter(models.Model):
    book = models.ForeignKey(Book, on_delete=models.CASCADE, related_name="chapters")
    number = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ["book", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["book", "number"],
                name="uniq_chapter_book_number",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.book.name} {self.number}"


class Verse(models.Model):
    chapter = models.ForeignKey(Chapter, on_delete=models.CASCADE, related_name="verses")
    number = models.PositiveSmallIntegerField()
    text = models.TextField()
    # all-MiniLM-L6-v2 → 384 dim; JSON list[float] (universal). Com PostgreSQL + extensão
    # vector, use migração opcional core/0004 para coluna nativa + IVFFlat.
    embedding = models.JSONField(null=True, blank=True)

    class Meta:
        ordering = ["chapter", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["chapter", "number"],
                name="uniq_verse_chapter_number",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.chapter}:{self.number}"


class EntityType(models.TextChoices):
    PERSON = "person", "Person"
    CITY = "city", "City"
    PEOPLE = "people", "People"
    EVENT = "event", "Event"
    THEME = "theme", "Theme"


class Entity(models.Model):
    name = models.CharField(max_length=255, db_index=True)
    type = models.CharField(max_length=32, choices=EntityType.choices, default=EntityType.PERSON)
    version = models.ForeignKey(
        BibleVersion,
        on_delete=models.CASCADE,
        related_name="entities",
        null=True,
        blank=True,
    )

    class Meta:
        ordering = ["name"]
        verbose_name_plural = "entities"

    def __str__(self) -> str:
        return self.name


class Relationship(models.Model):
    source_entity = models.ForeignKey(
        Entity,
        on_delete=models.CASCADE,
        related_name="outgoing_relationships",
    )
    target_entity = models.ForeignKey(
        Entity,
        on_delete=models.CASCADE,
        related_name="incoming_relationships",
    )
    relation_type = models.CharField(max_length=64)

    class Meta:
        ordering = ["source_entity", "relation_type", "target_entity"]

    def __str__(self) -> str:
        return f"{self.source_entity} —{self.relation_type}→ {self.target_entity}"


class Study(models.Model):
    class Source(models.TextChoices):
        MANUAL = "manual", "Manual"
        SEARCH = "search", "Busca"
        CHAT = "chat", "Perguntas"

    title = models.CharField(max_length=255)
    content = models.TextField(blank=True)
    source = models.CharField(
        max_length=16,
        choices=Source.choices,
        default=Source.MANUAL,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="studies",
    )

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title
