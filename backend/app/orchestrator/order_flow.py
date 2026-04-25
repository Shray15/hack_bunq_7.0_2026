"""Order orchestrator.

  * checkout(cart_id)        — refuse if no store selected; sum active items;
                                mint bunq URL via grocery-mcp; persist Order;
                                spawn bunq poller; emit ready_to_pay SSE.
  * get_order(order_id)
  * list_orders(...)

Per the Phase 3 plan, 'paid' is the terminal happy state — there is no
post-paid fulfillment step yet (place_order isn't exposed by grocery-mcp).
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import cast

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import grocery_mcp
from app.adapters.grocery_mcp import GroceryMcpError
from app.background.bunq_poll import poll_until_paid
from app.models import Cart as CartModel
from app.models import CartItem as CartItemModel
from app.models import Order as OrderModel
from app.realtime import EventName, hub
from app.schemas import CheckoutResponse, Order
from app.schemas.cart import Store
from app.schemas.order import OrderStatus

log = logging.getLogger(__name__)


async def checkout(
    *, db: AsyncSession, user_id: uuid.UUID, cart_id: uuid.UUID
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
    try:
        payload = await grocery_mcp.create_payment_request(amount, description)
    except GroceryMcpError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"grocery-mcp create_payment_request failed: {exc}",
        ) from exc

    request_id = str(payload.get("request_id") or "")
    payment_url = str(payload.get("payment_url") or "")
    if not request_id or not payment_url:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="grocery-mcp returned an incomplete payment payload",
        )

    order = OrderModel(
        owner_id=user_id,
        cart_id=cart_id,
        store=cart.selected_store,
        total_eur=round(amount, 2),
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
        {"order_id": str(order.id), "status": "ready_to_pay"},
    )

    asyncio.create_task(
        poll_until_paid(
            user_id=user_id,
            order_id=order.id,
            request_id=request_id,
        )
    )

    return CheckoutResponse(
        order_id=order.id,
        payment_url=payment_url,
        amount_eur=order.total_eur,
    )


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
    stmt = select(OrderModel).where(OrderModel.owner_id == user_id)
    if status_filter is not None:
        stmt = stmt.where(OrderModel.status == status_filter)
    stmt = stmt.order_by(OrderModel.created_at.desc()).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    return [_to_schema(r) for r in rows]


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


def _to_schema(row: OrderModel) -> Order:
    return Order(
        id=row.id,
        cart_id=row.cart_id,
        store=cast(Store, row.store),
        total_eur=row.total_eur,
        bunq_payment_url=row.bunq_payment_url,
        bunq_request_id=row.bunq_request_id,
        status=cast(OrderStatus, row.status),
        paid_at=row.paid_at,
        fulfilled_at=row.fulfilled_at,
        created_at=row.created_at,
    )
