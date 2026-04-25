"""Substitution orchestrator.

After the initial cart fan-out, every missing ingredient gets one chance:

  1. Ask Claude for up to 3 alternatives at this store.
  2. Probe grocery-mcp.search_products with each alternative in order.
  3. On the first hit, add the alternative as a CartItem at that store and
     drop the ingredient from cart.missing_by_store[store].

Cap = one substitution per missing ingredient. Emits per-substitution
`substitution_proposed` events (informational) and one `cart_ready` event at
the end with the updated comparison if anything changed.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import claude, grocery_mcp
from app.adapters.grocery_mcp import GroceryMcpError
from app.db import SessionLocal
from app.models import Cart as CartModel
from app.models import CartItem as CartItemModel
from app.models import Recipe as RecipeModel
from app.realtime import EventName, hub
from app.schemas import StoreComparison

log = logging.getLogger(__name__)


async def run_substitution_flow(*, user_id: uuid.UUID, cart_id: uuid.UUID) -> None:
    async with SessionLocal() as db:
        cart = (
            await db.execute(
                select(CartModel).where(
                    CartModel.id == cart_id, CartModel.owner_id == user_id
                )
            )
        ).scalar_one_or_none()
        if cart is None:
            return
        recipe = (
            await db.execute(select(RecipeModel).where(RecipeModel.id == cart.recipe_id))
        ).scalar_one_or_none()
        dish_name = recipe.name if recipe else "this dish"

        per_store_missing = {
            str(store): list(items)
            for store, items in (cart.missing_by_store or {}).items()
            if isinstance(items, list)
        }

        any_substitution = False
        for store, ingredients in per_store_missing.items():
            for ingredient in list(ingredients):
                hit = await _try_one_substitution(
                    db=db,
                    cart=cart,
                    store=store,
                    ingredient=ingredient,
                    dish_name=dish_name,
                    user_id=user_id,
                )
                if hit:
                    any_substitution = True

        if any_substitution:
            comparison = await _recompute_comparison(db, cart_id)
            await hub.publish(
                user_id,
                EventName.CART_READY,
                {
                    "cart_id": str(cart_id),
                    "comparison": [c.model_dump(mode="json") for c in comparison],
                },
            )


async def _try_one_substitution(
    *,
    db: AsyncSession,
    cart: CartModel,
    store: str,
    ingredient: str,
    dish_name: str,
    user_id: uuid.UUID,
) -> bool:
    try:
        alternatives = await claude.suggest_substitutions(
            ingredient=ingredient, dish_name=dish_name, store=store
        )
    except Exception as exc:  # noqa: BLE001 — never let a Bedrock error kill the task
        log.warning("substitution_llm_failed: %s/%s — %s", store, ingredient, exc)
        return False

    for alt in alternatives:
        try:
            payload = await grocery_mcp.search_products(
                store, [{"name": alt, "qty": 1, "unit": "pc"}]
            )
        except GroceryMcpError as exc:
            log.warning(
                "substitution_mcp_failed: %s/%s/%s — %s", store, ingredient, alt, exc
            )
            continue

        items = payload.get("items") or []
        if not items:
            continue

        first = items[0]
        await _persist_substitution(
            db=db,
            cart=cart,
            store=store,
            original=ingredient,
            substitute=alt,
            mcp_item=first,
        )
        await hub.publish(
            user_id,
            EventName.SUBSTITUTION_PROPOSED,
            {
                "cart_id": str(cart.id),
                "store": store,
                "original": ingredient,
                "substitute": alt,
                "product_id": str(first.get("product_id", "")),
            },
        )
        return True

    return False


async def _persist_substitution(
    *,
    db: AsyncSession,
    cart: CartModel,
    store: str,
    original: str,
    substitute: str,
    mcp_item: dict[str, Any],
) -> None:
    qty = float(mcp_item.get("qty", 1) or 1)
    price = float(mcp_item.get("price_eur", 0) or 0)
    image_url = mcp_item.get("image_url")
    unit = mcp_item.get("unit")
    db.add(
        CartItemModel(
            cart_id=cart.id,
            store=store,
            ingredient_name=substitute,
            product_id=str(mcp_item.get("product_id", "")),
            product_name=str(mcp_item.get("name", "")),
            image_url=image_url if isinstance(image_url, str) else None,
            qty=qty,
            unit=unit if isinstance(unit, str) else None,
            unit_price_eur=price,
            total_price_eur=round(price * qty, 2),
        )
    )

    # Drop the original ingredient from the per-store missing list.
    current = list(cart.missing_by_store.get(store, []))
    if original in current:
        current.remove(original)
    new_state = dict(cart.missing_by_store)
    new_state[store] = current
    cart.missing_by_store = new_state
    await db.commit()


async def _recompute_comparison(
    db: AsyncSession, cart_id: uuid.UUID
) -> list[StoreComparison]:
    cart = (
        await db.execute(select(CartModel).where(CartModel.id == cart_id))
    ).scalar_one()

    rows: list[StoreComparison] = []
    for store in ("ah", "picnic"):
        stmt = select(
            func.count(CartItemModel.id),
            func.coalesce(func.sum(CartItemModel.total_price_eur), 0.0),
        ).where(
            CartItemModel.cart_id == cart_id,
            CartItemModel.store == store,
            CartItemModel.removed_at.is_(None),
        )
        count, total = (await db.execute(stmt)).one()
        missing = list(cart.missing_by_store.get(store, []))
        rows.append(
            StoreComparison(
                store=store,
                total_eur=round(float(total), 2),
                item_count=int(count),
                missing=missing,
                missing_count=len(missing),
            )
        )
    return rows
