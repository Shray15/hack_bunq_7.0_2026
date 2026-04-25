import uuid
from datetime import date, datetime
from typing import Literal

from app.schemas.common import AppModel
from app.schemas.recipe import Recipe

MealPlanStatus = Literal["proposed", "accepted", "skipped"]


class MealPlan(AppModel):
    id: uuid.UUID
    recipe_id: uuid.UUID
    scheduled_for: date
    status: MealPlanStatus
    created_at: datetime
    recipe: Recipe | None = None


class MealPlanGenerateResponse(AppModel):
    plan: MealPlan
    accepted: bool = True
