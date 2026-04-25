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
    image_url = await gemini.generate_image(dish_name, summary)

    async with SessionLocal() as db:
        result = await db.execute(select(Recipe).where(Recipe.id == recipe_id))
        recipe = result.scalar_one_or_none()
        if recipe is None:
            log.warning("image_task_orphan: recipe %s vanished", recipe_id)
            return
        if image_url is None:
            recipe.image_status = "failed"
            await db.commit()
            await hub.publish(
                user_id,
                EventName.ERROR,
                {
                    "scope": "image",
                    "code": "image_generation_failed",
                    "message": "Image generation failed; please retry.",
                    "recipe_id": str(recipe_id),
                },
            )
            return

        recipe.image_url = image_url
        recipe.image_status = "ready"
        await db.commit()

    await hub.publish(
        user_id,
        EventName.IMAGE_READY,
        {"recipe_id": str(recipe_id), "image_url": image_url},
    )
