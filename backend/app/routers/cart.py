from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status

from app.dependencies import CurrentUserId
from app.realtime import EventName, hub
from app.schemas import Cart, CartFromRecipeRequest, CartItem, CartItemPatch
from app.stubs import make_cart

router = APIRouter(prefix="/cart", tags=["cart"])


@router.post("/from-recipe", response_model=Cart)
async def from_recipe(payload: CartFromRecipeRequest, user_id: CurrentUserId) -> Cart:
    cart = make_cart(recipe_id=payload.recipe_id)
    asyncio.create_task(
        hub.publish(
            user_id,
            EventName.CART_READY,
            {
                "cart_id": str(cart.id),
                "comparison": [c.model_dump(mode="json") for c in cart.comparison],
            },
        )
    )
    return cart


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
        product_name="AH Kipfilet 500g",
        qty=payload.qty if payload.qty is not None else 1,
        unit_price_eur=6.99,
        total_price_eur=(payload.qty or 1) * 6.99,
        removed_at=None,
    )
    if payload.removed:
        item.removed_at = datetime.now(UTC)
        item.total_price_eur = 0.0
    return item
