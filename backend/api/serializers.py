from rest_framework import serializers

from core.models import (
    Book,
    Chapter,
    CollectiveStudy,
    Entity,
    LearningGroup,
    Study,
    Verse,
)


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


class CollectiveStudySerializer(serializers.ModelSerializer):
    teacher_name = serializers.CharField(source="teacher.full_name", read_only=True)
    audience_group_name = serializers.CharField(source="audience_group.name", read_only=True)
    audience_group_slug = serializers.CharField(source="audience_group.slug", read_only=True)
    can_edit = serializers.SerializerMethodField()

    class Meta:
        model = CollectiveStudy
        fields = (
            "id",
            "title",
            "content",
            "lesson_at",
            "teacher",
            "teacher_name",
            "audience_group",
            "audience_group_name",
            "audience_group_slug",
            "allow_external_requests",
            "created_at",
            "updated_at",
            "can_edit",
        )
        read_only_fields = (
            "id",
            "teacher",
            "created_at",
            "updated_at",
            "teacher_name",
            "audience_group_name",
            "audience_group_slug",
            "can_edit",
        )

    def get_can_edit(self, obj):
        user = self.context.get("app_user")
        if user is None:
            return False
        return obj.teacher_id == user.id


class CollectiveStudyRequestableSerializer(serializers.ModelSerializer):
    teacher_name = serializers.CharField(source="teacher.full_name", read_only=True)
    audience_group_name = serializers.CharField(source="audience_group.name", read_only=True)

    class Meta:
        model = CollectiveStudy
        fields = (
            "id",
            "title",
            "lesson_at",
            "teacher_name",
            "audience_group_name",
            "allow_external_requests",
        )


class CollectiveStudyWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = CollectiveStudy
        fields = ("title", "content", "lesson_at", "audience_group", "allow_external_requests")

    def create(self, validated_data):
        validated_data["teacher"] = self.context["teacher"]
        return super().create(validated_data)


class LearningGroupSerializer(serializers.ModelSerializer):
    class Meta:
        model = LearningGroup
        fields = ("id", "name", "slug")
