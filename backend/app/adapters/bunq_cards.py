"""bunq sandbox cards & sub-accounts adapter.

Talks directly to the bunq SDK — NOT through MCP — because cards aren't an
LLM-callable tool, they're a user feature. The MCP server keeps owning the
bunq.me payment-link flow (`mcp/bunq_payment.py`).

Auth context is the same `bunq_sandbox.conf` that the MCP server's bootstrap
script writes. On EC2 both containers must mount the same `BUNQ_DATA_DIR`
volume so they share the conf and `account_id` sidecar.

Public API is `async`. The bunq SDK is synchronous, so each call wraps the
SDK in `asyncio.to_thread` to keep the FastAPI event loop free.
"""

from __future__ import annotations

import asyncio
import logging
import os
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path
from typing import Any

from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import (
    CardApiObject,
    CardDebitApiObject,
    MonetaryAccountBankApiObject,
    PaymentApiObject,
)
from bunq.sdk.model.generated.object_ import (
    AmountObject,
    PointerObject,
)

log = logging.getLogger(__name__)

DATA_DIR = Path(os.getenv("BUNQ_DATA_DIR", "."))
CONF_FILE = str(DATA_DIR / "bunq_sandbox.conf")
ACCOUNT_ID_FILE = DATA_DIR / "account_id"


class BunqCardsError(RuntimeError):
    """Raised on any bunq adapter failure callers should surface as 5xx/4xx."""


# ---------------------------------------------------------------------------
# Sync helpers — internal. Routers should never call these directly.
# ---------------------------------------------------------------------------


def _format_eur(amount_eur: Decimal | float | int) -> str:
    amount = Decimal(str(amount_eur)).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )
    if amount <= 0:
        raise ValueError("amount must be greater than 0")
    return f"{amount:.2f}"


def _resolve_primary_account_id() -> int:
    if ACCOUNT_ID_FILE.exists():
        return int(ACCOUNT_ID_FILE.read_text().strip())
    env_val = os.getenv("BUNQ_ACCOUNT_ID")
    if env_val and env_val != "0":
        return int(env_val)
    raise BunqCardsError(
        f"BUNQ_ACCOUNT_ID not configured: no sidecar at {ACCOUNT_ID_FILE} "
        "and BUNQ_ACCOUNT_ID env var unset. Run mcp/scripts/bootstrap_bunq.py "
        "and ensure backend mounts the same BUNQ_DATA_DIR volume."
    )


def _load_context() -> None:
    ctx = ApiContext.restore(CONF_FILE)
    BunqContext.load_api_context(ctx)


def _account_iban(account: Any) -> str:
    """Pull the IBAN out of a MonetaryAccountBank's alias list."""
    aliases = getattr(account, "alias", None) or []
    for alias in aliases:
        if getattr(alias, "type_", None) == "IBAN":
            return alias.value
    raise BunqCardsError(f"no IBAN alias on monetary account {account.id_}")


def _balance_decimal(account: Any) -> Decimal:
    balance = getattr(account, "balance", None)
    if balance is None:
        raise BunqCardsError(f"no balance on account {account.id_}")
    return Decimal(str(balance.value)).quantize(Decimal("0.01"))


# ---------------------------------------------------------------------------
# Sync ops — wrapped by the async public API below.
# ---------------------------------------------------------------------------


def _create_sub_account_sync(label: str, currency: str = "EUR") -> dict[str, Any]:
    _load_context()
    new_id = MonetaryAccountBankApiObject.create(
        currency=currency,
        description=label,
    ).value
    account = MonetaryAccountBankApiObject.get(monetary_account_id=new_id).value
    return {
        "monetary_account_id": int(new_id),
        "iban": _account_iban(account),
        "status": str(getattr(account, "status", "ACTIVE")),
    }


def _fund_sub_account_sync(
    monetary_account_id: int,
    amount_eur: Decimal | float,
    description: str,
) -> dict[str, Any]:
    _load_context()
    primary_id = _resolve_primary_account_id()
    amount = _format_eur(amount_eur)

    sub = MonetaryAccountBankApiObject.get(
        monetary_account_id=monetary_account_id
    ).value
    sub_iban = _account_iban(sub)
    sub_name = getattr(sub, "description", None) or "Meal card"

    payment_id = PaymentApiObject.create(
        amount=AmountObject(amount, "EUR"),
        counterparty_alias=PointerObject("IBAN", sub_iban, name=sub_name),
        description=description,
        monetary_account_id=primary_id,
    ).value

    refreshed = MonetaryAccountBankApiObject.get(
        monetary_account_id=monetary_account_id
    ).value
    return {
        "payment_id": int(payment_id),
        "balance_after": _balance_decimal(refreshed),
    }


def _issue_virtual_card_sync(
    monetary_account_id: int,
    name_on_card: str,
) -> dict[str, Any] | None:
    """Best-effort virtual card issuance. Returns None on sandbox failure
    so the caller can still ship a sub-account-only meal card."""
    _load_context()

    try:
        card_id = CardDebitApiObject.create(
            name_on_card=name_on_card,
            type_="VIRTUAL",
            second_line="MEAL CARD",
            monetary_account_id_fallback=monetary_account_id,
        ).value
    except Exception as exc:
        # TODO: revisit if sandbox card creation requires explicit PIN
        # assignment or a physical-card order flow.
        log.warning(
            "bunq sandbox virtual card creation failed (%s); "
            "meal card will operate as sub-account-only",
            exc,
        )
        return None

    try:
        card = CardApiObject.get(card_id=card_id).value
        last_4 = (
            getattr(card, "primary_account_number_four_digit", None)
            or getattr(card, "four_digit", None)
            or "0000"
        )
        status = str(getattr(card, "status", "ACTIVE"))
    except Exception as exc:
        log.warning(
            "card created (id=%s) but follow-up get failed: %s",
            card_id,
            exc,
        )
        last_4 = "0000"
        status = "ACTIVE"

    return {
        "card_id": int(card_id),
        "last_4": str(last_4),
        "status": status,
    }


def _get_balance_sync(monetary_account_id: int) -> Decimal:
    _load_context()
    account = MonetaryAccountBankApiObject.get(
        monetary_account_id=monetary_account_id
    ).value
    return _balance_decimal(account)


def _charge_card_sync(
    monetary_account_id: int,
    amount_eur: Decimal | float,
    description: str,
) -> dict[str, Any]:
    """Simulate a merchant charge: move money from the meal-card sub-account
    back to the primary account."""
    _load_context()
    primary_id = _resolve_primary_account_id()
    amount = _format_eur(amount_eur)

    primary = MonetaryAccountBankApiObject.get(
        monetary_account_id=primary_id
    ).value
    primary_iban = _account_iban(primary)
    primary_name = getattr(primary, "description", None) or "Primary"

    payment_id = PaymentApiObject.create(
        amount=AmountObject(amount, "EUR"),
        counterparty_alias=PointerObject("IBAN", primary_iban, name=primary_name),
        description=description,
        monetary_account_id=monetary_account_id,
    ).value

    refreshed = MonetaryAccountBankApiObject.get(
        monetary_account_id=monetary_account_id
    ).value
    return {
        "payment_id": int(payment_id),
        "balance_after": _balance_decimal(refreshed),
    }


def _list_card_transactions_sync(
    monetary_account_id: int,
    count: int = 50,
) -> list[dict[str, Any]]:
    _load_context()

    payments = PaymentApiObject.list(
        monetary_account_id=monetary_account_id,
        params={"count": str(count)},
    ).value

    out: list[dict[str, Any]] = []
    for p in payments:
        amt = getattr(p, "amount", None)
        if amt is None:
            continue
        out.append(
            {
                "id": str(p.id_),
                "amount_eur": Decimal(str(amt.value)).quantize(Decimal("0.01")),
                "description": getattr(p, "description", "") or "",
                "created_at": getattr(p, "created", None),
            }
        )
    return out


# ---------------------------------------------------------------------------
# Public async API.
# ---------------------------------------------------------------------------


async def create_sub_account(label: str, currency: str = "EUR") -> dict[str, Any]:
    """Create a new bunq sub-account for a meal-card budget."""
    return await asyncio.to_thread(_create_sub_account_sync, label, currency)


async def fund_sub_account(
    monetary_account_id: int,
    amount_eur: Decimal | float,
    description: str = "Meal card top-up",
) -> dict[str, Any]:
    """Move money from the primary account into the meal-card sub-account."""
    return await asyncio.to_thread(
        _fund_sub_account_sync, monetary_account_id, amount_eur, description
    )


async def issue_virtual_card(
    monetary_account_id: int,
    name_on_card: str,
) -> dict[str, Any] | None:
    """Issue a virtual debit card linked to the sub-account.

    Returns None on sandbox card-creation failure; callers should treat the
    meal card as still-valid (sub-account funds remain spendable)."""
    return await asyncio.to_thread(
        _issue_virtual_card_sync, monetary_account_id, name_on_card
    )


async def get_balance(monetary_account_id: int) -> Decimal:
    """Read the live balance of a meal-card sub-account."""
    return await asyncio.to_thread(_get_balance_sync, monetary_account_id)


async def charge_card(
    monetary_account_id: int,
    amount_eur: Decimal | float,
    description: str,
) -> dict[str, Any]:
    """Simulate a merchant charge by moving money out of the sub-account."""
    return await asyncio.to_thread(
        _charge_card_sync, monetary_account_id, amount_eur, description
    )


async def list_card_transactions(
    monetary_account_id: int,
    count: int = 50,
) -> list[dict[str, Any]]:
    """List recent payments on the meal-card sub-account.

    Each entry: {id, amount_eur (signed Decimal), description, created_at}.
    Negative amount_eur = charge (money out). Positive = top-up (money in)."""
    return await asyncio.to_thread(
        _list_card_transactions_sync, monetary_account_id, count
    )
