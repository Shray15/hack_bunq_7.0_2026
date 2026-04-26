"""Recipe brain orchestrator.

Two entry points:

  - run_chat_flow(transcript, …)  → NLU → ingredients||steps||macros (parallel) → persist → SSE
  - run_generate_flow(constraints, …)  → same, skipping NLU (constraints already given)

Both produce the same observable behaviour from iOS' perspective: a
`recipe_complete` SSE event once the recipe lands, then `image_ready` once the
image task finishes. LLM failures emit an `error` SSE and persist nothing.
"""

from __future__ import annotations

import asyncio
import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import deepseek
from app.adapters.deepseek import DeepSeekError, NLUResult, ProposedDish
from app.background.images import generate_recipe_image
from app.db import SessionLocal
from app.models import Recipe as RecipeModel
from app.realtime import EventName, hub
from app.schemas.common import Macros
from app.schemas.profile import Profile
from app.schemas.recipe import Recipe, RecipeConstraints, RecipeIngredient

log = logging.getLogger(__name__)


async def run_chat_flow(
    *,
    user_id: uuid.UUID,
    chat_id: uuid.UUID,
    transcript: str,
    profile: Profile,
    people: int = 1,
) -> None:
    """Voice/text → recipe pipeline. Pushes SSE events; returns nothing."""
    log.info("chat_flow_start: chat_id=%s user=%s", chat_id, user_id)
    try:
        nlu = await deepseek.parse_transcript_to_constraints(transcript, profile)
        log.info("chat_flow_nlu_done: dish=%r chat_id=%s", nlu.dish.name, chat_id)
    except DeepSeekError as exc:
        log.error("chat_flow_nlu_failed: chat_id=%s error=%s", chat_id, exc)
        await _emit_error(user_id, "nlu", "nlu_failed", str(exc), chat_id=chat_id)
        return

    await _generate_and_persist(
        user_id=user_id,
        chat_id=chat_id,
        nlu=nlu,
        people=people,
        source="chat",
    )


async def run_generate_flow(
    *,
    user_id: uuid.UUID,
    constraints: RecipeConstraints,
    profile: Profile,
    people: int = 1,
    parent_recipe_id: uuid.UUID | None = None,
) -> Recipe | None:
    """Programmatic recipe generation; returns the persisted recipe inline.

    Used by /recipes/generate and (Phase 4) by the meal-plan flow. Unlike
    run_chat_flow, this returns the Recipe so the caller can render it
    synchronously as a 200 response.
    """
    dish = await _propose_dish_for_constraints(constraints, profile)
    nlu = NLUResult(constraints=constraints, dish=dish)
    return await _generate_and_persist(
        user_id=user_id,
        chat_id=None,
        nlu=nlu,
        people=people,
        source="meal_plan" if parent_recipe_id else "chat",
        parent_recipe_id=parent_recipe_id,
        return_recipe=True,
    )


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _generate_and_persist(
    *,
    user_id: uuid.UUID,
    chat_id: uuid.UUID | None,
    nlu: NLUResult,
    people: int,
    source: str,
    parent_recipe_id: uuid.UUID | None = None,
    return_recipe: bool = False,
) -> Recipe | None:
    dish = nlu.dish
    log.info("recipe_pipeline_start: dish=%r chat_id=%s user=%s", dish.name, chat_id, user_id)

    try:
        log.info(
            "recipe_pipeline_step: generating ingredients+steps in parallel dish=%r",
            dish.name,
        )
        ingredients, steps = await asyncio.gather(
            deepseek.generate_ingredients(dish, nlu.constraints, people),
            deepseek.generate_steps(dish),
        )
        log.info(
            "recipe_pipeline_step: ingredients=%d steps=%d — generating macros",
            len(ingredients),
            len(steps),
        )
        macros = await deepseek.generate_macros(dish, ingredients, nlu.constraints)
        log.info(
            "recipe_pipeline_step: macros done calories=%d protein=%dg",
            macros.calories,
            macros.protein_g,
        )
    except DeepSeekError as exc:
        log.error("recipe_pipeline_llm_failed: dish=%r error=%s", dish.name, exc)
        await _emit_error(
            user_id, "recipe_generation", "llm_failed", str(exc), chat_id=chat_id
        )
        return None

    async with SessionLocal() as db:
        row = await _persist_recipe(
            db,
            owner_id=user_id,
            dish=dish,
            ingredients=ingredients,
            steps=steps,
            macros=macros,
            source=source,
            parent_recipe_id=parent_recipe_id,
        )
        recipe_payload = _row_to_schema(row)
    log.info("recipe_pipeline_persisted: recipe_id=%s dish=%r", recipe_payload.id, dish.name)

    await hub.publish(
        user_id,
        EventName.RECIPE_COMPLETE,
        {
            "chat_id": str(chat_id) if chat_id else None,
            "recipe_id": str(recipe_payload.id),
            "recipe": recipe_payload.model_dump(mode="json"),
        },
    )
    log.info(
        "recipe_pipeline_sse_sent: recipe_complete recipe_id=%s chat_id=%s",
        recipe_payload.id,
        chat_id,
    )

    asyncio.create_task(
        generate_recipe_image(
            user_id=user_id,
            recipe_id=recipe_payload.id,
            dish_name=dish.name,
            summary=dish.summary,
        )
    )
    log.info(
        "recipe_pipeline_image_task_spawned: recipe_id=%s dish=%r",
        recipe_payload.id,
        dish.name,
    )

    return recipe_payload if return_recipe else None


async def _propose_dish_for_constraints(
    constraints: RecipeConstraints, profile: Profile
) -> ProposedDish:
    """For programmatic /recipes/generate, derive a dish_name from constraints."""
    transcript = _constraints_to_transcript(constraints)
    nlu = await deepseek.parse_transcript_to_constraints(transcript, profile)
    return nlu.dish


def _constraints_to_transcript(c: RecipeConstraints) -> str:
    """Cheap reverse of NLU so generate_flow can reuse the same prompt path."""
    bits: list[str] = []
    if c.vibe:
        bits.append(c.vibe)
    if c.diet:
        bits.append(f"{c.diet} diet")
    if c.calories_max:
        bits.append(f"under {c.calories_max} kcal")
    if c.protein_g_min:
        bits.append(f"at least {c.protein_g_min} g protein")
    if c.must_use:
        bits.append(f"using {', '.join(c.must_use)}")
    if c.avoid:
        bits.append(f"avoiding {', '.join(c.avoid)}")
    return ", ".join(bits) if bits else "any high-quality home-cooked meal"


async def _persist_recipe(
    db: AsyncSession,
    *,
    owner_id: uuid.UUID,
    dish: ProposedDish,
    ingredients: list[RecipeIngredient],
    steps: list[str],
    macros: Macros,
    source: str,
    parent_recipe_id: uuid.UUID | None,
) -> RecipeModel:
    row = RecipeModel(
        owner_id=owner_id,
        name=dish.name,
        summary=dish.summary,
        prep_time_min=dish.prep_time_min,
        ingredients=[i.model_dump(mode="json") for i in ingredients],
        steps=list(steps),
        macros=macros.model_dump(mode="json"),
        validated_macros=None,
        image_url=None,
        image_status="pending",
        source=source,
        parent_recipe_id=parent_recipe_id,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


def _row_to_schema(row: RecipeModel) -> Recipe:
    return Recipe(
        id=row.id,
        name=row.name,
        summary=row.summary,
        prep_time_min=row.prep_time_min,
        ingredients=[RecipeIngredient.model_validate(i) for i in row.ingredients],
        steps=list(row.steps),
        macros=Macros.model_validate(row.macros),
        validated_macros=Macros.model_validate(row.validated_macros)
        if row.validated_macros
        else None,
        image_url=row.image_url,
        image_status=row.image_status,
        source=row.source,
        parent_recipe_id=row.parent_recipe_id,
        favorited_at=row.favorited_at,
        created_at=row.created_at,
    )


async def _emit_error(
    user_id: uuid.UUID,
    scope: str,
    code: str,
    message: str,
    *,
    chat_id: uuid.UUID | None = None,
) -> None:
    payload: dict[str, str | None] = {"scope": scope, "code": code, "message": message}
    if chat_id is not None:
        payload["chat_id"] = str(chat_id)
    log.warning("orchestrator_error: %s/%s — %s", scope, code, message)
    await hub.publish(user_id, EventName.ERROR, payload)
