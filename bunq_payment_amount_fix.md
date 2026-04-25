# bunq Payment Amount Fix

## Problem

During checkout, opening the bunq payment link can show an arbitrary or editable amount instead of the exact cart total.

The backend checkout flow already calculates the amount correctly:

1. It loads the selected cart.
2. It sums active cart items for the selected store.
3. It passes that amount into `grocery_mcp.create_payment_request(amount, description)`.
4. It stores the same amount as `order.total_eur`.

So the issue is likely not the backend total calculation. The likely issue is in `mcp/bunq_payment.py`, where the bunq payment URL is generated.

## Root Cause

`mcp/bunq_payment.py` currently creates a `RequestInquiryApiObject` and then falls back to a generic URL if bunq does not return `bunqme_share_url`:

```python
payment_url = inquiry.bunqme_share_url or f"https://bunq.me/pay/{inquiry_id}"
```

That fallback should not be used for checkout. It can send the user to a generic/manual bunq.me flow instead of a fixed-amount payment page, which is why the user may see an arbitrary amount.

## Fix

Use a bunq.me tab for fixed-amount checkout links and fail loudly if bunq does not return a fixed payment URL.

Replace `create_payment_request()` in `mcp/bunq_payment.py` with this implementation:

```python
from decimal import Decimal, ROUND_HALF_UP

from bunq.sdk.model.generated.endpoint import (
    BunqMeTabApiObject,
    BunqMeTabEntryApiObject,
)
from bunq.sdk.model.generated.object_ import AmountObject


def _format_eur(amount_eur: float) -> str:
    amount = Decimal(str(amount_eur)).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )
    if amount <= 0:
        raise ValueError("amount_eur must be greater than 0")
    return f"{amount:.2f}"


def create_payment_request(amount_eur: float, description: str = "Groceries") -> dict:
    """Create a fixed-amount bunq.me checkout link.

    Returns:
        {
            "request_id": str,
            "payment_url": str,
        }
    """
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

    return {
        "request_id": str(tab_id),
        "payment_url": payment_url,
    }
```

## Update Payment Status Polling

If `create_payment_request()` is changed from `RequestInquiryApiObject` to `BunqMeTabApiObject`, update `get_payment_status()` to read the bunq.me tab instead of request inquiry status.

```python
def get_payment_status(request_id: str) -> dict:
    """Return the current status for a bunq.me tab checkout link."""
    _load_context()
    account_id = _resolve_account_id()

    tab = BunqMeTabApiObject.get(
        bunq_me_tab_id=int(request_id),
        monetary_account_id=account_id,
    ).value

    status_raw = str(getattr(tab, "status", "")).upper()

    if status_raw in {"PAID", "ACCEPTED"}:
        status = "paid"
    elif status_raw in {"CANCELLED", "REJECTED"}:
        status = "rejected"
    elif getattr(tab, "time_expiry", None):
        status = "expired"
    else:
        status = "pending"

    return {
        "request_id": str(request_id),
        "status": status,
        "paid_at": getattr(tab, "updated", None) if status == "paid" else None,
    }
```

## Remove the Fallback

Delete this fallback completely:

```python
or f"https://bunq.me/pay/{inquiry_id}"
```

For checkout, a missing fixed payment URL should be treated as an error. Do not silently generate a generic URL.

## Test

Run this inside the MCP service environment:

```python
payment = create_payment_request(12.34, "Groceries from AH")
print(payment)
```

Then open `payment["payment_url"]`.

Expected result: bunq shows exactly `€12.34`, not a manually editable or arbitrary amount.

Also verify the backend checkout response still returns the same amount as the order total:

```json
{
  "amount_eur": 12.34,
  "payment_url": "...fixed bunq.me tab URL..."
}
```
