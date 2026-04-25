"""Cart orchestrator.

Three responsibilities:

  * from_recipe(recipe_id, people)        — fan out search_products across
                                            AH + Picnic in parallel, persist
                                            cart + cart_items, return totals.
  * select_store(cart_id, store)          — flip selected_store, return the
                                            persisted item list for that store.
  * patch_item(cart_id, item_id, patch)   — mark removed / change qty.

Cross-user isolation: every read/write checks `owner_id`. Other users can't
see, mutate, or check out somebody else's cart.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import UTC, datetime
from typing import Any, cast

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import grocery_mcp
from app.adapters.grocery_mcp import GroceryMcpError
from app.models import Cart as CartModel
from app.models import CartItem as CartItemModel
from app.models import Recipe as RecipeModel
from app.realtime import EventName, hub
from app.schemas import (
    CartComparisonResponse,
    CartItem,
    CartItemPatch,
    CartItemsResponse,
    StoreComparison,
)
from app.schemas.cart import Store

log = logging.getLogger(__name__)


SUPPORTED_STORES: tuple[Store, ...] = ("ah", "picnic")


async def from_recipe(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    recipe_id: uuid.UUID,
    people: int,
) -> CartComparisonResponse:
    recipe = await _load_recipe(db, recipe_id, user_id)
    ingredients_payload = _ingredients_for_mcp(recipe.ingredients, people)

    try:
        results = await asyncio.gather(
            *(
                grocery_mcp.search_products(store, ingredients_payload)
                for store in SUPPORTED_STORES
            )
        )
    except GroceryMcpError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"grocery-mcp unavailable: {exc}",
        ) from exc

    cart = CartModel(
        owner_id=user_id,
        recipe_id=recipe_id,
        people=people,
        status="open",
        selected_store=None,
        missing_by_store={
            store: payload.get("missing", [])
            for store, payload in zip(SUPPORTED_STORES, results, strict=True)
        },
    )
    db.add(cart)
    await db.flush()  # populate cart.id before adding items

    for store, payload in zip(SUPPORTED_STORES, results, strict=True):
        for item in payload.get("items", []):
            db.add(_item_row_from_mcp(cart_id=cart.id, store=store, item=item))

    await db.commit()
    await db.refresh(cart)

    comparison = _build_comparison(results)
    asyncio.create_task(
        hub.publish(
            user_id,
            EventName.CART_READY,
            {
                "cart_id": str(cart.id),
                "comparison": [c.model_dump(mode="json") for c in comparison],
            },
        )
    )
    return CartComparisonResponse(
        cart_id=cart.id,
        recipe_id=recipe_id,
        comparison=comparison,
    )


async def select_store(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    cart_id: uuid.UUID,
    store: Store,
) -> CartItemsResponse:
    cart = await _load_cart(db, cart_id, user_id)
    cart.selected_store = store
    await db.commit()

    items_rows = await _load_cart_items(db, cart_id, store)
    items = [_to_schema(row) for row in items_rows]
    total = round(
        sum(row.total_price_eur for row in items_rows if row.removed_at is None),
        2,
    )
    return CartItemsResponse(
        cart_id=cart.id,
        selected_store=store,
        total_eur=total,
        items=items,
    )


async def patch_item(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    cart_id: uuid.UUID,
    item_id: uuid.UUID,
    payload: CartItemPatch,
) -> CartItem:
    if payload.removed is None and payload.qty is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="provide either `removed` or `qty`",
        )

    # Ownership check: the cart must belong to the user.
    await _load_cart(db, cart_id, user_id)

    stmt = select(CartItemModel).where(
        CartItemModel.id == item_id, CartItemModel.cart_id == cart_id
    )
    item = (await db.execute(stmt)).scalar_one_or_none()
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="cart item not found"
        )

    if payload.qty is not None:
        item.qty = payload.qty
        item.total_price_eur = round(item.unit_price_eur * payload.qty, 2)
    if payload.removed is True:
        item.removed_at = datetime.now(UTC)
    elif payload.removed is False:
        item.removed_at = None

    await db.commit()
    await db.refresh(item)
    return _to_schema(item)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _load_recipe(
    db: AsyncSession, recipe_id: uuid.UUID, owner_id: uuid.UUID
) -> RecipeModel:
    stmt = select(RecipeModel).where(
        RecipeModel.id == recipe_id, RecipeModel.owner_id == owner_id
    )
    recipe = (await db.execute(stmt)).scalar_one_or_none()
    if recipe is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="recipe not found"
        )
    return recipe


async def _load_cart(
    db: AsyncSession, cart_id: uuid.UUID, owner_id: uuid.UUID
) -> CartModel:
    stmt = select(CartModel).where(
        CartModel.id == cart_id, CartModel.owner_id == owner_id
    )
    cart = (await db.execute(stmt)).scalar_one_or_none()
    if cart is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="cart not found")
    return cart


async def _load_cart_items(
    db: AsyncSession, cart_id: uuid.UUID, store: Store
) -> list[CartItemModel]:
    stmt = (
        select(CartItemModel)
        .where(CartItemModel.cart_id == cart_id, CartItemModel.store == store)
        .order_by(CartItemModel.ingredient_name)
    )
    return list((await db.execute(stmt)).scalars().all())


def _ingredients_for_mcp(
    persisted_ingredients: list[dict[str, Any]], people: int
) -> list[dict[str, Any]]:
    """Strip notes, scale qty per `people`, leave the rest as-is."""
    out: list[dict[str, Any]] = []
    for raw in persisted_ingredients:
        name = raw.get("name")
        qty = raw.get("qty", 1)
        unit = raw.get("unit", "")
        if not name:
            continue
        try:
            qty_scaled = float(qty) * max(1, people)
        except (TypeError, ValueError):
            qty_scaled = 1.0
        out.append({"name": name, "qty": qty_scaled, "unit": unit})
    return out


def _item_row_from_mcp(
    *, cart_id: uuid.UUID, store: Store, item: dict[str, Any]
) -> CartItemModel:
    qty = float(item.get("qty", 1) or 1)
    price = float(item.get("price_eur", 0) or 0)
    image_url = item.get("image_url")
    unit = item.get("unit")
    return CartItemModel(
        cart_id=cart_id,
        store=store,
        ingredient_name=str(item.get("ingredient", "")),
        product_id=str(item.get("product_id", "")),
        product_name=str(item.get("name", "")),
        image_url=image_url if isinstance(image_url, str) else None,
        qty=qty,
        unit=unit if isinstance(unit, str) else None,
        unit_price_eur=price,
        total_price_eur=round(price * qty, 2),
    )


def _build_comparison(results: list[dict[str, Any]]) -> list[StoreComparison]:
    rows: list[StoreComparison] = []
    for store, payload in zip(SUPPORTED_STORES, results, strict=True):
        items = payload.get("items") or []
        missing_raw = payload.get("missing") or []
        missing: list[str] = [str(m) for m in missing_raw] if isinstance(missing_raw, list) else []
        total = float(payload.get("total_eur") or 0)
        rows.append(
            StoreComparison(
                store=store,
                total_eur=round(total, 2),
                item_count=len(items) if isinstance(items, list) else 0,
                missing=missing,
                missing_count=len(missing),
            )
        )
    return rows


def _to_schema(row: CartItemModel) -> CartItem:
    return CartItem(
        id=row.id,
        ingredient_name=row.ingredient_name,
        store=cast(Store, row.store),
        product_id=row.product_id,
        product_name=row.product_name,
        image_url=row.image_url,
        qty=row.qty,
        unit=row.unit,
        unit_price_eur=row.unit_price_eur,
        total_price_eur=row.total_price_eur,
        removed_at=row.removed_at,
    )
