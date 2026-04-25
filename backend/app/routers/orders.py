from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query

from app.dependencies import CurrentUserId, DbSession
from app.orchestrator import order_flow
from app.schemas import CheckoutRequest, CheckoutResponse, Order
from app.schemas.order import OrderStatus

router = APIRouter(tags=["orders"])


@router.post("/order/checkout", response_model=CheckoutResponse)
async def checkout(
    payload: CheckoutRequest, user_id: CurrentUserId, db: DbSession
) -> CheckoutResponse:
    return await order_flow.checkout(
        db=db,
        user_id=user_id,
        cart_id=payload.cart_id,
        payment_method=payload.payment_method,
    )


@router.get("/orders/{order_id}", response_model=Order)
async def get_order(
    order_id: uuid.UUID, user_id: CurrentUserId, db: DbSession
) -> Order:
    return await order_flow.get_order(db=db, user_id=user_id, order_id=order_id)


@router.get("/orders", response_model=list[Order])
async def list_orders(
    user_id: CurrentUserId,
    db: DbSession,
    status: Annotated[OrderStatus | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[Order]:
    return await order_flow.list_orders(
        db=db, user_id=user_id, status_filter=status, limit=limit
    )
