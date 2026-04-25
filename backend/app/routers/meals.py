from __future__ import annotations

import uuid
from datetime import date as date_cls
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query

from app.dependencies import CurrentUserId
from app.schemas import (
    MealLog,
    MealLogRequest,
    MealOption,
    MealsHistoryResponse,
    MealsTodayResponse,
)
from app.schemas.common import Macros
from app.stubs import make_meal_log, make_meal_options

router = APIRouter(prefix="/meals", tags=["meals"])


@router.post("/log", response_model=MealLog)
async def log_meal(payload: MealLogRequest, user_id: CurrentUserId) -> MealLog:
    return make_meal_log(recipe_id=payload.recipe_id, portion=payload.portion)


@router.get("/today", response_model=MealsTodayResponse)
async def meals_today(user_id: CurrentUserId) -> MealsTodayResponse:
    sample = make_meal_log(recipe_id=uuid.uuid4(), portion=0.5)
    consumed = sample.macros_computed
    target = Macros(calories=2200, protein_g=150, carbs_g=250, fat_g=70)
    remaining = Macros(
        calories=target.calories - consumed.calories,
        protein_g=target.protein_g - consumed.protein_g,
        carbs_g=target.carbs_g - consumed.carbs_g,
        fat_g=target.fat_g - consumed.fat_g,
    )
    return MealsTodayResponse(
        date=date_cls.today(),
        meals=[sample],
        consumed=consumed,
        target=target,
        remaining=remaining,
    )


@router.get("/history", response_model=MealsHistoryResponse)
async def meals_history(
    user_id: CurrentUserId,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: Annotated[datetime | None, Query()] = None,
) -> MealsHistoryResponse:
    return MealsHistoryResponse(meals=[make_meal_log(recipe_id=uuid.uuid4(), portion=1.0)])


@router.get("/options", response_model=list[MealOption])
async def meal_options(user_id: CurrentUserId) -> list[MealOption]:
    return make_meal_options()
