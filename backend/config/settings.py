"""
Django settings — Bible Intelligent App backend.
"""
import os
import sys
from pathlib import Path

from django.core.management.utils import get_random_secret_key

BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

# Carrega `.env` na raiz do repositório (pasta acima de `backend/`).
# `override=True`: valores no `.env` prevalecem sobre variáveis vazias/antigas no ambiente
# (caso comum após adicionar OPENAI_API_KEY ao ficheiro sem reiniciar o IDE/serviço).
# Em CI/produção defina as variáveis no orchestrator; use `DOTENV_OVERRIDE=0` para não sobrescrever.
try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None
if load_dotenv:
    _env_path = BASE_DIR.parent / ".env"
    _override = os.environ.get("DOTENV_OVERRIDE", "1").strip().lower() in ("1", "true", "yes")
    load_dotenv(_env_path, override=_override)

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", get_random_secret_key())
DEBUG = os.environ.get("DEBUG", "1") in ("1", "true", "True", "yes")
ALLOWED_HOSTS = [h.strip() for h in os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if h.strip()]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.postgres",
    "rest_framework",
    "corsheaders",
    "core",
    "api",
    "embeddings",
    "search",
    "rag",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

_db_name = os.environ.get("DB_NAME", "").strip()
if _db_name:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": _db_name,
            "USER": os.environ.get("DB_USER", "postgres"),
            "PASSWORD": os.environ.get("DB_PASSWORD", "postgres"),
            "HOST": os.environ.get("DB_HOST", "localhost"),
            "PORT": os.environ.get("DB_PORT", "5432"),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "pt-br"
TIME_ZONE = "America/Sao_Paulo"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
if DEBUG:
    _staticfiles_backend = "django.contrib.staticfiles.storage.StaticFilesStorage"
else:
    _staticfiles_backend = "whitenoise.storage.CompressedManifestStaticFilesStorage"
STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": _staticfiles_backend,
    },
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Produção (PythonAnywhere e similares): atrás de proxy HTTPS
if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True

_csrf_origins = [x.strip() for x in os.environ.get("CSRF_TRUSTED_ORIGINS", "").split(",") if x.strip()]
if _csrf_origins:
    CSRF_TRUSTED_ORIGINS = _csrf_origins

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "bible-intelligent",
    }
}

CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = [
    o.strip()
    for o in os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://127.0.0.1:8080").split(",")
    if o.strip()
]

REST_FRAMEWORK = {
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 50,
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.AllowAny",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "120/minute",
        "user": "600/minute",
        "search": "60/minute",
        "ask": "30/minute",
    },
}

# FTS: exige PostgreSQL. Sem DB_NAME, import/search usam fallback icontains apenas.
USE_POSTGRES_SEARCH = bool(_db_name)

# RAG / embeddings (sentence-transformers all-MiniLM-L6-v2 → 384 dim)
EMBEDDING_MODEL_NAME = os.environ.get(
    "EMBEDDING_MODEL_NAME",
    "sentence-transformers/all-MiniLM-L6-v2",
)
EMBEDDING_DIMENSION = 384
RAG_TOP_K_SEMANTIC = min(int(os.environ.get("RAG_TOP_K_SEMANTIC", "24")), 64)
RAG_TOP_K_TEXT = min(int(os.environ.get("RAG_TOP_K_TEXT", "16")), 40)
RAG_TOP_K_FINAL = min(int(os.environ.get("RAG_TOP_K_FINAL", "12")), 24)
try:
    RAG_BIOGRAPHY_TOP_SEMANTIC = min(int(os.environ.get("RAG_BIOGRAPHY_TOP_SEMANTIC", "56")), 96)
    RAG_BIOGRAPHY_TOP_TEXT = min(int(os.environ.get("RAG_BIOGRAPHY_TOP_TEXT", "80")), 120)
    RAG_BIOGRAPHY_TOP_FINAL = min(int(os.environ.get("RAG_BIOGRAPHY_TOP_FINAL", "56")), 96)
except ValueError:
    RAG_BIOGRAPHY_TOP_SEMANTIC = 56
    RAG_BIOGRAPHY_TOP_TEXT = 80
    RAG_BIOGRAPHY_TOP_FINAL = 56
try:
    OPENAI_BIOGRAPHY_MAX_TOKENS = max(1024, min(int(os.environ.get("OPENAI_BIOGRAPHY_MAX_TOKENS", "8192")), 16384))
except ValueError:
    OPENAI_BIOGRAPHY_MAX_TOKENS = 8192
RAG_CACHE_TTL = int(os.environ.get("RAG_CACHE_TTL", "300"))
# Cache semântico do /api/ask (embeddings; reduz chamadas OpenAI)
SEMANTIC_ASK_CACHE_ENABLED = os.environ.get("SEMANTIC_ASK_CACHE_ENABLED", "1").strip().lower() in (
    "1",
    "true",
    "yes",
)
try:
    SEMANTIC_ASK_CACHE_MIN_SIMILARITY = float(os.environ.get("SEMANTIC_ASK_CACHE_MIN_SIMILARITY", "0.9"))
    SEMANTIC_ASK_CACHE_MIN_SIMILARITY = min(max(SEMANTIC_ASK_CACHE_MIN_SIMILARITY, 0.5), 1.0)
except ValueError:
    SEMANTIC_ASK_CACHE_MIN_SIMILARITY = 0.9
try:
    SEMANTIC_ASK_CACHE_LOOKBACK = max(10, min(int(os.environ.get("SEMANTIC_ASK_CACHE_LOOKBACK", "400")), 5000))
except ValueError:
    SEMANTIC_ASK_CACHE_LOOKBACK = 400
# LLM: OPENAI_API_KEY + OPENAI_API_BASE (opcional) ou apenas Stub
def _env_str(name: str, default: str = "") -> str:
    v = os.environ.get(name, default)
    return v.strip().strip('"').strip("'") if isinstance(v, str) else default


OPENAI_API_KEY = _env_str("OPENAI_API_KEY")
OPENAI_API_BASE = _env_str("OPENAI_API_BASE", "https://api.openai.com/v1")
OPENAI_MODEL = _env_str("OPENAI_MODEL", "gpt-4o-mini")
try:
    OPENAI_MAX_RETRIES = max(1, min(int(os.environ.get("OPENAI_MAX_RETRIES", "4")), 8))
except ValueError:
    OPENAI_MAX_RETRIES = 4
