from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Query

from app.dependencies import CurrentUserId
from app.schemas import (
    FavoriteToggleResponse,
    Recipe,
    RecipeGenerateRequest,
    RecipeListResponse,
    RecookResponse,
)
from app.stubs import make_recipe

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.post("/generate", response_model=Recipe)
async def generate(payload: RecipeGenerateRequest, user_id: CurrentUserId) -> Recipe:
    recipe = make_recipe()
    if payload.refine_of:
        recipe.parent_recipe_id = payload.refine_of
    return recipe


@router.get("/{recipe_id}", response_model=Recipe)
async def get_recipe(recipe_id: uuid.UUID, user_id: CurrentUserId) -> Recipe:
    return make_recipe(recipe_id=recipe_id)


@router.get("", response_model=RecipeListResponse)
async def list_recipes(
    user_id: CurrentUserId,
    favorited: bool | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> RecipeListResponse:
    sample = [make_recipe(name="Lemon Herb Chicken"), make_recipe(name="Tofu Stir Fry")]
    if favorited:
        for r in sample:
            r.favorited_at = datetime.now(UTC)
    return RecipeListResponse(recipes=sample[:limit], next_cursor=None)


@router.post("/{recipe_id}/favorite", response_model=FavoriteToggleResponse)
async def toggle_favorite(
    recipe_id: uuid.UUID, user_id: CurrentUserId
) -> FavoriteToggleResponse:
    return FavoriteToggleResponse(
        recipe_id=recipe_id, favorited=True, favorited_at=datetime.now(UTC)
    )


@router.post("/{recipe_id}/recook", response_model=RecookResponse)
async def recook(recipe_id: uuid.UUID, user_id: CurrentUserId) -> RecookResponse:
    return RecookResponse(cart_id=uuid.uuid4(), recipe_id=recipe_id)
