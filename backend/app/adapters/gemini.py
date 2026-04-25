"""Gemini Nano-Banana image generation adapter.

Generates a single dish image, returns it as an inline `data:image/png;base64,…`
URL. Time-capped — on any failure the caller falls back to a placeholder URL
and marks `image_status="failed"`. We don't retry inside the adapter; the
orchestrator decides what to do.
"""

from __future__ import annotations

import asyncio
import base64
import functools
import logging
from typing import Any

from app.config import settings

log = logging.getLogger(__name__)


class GeminiError(RuntimeError):
    pass


def is_configured() -> bool:
    return bool(settings.gemini_api_key)


async def generate_image(dish_name: str, summary: str | None = None) -> str | None:
    """Return a data: URL for the dish, or None on real (configured) failure.

    When `GEMINI_API_KEY` is empty (local dev / tests) we return a deterministic
    placeholder URL so the rest of the flow can succeed end-to-end. We only
    return None when Gemini was actually attempted and failed; the background
    task converts that into an `error` SSE event.
    """
    if not is_configured():
        return _placeholder_url(dish_name)

    prompt = (
        f"A vibrant, appetizing food photograph of {dish_name}, plated on a clean "
        f"surface with soft natural lighting. {summary or ''}".strip()
    )

    try:
        return await asyncio.wait_for(
            asyncio.to_thread(_blocking_generate, prompt),
            timeout=settings.gemini_timeout_seconds,
        )
    except TimeoutError:
        log.warning("gemini_timeout: %s", dish_name)
        return None
    except Exception as exc:  # noqa: BLE001 — best-effort
        log.warning("gemini_failed: %s — %s", dish_name, exc)
        return None


@functools.lru_cache(maxsize=1)
def _client() -> Any:
    from google import genai  # imported lazily so import-time isn't paid in tests

    return genai.Client(api_key=settings.gemini_api_key)


def _blocking_generate(prompt: str) -> str | None:
    from google.genai import types as genai_types

    response = _client().models.generate_content(
        model=settings.gemini_image_model,
        contents=prompt,
        config=genai_types.GenerateContentConfig(response_modalities=["IMAGE"]),
    )
    candidates = getattr(response, "candidates", None) or []
    if not candidates:
        raise GeminiError("Gemini returned no candidates")

    parts = getattr(candidates[0].content, "parts", None) or []
    for part in parts:
        inline = getattr(part, "inline_data", None)
        if inline and getattr(inline, "data", None):
            mime = getattr(inline, "mime_type", None) or "image/png"
            data: bytes = inline.data
            b64 = base64.b64encode(data).decode("ascii")
            return f"data:{mime};base64,{b64}"

    raise GeminiError("Gemini response had no inline_data")


def _placeholder_url(dish_name: str) -> str:
    label = dish_name.replace(" ", "+") or "Dish"
    return f"https://placehold.co/640x480/png?text={label}"
