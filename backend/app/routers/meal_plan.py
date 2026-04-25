from __future__ import annotations

from fastapi import APIRouter

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import meal_plan_flow
from app.schemas import MealPlan, MealPlanGenerateResponse

router = APIRouter(prefix="/meal-plan", tags=["meal_plan"])


@router.post("/tomorrow", response_model=MealPlanGenerateResponse)
async def generate_tomorrow(
    user_id: CurrentUserId, db: DbSession
) -> MealPlanGenerateResponse:
    return await meal_plan_flow.generate_for_tomorrow(db=db, user_id=user_id)


@router.get("/upcoming", response_model=list[MealPlan])
async def upcoming(user_id: CurrentUserId, db: DbSession) -> list[MealPlan]:
    return await meal_plan_flow.list_upcoming(db=db, user_id=user_id)
