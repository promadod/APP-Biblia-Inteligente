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


class AppChannel(models.TextChoices):
    WEB = "web", "Web (Vercel)"
    ANDROID = "android", "Android (APK)"
    IOS = "ios", "iOS"
    UNKNOWN = "unknown", "Desconhecido"


class LearningGroup(models.Model):
    """Grupo pedagógico (ex.: Alunos, Professores, turmas). Gerido no Django Admin."""

    name = models.CharField(max_length=128)
    slug = models.SlugField(max_length=64, unique=True)

    class Meta:
        ordering = ["name"]

    def __str__(self) -> str:
        return self.name


class AppUserAccount(models.Model):
    """Cadastros da app móvel/Web (autenticação própria; não é o utilizador Django admin)."""

    username = models.CharField(max_length=150, unique=True, db_index=True)
    full_name = models.CharField(max_length=255)
    age = models.PositiveSmallIntegerField()
    password_hash = models.CharField(max_length=64)
    channel = models.CharField(
        max_length=16,
        choices=AppChannel.choices,
        default=AppChannel.UNKNOWN,
        db_index=True,
    )
    learning_group = models.ForeignKey(
        LearningGroup,
        on_delete=models.PROTECT,
        related_name="members",
        null=True,
        blank=True,
    )
    api_token = models.CharField(max_length=80, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "conta da app"
        verbose_name_plural = "contas da app"

    def __str__(self) -> str:
        return self.username


class CollectiveStudy(models.Model):
    """Aula / estudo coletivo criado por um professor (conta app no grupo Professores)."""

    title = models.CharField(max_length=255)
    content = models.TextField(blank=True)
    lesson_at = models.DateTimeField(db_index=True)
    teacher = models.ForeignKey(
        AppUserAccount,
        on_delete=models.CASCADE,
        related_name="collective_studies_authored",
    )
    audience_group = models.ForeignKey(
        LearningGroup,
        on_delete=models.PROTECT,
        related_name="collective_studies",
    )
    allow_external_requests = models.BooleanField(
        default=True,
        help_text="Se verdadeiro, utilizadores fora do grupo audiência podem pedir acesso.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-lesson_at"]

    def __str__(self) -> str:
        return self.title


class CollectiveStudyAccessRequest(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pendente"
        ACCEPTED = "accepted", "Aceite"
        REJECTED = "rejected", "Rejeitado"

    study = models.ForeignKey(
        CollectiveStudy,
        on_delete=models.CASCADE,
        related_name="access_requests",
    )
    user = models.ForeignKey(
        AppUserAccount,
        on_delete=models.CASCADE,
        related_name="collective_access_requests",
    )
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.PENDING,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["study", "user"],
                name="uniq_collective_access_study_user",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.user} → {self.study} ({self.status})"
