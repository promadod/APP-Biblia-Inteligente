from django.contrib import admin

from .models import (
    AppUserAccount,
    BibleVersion,
    Book,
    Chapter,
    CollectiveStudy,
    CollectiveStudyAccessRequest,
    Entity,
    LearningGroup,
    Relationship,
    Study,
    Verse,
)


@admin.register(BibleVersion)
class BibleVersionAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "language")


class ChapterInline(admin.TabularInline):
    model = Chapter
    extra = 0


@admin.register(Book)
class BookAdmin(admin.ModelAdmin):
    list_display = ("name", "abbreviation", "order", "version")
    list_filter = ("version",)
    inlines = [ChapterInline]


@admin.register(Chapter)
class ChapterAdmin(admin.ModelAdmin):
    list_display = ("book", "number")


@admin.register(Verse)
class VerseAdmin(admin.ModelAdmin):
    list_display = ("chapter", "number")
    search_fields = ("text",)


@admin.register(Entity)
class EntityAdmin(admin.ModelAdmin):
    list_display = ("name", "type", "version")
    search_fields = ("name",)


@admin.register(Relationship)
class RelationshipAdmin(admin.ModelAdmin):
    list_display = ("source_entity", "relation_type", "target_entity")


@admin.register(Study)
class StudyAdmin(admin.ModelAdmin):
    list_display = ("title", "source", "created_at", "user")


@admin.register(AppUserAccount)
class AppUserAccountAdmin(admin.ModelAdmin):
    list_display = ("username", "full_name", "age", "learning_group", "channel", "created_at")
    list_filter = ("channel", "learning_group")
    search_fields = ("username", "full_name")
    readonly_fields = ("password_hash", "api_token", "created_at")
    ordering = ("-created_at",)


@admin.register(LearningGroup)
class LearningGroupAdmin(admin.ModelAdmin):
    list_display = ("name", "slug")
    search_fields = ("name", "slug")
    prepopulated_fields = {"slug": ("name",)}


@admin.register(CollectiveStudy)
class CollectiveStudyAdmin(admin.ModelAdmin):
    list_display = ("title", "lesson_at", "teacher", "audience_group", "updated_at")
    list_filter = ("audience_group",)
    search_fields = ("title", "teacher__username", "teacher__full_name")
    raw_id_fields = ("teacher", "audience_group")
    ordering = ("-lesson_at",)


@admin.register(CollectiveStudyAccessRequest)
class CollectiveStudyAccessRequestAdmin(admin.ModelAdmin):
    list_display = ("study", "user", "status", "created_at")
    list_filter = ("status",)
    raw_id_fields = ("study", "user")
    ordering = ("-created_at",)
