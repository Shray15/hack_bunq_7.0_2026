import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel, Macros

ImageStatus = Literal["pending", "ready", "failed"]
RecipeSource = Literal["chat", "meal_plan", "recook"]


class RecipeIngredient(AppModel):
    name: str
    qty: float
    unit: str
    notes: str | None = None


class RecipeConstraints(AppModel):
    calories_max: int | None = None
    protein_g_min: int | None = None
    carbs_g_max: int | None = None
    fat_g_max: int | None = None
    diet: str | None = None
    allergies: list[str] = []
    vibe: str | None = None
    must_use: list[str] = []
    avoid: list[str] = []


class Recipe(AppModel):
    id: uuid.UUID
    name: str
    summary: str | None = None
    prep_time_min: int
    ingredients: list[RecipeIngredient]
    steps: list[str]
    macros: Macros
    validated_macros: Macros | None = None
    image_url: str | None = None
    image_status: ImageStatus = "pending"
    source: RecipeSource = "chat"
    parent_recipe_id: uuid.UUID | None = None
    favorited_at: datetime | None = None
    created_at: datetime


class ChatRequest(AppModel):
    transcript: str = Field(min_length=1, max_length=2000)


class ChatAccepted(AppModel):
    chat_id: uuid.UUID
    accepted: bool = True


class RecipeGenerateRequest(AppModel):
    constraints: RecipeConstraints
    refine_of: uuid.UUID | None = None


class RecipeListResponse(AppModel):
    recipes: list[Recipe]
    next_cursor: str | None = None


class FavoriteToggleResponse(AppModel):
    recipe_id: uuid.UUID
    favorited: bool
    favorited_at: datetime | None


class RecookResponse(AppModel):
    cart_id: uuid.UUID
    recipe_id: uuid.UUID
