"""Interface genérica para LLM (OpenAI-compatible ou stub)."""
from __future__ import annotations

import json
import logging
import re
import time
from abc import ABC, abstractmethod
from typing import Any

import httpx
from django.conf import settings

logger = logging.getLogger(__name__)


class LLMRateLimitedError(Exception):
    """HTTP 429 ou overload no fornecedor do modelo."""


class LLMBackend(ABC):
    @abstractmethod
    def generate(self, system_prompt: str, user_prompt: str, max_tokens: int = 1024) -> str:
        pass


class StubLLMBackend(LLMBackend):
    """Resposta local sem API externa — indica configurar OPENAI_API_KEY."""

    def generate(self, system_prompt: str, user_prompt: str, max_tokens: int = 1024) -> str:
        return (
            "[Resposta automática sem LLM externo] Configure OPENAI_API_KEY no ambiente para gerar texto "
            "com modelo de IA. Enquanto isso, use apenas os versículos listados em “Versículos relevantes” "
            "no contexto enviado ao servidor. Se necessário, refine a pergunta ou execute "
            "`python manage.py generate_embeddings` para melhorar a recuperação semântica."
        )


class OpenAICompatibleBackend(LLMBackend):
    """Chat completions em API compatível com OpenAI (OpenAI, Azure OpenAI, LiteLLM, Ollama openai plugin, etc.)."""

    def __init__(self) -> None:
        self.api_key = settings.OPENAI_API_KEY
        self.base = settings.OPENAI_API_BASE.rstrip("/")
        self.model = settings.OPENAI_MODEL

    def generate(self, system_prompt: str, user_prompt: str, max_tokens: int = 1024) -> str:
        if not self.api_key:
            return StubLLMBackend().generate(system_prompt, user_prompt, max_tokens=max_tokens)
        url = f"{self.base}/chat/completions"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.3,
            "max_tokens": max_tokens,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        max_attempts = getattr(settings, "OPENAI_MAX_RETRIES", 4)
        try:
            with httpx.Client(timeout=120.0) as client:
                for attempt in range(max_attempts):
                    r = client.post(url, json=payload, headers=headers)
                    if r.status_code == 429:
                        if attempt >= max_attempts - 1:
                            raise LLMRateLimitedError(
                                "Limite de pedidos ao serviço de IA (429). Aguarde alguns minutos ou verifique o plano da API."
                            )
                        wait_s = 5
                        ra = r.headers.get("Retry-After")
                        if ra:
                            try:
                                wait_s = min(max(int(float(ra)), 1), 120)
                            except ValueError:
                                wait_s = min(2**attempt * 2, 60)
                        else:
                            wait_s = min(2**attempt * 2, 60)
                        logger.warning(
                            "OpenAI 429 — nova tentativa %s/%s após %ss",
                            attempt + 2,
                            max_attempts,
                            wait_s,
                        )
                        time.sleep(wait_s)
                        continue
                    r.raise_for_status()
                    data = r.json()
                    return data["choices"][0]["message"]["content"].strip()
        except LLMRateLimitedError:
            raise
        except httpx.HTTPStatusError as exc:
            code = exc.response.status_code
            logger.exception("Falha HTTP ao chamar LLM: %s", exc)
            return (
                f"Erro HTTP {code} ao contactar o modelo. Verifique OPENAI_API_BASE, chave e quotas."
            )
        except Exception as exc:
            logger.exception("Falha ao chamar LLM: %s", exc)
            return (
                f"Erro ao contactar o modelo de IA ({exc}). Verifique OPENAI_API_BASE e a chave. "
                "Consulte manualmente os versículos retornados em sources."
            )


def get_llm_backend() -> LLMBackend:
    if settings.OPENAI_API_KEY:
        return OpenAICompatibleBackend()
    return StubLLMBackend()


def generate_answer(question: str, context: str) -> tuple[str, str]:
    """
    Monta prompt restrito ao contexto e devolve (resposta, nome_backend).
    """
    system = (
        "És um assistente bíblico. Usa exclusivamente o contexto fornecido — versículos e notas de entidades — "
        "para responder em português. Se o contexto não bastar, diz claramente que não há informação suficiente "
        "nos trechos recuperados. Não inventes factos fora do contexto."
    )
    user = (
        "Usa apenas o contexto abaixo para responder.\n\n"
        f"{context}\n\n"
        f"Pergunta:\n{question}"
    )
    backend = get_llm_backend()
    name = "openai" if settings.OPENAI_API_KEY else "stub"
    return backend.generate(system, user), name


def _is_openai_transport_error_text(text: str) -> bool:
    t = (text or "").strip()
    if not t:
        return False
    if t.startswith("Erro ao contactar o modelo") or t.startswith("Erro HTTP "):
        return True
    if "Too Many Requests" in t:
        return True
    if "429" in t and ("chat/completions" in t or "openai" in t.lower() or "modelo de IA" in t):
        return True
    return False


def _strip_json_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.IGNORECASE)
        t = re.sub(r"\s*```\s*$", "", t)
    return t.strip()


def generate_structured_answer(question: str, context: str) -> tuple[dict[str, str], str]:
    """
    Devolve ({"chronology": str, "life_summary": str}, backend_name).
    Texto só com base no contexto; versículos ordenados ficam à parte na API.
    """
    name = "openai" if settings.OPENAI_API_KEY else "stub"
    if not settings.OPENAI_API_KEY:
        return {
            "chronology": (
                "Configure OPENAI_API_KEY para gerar cronologia e traço de vida automáticos. "
                "Os versículos listados na resposta estão em ordem bíblica (livro, capítulo, versículo)."
            ),
            "life_summary": (
                "[Sem LLM externo] Use os trechos recuperados no servidor e refine a pergunta. "
                "Execute `python manage.py generate_embeddings` para melhorar a recuperação semântica."
            ),
        }, name

    system = (
        "És um assistente bíblico. Usa exclusivamente o contexto fornecido (versículos e notas de entidades). "
        "Não inventes factos fora desse contexto. "
        "Responde APENAS com um objeto JSON válido (sem markdown), chaves exatas em português:\n"
        '{"cronologia": "...", "traco_vida": "..."}\n'
        "- cronologia: marcos ou eventos em ordem temporal quando o contexto permitir; caso contrário indica limitações.\n"
        "- traco_vida: síntese do papel, chamado ou trajetória do tema/pessoa com base só nos trechos."
    )
    user = f"Contexto:\n{context}\n\nPergunta:\n{question}\n\nResponde só com o JSON."
    backend = OpenAICompatibleBackend()
    try:
        raw = backend.generate(system, user, max_tokens=2048)
    except LLMRateLimitedError as exc:
        msg = str(exc)
        return {
            "chronology": msg,
            "life_summary": (
                "Os versículos abaixo foram recuperados do texto sagrado (ordem bíblica). "
                "Pode estudá-los mesmo quando o modelo de IA está indisponível ou limitado."
            ),
        }, "openai"

    if _is_openai_transport_error_text(raw):
        return {
            "chronology": (
                "Não foi possível gerar texto com o modelo de IA neste momento (rede, quota ou limite de pedidos)."
            ),
            "life_summary": (
                "Use a lista de versículos na ordem bíblica abaixo para o seu estudo. "
                "Se vir erro 429, aguarde alguns minutos ou reduza o ritmo de perguntas."
            ),
        }, "openai"

    try:
        parsed = json.loads(_strip_json_fence(raw))
        cron = str(parsed.get("cronologia") or parsed.get("chronology") or "").strip()
        life = str(parsed.get("traco_vida") or parsed.get("life_summary") or "").strip()
        return {"chronology": cron, "life_summary": life}, name
    except (json.JSONDecodeError, TypeError, ValueError) as exc:
        logger.warning("Resposta do LLM não é JSON válido (%s); fallback texto único", exc)
        if _is_openai_transport_error_text(raw):
            return {
                "chronology": (
                    "Não foi possível gerar texto com o modelo de IA neste momento (rede, quota ou limite de pedidos)."
                ),
                "life_summary": (
                    "Use a lista de versículos na ordem bíblica abaixo para o seu estudo."
                ),
            }, name
        return {"chronology": "", "life_summary": raw.strip()[:12000]}, name


BIBLICAL_BIOGRAPHY_SYSTEM_PROMPT = """És um historiador bíblico em português (Portugal / Brasil). Trabalhas APENAS
com o CONTEXTO enviado pelo servidor: lista de versículos recuperados, entidades e relações. Esse contexto provém
da Bíblia importada na aplicação — não tens acesso a Talmude, Midrash ou livros históricos externos nesta API.

Regras estritas:
• Não inventes datas absolutas (ex.: «650 a.C.», «586 a.C.») nem cronologias históricas extra-bíblicas, a menos que
  apareçam explicitamente no texto do contexto.
• Não cites tradições rabínicas ou enciclopédias. Se o contexto não mencionar um facto, declara a lacuna em vez
  de preencher com conhecimento geral.
• Cada afirmação factual sobre o personagem ou evento deve poder sustentar-se em versículos do contexto; usa
  referências curtas entre parêntesis ou no fim do parágrafo (ex.: Jr 1:5; Jr 20:2).
• Personagens com pouca informação: deixa isso claro e desenvolve o que o contexto permite (genealogias,
  livro, papel).

Objetivo narrativo (história completa «do princípio ao fim» dentro do permitido pelo contexto):
1) lifeSummary — texto denso e longo (vários parágrafos se houver material): genealogia, lugar, tribo/família,
   cenário espiritual e político **antes** do nascimento quando o contexto o permitir (profetas, alianças, reinos
   mencionados nos versículos).
2) chronology — corpo principal em Markdown com subtítulos ### no mínimo:
   ### Genealogia e origem
   ### Chamado e início do ministério
   ### Percurso (ordenar acontecimentos na ordem em que a narrativa bíblica os apresenta ou na ordem lógica dos
       capítulos/versículos do contexto)
   ### Oposição, provações e sinais (se aplicável)
   ### Desfecho e legado
   Usa listas com • ou números. Cada secção deve integrar o máximo de detalhe dos versículos fornecidos.
3) text — conclusão teológica do legado e do papel redentor/moral no plano de Deus, só com base no contexto.
4) sources — array de strings com referências «Livro capítulo:versículo» que efectivamente usaste (prioriza as do
   contexto).

Sê abundante: usa e sintetiza TODOS os trechos relevantes do contexto. Se o contexto for curto, o texto será curto
— explica isso honestamente.

Responde APENAS com JSON válido (sem markdown à volta), chaves em inglês exactamente:
{
  "lifeSummary": "...",
  "chronology": "...",
  "text": "...",
  "sources": ["Jr 1:5", "Jr 20:2"]
}
Escapa aspas internas em JSON com \\"."""


def _fallback_biography_stub(fallback_ref_strings: list[str]) -> dict[str, Any]:
    refs = [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48]
    return {
        "lifeSummary": (
            "Configure OPENAI_API_KEY no servidor para gerar automaticamente esta narrativa. "
            "Enquanto isso, use os trechos completos listados abaixo (ordem bíblica)."
        ),
        "chronology": (
            "[Sem modelo externo] O contexto recuperado pelo RAG está na lista de versículos; "
            "refine a pergunta ou execute `python manage.py generate_embeddings` para melhor recuperação."
        ),
        "text": (
            "Leia os versículos na ordem canónica e construa o estudo manualmente ou active o LLM quando possível."
        ),
        "sources": refs,
    }


def _parse_biography_json(raw: str, fallback_ref_strings: list[str]) -> dict[str, Any]:
    parsed = json.loads(_strip_json_fence(raw))
    life = str(parsed.get("lifeSummary") or parsed.get("life_summary") or "").strip()
    chron = str(parsed.get("chronology") or parsed.get("cronologia") or "").strip()
    conclusion = str(parsed.get("text") or parsed.get("conclusao") or "").strip()
    src_raw = parsed.get("sources")
    sources: list[str] = []
    if isinstance(src_raw, list):
        sources = [str(x).strip() for x in src_raw if str(x).strip()]
    if not sources and fallback_ref_strings:
        sources = [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48]
    return {
        "lifeSummary": life,
        "chronology": chron,
        "text": conclusion,
        "sources": sources,
    }


def generate_biblical_biography_answer(
    question: str,
    context: str,
    fallback_ref_strings: list[str],
) -> tuple[dict[str, Any], str]:
    """
    JSON exclusivo da feature Perguntas (personagens/acontecimentos): lifeSummary, chronology, text, sources[].
    """
    name = "openai" if settings.OPENAI_API_KEY else "stub"
    if not settings.OPENAI_API_KEY:
        return _fallback_biography_stub(fallback_ref_strings), name

    user = (
        f"Contexto (única fonte obrigatória para factos):\n{context}\n\n"
        f"Pergunta ou tema:\n{question}\n\n"
        "Produz uma narrativa tão completa quanto o contexto permitir; integra o máximo de versículos relevantes. "
        "Responde só com o JSON pedido."
    )
    backend = OpenAICompatibleBackend()
    try:
        max_tok = getattr(settings, "OPENAI_BIOGRAPHY_MAX_TOKENS", 8192)
        raw = backend.generate(BIBLICAL_BIOGRAPHY_SYSTEM_PROMPT, user, max_tokens=max_tok)
    except LLMRateLimitedError as exc:
        return {
            "lifeSummary": str(exc),
            "chronology": "",
            "text": (
                "Os versículos abaixo foram recuperados em ordem bíblica; pode estudá-los enquanto o serviço de IA "
                "está limitado."
            ),
            "sources": [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48],
        }, "openai"

    if _is_openai_transport_error_text(raw):
        return {
            "lifeSummary": (
                "Não foi possível gerar texto com o modelo de IA neste momento (rede, quota ou limite de pedidos)."
            ),
            "chronology": "",
            "text": (
                "Use as referências e trechos abaixo. Se vir 429, aguarde alguns minutos ou reduza pedidos."
            ),
            "sources": [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48],
        }, "openai"

    try:
        return _parse_biography_json(raw, fallback_ref_strings), name
    except (json.JSONDecodeError, TypeError, ValueError) as exc:
        logger.warning("JSON biografia inválido (%s); fallback", exc)
        if _is_openai_transport_error_text(raw):
            return {
                "lifeSummary": (
                    "Não foi possível gerar texto com o modelo de IA neste momento (rede, quota ou limite de pedidos)."
                ),
                "chronology": "",
                "text": "Use os versículos em ordem bíblica listados na resposta da API.",
                "sources": [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48],
            }, name
        return {
            "lifeSummary": "",
            "chronology": raw.strip()[:12000],
            "text": "",
            "sources": [str(x).strip() for x in fallback_ref_strings if str(x).strip()][:48],
        }, name
