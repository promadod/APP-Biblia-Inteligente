from django.contrib import admin

from .models import BibleVersion, Book, Chapter, Entity, Relationship, Study, Verse


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
