from django.contrib import admin

from .models import AskLog, AskSemanticCache


@admin.register(AskLog)
class AskLogAdmin(admin.ModelAdmin):
    list_display = ("question", "sources_count", "backend", "version_code", "created_at")
    search_fields = ("question",)
    readonly_fields = ("created_at",)


@admin.register(AskSemanticCache)
class AskSemanticCacheAdmin(admin.ModelAdmin):
    list_display = ("question_text", "version_code", "intent", "created_at")
    search_fields = ("question_text",)
    readonly_fields = ("question_text", "question_embedding", "response_body", "created_at")