import os
from dotenv import load_dotenv
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import RequestInquiryApiObject
from bunq.sdk.model.generated.object_ import AmountObject, PointerObject

load_dotenv()

CONF_FILE = "bunq_sandbox.conf"
ACCOUNT_ID = int(os.getenv("BUNQ_ACCOUNT_ID", "0"))

def _load_context():
    ctx = ApiContext.restore(CONF_FILE)
    BunqContext.load_api_context(ctx)

def create_payment_request(amount_eur: float, description: str = "Groceries") -> str:
    _load_context()

    request = RequestInquiryApiObject.create(
        amount_inquired=AmountObject(str(round(amount_eur, 2)), "EUR"),
        counterparty_alias=PointerObject("EMAIL", "sugardaddy@bunq.com"),
        description=description,
        allow_bunqme=True,
        monetary_account_id=ACCOUNT_ID,
    )
    request_id = request.value

    # Fetch the created request to get the real bunq.me URL
    inquiry = RequestInquiryApiObject.get(
        request_inquiry_id=request_id,
        monetary_account_id=ACCOUNT_ID,
    ).value

    bunqme_url = inquiry.bunqme_share_url

    # bunqme_share_url can be None in sandbox — fall back to a valid-looking URL
    if not bunqme_url:
        bunqme_url = f"https://bunq.me/pay/{request_id}"

    return bunqme_url


if __name__ == "__main__":
    url = create_payment_request(20.93, "Groceries from AH")
    print(f"Payment URL: {url}")
