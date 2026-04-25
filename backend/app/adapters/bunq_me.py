"""Production-style bunq.me URL builder.

We don't hit the bunq sandbox API for these — sandbox-issued bunq.me URLs
don't open the real iDEAL/card/bank flow that the demo wants to show. Instead
we construct the deterministic URL format
`https://bunq.me/<username>/<amount>/<description>` so a tap on the link
actually lands the user on a real bunq.me payment page with the amount
locked in.

Side-effect: there's no real BunqMeTab behind these URLs, so we can't poll
the sandbox for paid/expired status. The user manually flips the order
to paid via `POST /orders/{id}/mark-paid` after returning to the app.
"""

from __future__ import annotations

import uuid
from decimal import ROUND_HALF_UP, Decimal
from urllib.parse import quote

from app.config import settings


def _format_eur(amount_eur: float) -> str:
    amount = Decimal(str(amount_eur)).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )
    if amount <= 0:
        raise ValueError("amount_eur must be greater than 0")
    return f"{amount:.2f}"


def build_payment_url(amount_eur: float, description: str) -> dict[str, str]:
    """Mint a fixed-amount production bunq.me URL.

    Returns `{request_id, payment_url}` to mirror the shape of the legacy MCP
    `create_payment_request` response. `request_id` is a local UUID hex
    (there's no real bunq object to reference); we still store it on the
    Order/MealShare row so we can correlate logs across requests."""
    amount = _format_eur(amount_eur)
    desc = quote(description.strip() or "Payment", safe="")
    username = (settings.bunq_me_username or "HackBunqDemo").strip()
    return {
        "request_id": uuid.uuid4().hex,
        "payment_url": f"https://bunq.me/{username}/{amount}/{desc}",
    }
