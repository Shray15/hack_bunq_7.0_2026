"""Meal logging orchestrator.

  * log_meal(recipe_id, portion, eaten_at)  — derive macros from
                                               recipe.macros × portion, persist
                                               a meals_consumed row, return it.
  * meals_today()                            — sum of today's logs + remaining vs profile.
  * meals_history(from_, to)                 — paginated time window.
  * meal_options()                           — recipes the user has paid for or
                                               recently consumed; iOS picker.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import MealConsumed as MealConsumedModel
from app.models import Order as OrderModel
from app.models import Profile as ProfileModel
from app.models import Recipe as RecipeModel
from app.schemas.common import Macros
from app.schemas.meal import (
    MealLog,
    MealOption,
    MealsHistoryResponse,
    MealsTodayResponse,
)


async def log_meal(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    recipe_id: uuid.UUID,
    portion: float,
    eaten_at: datetime | None,
    source: str = "manual",
) -> MealLog:
    recipe = await _load_recipe(db, recipe_id, user_id)
    macros_full = Macros.model_validate(recipe.macros)
    macros_scaled = _scale_macros(macros_full, portion)

    row = MealConsumedModel(
        owner_id=user_id,
        recipe_id=recipe_id,
        portion=portion,
        calories_computed=macros_scaled.calories,
        macros_computed=macros_scaled.model_dump(mode="json"),
        eaten_at=eaten_at or datetime.now(UTC),
        source=source,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _to_meal_log(row, recipe.name)


async def meals_today(
    *, db: AsyncSession, user_id: uuid.UUID
) -> MealsTodayResponse:
    today = date.today()
    start = datetime.combine(today, time.min, tzinfo=UTC)
    end = start + timedelta(days=1)

    rows = await _load_meals_in_window(db, user_id, start, end)
    consumed = _sum_macros(r.macros_computed for r in rows)

    target = await _profile_target(db, user_id)
    remaining = _diff_macros(target, consumed) if target else None

    recipe_names = await _load_recipe_names(db, [r.recipe_id for r in rows])
    return MealsTodayResponse(
        date=today,
        meals=[_to_meal_log(r, recipe_names.get(r.recipe_id, "")) for r in rows],
        consumed=consumed,
        target=target,
        remaining=remaining,
    )


async def meals_history(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    from_: datetime | None,
    to: datetime | None,
) -> MealsHistoryResponse:
    if from_ is None:
        from_ = datetime.now(UTC) - timedelta(days=30)
    if to is None:
        to = datetime.now(UTC)
    rows = await _load_meals_in_window(db, user_id, from_, to)
    recipe_names = await _load_recipe_names(db, [r.recipe_id for r in rows])
    return MealsHistoryResponse(
        meals=[_to_meal_log(r, recipe_names.get(r.recipe_id, "")) for r in rows]
    )


async def meal_options(
    *, db: AsyncSession, user_id: uuid.UUID, limit: int = 20
) -> list[MealOption]:
    """Recipes the user has paid for, consumed in the past 30 days, or favorited."""
    from app.models import Cart as CartModel  # local import: avoid model cycles

    cutoff = datetime.now(UTC) - timedelta(days=30)

    consumed_ids = select(MealConsumedModel.recipe_id).where(
        MealConsumedModel.owner_id == user_id,
        MealConsumedModel.eaten_at >= cutoff,
    )
    paid_cart_ids = select(OrderModel.cart_id).where(
        OrderModel.owner_id == user_id, OrderModel.status == "paid"
    )
    paid_recipe_ids = select(CartModel.recipe_id).where(
        CartModel.id.in_(paid_cart_ids)
    )

    candidate_ids_stmt = consumed_ids.union(paid_recipe_ids)
    candidate_ids = {row[0] for row in (await db.execute(candidate_ids_stmt)).all()}

    recipes_stmt = (
        select(RecipeModel)
        .where(
            RecipeModel.owner_id == user_id,
            or_(
                RecipeModel.id.in_(candidate_ids) if candidate_ids else False,
                RecipeModel.favorited_at.is_not(None),
            ),
        )
        .order_by(RecipeModel.created_at.desc())
        .limit(limit)
    )
    recipes = list((await db.execute(recipes_stmt)).scalars().all())

    options: list[MealOption] = []
    for r in recipes:
        if r.favorited_at is not None:
            reason: str = "favorite"
        elif r.id in candidate_ids:
            reason = "ordered"
        else:
            reason = "prepared"
        options.append(
            MealOption(
                recipe_id=r.id,
                name=r.name,
                macros=Macros.model_validate(r.macros),
                last_seen_at=r.favorited_at or r.created_at,
                reason=reason,
            )
        )
    return options


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _load_recipe(
    db: AsyncSession, recipe_id: uuid.UUID, owner_id: uuid.UUID
) -> RecipeModel:
    stmt = select(RecipeModel).where(
        RecipeModel.id == recipe_id, RecipeModel.owner_id == owner_id
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="recipe not found"
        )
    return row


async def _load_meals_in_window(
    db: AsyncSession,
    user_id: uuid.UUID,
    start: datetime,
    end: datetime,
) -> list[MealConsumedModel]:
    stmt = (
        select(MealConsumedModel)
        .where(
            MealConsumedModel.owner_id == user_id,
            MealConsumedModel.eaten_at >= start,
            MealConsumedModel.eaten_at < end,
        )
        .order_by(MealConsumedModel.eaten_at.desc())
    )
    return list((await db.execute(stmt)).scalars().all())


async def _load_recipe_names(
    db: AsyncSession, recipe_ids: list[uuid.UUID]
) -> dict[uuid.UUID, str]:
    if not recipe_ids:
        return {}
    stmt = select(RecipeModel.id, RecipeModel.name).where(
        RecipeModel.id.in_(set(recipe_ids))
    )
    return {row[0]: row[1] for row in (await db.execute(stmt)).all()}


async def _profile_target(
    db: AsyncSession, user_id: uuid.UUID
) -> Macros | None:
    stmt = select(ProfileModel).where(ProfileModel.user_id == user_id)
    p = (await db.execute(stmt)).scalar_one_or_none()
    if p is None or p.daily_calorie_target is None:
        return None
    return Macros(
        calories=p.daily_calorie_target,
        protein_g=p.protein_g_target or 0,
        carbs_g=p.carbs_g_target or 0,
        fat_g=p.fat_g_target or 0,
    )


def _scale_macros(macros: Macros, portion: float) -> Macros:
    return Macros(
        calories=int(macros.calories * portion),
        protein_g=int(macros.protein_g * portion),
        carbs_g=int(macros.carbs_g * portion),
        fat_g=int(macros.fat_g * portion),
    )


def _sum_macros(samples: Iterable[dict[str, Any]]) -> Macros:
    out = Macros(calories=0, protein_g=0, carbs_g=0, fat_g=0)
    for raw in samples:
        m = Macros.model_validate(raw)
        out = Macros(
            calories=out.calories + m.calories,
            protein_g=out.protein_g + m.protein_g,
            carbs_g=out.carbs_g + m.carbs_g,
            fat_g=out.fat_g + m.fat_g,
        )
    return out


def _diff_macros(target: Macros, consumed: Macros) -> Macros:
    return Macros(
        calories=target.calories - consumed.calories,
        protein_g=target.protein_g - consumed.protein_g,
        carbs_g=target.carbs_g - consumed.carbs_g,
        fat_g=target.fat_g - consumed.fat_g,
    )


def _to_meal_log(row: MealConsumedModel, recipe_name: str) -> MealLog:
    return MealLog(
        id=row.id,
        recipe_id=row.recipe_id,
        recipe_name=recipe_name,
        portion=row.portion,
        calories_computed=row.calories_computed,
        macros_computed=Macros.model_validate(row.macros_computed),
        eaten_at=row.eaten_at,
        source=row.source,
    )
