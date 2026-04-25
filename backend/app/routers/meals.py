from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import meal_flow
from app.schemas import (
    MealLog,
    MealLogRequest,
    MealOption,
    MealsHistoryResponse,
    MealsTodayResponse,
)

router = APIRouter(prefix="/meals", tags=["meals"])


@router.post("/log", response_model=MealLog)
async def log_meal(
    payload: MealLogRequest, user_id: CurrentUserId, db: DbSession
) -> MealLog:
    return await meal_flow.log_meal(
        db=db,
        user_id=user_id,
        recipe_id=payload.recipe_id,
        portion=payload.portion,
        eaten_at=payload.eaten_at,
    )


@router.get("/today", response_model=MealsTodayResponse)
async def meals_today(
    user_id: CurrentUserId, db: DbSession
) -> MealsTodayResponse:
    return await meal_flow.meals_today(db=db, user_id=user_id)


@router.get("/history", response_model=MealsHistoryResponse)
async def meals_history(
    user_id: CurrentUserId,
    db: DbSession,
    from_: Annotated[datetime | None, Query(alias="from")] = None,
    to: Annotated[datetime | None, Query()] = None,
) -> MealsHistoryResponse:
    return await meal_flow.meals_history(db=db, user_id=user_id, from_=from_, to=to)


@router.get("/options", response_model=list[MealOption])
async def meal_options(
    user_id: CurrentUserId, db: DbSession
) -> list[MealOption]:
    return await meal_flow.meal_options(db=db, user_id=user_id)
