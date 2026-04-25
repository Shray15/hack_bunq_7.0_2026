from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status

from app.dependencies import CurrentUserId
from app.realtime import EventName, hub
from app.schemas import (
    CartComparisonResponse,
    CartFromRecipeRequest,
    CartItem,
    CartItemPatch,
    CartItemsResponse,
    SelectStoreRequest,
)
from app.stubs import make_cart_items, make_comparison

router = APIRouter(prefix="/cart", tags=["cart"])


@router.post("/from-recipe", response_model=CartComparisonResponse)
async def from_recipe(
    payload: CartFromRecipeRequest, user_id: CurrentUserId
) -> CartComparisonResponse:
    cart_id = uuid.uuid4()
    comparison = make_comparison()
    asyncio.create_task(
        hub.publish(
            user_id,
            EventName.CART_READY,
            {
                "cart_id": str(cart_id),
                "comparison": [c.model_dump(mode="json") for c in comparison],
            },
        )
    )
    return CartComparisonResponse(
        cart_id=cart_id,
        recipe_id=payload.recipe_id,
        comparison=comparison,
    )


@router.post("/{cart_id}/select-store", response_model=CartItemsResponse)
async def select_store(
    cart_id: uuid.UUID, payload: SelectStoreRequest, user_id: CurrentUserId
) -> CartItemsResponse:
    items = make_cart_items(store=payload.store)
    total = round(sum(i.total_price_eur for i in items), 2)
    return CartItemsResponse(
        cart_id=cart_id,
        selected_store=payload.store,
        total_eur=total,
        items=items,
    )


@router.patch("/{cart_id}/items/{item_id}", response_model=CartItem)
async def patch_item(
    cart_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: CartItemPatch,
    user_id: CurrentUserId,
) -> CartItem:
    if payload.removed is None and payload.qty is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="provide either `removed` or `qty`",
        )
    item = CartItem(
        id=item_id,
        ingredient_name="chicken breast",
        store="ah",
        product_id="ah-7421",
        product_name="Kipfilet 500g",
        image_url="https://placehold.co/240x240/png?text=Kipfilet",
        qty=payload.qty if payload.qty is not None else 1,
        unit="500 g",
        unit_price_eur=6.99,
        total_price_eur=(payload.qty or 1) * 6.99,
        removed_at=None,
    )
    if payload.removed:
        item.removed_at = datetime.now(UTC)
        item.total_price_eur = 0.0
    return item
