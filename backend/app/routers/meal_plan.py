from __future__ import annotations

import asyncio

from fastapi import APIRouter

from app.dependencies import CurrentUserId
from app.realtime import EventName, hub
from app.schemas import MealPlan, MealPlanGenerateResponse
from app.stubs import make_meal_plan, make_recipe

router = APIRouter(prefix="/meal-plan", tags=["meal_plan"])


@router.post("/tomorrow", response_model=MealPlanGenerateResponse)
async def generate_tomorrow(user_id: CurrentUserId) -> MealPlanGenerateResponse:
    recipe = make_recipe(name="Salmon Teriyaki Bowl")
    plan = make_meal_plan(recipe=recipe)
    asyncio.create_task(
        hub.publish(
            user_id,
            EventName.MEAL_PLAN_READY,
            {"recipe_id": str(plan.recipe_id), "scheduled_for": plan.scheduled_for.isoformat()},
        )
    )
    return MealPlanGenerateResponse(plan=plan)


@router.get("/upcoming", response_model=list[MealPlan])
async def upcoming(user_id: CurrentUserId) -> list[MealPlan]:
    recipe = make_recipe(name="Salmon Teriyaki Bowl")
    return [make_meal_plan(recipe=recipe)]
