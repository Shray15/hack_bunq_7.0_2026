"""Phase 3 cart + order flow tests, using the grocery-mcp stub.

The full demo path is exercised: signup → /recipes/generate (synchronous
recipe creation) → /cart/from-recipe (parallel AH+Picnic fan-out) →
/cart/{id}/select-store → PATCH item → /order/checkout → wait for the
`order_status:paid` SSE event from the bunq poller.
"""

from __future__ import annotations

import asyncio
import uuid

from httpx import AsyncClient
from sqlalchemy import select

from app.db import SessionLocal
from app.models import Cart as CartModel
from app.models import Order as OrderModel
from app.realtime import hub
from app.security import decode_token
from tests.conftest import signup_and_token


async def _generate_recipe(client: AsyncClient, headers: dict[str, str]) -> str:
    resp = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "demo butter chicken"}},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def test_cart_from_recipe_returns_two_store_comparison(
    client: AsyncClient,
) -> None:
    token = await signup_and_token(client, email="cart1@test.dev")
    user_id = decode_token(token)
    headers = {"Authorization": f"Bearer {token}"}

    recipe_id = await _generate_recipe(client, headers)

    resp = await client.post(
        "/cart/from-recipe",
        json={"recipe_id": recipe_id, "people": 2},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    cart_id = body["cart_id"]
    uuid.UUID(cart_id)
    assert body["recipe_id"] == recipe_id
    assert "items" not in body  # comparison-only response

    stores = {row["store"]: row for row in body["comparison"]}
    assert set(stores) == {"ah", "picnic"}
    # AH stub catalogues every demo ingredient; picnic is missing parsley.
    assert stores["ah"]["missing_count"] == 0
    assert stores["picnic"]["missing_count"] == 1
    assert stores["ah"]["item_count"] >= 5
    assert stores["picnic"]["item_count"] >= 4
    assert stores["ah"]["total_eur"] > 0

    # Cart row was persisted, with items for both stores.
    async with SessionLocal() as db:
        cart_row = (
            await db.execute(
                select(CartModel).where(CartModel.owner_id == user_id)
            )
        ).scalar_one()
        assert cart_row.selected_store is None
        assert cart_row.people == 2
        assert "ah" in cart_row.missing_by_store
        assert cart_row.missing_by_store["picnic"] == ["parsley"]


async def test_select_store_then_patch_item_then_checkout_paid(
    client: AsyncClient,
) -> None:
    token = await signup_and_token(client, email="cart2@test.dev")
    user_id = decode_token(token)
    headers = {"Authorization": f"Bearer {token}"}

    recipe_id = await _generate_recipe(client, headers)

    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": recipe_id, "people": 1},
            headers=headers,
        )
    ).json()
    cart_id = cart["cart_id"]
    ah_total = next(c["total_eur"] for c in cart["comparison"] if c["store"] == "ah")

    select_resp = await client.post(
        f"/cart/{cart_id}/select-store",
        json={"store": "ah"},
        headers=headers,
    )
    assert select_resp.status_code == 200
    select_body = select_resp.json()
    assert select_body["selected_store"] == "ah"
    assert select_body["total_eur"] == ah_total
    items = select_body["items"]
    assert len(items) >= 5
    for item in items:
        assert item["store"] == "ah"
        assert item["image_url"]

    # Remove the most expensive item; total should drop accordingly.
    target = max(items, key=lambda i: i["total_price_eur"])
    patched = await client.patch(
        f"/cart/{cart_id}/items/{target['id']}",
        json={"removed": True},
        headers=headers,
    )
    assert patched.status_code == 200
    assert patched.json()["removed_at"] is not None

    # Re-read the basket: removed item still listed (so iOS can toggle back),
    # but the total reflects only active items.
    after = (
        await client.post(
            f"/cart/{cart_id}/select-store",
            json={"store": "ah"},
            headers=headers,
        )
    ).json()
    assert after["total_eur"] == round(ah_total - target["total_price_eur"], 2)

    # Subscribe to the SSE hub so we can assert paid arrives.
    seen: list[dict[str, str | None]] = []

    async def consume() -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            seen.append({"name": event.name, "status": event.data.get("status")})
            if event.name == "order_status" and event.data.get("status") == "paid":
                return

    consumer = asyncio.create_task(consume())
    await asyncio.sleep(0.1)

    checkout = await client.post(
        "/order/checkout", json={"cart_id": cart_id}, headers=headers
    )
    assert checkout.status_code == 200, checkout.text
    co_body = checkout.json()
    assert co_body["payment_url"].startswith("https://")
    assert co_body["amount_eur"] == after["total_eur"]
    order_id = co_body["order_id"]
    uuid.UUID(order_id)

    await asyncio.wait_for(consumer, timeout=3.0)
    statuses = [e["status"] for e in seen if e["name"] == "order_status"]
    assert "ready_to_pay" in statuses
    assert "paid" in statuses
    assert statuses.index("ready_to_pay") < statuses.index("paid")

    # Order row was transitioned to paid.
    async with SessionLocal() as db:
        order_row = (
            await db.execute(
                select(OrderModel).where(OrderModel.id == uuid.UUID(order_id))
            )
        ).scalar_one()
        assert order_row.status == "paid"
        assert order_row.paid_at is not None


async def test_checkout_without_select_store_fails(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="cart3@test.dev")
    headers = {"Authorization": f"Bearer {token}"}

    recipe_id = await _generate_recipe(client, headers)
    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": recipe_id, "people": 1},
            headers=headers,
        )
    ).json()
    bad = await client.post(
        "/order/checkout", json={"cart_id": cart["cart_id"]}, headers=headers
    )
    assert bad.status_code == 400
    assert "selected_store" in bad.json()["detail"]


async def test_cart_404_for_other_users_cart(client: AsyncClient) -> None:
    alice = await signup_and_token(client, email="alice3@test.dev")
    bob = await signup_and_token(client, email="bob3@test.dev")
    a_headers = {"Authorization": f"Bearer {alice}"}
    b_headers = {"Authorization": f"Bearer {bob}"}

    rid = await _generate_recipe(client, a_headers)
    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": rid, "people": 1},
            headers=a_headers,
        )
    ).json()
    cart_id = cart["cart_id"]

    bobs_view = await client.post(
        f"/cart/{cart_id}/select-store",
        json={"store": "ah"},
        headers=b_headers,
    )
    assert bobs_view.status_code == 404


async def test_get_and_list_orders(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="orders@test.dev")
    headers = {"Authorization": f"Bearer {token}"}

    recipe_id = await _generate_recipe(client, headers)
    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": recipe_id, "people": 1},
            headers=headers,
        )
    ).json()
    await client.post(
        f"/cart/{cart['cart_id']}/select-store",
        json={"store": "picnic"},
        headers=headers,
    )

    co = await client.post(
        "/order/checkout", json={"cart_id": cart["cart_id"]}, headers=headers
    )
    assert co.status_code == 200
    order_id = co.json()["order_id"]

    one = await client.get(f"/orders/{order_id}", headers=headers)
    assert one.status_code == 200
    assert one.json()["store"] == "picnic"

    listed = await client.get("/orders", headers=headers)
    assert listed.status_code == 200
    assert any(o["id"] == order_id for o in listed.json())
