"""bunq payment status poller.

Started by `order_flow.checkout`. Polls grocery-mcp's `get_payment_status`
every `BUNQ_POLL_INTERVAL_SECONDS` for up to `BUNQ_POLL_MAX_SECONDS`. On
status='paid' it transitions the order, persists `paid_at`, and pushes an
`order_status` SSE event. On expired/rejected/timeout it transitions to a
terminal error state and pushes the same event so iOS can react.

The poller cancels itself if the order has already moved past `ready_to_pay`
(e.g. someone else flipped the row), so we don't fight other writers.
"""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from datetime import UTC, datetime

from sqlalchemy import select

from app.adapters import grocery_mcp
from app.adapters.grocery_mcp import GroceryMcpError
from app.config import settings
from app.db import SessionLocal
from app.models import Order
from app.realtime import EventName, hub

log = logging.getLogger(__name__)

_TERMINAL_STATUSES = {"paid", "payment_failed"}


async def poll_until_paid(
    *, user_id: uuid.UUID, order_id: uuid.UUID, request_id: str
) -> None:
    deadline = time.monotonic() + settings.bunq_poll_max_seconds
    interval = max(0.1, settings.bunq_poll_interval_seconds)

    while time.monotonic() < deadline:
        try:
            status_payload = await grocery_mcp.get_payment_status(request_id)
        except GroceryMcpError as exc:
            log.warning("bunq_poll_mcp_error: order=%s — %s", order_id, exc)
            await asyncio.sleep(interval)
            continue

        bunq_status = str(status_payload.get("status", "pending")).lower()
        log.debug("bunq_poll: order=%s status=%s", order_id, bunq_status)

        if bunq_status == "paid":
            await _transition(order_id, user_id, "paid", paid=True)
            return
        if bunq_status in {"rejected", "expired"}:
            await _transition(order_id, user_id, "payment_failed", paid=False)
            return
        if not await _is_still_ready_to_pay(order_id):
            log.info("bunq_poll_cancelled: order=%s no longer ready_to_pay", order_id)
            return

        await asyncio.sleep(interval)

    await _transition(order_id, user_id, "payment_failed", paid=False)


async def _transition(
    order_id: uuid.UUID, user_id: uuid.UUID, new_status: str, *, paid: bool
) -> None:
    # Lazy import: order_flow imports bunq_poll at module load, so we can't
    # import it at the top of this file without a circular import.
    from app.orchestrator.order_flow import autolog_meal_for_order

    async with SessionLocal() as db:
        row = (
            await db.execute(select(Order).where(Order.id == order_id))
        ).scalar_one_or_none()
        if row is None:
            return
        if row.status in _TERMINAL_STATUSES:
            # Someone else got here first — don't double-publish.
            return
        row.status = new_status
        if paid:
            row.paid_at = datetime.now(UTC)
            await autolog_meal_for_order(db, row)
        await db.commit()
        await db.refresh(row)

    payload: dict[str, str | None] = {
        "order_id": str(order_id),
        "status": new_status,
        "payment_method": "bunq_me",
    }
    if paid:
        payload["paid_at"] = row.paid_at.isoformat() if row.paid_at else None
    await hub.publish(user_id, EventName.ORDER_STATUS, payload)


async def _is_still_ready_to_pay(order_id: uuid.UUID) -> bool:
    async with SessionLocal() as db:
        row = (
            await db.execute(select(Order).where(Order.id == order_id))
        ).scalar_one_or_none()
        return row is not None and row.status == "ready_to_pay"
