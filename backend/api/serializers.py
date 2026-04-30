from rest_framework import serializers

from core.models import Book, Chapter, Entity, Study, Verse


class VerseSerializer(serializers.ModelSerializer):
    book = serializers.CharField(source="chapter.book.name", read_only=True)
    book_id = serializers.IntegerField(source="chapter.book.id", read_only=True)
    chapter_number = serializers.IntegerField(source="chapter.number", read_only=True)

    class Meta:
        model = Verse
        fields = ("id", "book", "book_id", "chapter_number", "number", "text")


class BookSerializer(serializers.ModelSerializer):
    version_code = serializers.CharField(source="version.code", read_only=True)

    class Meta:
        model = Book
        fields = ("id", "name", "abbreviation", "order", "version_code")


class ChapterSerializer(serializers.ModelSerializer):
    book_name = serializers.CharField(source="book.name", read_only=True)
    book_id = serializers.IntegerField(source="book.id", read_only=True)

    class Meta:
        model = Chapter
        fields = ("id", "number", "book_id", "book_name")


class EntitySerializer(serializers.ModelSerializer):
    class Meta:
        model = Entity
        fields = ("id", "name", "type")


class StudySerializer(serializers.ModelSerializer):
    class Meta:
        model = Study
        fields = ("id", "title", "content", "source", "created_at", "updated_at", "user")
        read_only_fields = ("id", "created_at", "updated_at")
