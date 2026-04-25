"""Meal plan orchestrator.

`/meal-plan/tomorrow` derives a `RecipeConstraints` from the user's profile
(daily targets, diet, allergies) plus today's already-logged macros, then
delegates to `run_generate_flow` to produce a fresh recipe. The recipe is
persisted as a MealPlan row scheduled for tomorrow and the `meal_plan_ready`
SSE event lets iOS know to refresh the upcoming list.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import MealPlan as MealPlanModel
from app.models import Profile as ProfileModel
from app.orchestrator.chat_flow import run_generate_flow
from app.orchestrator.meal_flow import meals_today
from app.realtime import EventName, hub
from app.schemas import MealPlan, MealPlanGenerateResponse, Profile
from app.schemas.recipe import Recipe, RecipeConstraints


async def generate_for_tomorrow(
    *, db: AsyncSession, user_id: uuid.UUID
) -> MealPlanGenerateResponse:
    profile = await _load_profile(db, user_id)
    today = await meals_today(db=db, user_id=user_id)
    constraints = _build_constraints(profile, today_consumed=today.consumed)

    recipe = await run_generate_flow(
        user_id=user_id, constraints=constraints, profile=profile
    )
    if recipe is None:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="meal-plan generation failed (see SSE error event)",
        )

    scheduled = date.today() + timedelta(days=1)
    plan_row = MealPlanModel(
        owner_id=user_id,
        recipe_id=recipe.id,
        scheduled_for=scheduled,
        status="proposed",
    )
    db.add(plan_row)
    await db.commit()
    await db.refresh(plan_row)

    await hub.publish(
        user_id,
        EventName.MEAL_PLAN_READY,
        {
            "plan_id": str(plan_row.id),
            "recipe_id": str(recipe.id),
            "scheduled_for": scheduled.isoformat(),
        },
    )
    return MealPlanGenerateResponse(plan=_to_schema(plan_row, recipe))


async def list_upcoming(
    *, db: AsyncSession, user_id: uuid.UUID, limit: int = 7
) -> list[MealPlan]:
    today = date.today()
    stmt = (
        select(MealPlanModel)
        .where(
            MealPlanModel.owner_id == user_id,
            MealPlanModel.scheduled_for >= today,
            MealPlanModel.status == "proposed",
        )
        .order_by(MealPlanModel.scheduled_for)
        .limit(limit)
    )
    rows = list((await db.execute(stmt)).scalars().all())
    if not rows:
        return []

    from app.models import Recipe as RecipeModel  # local import; keeps cycles out

    recipe_ids = [r.recipe_id for r in rows]
    recipes_stmt = select(RecipeModel).where(RecipeModel.id.in_(recipe_ids))
    recipe_rows = (await db.execute(recipes_stmt)).scalars().all()
    recipes_by_id = {r.id: _recipe_row_to_schema(r) for r in recipe_rows}

    return [_to_schema(r, recipes_by_id.get(r.recipe_id)) for r in rows]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _load_profile(db: AsyncSession, user_id: uuid.UUID) -> Profile:
    stmt = select(ProfileModel).where(ProfileModel.user_id == user_id)
    p = (await db.execute(stmt)).scalar_one_or_none()
    if p is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="profile missing — call PATCH /user/profile first",
        )
    return Profile.model_validate(p)


def _build_constraints(profile: Profile, *, today_consumed) -> RecipeConstraints:  # type: ignore[no-untyped-def]
    """One meal sized for what's left of the day, capped to sensible per-meal limits."""
    cap_calories = profile.daily_calorie_target or 2000
    one_meal_calories = max(300, min(900, cap_calories // 3))

    protein_target = profile.protein_g_target or 0
    one_meal_protein = max(15, min(70, protein_target // 3))

    return RecipeConstraints(
        calories_max=one_meal_calories,
        protein_g_min=one_meal_protein,
        diet=profile.diet,
        allergies=list(profile.allergies),
        vibe="tomorrow's macro-aware dinner",
    )


def _to_schema(row: MealPlanModel, recipe: Recipe | None) -> MealPlan:
    return MealPlan(
        id=row.id,
        recipe_id=row.recipe_id,
        scheduled_for=row.scheduled_for,
        status=row.status,
        created_at=row.created_at,
        recipe=recipe,
    )


def _recipe_row_to_schema(row) -> Recipe:  # type: ignore[no-untyped-def]
    # Local lightweight conversion to avoid importing chat_flow's helper, which
    # would create a cycle (chat_flow → run_generate_flow → ... → here).
    from app.schemas.common import Macros
    from app.schemas.recipe import RecipeIngredient

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
