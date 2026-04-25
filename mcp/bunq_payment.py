import os
from dotenv import load_dotenv
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import RequestInquiryApiObject
from bunq.sdk.model.generated.object_ import AmountObject, PointerObject

load_dotenv()

CONF_FILE = "bunq_sandbox.conf"
ACCOUNT_ID = int(os.getenv("BUNQ_ACCOUNT_ID", "0"))

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

    inquiry_id = RequestInquiryApiObject.create(
        amount_inquired=AmountObject(str(round(amount_eur, 2)), "EUR"),
        counterparty_alias=PointerObject("EMAIL", "sugardaddy@bunq.com"),
        description=description,
        allow_bunqme=True,
        monetary_account_id=ACCOUNT_ID,
    ).value

    inquiry = RequestInquiryApiObject.get(
        request_inquiry_id=inquiry_id,
        monetary_account_id=ACCOUNT_ID,
    ).value

    payment_url = inquiry.bunqme_share_url or f"https://bunq.me/pay/{inquiry_id}"
    return {"request_id": str(inquiry_id), "payment_url": payment_url}


def get_payment_status(request_id: str) -> dict:
    """Look up the current status of a bunq payment request.

    Returns {"request_id": str, "status": "pending"|"paid"|"rejected"|"expired",
             "paid_at": str|None}.
    paid_at is populated only when status == "paid"."""
    _load_context()

    inquiry = RequestInquiryApiObject.get(
        request_inquiry_id=int(request_id),
        monetary_account_id=ACCOUNT_ID,
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
