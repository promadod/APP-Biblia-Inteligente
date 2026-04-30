"""
Geração de embeddings via API OpenAI (`text-embedding-3-small`), dimensão configurável.
Sem sentence-transformers/torch — adequado a ambientes com quota de disco limitada.
"""
from __future__ import annotations

import logging
import math
from typing import Iterable

import httpx
from django.conf import settings

logger = logging.getLogger(__name__)

OPENAI_EMBEDDINGS_PATH = "/embeddings"


def _zero_vector() -> list[float]:
    return [0.0] * settings.EMBEDDING_DIMENSION


def _l2_normalize(vec: list[float]) -> list[float]:
    s = math.sqrt(sum(x * x for x in vec))
    if s < 1e-12:
        return _zero_vector()
    return [x / s for x in vec]


def _embeddings_url() -> str:
    return f"{settings.OPENAI_API_BASE.rstrip('/')}{OPENAI_EMBEDDINGS_PATH}"


def _embedding_model() -> str:
    return getattr(settings, "OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")


def _call_openai_embeddings(inputs: list[str]) -> list[list[float]]:
    """Uma chamada HTTP; `inputs` não vazio."""
    key = (settings.OPENAI_API_KEY or "").strip()
    if not key:
        return [_zero_vector() for _ in inputs]

    dim = settings.EMBEDDING_DIMENSION
    payload = {
        "model": _embedding_model(),
        "input": inputs,
        "dimensions": dim,
    }
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    url = _embeddings_url()

    with httpx.Client(timeout=120.0) as client:
        r = client.post(url, json=payload, headers=headers)
        r.raise_for_status()
        body = r.json()

    data = body.get("data") or []
    # Ordenar pelo índice devolvido pela API
    indexed = sorted(data, key=lambda x: x.get("index", 0))
    out: list[list[float]] = []
    for item in indexed:
        emb = item.get("embedding")
        if not isinstance(emb, list) or len(emb) != dim:
            logger.error(
                "Embedding inválido da API (esperado dim=%s, recebido=%s)",
                dim,
                len(emb) if isinstance(emb, list) else None,
            )
            raise ValueError("Resposta de embeddings inválida")
        out.append(_l2_normalize([float(x) for x in emb]))
    if len(out) != len(inputs):
        raise ValueError(f"Tamanho da resposta ({len(out)}) != entrada ({len(inputs)})")
    return out


def generate_embedding(text: str) -> list[float]:
    """Vetor L2-normalizado de comprimento `EMBEDDING_DIMENSION`, ou zeros sem chave."""
    text = (text or "").strip()
    if not text:
        return _zero_vector()

    key = (settings.OPENAI_API_KEY or "").strip()
    if not key:
        return _zero_vector()

    try:
        vecs = _call_openai_embeddings([text])
        return vecs[0] if vecs else _zero_vector()
    except Exception as exc:
        logger.warning("generate_embedding falhou: %s", exc)
        raise


def batch_generate_embeddings(texts: Iterable[str], batch_size: int = 64) -> list[list[float]]:
    """
    Vários textos em lotes HTTP (máx. `batch_size` inputs por pedido, até 2048 pela API OpenAI).
    Textos vazios são enviados como um espaço para manter alinhamento índice ↔ versículo.
    """
    texts_list = [t.strip() if t else "" for t in texts]
    if not texts_list:
        return []

    key = (settings.OPENAI_API_KEY or "").strip()
    if not key:
        return [_zero_vector() for _ in texts_list]

    # OpenAI permite até 2048 inputs por pedido; limitamos pelo batch_size do chamador
    max_inputs = min(batch_size, 2048)
    out: list[list[float]] = []

    for start in range(0, len(texts_list), max_inputs):
        chunk = texts_list[start : start + max_inputs]
        inputs = [t if t else " " for t in chunk]
        try:
            out.extend(_call_openai_embeddings(inputs))
        except Exception as exc:
            logger.error("batch_generate_embeddings falhou no lote [%s:%s]: %s", start, start + len(chunk), exc)
            raise

    return out
