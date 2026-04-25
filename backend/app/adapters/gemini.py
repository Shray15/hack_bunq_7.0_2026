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


async def generate_image(dish_name: str, summary: str | None = None) -> str:
    """Return a usable image URL for the dish.

    Order of preference:
      1. A real Gemini-generated `data:image/png;base64,…` URL.
      2. A deterministic placehold.co URL (when Gemini is unconfigured, times
         out, or errors out).

    We never return None — a missing image is worse for the demo than a stock
    placeholder. The background task uses this directly as the image_url.
    """
    if not is_configured():
        return _placeholder_url(dish_name)

    prompt = (
        f"A vibrant, appetizing food photograph of {dish_name}, plated on a clean "
        f"surface with soft natural lighting. {summary or ''}".strip()
    )

    try:
        result = await asyncio.wait_for(
            asyncio.to_thread(_blocking_generate, prompt),
            timeout=settings.gemini_timeout_seconds,
        )
        if result is None:
            log.warning("gemini_returned_none: %s — using placeholder", dish_name)
            return _placeholder_url(dish_name)
        return result
    except TimeoutError:
        log.warning(
            "gemini_timeout (%.1fs): %s — using placeholder",
            settings.gemini_timeout_seconds,
            dish_name,
        )
        return _placeholder_url(dish_name)
    except Exception as exc:  # noqa: BLE001 — best-effort
        log.warning("gemini_failed: %s — %s — using placeholder", dish_name, exc)
        return _placeholder_url(dish_name)


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
