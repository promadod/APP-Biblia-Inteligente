from django.db import models


class AskLog(models.Model):
    """Registro de perguntas ao endpoint RAG (auditoria)."""

    question = models.TextField()
    answer_preview = models.TextField(blank=True)
    version_code = models.CharField(max_length=32, blank=True)
    sources_count = models.PositiveSmallIntegerField(default=0)
    backend = models.CharField(max_length=32, default="stub", help_text="stub | openai")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.question[:60]


class AskSemanticCache(models.Model):
    """
    Respostas anteriores do /api/ask indexadas por embedding da pergunta
    (cache semântico: perguntas parecidas reutilizam a mesma resposta).
    """

    question_text = models.TextField(help_text="Texto normalizado usado no embedding")
    question_embedding = models.JSONField(help_text="Vetor float[E] (ex.: 384d)")
    version_code = models.CharField(max_length=32, blank=True, db_index=True)
    intent = models.CharField(max_length=64, blank=True, db_index=True)
    response_body = models.JSONField(help_text="Corpo JSON devolvido ao cliente")

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["version_code", "intent", "created_at"]),
        ]

    def __str__(self) -> str:
        return self.question_text[:80]