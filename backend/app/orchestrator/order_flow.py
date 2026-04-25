"""Order orchestrator.

  * checkout(cart_id, payment_method) — refuse if no store selected; sum active
                                          items; either mint a bunq.me URL via
                                          grocery-mcp (default) OR debit the
                                          user's monthly meal card. Persists
                                          Order, spawns bunq poller (bunq_me
                                          path only), emits SSE.
  * get_order(order_id)
  * list_orders(...)
  * autolog_meal_for_order(...)         — shared helper used by checkout
                                          (meal_card path) and bunq_poll
                                          (bunq_me path) to log a MealConsumed
                                          row when an order transitions to
                                          paid.

Per the Phase 3 plan, 'paid' is the terminal happy state — there is no
post-paid fulfillment step yet (place_order isn't exposed by grocery-mcp).
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import UTC, datetime
from typing import cast

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import bunq_me
from app.models import Cart as CartModel
from app.models import CartItem as CartItemModel
from app.models import MealConsumed
from app.models import Order as OrderModel
from app.models import Recipe as RecipeModel
from app.orchestrator import meal_card_flow
from app.orchestrator.cart_flow import commit_picnic_cart_safely
from app.realtime import EventName, hub
from app.schemas import CheckoutResponse, Order
from app.schemas.cart import Store
from app.schemas.common import Macros
from app.schemas.order import OrderStatus, PaymentMethod

log = logging.getLogger(__name__)


async def checkout(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    cart_id: uuid.UUID,
    payment_method: PaymentMethod = "bunq_me",
) -> CheckoutResponse:
    cart = await _load_cart(db, cart_id, user_id)
    if cart.selected_store is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="cart has no selected_store; call /cart/{id}/select-store first",
        )

    amount = await _active_total(db, cart_id, cart.selected_store)
    if amount <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="cart total is zero; nothing to pay for",
        )

    description = f"Groceries from {cart.selected_store.upper()}"

    if payment_method == "meal_card":
        return await _checkout_meal_card(
            db=db,
            user_id=user_id,
            cart=cart,
            amount=amount,
            description=description,
        )
    return await _checkout_bunq_me(
        db=db,
        user_id=user_id,
        cart=cart,
        amount=amount,
        description=description,
    )


# ---------------------------------------------------------------------------
# bunq.me path (existing — kept intact, just refactored into a helper).
# ---------------------------------------------------------------------------


async def _checkout_bunq_me(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    cart: CartModel,
    amount: float,
    description: str,
) -> CheckoutResponse:
    # Build a production bunq.me URL directly (no sandbox API). Sandbox URLs
    # don't open the real iDEAL flow, and the demo wants to show what a
    # customer would actually see in the browser. The order stays in
    # "ready_to_pay" until the user taps "I already paid" in the app, which
    # POSTs to /orders/{id}/mark-paid.
    payload = bunq_me.build_payment_url(amount, description)
    request_id = payload["request_id"]
    payment_url = payload["payment_url"]

    order = OrderModel(
        owner_id=user_id,
        cart_id=cart.id,
        store=cart.selected_store,
        total_eur=round(amount, 2),
        payment_method="bunq_me",
        bunq_request_id=request_id,
        bunq_payment_url=payment_url,
        status="ready_to_pay",
    )
    db.add(order)
    await db.commit()
    await db.refresh(order)

    await hub.publish(
        user_id,
        EventName.ORDER_STATUS,
        {
            "order_id": str(order.id),
            "status": "ready_to_pay",
            "payment_method": "bunq_me",
        },
    )

    if cart.selected_store == "picnic":
        active_items = await _active_picnic_items(db, cart.id)
        if active_items:
            asyncio.create_task(commit_picnic_cart_safely(active_items))

    return CheckoutResponse(
        order_id=order.id,
        payment_url=payment_url,
        amount_eur=order.total_eur,
        payment_method="bunq_me",
        status="ready_to_pay",
    )


# ---------------------------------------------------------------------------
# Meal-card path — synchronous: card is debited and order goes straight to
# 'paid' before we return. No bunq poller; no payment URL.
# ---------------------------------------------------------------------------


async def _checkout_meal_card(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    cart: CartModel,
    amount: float,
    description: str,
) -> CheckoutResponse:
    card_row, bunq_payment_id = await meal_card_flow.charge_for_order(
        db=db,
        user_id=user_id,
        amount_eur=amount,
        description=description,
    )

    paid_at = datetime.now(UTC)
    order = OrderModel(
        owner_id=user_id,
        cart_id=cart.id,
        store=cart.selected_store,
        total_eur=round(amount, 2),
        payment_method="meal_card",
        bunq_payment_id=bunq_payment_id,
        status="paid",
        paid_at=paid_at,
    )
    db.add(order)
    await autolog_meal_for_order(db, order)
    # Single commit for: updated card balance (set in charge_for_order) +
    # new Order row + MealConsumed row.
    await db.commit()
    await db.refresh(order)

    await hub.publish(
        user_id,
        EventName.ORDER_STATUS,
        {
            "order_id": str(order.id),
            "status": "paid",
            "paid_at": paid_at.isoformat(),
            "payment_method": "meal_card",
            "balance_after_eur": round(card_row.current_balance_eur, 2),
        },
    )

    if cart.selected_store == "picnic":
        active_items = await _active_picnic_items(db, cart.id)
        if active_items:
            asyncio.create_task(commit_picnic_cart_safely(active_items))

    return CheckoutResponse(
        order_id=order.id,
        payment_url=None,
        amount_eur=order.total_eur,
        payment_method="meal_card",
        status="paid",
    )


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


async def autolog_meal_for_order(db: AsyncSession, order: OrderModel) -> None:
    """Insert a meals_consumed row for the recipe behind a paid order.

    Called inline from the meal-card checkout path (which transitions to paid
    synchronously) and from bunq_poll on bunq.me paid events. Caller is
    responsible for committing the session."""
    cart = (
        await db.execute(select(CartModel).where(CartModel.id == order.cart_id))
    ).scalar_one_or_none()
    if cart is None:
        return
    recipe = (
        await db.execute(select(RecipeModel).where(RecipeModel.id == cart.recipe_id))
    ).scalar_one_or_none()
    if recipe is None:
        return
    macros = Macros.model_validate(recipe.macros)
    db.add(
        MealConsumed(
            owner_id=order.owner_id,
            recipe_id=recipe.id,
            portion=1.0,
            calories_computed=macros.calories,
            macros_computed=macros.model_dump(mode="json"),
            eaten_at=datetime.now(UTC),
            source="order",
        )
    )


async def _active_picnic_items(
    db: AsyncSession, cart_id: uuid.UUID
) -> list[dict[str, object]]:
    stmt = select(CartItemModel).where(
        CartItemModel.cart_id == cart_id,
        CartItemModel.store == "picnic",
        CartItemModel.removed_at.is_(None),
    )
    rows = list((await db.execute(stmt)).scalars().all())
    return [{"product_id": r.product_id, "qty": int(r.qty)} for r in rows]


async def mark_paid(
    *, db: AsyncSession, user_id: uuid.UUID, order_id: uuid.UUID
) -> Order:
    """Manual paid transition for the bunq.me path.

    With production bunq.me URLs we don't poll a sandbox tab anymore — the
    user taps 'I already paid' after the iDEAL flow completes in the browser
    and iOS calls this endpoint. Idempotent: returns the existing paid order
    if it's already paid; refuses anything that isn't currently
    `ready_to_pay`."""
    row = await _load_order(db, order_id, user_id)
    if row.status == "paid":
        return _to_schema(row)
    if row.status != "ready_to_pay":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"order is in status '{row.status}'; cannot mark paid",
        )

    row.status = "paid"
    row.paid_at = datetime.now(UTC)
    await autolog_meal_for_order(db, row)
    await db.commit()
    await db.refresh(row)

    await hub.publish(
        user_id,
        EventName.ORDER_STATUS,
        {
            "order_id": str(row.id),
            "status": "paid",
            "paid_at": row.paid_at.isoformat() if row.paid_at else None,
            "payment_method": row.payment_method,
        },
    )

    return _to_schema(row)


async def get_order(
    *, db: AsyncSession, user_id: uuid.UUID, order_id: uuid.UUID
) -> Order:
    row = await _load_order(db, order_id, user_id)
    return _to_schema(row)


async def list_orders(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    status_filter: OrderStatus | None,
    limit: int,
) -> list[Order]:
    # Outer-join to recipes via the cart so the history screen can show a
    # human-readable meal name without a follow-up fetch per row.
    stmt = (
        select(OrderModel, RecipeModel.name)
        .outerjoin(CartModel, CartModel.id == OrderModel.cart_id)
        .outerjoin(RecipeModel, RecipeModel.id == CartModel.recipe_id)
        .where(OrderModel.owner_id == user_id)
    )
    if status_filter is not None:
        stmt = stmt.where(OrderModel.status == status_filter)
    stmt = stmt.order_by(OrderModel.created_at.desc()).limit(limit)
    rows = (await db.execute(stmt)).all()
    return [_to_schema(order, recipe_name=name) for order, name in rows]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


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


async def _load_order(
    db: AsyncSession, order_id: uuid.UUID, owner_id: uuid.UUID
) -> OrderModel:
    stmt = select(OrderModel).where(
        OrderModel.id == order_id, OrderModel.owner_id == owner_id
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="order not found")
    return row


async def _active_total(db: AsyncSession, cart_id: uuid.UUID, store: str) -> float:
    stmt = select(CartItemModel).where(
        CartItemModel.cart_id == cart_id,
        CartItemModel.store == store,
        CartItemModel.removed_at.is_(None),
    )
    rows = list((await db.execute(stmt)).scalars().all())
    return round(sum(r.total_price_eur for r in rows), 2)


def _to_schema(row: OrderModel, recipe_name: str | None = None) -> Order:
    return Order(
        id=row.id,
        cart_id=row.cart_id,
        store=cast(Store, row.store),
        total_eur=row.total_eur,
        payment_method=cast(PaymentMethod, row.payment_method),
        bunq_payment_url=row.bunq_payment_url,
        bunq_request_id=row.bunq_request_id,
        bunq_payment_id=row.bunq_payment_id,
        status=cast(OrderStatus, row.status),
        paid_at=row.paid_at,
        fulfilled_at=row.fulfilled_at,
        created_at=row.created_at,
        recipe_name=recipe_name,
    )
