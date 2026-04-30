from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("books", views.BookViewSet, basename="book")
router.register("studies", views.StudyViewSet, basename="study")

urlpatterns = [
    path("", include(router.urls)),
    path("ask", views.AskAPIView.as_view(), name="ask"),
    path("search", views.SearchView.as_view(), name="search"),
    path("narrative", views.NarrativeView.as_view(), name="narrative"),
    path("chapters/<int:pk>/verses", views.ChapterVersesView.as_view(), name="chapter-verses"),
    path("verse/random", views.RandomVerseView.as_view(), name="verse-random"),
    path("verse/daily", views.DailyVerseView.as_view(), name="verse-daily"),
    path("health", views.health, name="health"),
]
