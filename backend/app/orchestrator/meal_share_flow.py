"""Meal-share orchestrator.

Generates a 'split the cost' bunq.me link for a paid order. The link is
fixed-amount per person, minted via the existing MCP `create_payment_request`
(which now uses BunqMeTab — see Phase 0 fix). One MealShare row is created
per (order, participant_count) combo so re-opening the same split returns the
same URL instead of creating duplicates.
"""

from __future__ import annotations

import logging
import uuid
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import grocery_mcp
from app.adapters.grocery_mcp import GroceryMcpError
from app.models import Cart as CartModel
from app.models import MealShare as MealShareModel
from app.models import Order as OrderModel
from app.models import Recipe as RecipeModel
from app.schemas.meal_share import ShareCostOut, ShareStatus

log = logging.getLogger(__name__)

# bunq BunqMeTab status (from MCP) -> our share status. Anything not paid yet
# is "open" so the share UI keeps the "share with friends" state showing.
_SHARE_STATUS_MAP: dict[str, ShareStatus] = {
    "paid": "closed",
    "rejected": "closed",
    "expired": "closed",
}


async def create_share(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    order_id: uuid.UUID,
    participant_count: int,
    include_self: bool,
) -> ShareCostOut:
    """Create (or return existing) split-cost link for `order_id`."""
    order = await _load_paid_order(db, order_id, user_id)
    divisor = participant_count + (1 if include_self else 0)
    if divisor < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="splitting requires at least 2 people",
        )

    per_person = _round_half_up(order.total_eur / divisor)

    # Idempotency: if there's already an open share for this (order,
    # participant_count, include_self), return it untouched.
    existing = await _find_existing(
        db, order_id, participant_count, include_self
    )
    if existing is not None and existing.status == "open":
        return _to_schema(existing)

    description = await _share_description(db, order)
    try:
        payload = await grocery_mcp.create_payment_request(
            float(per_person), description
        )
    except GroceryMcpError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"grocery-mcp create_payment_request failed: {exc}",
        ) from exc

    request_id = str(payload.get("request_id") or "")
    share_url = str(payload.get("payment_url") or "")
    if not share_url:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="grocery-mcp returned no share URL",
        )

    row = MealShareModel(
        order_id=order.id,
        owner_id=user_id,
        participant_count=participant_count,
        include_self=include_self,
        per_person_eur=float(per_person),
        total_eur=float(order.total_eur),
        bunq_request_id=request_id or None,
        share_url=share_url,
        status="open",
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _to_schema(row)


async def get_latest_share(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    order_id: uuid.UUID,
    refresh_status: bool = True,
) -> ShareCostOut | None:
    """Return the most recent share for this order, refreshing bunq status."""
    await _load_paid_order(db, order_id, user_id)

    stmt = (
        select(MealShareModel)
        .where(
            MealShareModel.order_id == order_id,
            MealShareModel.owner_id == user_id,
        )
        .order_by(MealShareModel.created_at.desc())
        .limit(1)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        return None

    if refresh_status and row.status == "open" and row.bunq_request_id:
        await _maybe_close_share(db, row)

    return _to_schema(row)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _load_paid_order(
    db: AsyncSession, order_id: uuid.UUID, owner_id: uuid.UUID
) -> OrderModel:
    stmt = select(OrderModel).where(
        OrderModel.id == order_id, OrderModel.owner_id == owner_id
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="order not found"
        )
    if row.status != "paid":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "order is not paid yet; share-cost is available after the "
                "order transitions to paid"
            ),
        )
    return row


async def _find_existing(
    db: AsyncSession,
    order_id: uuid.UUID,
    participant_count: int,
    include_self: bool,
) -> MealShareModel | None:
    stmt = (
        select(MealShareModel)
        .where(
            MealShareModel.order_id == order_id,
            MealShareModel.participant_count == participant_count,
            MealShareModel.include_self == include_self,
        )
        .order_by(MealShareModel.created_at.desc())
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


async def _share_description(db: AsyncSession, order: OrderModel) -> str:
    """Build a friendly bunq.me description like 'Your share of Pad Thai'."""
    cart = (
        await db.execute(select(CartModel).where(CartModel.id == order.cart_id))
    ).scalar_one_or_none()
    if cart is None:
        return "Your share of dinner"
    recipe = (
        await db.execute(select(RecipeModel).where(RecipeModel.id == cart.recipe_id))
    ).scalar_one_or_none()
    if recipe is None or not recipe.name:
        return "Your share of dinner"
    return f"Your share of {recipe.name}"


async def _maybe_close_share(db: AsyncSession, row: MealShareModel) -> None:
    """One-shot bunq status check; flip to 'closed' on terminal state."""
    if row.bunq_request_id is None:
        return
    try:
        payload = await grocery_mcp.get_payment_status(row.bunq_request_id)
    except GroceryMcpError as exc:
        log.warning("share_status_check_failed: share=%s — %s", row.id, exc)
        return
    bunq_status = str(payload.get("status", "pending")).lower()
    new_status = _SHARE_STATUS_MAP.get(bunq_status, "open")
    if new_status != row.status:
        row.status = new_status
        await db.commit()


def _round_half_up(value: float) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _to_schema(row: MealShareModel) -> ShareCostOut:
    return ShareCostOut.model_validate(row)
