import hashlib
import logging
import secrets

from django.conf import settings
from django.core.cache import cache
from django.db.models import Max, Min, Q
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, throttle_classes
from rest_framework.response import Response
from rest_framework.views import APIView

from core.models import (
    AppUserAccount,
    Book,
    Chapter,
    CollectiveStudy,
    CollectiveStudyAccessRequest,
    LearningGroup,
    Study,
    Verse,
)
from rag.context_builder import build_context
from rag.llm_service import generate_biblical_biography_answer, generate_structured_answer
from rag.models import AskLog
from rag.semantic_cache import lookup_similar_response, store_response
from rag.verse_ordering import sort_verses_bible_order
from services.narrative import NarrativeService
from services.search import unified_search

from .serializers import (
    BookSerializer,
    ChapterSerializer,
    CollectiveStudyRequestableSerializer,
    CollectiveStudySerializer,
    CollectiveStudyWriteSerializer,
    LearningGroupSerializer,
    StudySerializer,
    VerseSerializer,
)
from .throttles import AskThrottle, SearchThrottle

logger = logging.getLogger(__name__)

INTENT_BIBLICAL_BIOGRAPHY = "biblical_biography"


def _norm_app_username(value: object) -> str:
    return (str(value) if value is not None else "").strip().lower()


def _hash_password_plain(plain: str) -> str:
    return hashlib.sha256(plain.encode("utf-8")).hexdigest()


def _ensure_api_token(user: AppUserAccount) -> str:
    if not user.api_token:
        user.api_token = secrets.token_urlsafe(48)
        user.save(update_fields=["api_token"])
    return user.api_token


def _user_auth_payload(user: AppUserAccount) -> dict:
    lg_slug = user.learning_group.slug if user.learning_group_id else None
    return {
        "username": user.username,
        "full_name": user.full_name,
        "age": user.age,
        "api_token": _ensure_api_token(user),
        "learning_group_slug": lg_slug,
    }


def _get_app_user_from_request(request):
    username = _norm_app_username(
        request.headers.get("X-App-Username") or request.META.get("HTTP_X_APP_USERNAME", "")
    )
    token = (request.headers.get("X-App-Token") or request.META.get("HTTP_X_APP_TOKEN") or "").strip()
    if not username or not token:
        return None
    user = AppUserAccount.objects.select_related("learning_group").filter(username=username).first()
    if user is None or user.api_token != token:
        return None
    return user


def _visible_collective_studies_queryset(user: AppUserAccount):
    return (
        CollectiveStudy.objects.filter(
            Q(teacher=user)
            | Q(audience_group_id=user.learning_group_id)
            | Q(
                access_requests__user=user,
                access_requests__status=CollectiveStudyAccessRequest.Status.ACCEPTED,
            )
        )
        .distinct()
        .select_related("teacher", "audience_group")
        .order_by("-lesson_at")
    )


def _requestable_collective_studies_queryset(user: AppUserAccount):
    if user.learning_group_id is None:
        return CollectiveStudy.objects.none()
    blocked = CollectiveStudyAccessRequest.objects.filter(
        user=user,
        status__in=[
            CollectiveStudyAccessRequest.Status.PENDING,
            CollectiveStudyAccessRequest.Status.ACCEPTED,
        ],
    ).values_list("study_id", flat=True)
    return (
        CollectiveStudy.objects.filter(allow_external_requests=True)
        .exclude(audience_group_id=user.learning_group_id)
        .exclude(teacher=user)
        .exclude(pk__in=blocked)
        .select_related("teacher", "audience_group")
        .order_by("-lesson_at")
    )


def _can_read_collective_study(user: AppUserAccount, study: CollectiveStudy) -> bool:
    if study.teacher_id == user.id:
        return True
    if user.learning_group_id and study.audience_group_id == user.learning_group_id:
        return True
    return CollectiveStudyAccessRequest.objects.filter(
        study=study,
        user=user,
        status=CollectiveStudyAccessRequest.Status.ACCEPTED,
    ).exists()


class AppUserRegisterView(APIView):
    """POST cria conta; repetição com a mesma senha (duplo envio) → 200 idempotente."""

    authentication_classes = []
    permission_classes = []

    def post(self, request):
        username = _norm_app_username(request.data.get("username"))
        password = str(request.data.get("password") or "")
        full_name = str(request.data.get("full_name") or "").strip()
        age_raw = request.data.get("age")
        channel = str(request.data.get("channel") or "").strip().lower() or "unknown"

        if not username:
            return Response({"detail": "Informe um usuário."}, status=status.HTTP_400_BAD_REQUEST)
        if not full_name:
            return Response({"detail": "Informe o nome completo."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            age = int(age_raw)
        except (TypeError, ValueError):
            return Response({"detail": "Informe uma idade válida."}, status=status.HTTP_400_BAD_REQUEST)
        if age < 1 or age > 120:
            return Response({"detail": "Informe uma idade válida."}, status=status.HTTP_400_BAD_REQUEST)
        if len(password) < 4:
            return Response(
                {"detail": "A senha deve ter pelo menos 4 caracteres."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        valid_channels = {"web", "android", "ios", "unknown"}
        if channel not in valid_channels:
            channel = "unknown"

        pw_hash = _hash_password_plain(password)
        existing = AppUserAccount.objects.filter(username=username).first()
        if existing:
            if existing.password_hash == pw_hash:
                return Response(_user_auth_payload(existing))
            return Response(
                {"detail": "Este usuário já está cadastrado."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        alunos = LearningGroup.objects.filter(slug="alunos").first()
        obj = AppUserAccount.objects.create(
            username=username,
            full_name=full_name,
            age=age,
            password_hash=pw_hash,
            channel=channel,
            learning_group=alunos,
        )
        _ensure_api_token(obj)
        body = _user_auth_payload(obj)
        return Response(body, status=status.HTTP_201_CREATED)


class AppUserLoginView(APIView):
    authentication_classes = []
    permission_classes = []

    def post(self, request):
        username = _norm_app_username(request.data.get("username"))
        password = str(request.data.get("password") or "")
        if not username or not password:
            return Response(
                {"detail": "Preencha usuário e senha."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        pw_hash = _hash_password_plain(password)
        user = AppUserAccount.objects.filter(username=username).first()
        if user is None or user.password_hash != pw_hash:
            return Response(
                {"detail": "Usuário ou senha incorretos."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(_user_auth_payload(user))


class CollectiveStudyViewSet(viewsets.ModelViewSet):
    """Estudos coletivos (aulas). Autenticação: cabeçalhos X-App-Username + X-App-Token."""

    authentication_classes = []
    permission_classes = []
    lookup_field = "pk"

    def get_queryset(self):
        return CollectiveStudy.objects.none()

    def get_serializer_class(self):
        if self.action in ("create", "partial_update", "update"):
            return CollectiveStudyWriteSerializer
        return CollectiveStudySerializer

    def list(self, request, *args, **kwargs):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"readable": [], "requestable": []})
        readable = _visible_collective_studies_queryset(app_user)
        requestable = _requestable_collective_studies_queryset(app_user)
        ctx = {"request": request, "app_user": app_user}
        return Response(
            {
                "readable": CollectiveStudySerializer(readable, many=True, context=ctx).data,
                "requestable": CollectiveStudyRequestableSerializer(requestable, many=True).data,
            }
        )

    def retrieve(self, request, *args, **kwargs):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"detail": "Autenticação necessária."}, status=status.HTTP_401_UNAUTHORIZED)
        pk = kwargs.get("pk")
        study = (
            CollectiveStudy.objects.select_related("teacher", "audience_group").filter(pk=pk).first()
        )
        if study is None:
            return Response({"detail": "Não encontrado."}, status=status.HTTP_404_NOT_FOUND)
        if not _can_read_collective_study(app_user, study):
            return Response({"detail": "Sem permissão."}, status=status.HTTP_403_FORBIDDEN)
        ser = CollectiveStudySerializer(
            study, context={"request": request, "app_user": app_user}
        )
        return Response(ser.data)

    def create(self, request, *args, **kwargs):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"detail": "Autenticação necessária."}, status=status.HTTP_401_UNAUTHORIZED)
        if (
            app_user.learning_group is None
            or app_user.learning_group.slug != "professores"
        ):
            return Response(
                {"detail": "Apenas utilizadores no grupo Professores podem criar aulas coletivas."},
                status=status.HTTP_403_FORBIDDEN,
            )
        ser = CollectiveStudyWriteSerializer(data=request.data, context={"teacher": app_user})
        ser.is_valid(raise_exception=True)
        study = ser.save()
        out = CollectiveStudySerializer(
            study, context={"request": request, "app_user": app_user}
        )
        return Response(out.data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"detail": "Autenticação necessária."}, status=status.HTTP_401_UNAUTHORIZED)
        study = CollectiveStudy.objects.filter(pk=kwargs.get("pk")).first()
        if study is None:
            return Response({"detail": "Não encontrado."}, status=status.HTTP_404_NOT_FOUND)
        if study.teacher_id != app_user.id:
            return Response({"detail": "Só o professor autor pode editar."}, status=status.HTTP_403_FORBIDDEN)
        ser = CollectiveStudyWriteSerializer(study, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        study = ser.save()
        out = CollectiveStudySerializer(
            study, context={"request": request, "app_user": app_user}
        )
        return Response(out.data)

    def destroy(self, request, *args, **kwargs):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"detail": "Autenticação necessária."}, status=status.HTTP_401_UNAUTHORIZED)
        study = CollectiveStudy.objects.filter(pk=kwargs.get("pk")).first()
        if study is None:
            return Response({"detail": "Não encontrado."}, status=status.HTTP_404_NOT_FOUND)
        if study.teacher_id != app_user.id:
            return Response({"detail": "Só o professor autor pode eliminar."}, status=status.HTTP_403_FORBIDDEN)
        study.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="request-access")
    def request_access(self, request, pk=None):
        app_user = _get_app_user_from_request(request)
        if not app_user:
            return Response({"detail": "Autenticação necessária."}, status=status.HTTP_401_UNAUTHORIZED)
        study = CollectiveStudy.objects.filter(pk=pk).first()
        if study is None:
            return Response({"detail": "Não encontrado."}, status=status.HTTP_404_NOT_FOUND)
        if study.teacher_id == app_user.id:
            return Response({"detail": "É o autor desta aula."}, status=status.HTTP_400_BAD_REQUEST)
        if (
            app_user.learning_group_id
            and study.audience_group_id == app_user.learning_group_id
        ):
            return Response({"detail": "Já tem acesso a esta aula."}, status=status.HTTP_400_BAD_REQUEST)
        if not study.allow_external_requests:
            return Response(
                {"detail": "Esta aula não aceita pedidos externos."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        req_obj, created = CollectiveStudyAccessRequest.objects.get_or_create(
            study=study,
            user=app_user,
            defaults={"status": CollectiveStudyAccessRequest.Status.PENDING},
        )
        if not created and req_obj.status != CollectiveStudyAccessRequest.Status.REJECTED:
            return Response(
                {"detail": "Pedido já registado."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if req_obj.status == CollectiveStudyAccessRequest.Status.REJECTED:
            req_obj.status = CollectiveStudyAccessRequest.Status.PENDING
            req_obj.save(update_fields=["status"])
        return Response({"detail": "Pedido enviado. Aguarde aprovação no administrador."}, status=status.HTTP_200_OK)


class LearningGroupListView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        qs = LearningGroup.objects.order_by("name")
        return Response(LearningGroupSerializer(qs, many=True).data)


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
