import os
from pathlib import Path
from dotenv import load_dotenv
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import RequestInquiryApiObject
from bunq.sdk.model.generated.object_ import AmountObject, PointerObject

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

# bunq RequestInquiry.status -> our public enum
_STATUS_MAP = {
    "PENDING": "pending",
    "ACCEPTED": "paid",
    "REJECTED": "rejected",
    "REVOKED": "rejected",
    "EXPIRED": "expired",
}


def _load_context() -> None:
    ctx = ApiContext.restore(CONF_FILE)
    BunqContext.load_api_context(ctx)


def create_payment_request(amount_eur: float, description: str = "Groceries") -> dict:
    """Mint a bunq sandbox payment request.

    Returns {"request_id": str, "payment_url": str}."""
    _load_context()
    account_id = _resolve_account_id()

    inquiry_id = RequestInquiryApiObject.create(
        amount_inquired=AmountObject(str(round(amount_eur, 2)), "EUR"),
        counterparty_alias=PointerObject("EMAIL", "sugardaddy@bunq.com"),
        description=description,
        allow_bunqme=True,
        monetary_account_id=account_id,
    ).value

    inquiry = RequestInquiryApiObject.get(
        request_inquiry_id=inquiry_id,
        monetary_account_id=account_id,
    ).value

    payment_url = inquiry.bunqme_share_url or f"https://bunq.me/pay/{inquiry_id}"
    return {"request_id": str(inquiry_id), "payment_url": payment_url}


def get_payment_status(request_id: str) -> dict:
    """Look up the current status of a bunq payment request.

    Returns {"request_id": str, "status": "pending"|"paid"|"rejected"|"expired",
             "paid_at": str|None}.
    paid_at is populated only when status == "paid"."""
    _load_context()
    account_id = _resolve_account_id()

    inquiry = RequestInquiryApiObject.get(
        request_inquiry_id=int(request_id),
        monetary_account_id=account_id,
    ).value

    status = _STATUS_MAP.get(inquiry.status, "pending")
    paid_at = None
    if status == "paid":
        # time_responded is when the counterparty accepted; preferred over `updated`
        paid_at = getattr(inquiry, "time_responded", None) or getattr(inquiry, "updated", None)

    return {"request_id": str(request_id), "status": status, "paid_at": paid_at}


if __name__ == "__main__":
    payment = create_payment_request(20.93, "Groceries from AH")
    print(f"Created: {payment}")
    status = get_payment_status(payment["request_id"])
    print(f"Status:  {status}")
