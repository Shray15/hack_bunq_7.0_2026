from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.dependencies import CurrentUser, DbSession
from app.models import Recipe as RecipeModel
from app.orchestrator.chat_flow import run_generate_flow
from app.schemas import (
    FavoriteToggleResponse,
    Profile,
    Recipe,
    RecipeGenerateRequest,
    RecipeListResponse,
    RecookResponse,
)
from app.schemas.common import Macros
from app.schemas.recipe import RecipeIngredient
from app.services.rate_limit import enforce_chat_rate_limit

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.post("/generate", response_model=Recipe)
async def generate(
    payload: RecipeGenerateRequest, user: CurrentUser
) -> Recipe:
    enforce_chat_rate_limit(user.id)
    if user.profile is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="profile missing — call PATCH /user/profile first",
        )
    profile = Profile.model_validate(user.profile)
    recipe = await run_generate_flow(
        user_id=user.id,
        constraints=payload.constraints,
        profile=profile,
        parent_recipe_id=payload.refine_of,
    )
    if recipe is None:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="recipe generation failed (see SSE error event)",
        )
    return recipe


@router.get("/{recipe_id}", response_model=Recipe)
async def get_recipe(
    recipe_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> Recipe:
    row = await _load_owned(db, recipe_id, user.id)
    return _row_to_schema(row)


@router.get("", response_model=RecipeListResponse)
async def list_recipes(
    user: CurrentUser,
    db: DbSession,
    favorited: bool | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> RecipeListResponse:
    stmt = select(RecipeModel).where(RecipeModel.owner_id == user.id)
    if favorited is True:
        stmt = stmt.where(RecipeModel.favorited_at.is_not(None)).order_by(
            RecipeModel.favorited_at.desc()
        )
    elif favorited is False:
        stmt = stmt.where(RecipeModel.favorited_at.is_(None)).order_by(
            RecipeModel.created_at.desc()
        )
    else:
        stmt = stmt.order_by(RecipeModel.created_at.desc())
    stmt = stmt.limit(limit)

    rows = (await db.execute(stmt)).scalars().all()
    return RecipeListResponse(
        recipes=[_row_to_schema(r) for r in rows], next_cursor=None
    )


@router.post("/{recipe_id}/favorite", response_model=FavoriteToggleResponse)
async def toggle_favorite(
    recipe_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> FavoriteToggleResponse:
    row = await _load_owned(db, recipe_id, user.id)
    if row.favorited_at is None:
        row.favorited_at = datetime.now(UTC)
    else:
        row.favorited_at = None
    await db.commit()
    return FavoriteToggleResponse(
        recipe_id=row.id,
        favorited=row.favorited_at is not None,
        favorited_at=row.favorited_at,
    )


@router.post("/{recipe_id}/recook", response_model=RecookResponse)
async def recook(
    recipe_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> RecookResponse:
    row = await _load_owned(db, recipe_id, user.id)
    # Phase 3 will materialise a real cart here. For now, return the recipe id
    # and a fresh cart_id that the cart router will accept when called next.
    return RecookResponse(cart_id=uuid.uuid4(), recipe_id=row.id)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


async def _load_owned(
    db: DbSession, recipe_id: uuid.UUID, owner_id: uuid.UUID
) -> RecipeModel:
    stmt = select(RecipeModel).where(
        RecipeModel.id == recipe_id, RecipeModel.owner_id == owner_id
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="recipe not found")
    return row


def _row_to_schema(row: RecipeModel) -> Recipe:
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
