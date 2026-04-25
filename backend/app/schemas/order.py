import uuid
from datetime import datetime
from typing import Literal

from app.schemas.cart import Store
from app.schemas.common import AppModel

OrderStatus = Literal[
    "draft",
    "ready_to_pay",
    "paid",
    "fulfilled",
    "payment_failed",
    "mcp_failed",
]


class Order(AppModel):
    id: uuid.UUID
    cart_id: uuid.UUID
    store: Store
    total_eur: float
    bunq_payment_url: str | None
    bunq_request_id: str | None
    status: OrderStatus
    paid_at: datetime | None
    fulfilled_at: datetime | None
    created_at: datetime


class CheckoutRequest(AppModel):
    cart_id: uuid.UUID


class CheckoutResponse(AppModel):
    order_id: uuid.UUID
    payment_url: str
    amount_eur: float
