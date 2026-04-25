from __future__ import annotations

import uuid

from fastapi import APIRouter

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import cart_flow
from app.schemas import (
    CartComparisonResponse,
    CartFromRecipeRequest,
    CartItem,
    CartItemPatch,
    CartItemsResponse,
    SelectStoreRequest,
)

router = APIRouter(prefix="/cart", tags=["cart"])


@router.post("/from-recipe", response_model=CartComparisonResponse)
async def from_recipe(
    payload: CartFromRecipeRequest, user_id: CurrentUserId, db: DbSession
) -> CartComparisonResponse:
    return await cart_flow.from_recipe(
        db=db,
        user_id=user_id,
        recipe_id=payload.recipe_id,
        people=payload.people,
    )


@router.post("/{cart_id}/select-store", response_model=CartItemsResponse)
async def select_store(
    cart_id: uuid.UUID,
    payload: SelectStoreRequest,
    user_id: CurrentUserId,
    db: DbSession,
) -> CartItemsResponse:
    return await cart_flow.select_store(
        db=db, user_id=user_id, cart_id=cart_id, store=payload.store
    )


@router.patch("/{cart_id}/items/{item_id}", response_model=CartItem)
async def patch_item(
    cart_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: CartItemPatch,
    user_id: CurrentUserId,
    db: DbSession,
) -> CartItem:
    return await cart_flow.patch_item(
        db=db,
        user_id=user_id,
        cart_id=cart_id,
        item_id=item_id,
        payload=payload,
    )
