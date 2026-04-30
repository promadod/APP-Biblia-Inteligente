import hashlib
import logging

from django.conf import settings
from django.core.cache import cache
from django.db.models import Max, Min
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, throttle_classes
from rest_framework.response import Response
from rest_framework.views import APIView

from core.models import Book, Chapter, Study, Verse
from rag.context_builder import build_context
from rag.llm_service import generate_biblical_biography_answer, generate_structured_answer
from rag.models import AskLog
from rag.semantic_cache import lookup_similar_response, store_response
from rag.verse_ordering import sort_verses_bible_order
from services.narrative import NarrativeService
from services.search import unified_search

from .serializers import BookSerializer, ChapterSerializer, StudySerializer, VerseSerializer
from .throttles import AskThrottle, SearchThrottle

logger = logging.getLogger(__name__)

INTENT_BIBLICAL_BIOGRAPHY = "biblical_biography"


def _serialize_search(payload: dict) -> dict:
    return {
        "verses": VerseSerializer(payload["verses"], many=True).data,
        "books": BookSerializer(payload["books"], many=True).data,
        "chapters": ChapterSerializer(payload["chapters"], many=True).data,
        "entities": [
            {"id": e.id, "name": e.name, "type": e.type} for e in payload["entities"]
        ],
    }


class SearchView(APIView):
    throttle_classes = [SearchThrottle]

    def get(self, request):
        q = request.query_params.get("q", "").strip()
        version = request.query_params.get("version")
        limit = min(int(request.query_params.get("limit", 50)), 100)
        cache_key = f"api:search:{hashlib.sha256(f'{q}:{version}:{limit}'.encode()).hexdigest()[:48]}"
        cached = cache.get(cache_key)
        if cached is not None:
            return Response(cached)

        raw = unified_search(q, version, limit=limit)
        narrative = NarrativeService().build(q, raw["verses"], raw["entities"])
        body = _serialize_search(raw)
        body["narrative"] = narrative
        cache.set(cache_key, body, 120)
        return Response(body)


class NarrativeView(APIView):
    throttle_classes = [SearchThrottle]

    def get(self, request):
        q = request.query_params.get("q", "").strip()
        version = request.query_params.get("version")
        raw = unified_search(q, version, limit=40)
        text = NarrativeService().build(q, raw["verses"], raw["entities"])
        return Response({"query": q, "narrative": text})


class BookViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = BookSerializer
    pagination_class = None

    def get_queryset(self):
        qs = Book.objects.select_related("version").order_by("version", "order", "name")
        code = self.request.query_params.get("version")
        if code:
            qs = qs.filter(version__code=code)
        return qs

    @action(detail=True, methods=["get"], url_path="chapters")
    def chapters(self, request, pk=None):
        book = self.get_object()
        chs = book.chapters.order_by("number")
        return Response(ChapterSerializer(chs, many=True).data)


class ChapterVersesView(APIView):
    def get(self, request, pk):
        ch = Chapter.objects.select_related("book").get(pk=pk)
        verses = ch.verses.order_by("number")
        return Response(VerseSerializer(verses, many=True).data)


class RandomVerseView(APIView):
    def get(self, request):
        book_id = request.query_params.get("book_id")
        qs = Verse.objects.select_related("chapter__book")
        if book_id:
            qs = qs.filter(chapter__book_id=book_id)
        low = qs.aggregate(m=Min("id"))["m"]
        high = qs.aggregate(m=Max("id"))["m"]
        if low is None or high is None:
            return Response({"detail": "Sem versículos."}, status=status.HTTP_404_NOT_FOUND)
        import random

        for _ in range(12):
            rid = random.randint(low, high)
            v = qs.filter(id__gte=rid).first()
            if v:
                return Response(VerseSerializer(v).data)
        v = qs.order_by("?").first()
        return Response(VerseSerializer(v).data)


class DailyVerseView(APIView):
    def get(self, request):
        version_code = request.query_params.get("version", "BKJ_PT")
        qs = Verse.objects.filter(chapter__book__version__code=version_code)
        ids = list(qs.values_list("id", flat=True))
        if not ids:
            return Response({"detail": "Importe a Bíblia primeiro."}, status=status.HTTP_404_NOT_FOUND)
        today = timezone.now().date()
        seed = f"{version_code}:{today.isoformat()}".encode()
        h = int(hashlib.sha256(seed).hexdigest(), 16)
        vid = ids[h % len(ids)]
        v = Verse.objects.select_related("chapter__book").get(pk=vid)
        return Response(VerseSerializer(v).data)


class StudyViewSet(viewsets.ModelViewSet):
    serializer_class = StudySerializer
    queryset = Study.objects.all()

    def perform_create(self, serializer):
        serializer.save(user=self.request.user if self.request.user.is_authenticated else None)


@api_view(["GET"])
def health(_request):
    return Response({"status": "ok"})


class AskAPIView(APIView):
    throttle_classes = [AskThrottle]

    def post(self, request):
        question = (request.data.get("question") or "").strip()
        if not question:
            return Response({"detail": "Campo question é obrigatório."}, status=status.HTTP_400_BAD_REQUEST)

        version = (request.data.get("version") or "").strip() or None
        intent = (request.data.get("intent") or "").strip()
        cache_key = (
            f"rag:ask:v6:{intent}:{hashlib.sha256(f'{question}:{version}'.encode()).hexdigest()[:48]}"
        )
        cached = cache.get(cache_key)
        if cached is not None:
            return Response(cached)

        sem_body = lookup_similar_response(question, version, intent)
        if sem_body is not None:
            cache.set(cache_key, sem_body, getattr(settings, "RAG_CACHE_TTL", 300))
            return Response(sem_body)

        try:
            is_bio = intent == INTENT_BIBLICAL_BIOGRAPHY
            context_text, verses, _meta = build_context(
                question,
                version_code=version,
                biography_mode=is_bio,
            )
            verses_sorted = sort_verses_bible_order(verses)
            verse_refs = [
                f"{v.chapter.book.name} {v.chapter.number}:{v.number}"
                for v in verses_sorted
            ]
            source_objects = [
                {
                    "book": v.chapter.book.name,
                    "chapter": v.chapter.number,
                    "verse": v.number,
                    "text": v.text,
                }
                for v in verses_sorted
            ]
            if intent == INTENT_BIBLICAL_BIOGRAPHY:
                bio, backend_name = generate_biblical_biography_answer(
                    question, context_text, verse_refs
                )
            else:
                structured, backend_name = generate_structured_answer(question, context_text)
        except Exception as exc:
            logger.exception("RAG falhou: %s", exc)
            return Response(
                {
                    "detail": str(exc),
                    "answer": "",
                    "chronology": "",
                    "life_summary": "",
                    "sources": [],
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        if intent == INTENT_BIBLICAL_BIOGRAPHY:
            assert bio is not None
            preview_txt = (
                f"{bio.get('lifeSummary', '')[:800]}\n{bio.get('chronology', '')[:800]}\n{bio.get('text', '')[:400]}"
            ).strip()
            body = {
                "intent": INTENT_BIBLICAL_BIOGRAPHY,
                "lifeSummary": bio["lifeSummary"],
                "chronology": bio["chronology"],
                "text": bio["text"],
                "sources": bio["sources"],
                "verses": source_objects,
                "backend": backend_name,
            }
            cache.set(cache_key, body, getattr(settings, "RAG_CACHE_TTL", 300))
            store_response(question, version, intent, body)

            AskLog.objects.create(
                question=question[:4000],
                answer_preview=preview_txt[:2000],
                version_code=version or "",
                sources_count=len(source_objects),
                backend=backend_name or "",
            )
            return Response(body)

        chronology = structured.get("chronology") or ""
        life_summary = structured.get("life_summary") or ""
        sources = source_objects
        answer_markdown = (
            f"## Cronologia\n\n{chronology}\n\n## Traço de vida\n\n{life_summary}".strip()
        )
        body = {
            "chronology": chronology,
            "life_summary": life_summary,
            "answer": answer_markdown,
            "sources": sources,
            "backend": backend_name,
        }
        cache.set(cache_key, body, getattr(settings, "RAG_CACHE_TTL", 300))
        store_response(question, version, intent, body)

        AskLog.objects.create(
            question=question[:4000],
            answer_preview=(answer_markdown[:2000] if answer_markdown else life_summary[:2000]),
            version_code=version or "",
            sources_count=len(sources),
            backend=backend_name,
        )

        return Response(body)
