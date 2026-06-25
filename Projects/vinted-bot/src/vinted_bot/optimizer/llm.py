"""Client LM Studio (API OpenAI-compatible).

Le serveur tourne sur le PC Windows (cf wol.py pour la séquence WoL).
Format de réponse forcé en JSON via response_format={"type": "json_object"}.
"""

from __future__ import annotations

import json
import time
from typing import Any

import httpx
from loguru import logger
from openai import OpenAI

from ..config import settings
from .prompts import SYSTEM_PROMPT, build_user_prompt


def get_client() -> OpenAI:
    """Client OpenAI pointé vers LM Studio."""
    return OpenAI(
        base_url=settings.llm_base_url,
        api_key="lm-studio",
        timeout=settings.llm_timeout_sec,
    )


def is_ready(timeout: float = 2.0) -> bool:
    """Ping rapide /v1/models pour savoir si LM Studio est servi."""
    try:
        with httpx.Client(timeout=timeout) as c:
            r = c.get(f"{settings.llm_base_url}/models")
            return r.status_code == 200
    except (httpx.RequestError, httpx.HTTPError):
        return False


def wait_for_ready(timeout_sec: int | None = None) -> bool:
    """Poll /v1/models jusqu'à ce que LM Studio réponde, ou timeout."""
    timeout_sec = timeout_sec or settings.pc_llm_ready_timeout_sec
    start = time.time()
    while time.time() - start < timeout_sec:
        if is_ready():
            elapsed = int(time.time() - start)
            logger.info(f"LM Studio prêt après {elapsed}s")
            return True
        time.sleep(3)
    logger.error(f"LM Studio pas prêt après {timeout_sec}s")
    return False


def optimize_item(
    current_title: str,
    current_description: str,
    brand: str | None,
    size: str | None,
    category: str,
    color: str | None = None,
    condition: str | None = None,
) -> dict[str, Any]:
    """Génère une proposition optimisée via Mistral.

    Renvoie {"title": str, "description": str, "rationale": str, "confidence": float}.
    Lève ValueError si le LLM produit du JSON invalide.
    """
    user_prompt = build_user_prompt(
        current_title=current_title,
        current_description=current_description,
        brand=brand,
        size=size,
        category=category,
        color=color,
        condition=condition,
    )

    # LM Studio attend response_format.type = 'json_schema' (pas 'json_object')
    proposal_schema = {
        "type": "json_schema",
        "json_schema": {
            "name": "vinted_optimization_proposal",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "maxLength": 80},
                    "description": {"type": "string"},
                    "rationale": {"type": "string"},
                    "confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0},
                },
                "required": ["title", "description", "rationale", "confidence"],
                "additionalProperties": False,
            },
        },
    }

    client = get_client()
    resp = client.chat.completions.create(
        model=settings.llm_model_id,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        max_tokens=settings.llm_max_tokens,
        temperature=0.4,
        response_format=proposal_schema,
    )
    content = resp.choices[0].message.content or "{}"

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(
            f"LLM a renvoyé du JSON invalide : {e}. Contenu brut : {content[:300]!r}"
        ) from e

    for field in ("title", "description", "rationale", "confidence"):
        if field not in parsed:
            raise ValueError(
                f"Champ manquant dans réponse LLM : {field!r}. Reçu : {list(parsed.keys())}"
            )

    try:
        parsed["confidence"] = max(0.0, min(1.0, float(parsed["confidence"])))
    except (TypeError, ValueError):
        parsed["confidence"] = 0.5

    if len(parsed["title"]) > 80:
        logger.warning(f"Titre trop long ({len(parsed['title'])} chars), trim à 80")
        parsed["title"] = parsed["title"][:80].rstrip()

    return parsed
