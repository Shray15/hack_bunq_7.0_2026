import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel, Macros

MealSource = Literal["order", "manual"]


class MealLog(AppModel):
    id: uuid.UUID
    recipe_id: uuid.UUID
    recipe_name: str
    portion: float
    calories_computed: int
    macros_computed: Macros
    eaten_at: datetime
    source: MealSource


class MealLogRequest(AppModel):
    recipe_id: uuid.UUID
    portion: float = Field(default=1.0, gt=0, le=10)
    eaten_at: datetime | None = None


class MealsTodayResponse(AppModel):
    date: date
    meals: list[MealLog]
    consumed: Macros
    target: Macros | None
    remaining: Macros | None


class MealsHistoryResponse(AppModel):
    meals: list[MealLog]


class MealOption(AppModel):
    recipe_id: uuid.UUID
    name: str
    macros: Macros
    last_seen_at: datetime
    reason: Literal["ordered", "prepared", "favorite"]
