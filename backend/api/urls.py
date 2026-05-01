from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("books", views.BookViewSet, basename="book")
router.register("collective-studies", views.CollectiveStudyViewSet, basename="collective-study")

urlpatterns = [
    path("auth/register", views.AppUserRegisterView.as_view(), name="auth-register"),
    path("auth/login", views.AppUserLoginView.as_view(), name="auth-login"),
    path("learning-groups/", views.LearningGroupListView.as_view(), name="learning-groups"),
    path("", include(router.urls)),
    path("ask", views.AskAPIView.as_view(), name="ask"),
    path("search", views.SearchView.as_view(), name="search"),
    path("narrative", views.NarrativeView.as_view(), name="narrative"),
    path("chapters/<int:pk>/verses", views.ChapterVersesView.as_view(), name="chapter-verses"),
    path("verse/random", views.RandomVerseView.as_view(), name="verse-random"),
    path("verse/daily", views.DailyVerseView.as_view(), name="verse-daily"),
    path("health", views.health, name="health"),
]
