import os
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from dotenv import load_dotenv
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import (
    BunqMeTabApiObject,
    BunqMeTabEntryApiObject,
)
from bunq.sdk.model.generated.object_ import AmountObject

load_dotenv()

DATA_DIR = Path(os.getenv("BUNQ_DATA_DIR", "."))
CONF_FILE = str(DATA_DIR / "bunq_sandbox.conf")
ACCOUNT_ID_FILE = DATA_DIR / "account_id"


def _resolve_account_id() -> int:
    """Account ID comes from the bootstrap-written sidecar; falls back to env
    for local dev that hasn't been migrated yet."""
    if ACCOUNT_ID_FILE.exists():
        return int(ACCOUNT_ID_FILE.read_text().strip())
    env_val = os.getenv("BUNQ_ACCOUNT_ID")
    if env_val and env_val != "0":
        return int(env_val)
    raise RuntimeError(
        f"BUNQ_ACCOUNT_ID not configured: no sidecar at {ACCOUNT_ID_FILE} "
        "and BUNQ_ACCOUNT_ID env var unset. Run scripts/bootstrap_bunq.py."
    )


# bunq BunqMeTab.status -> our public enum
_STATUS_MAP = {
    "WAITING_FOR_PAYMENT": "pending",
    "PAID": "paid",
    "ACCEPTED": "paid",
    "CANCELLED": "rejected",
    "REJECTED": "rejected",
    "EXPIRED": "expired",
}


def _load_context() -> None:
    ctx = ApiContext.restore(CONF_FILE)
    BunqContext.load_api_context(ctx)


def _format_eur(amount_eur: float) -> str:
    amount = Decimal(str(amount_eur)).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )
    if amount <= 0:
        raise ValueError("amount_eur must be greater than 0")
    return f"{amount:.2f}"


def create_payment_request(amount_eur: float, description: str = "Groceries") -> dict:
    """Mint a fixed-amount bunq.me checkout link via BunqMeTab.

    Returns {"request_id": str, "payment_url": str}. Raises if bunq does not
    return a fixed-amount share URL — we never silently fall back to a
    generic /pay link, since that would let the payer enter any amount."""
    _load_context()
    account_id = _resolve_account_id()

    amount = _format_eur(amount_eur)

    tab_id = BunqMeTabApiObject.create(
        bunqme_tab_entry=BunqMeTabEntryApiObject(
            amount_inquired=AmountObject(amount, "EUR"),
            description=description,
        ),
        monetary_account_id=account_id,
    ).value

    tab = BunqMeTabApiObject.get(
        bunq_me_tab_id=tab_id,
        monetary_account_id=account_id,
    ).value

    payment_url = getattr(tab, "bunqme_tab_share_url", None)
    if not payment_url:
        raise RuntimeError("bunq did not return bunqme_tab_share_url")

    returned_amount = getattr(
        getattr(tab, "bunqme_tab_entry", None),
        "amount_inquired",
        None,
    )
    if returned_amount and getattr(returned_amount, "value", amount) != amount:
        raise RuntimeError(
            f"bunq amount mismatch: expected {amount}, got {returned_amount.value}"
        )

    return {"request_id": str(tab_id), "payment_url": payment_url}


def get_payment_status(request_id: str) -> dict:
    """Look up the current status of a bunq.me tab.

    Returns {"request_id": str, "status": "pending"|"paid"|"rejected"|"expired",
             "paid_at": str|None}.
    paid_at is populated only when status == "paid"."""
    _load_context()
    account_id = _resolve_account_id()

    tab = BunqMeTabApiObject.get(
        bunq_me_tab_id=int(request_id),
        monetary_account_id=account_id,
    ).value

    status_raw = str(getattr(tab, "status", "")).upper()
    status = _STATUS_MAP.get(status_raw, "pending")
    paid_at = getattr(tab, "updated", None) if status == "paid" else None

    return {"request_id": str(request_id), "status": status, "paid_at": paid_at}


if __name__ == "__main__":
    payment = create_payment_request(20.93, "Groceries from AH")
    print(f"Created: {payment}")
    status = get_payment_status(payment["request_id"])
    print(f"Status:  {status}")
