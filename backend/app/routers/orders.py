from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query

from app.dependencies import CurrentUserId
from app.realtime import EventName, hub
from app.schemas import CheckoutRequest, CheckoutResponse, Order
from app.schemas.order import OrderStatus
from app.stubs import make_order

router = APIRouter(tags=["orders"])


@router.post("/cart/{cart_id}/checkout", response_model=CheckoutResponse)
async def checkout(
    cart_id: uuid.UUID, payload: CheckoutRequest, user_id: CurrentUserId
) -> CheckoutResponse:
    order = make_order(cart_id=cart_id, store=payload.store)
    await hub.publish(
        user_id,
        EventName.ORDER_STATUS,
        {"order_id": str(order.id), "status": order.status},
    )
    return CheckoutResponse(
        order_id=order.id,
        payment_url=order.bunq_payment_url or "",
        amount_eur=order.total_eur,
    )


@router.get("/orders/{order_id}", response_model=Order)
async def get_order(order_id: uuid.UUID, user_id: CurrentUserId) -> Order:
    return make_order(cart_id=uuid.uuid4(), order_id=order_id)


@router.get("/orders", response_model=list[Order])
async def list_orders(
    user_id: CurrentUserId,
    status: Annotated[OrderStatus | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[Order]:
    sample = [
        make_order(cart_id=uuid.uuid4(), status=status or "ready_to_pay"),
        make_order(cart_id=uuid.uuid4(), status=status or "fulfilled"),
    ]
    return sample[:limit]
