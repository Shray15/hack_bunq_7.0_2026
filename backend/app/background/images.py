"""Background task: generate the dish image and update the recipe row."""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import select

from app.adapters import gemini
from app.db import SessionLocal
from app.models import Recipe
from app.realtime import EventName, hub

log = logging.getLogger(__name__)


async def generate_recipe_image(
    *, user_id: uuid.UUID, recipe_id: uuid.UUID, dish_name: str, summary: str | None
) -> None:
    log.info("image_task_start: recipe_id=%s dish=%r", recipe_id, dish_name)
    image_url = await gemini.generate_image(dish_name, summary)
    log.info("image_task_gemini_ok: recipe_id=%s url_len=%d", recipe_id, len(image_url))

    async with SessionLocal() as db:
        result = await db.execute(select(Recipe).where(Recipe.id == recipe_id))
        recipe = result.scalar_one_or_none()
        if recipe is None:
            log.warning("image_task_orphan: recipe %s vanished", recipe_id)
            return
        recipe.image_url = image_url
        recipe.image_status = "ready"
        await db.commit()
    log.info("image_task_db_updated: recipe_id=%s status=ready", recipe_id)

    await hub.publish(
        user_id,
        EventName.IMAGE_READY,
        {"recipe_id": str(recipe_id), "image_url": image_url},
    )
    log.info("image_task_sse_sent: image_ready recipe_id=%s", recipe_id)
