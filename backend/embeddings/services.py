"""
Geração de embeddings com sentence-transformers (all-MiniLM-L6-v2, 384 dim).
"""
from __future__ import annotations

import logging
from typing import Iterable

from django.conf import settings
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

_model = None


def get_sentence_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer

        name = settings.EMBEDDING_MODEL_NAME
        logger.info("Carregando modelo de embeddings: %s", name)
        _model = SentenceTransformer(name)
    return _model


def generate_embedding(text: str) -> list[float]:
    """Retorna vetor de 384 floats normalizado (norma L2 ≈ 1 para modelo ST)."""
    text = (text or "").strip()
    if not text:
        return [0.0] * settings.EMBEDDING_DIMENSION
    model = get_sentence_model()
    vec = model.encode(text, convert_to_numpy=True, normalize_embeddings=True)
    return vec.astype("float32").tolist()


def batch_generate_embeddings(texts: Iterable[str], batch_size: int = 64) -> list[list[float]]:
    texts = [t.strip() if t else "" for t in texts]
    if not texts:
        return []
    model = get_sentence_model()
    import numpy as np

    out: list[list[float]] = []
    batch: list[str] = []
    for t in texts:
        batch.append(t if t else " ")
        if len(batch) >= batch_size:
            emb = model.encode(batch, convert_to_numpy=True, normalize_embeddings=True)
            out.extend(emb.astype("float32").tolist())
            batch = []
    if batch:
        emb = model.encode(batch, convert_to_numpy=True, normalize_embeddings=True)
        out.extend(emb.astype("float32").tolist())
    return out
