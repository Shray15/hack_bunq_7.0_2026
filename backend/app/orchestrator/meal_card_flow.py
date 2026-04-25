"""Meal card orchestrator.

Owns the lifecycle of monthly bunq meal cards:

  * get_or_create_current — idempotent setup; one card per (user, month).
  * get_current            — current month's card with refreshed bunq balance.
  * topup                  — add more funds to the current month's card.
  * list_transactions      — recent payments on the bunq sub-account.
  * charge_for_order       — debit the card for an order checkout. Used by
                             order_flow when payment_method == "meal_card".

Bunq is the source of truth for balance; we cache `current_balance_eur` after
each mutation but always refresh on read.
"""

from __future__ import annotations

import calendar
import logging
import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters import bunq_cards
from app.models import MealCard as MealCardModel
from app.models import User
from app.schemas.meal_card import MealCardOut, MealCardTransactionOut

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


async def get_or_create_current(
    *, db: AsyncSession, user_id: uuid.UUID, monthly_budget_eur: float
) -> MealCardOut:
    """Return the current month's meal card, creating one in bunq if missing.

    Idempotent: if a card already exists for the user this month, returns it
    untouched (does NOT re-fund or change the budget). This prevents accidental
    double-creation if the iOS setup flow is retried."""
    month_year = _current_month_year()
    existing = await _load_for_month(db, user_id, month_year)
    if existing is not None:
        await _refresh_balance(db, existing)
        return _to_schema(existing)

    label = f"Meal Card {month_year}"
    sub = await bunq_cards.create_sub_account(label)
    sub_ma_id = int(sub["monetary_account_id"])

    try:
        await bunq_cards.fund_sub_account(
            sub_ma_id,
            monthly_budget_eur,
            description=f"Initial budget for {month_year}",
        )
    except Exception as exc:
        log.error("meal_card_funding_failed: ma=%s — %s", sub_ma_id, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"bunq sub-account funded failed: {exc}",
        ) from exc

    name_on_card = await _name_on_card_for(db, user_id)
    card_info = await bunq_cards.issue_virtual_card(sub_ma_id, name_on_card)

    balance = await bunq_cards.get_balance(sub_ma_id)

    row = MealCardModel(
        owner_id=user_id,
        bunq_monetary_account_id=sub_ma_id,
        bunq_card_id=card_info["card_id"] if card_info else None,
        iban=str(sub["iban"]),
        last_4=card_info["last_4"] if card_info else None,
        monthly_budget_eur=float(monthly_budget_eur),
        current_balance_eur=float(balance),
        month_year=month_year,
        status="active",
        expires_at=_end_of_month(month_year),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _to_schema(row)


async def get_current(
    *, db: AsyncSession, user_id: uuid.UUID
) -> MealCardOut | None:
    """Return current month's active card with a fresh balance, or None."""
    month_year = _current_month_year()
    row = await _load_for_month(db, user_id, month_year)
    if row is None:
        return None
    await _refresh_balance(db, row)
    return _to_schema(row)


async def topup(
    *, db: AsyncSession, user_id: uuid.UUID, amount_eur: float
) -> MealCardOut:
    row = await _require_current(db, user_id)
    try:
        result = await bunq_cards.fund_sub_account(
            row.bunq_monetary_account_id,
            amount_eur,
            description="Meal card top-up",
        )
    except Exception as exc:
        log.error("meal_card_topup_failed: ma=%s — %s", row.bunq_monetary_account_id, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"bunq topup failed: {exc}",
        ) from exc

    row.current_balance_eur = float(result["balance_after"])
    await db.commit()
    await db.refresh(row)
    return _to_schema(row)


async def list_transactions(
    *, db: AsyncSession, user_id: uuid.UUID, limit: int = 50
) -> list[MealCardTransactionOut]:
    row = await _require_current(db, user_id)
    items = await bunq_cards.list_card_transactions(
        row.bunq_monetary_account_id, count=limit
    )
    return [
        MealCardTransactionOut(
            id=str(item["id"]),
            amount_eur=float(item["amount_eur"]),
            description=str(item.get("description") or ""),
            created_at=_parse_dt(item.get("created_at")),
        )
        for item in items
    ]


async def charge_for_order(
    *,
    db: AsyncSession,
    user_id: uuid.UUID,
    amount_eur: float,
    description: str,
) -> tuple[MealCardModel, str]:
    """Charge the current month's meal card for an order.

    Validates balance, calls bunq, updates the cached balance, and returns
    (card_row, bunq_payment_id). Caller (order_flow.checkout) is responsible
    for persisting the Order row in the same transaction.

    Raises HTTPException(400) on insufficient balance, 502 on bunq failure."""
    row = await _require_current(db, user_id)

    # Trust the cached balance for the upfront check; bunq will reject the
    # payment if reality is different and we'll surface that as 502.
    if row.current_balance_eur + 1e-6 < amount_eur:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"insufficient meal-card balance: have €{row.current_balance_eur:.2f}, "
                f"need €{amount_eur:.2f}"
            ),
        )

    try:
        result = await bunq_cards.charge_card(
            row.bunq_monetary_account_id,
            amount_eur,
            description=description,
        )
    except Exception as exc:
        log.error(
            "meal_card_charge_failed: ma=%s amount=%s — %s",
            row.bunq_monetary_account_id,
            amount_eur,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"bunq meal-card charge failed: {exc}",
        ) from exc

    row.current_balance_eur = float(result["balance_after"])
    # Don't commit — caller will commit alongside the new Order row.
    return row, str(result["payment_id"])


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


async def _load_for_month(
    db: AsyncSession, owner_id: uuid.UUID, month_year: str
) -> MealCardModel | None:
    stmt = select(MealCardModel).where(
        MealCardModel.owner_id == owner_id,
        MealCardModel.month_year == month_year,
    )
    return (await db.execute(stmt)).scalar_one_or_none()


async def _require_current(
    db: AsyncSession, owner_id: uuid.UUID
) -> MealCardModel:
    row = await _load_for_month(db, owner_id, _current_month_year())
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="no active meal card for the current month",
        )
    return row


async def _refresh_balance(db: AsyncSession, row: MealCardModel) -> None:
    try:
        balance = await bunq_cards.get_balance(row.bunq_monetary_account_id)
    except Exception as exc:
        log.warning(
            "meal_card_refresh_balance_failed: ma=%s — %s; serving cached",
            row.bunq_monetary_account_id,
            exc,
        )
        return
    new_balance = float(balance)
    if abs(row.current_balance_eur - new_balance) > 1e-6:
        row.current_balance_eur = new_balance
        await db.commit()
        await db.refresh(row)


async def _name_on_card_for(db: AsyncSession, user_id: uuid.UUID) -> str:
    user = (
        await db.execute(select(User).where(User.id == user_id))
    ).scalar_one_or_none()
    if user is None or not getattr(user, "email", None):
        return "MEAL CARD HOLDER"
    # Take everything before '@', uppercase, swap punctuation for spaces.
    local = str(user.email).split("@", 1)[0].replace(".", " ").replace("_", " ")
    return local.upper()[:22] or "MEAL CARD HOLDER"


def _current_month_year() -> str:
    return datetime.now(UTC).strftime("%Y-%m")


def _end_of_month(month_year: str) -> datetime:
    year_str, month_str = month_year.split("-")
    year, month = int(year_str), int(month_str)
    last_day = calendar.monthrange(year, month)[1]
    return datetime(year, month, last_day, 23, 59, 59, tzinfo=UTC)


def _parse_dt(raw: object) -> datetime | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw
    try:
        return datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return None


def _to_schema(row: MealCardModel) -> MealCardOut:
    return MealCardOut.model_validate(row)
