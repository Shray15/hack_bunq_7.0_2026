"""Phase 4 — substitutions, meals, meal plan, auto-log on paid."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.adapters import claude
from app.db import SessionLocal
from app.models import Cart as CartModel
from app.models import MealConsumed
from app.models import MealPlan as MealPlanModel
from app.realtime import hub
from app.security import decode_token
from tests.conftest import signup_and_token

# ---------------------------------------------------------------------------
# Substitution flow
# ---------------------------------------------------------------------------


async def test_substitution_swaps_missing_picnic_parsley(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The cart self-heals: parsley → italian parsley at Picnic."""
    token = await signup_and_token(client, email="sub1@test.dev")
    user_id = decode_token(token)
    headers = {"Authorization": f"Bearer {token}"}

    async def fake_suggest(*, ingredient: str, dish_name: str, store: str) -> list[str]:
        if ingredient.lower() == "peterselie":
            return ["italiaanse peterselie"]
        return []

    monkeypatch.setattr(claude, "suggest_substitutions", fake_suggest)

    seen: list[dict[str, str | None]] = []

    async def consume() -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            seen.append({"name": event.name, "store": event.data.get("store")})
            if event.name == "substitution_proposed":
                return

    consumer = asyncio.create_task(consume())
    await asyncio.sleep(0.1)

    gen = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "demo dish with parsley"}},
        headers=headers,
    )
    rid = gen.json()["id"]

    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": rid, "people": 1},
            headers=headers,
        )
    ).json()

    # Initial response shows parsley still missing at Picnic.
    picnic_initial = next(c for c in cart["comparison"] if c["store"] == "picnic")
    assert picnic_initial["missing_count"] == 1

    await asyncio.wait_for(consumer, timeout=3.0)
    assert any(
        e["name"] == "substitution_proposed" and e["store"] == "picnic" for e in seen
    )

    # After the background substitution lands, picnic_basket gains a row and
    # the cart's missing_by_store is empty.
    await asyncio.sleep(0.2)
    items = (
        await client.post(
            f"/cart/{cart['cart_id']}/select-store",
            json={"store": "picnic"},
            headers=headers,
        )
    ).json()
    italian = [
        i for i in items["items"] if i["ingredient_name"] == "italiaanse peterselie"
    ]
    assert italian, items["items"]

    async with SessionLocal() as db:
        cart_row = (
            await db.execute(
                select(CartModel).where(CartModel.id == uuid.UUID(cart["cart_id"]))
            )
        ).scalar_one()
        assert cart_row.missing_by_store["picnic"] == []


# ---------------------------------------------------------------------------
# Meal logging
# ---------------------------------------------------------------------------


async def test_meal_log_today_history_options(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="meals1@test.dev")
    headers = {"Authorization": f"Bearer {token}"}

    # Set a profile target so /meals/today returns a `remaining`.
    await client.patch(
        "/user/profile",
        json={
            "daily_calorie_target": 2400,
            "protein_g_target": 180,
            "carbs_g_target": 250,
            "fat_g_target": 70,
        },
        headers=headers,
    )

    gen = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "tracker test"}},
        headers=headers,
    )
    rid = gen.json()["id"]

    log1 = await client.post(
        "/meals/log", json={"recipe_id": rid, "portion": 1.0}, headers=headers
    )
    assert log1.status_code == 200
    log2 = await client.post(
        "/meals/log", json={"recipe_id": rid, "portion": 0.5}, headers=headers
    )
    assert log2.status_code == 200

    today = await client.get("/meals/today", headers=headers)
    assert today.status_code == 200
    body = today.json()
    assert len(body["meals"]) == 2

    cal1 = log1.json()["calories_computed"]
    cal2 = log2.json()["calories_computed"]
    assert body["consumed"]["calories"] == cal1 + cal2
    assert body["target"]["calories"] == 2400
    assert body["remaining"]["calories"] == 2400 - body["consumed"]["calories"]

    history = await client.get("/meals/history", headers=headers)
    assert history.status_code == 200
    assert len(history.json()["meals"]) == 2

    options = await client.get("/meals/options", headers=headers)
    assert options.status_code == 200
    # The recipe should appear since the user logged a consumption.
    rids = {o["recipe_id"] for o in options.json()}
    assert rid in rids


async def test_meal_log_404_for_unknown_recipe(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="meals2@test.dev")
    headers = {"Authorization": f"Bearer {token}"}
    bad = await client.post(
        "/meals/log",
        json={"recipe_id": str(uuid.uuid4()), "portion": 1.0},
        headers=headers,
    )
    assert bad.status_code == 404


# ---------------------------------------------------------------------------
# Meal plan
# ---------------------------------------------------------------------------


async def test_meal_plan_tomorrow_persists_and_lists(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="plan1@test.dev")
    user_id = decode_token(token)
    headers = {"Authorization": f"Bearer {token}"}
    await client.patch(
        "/user/profile",
        json={"daily_calorie_target": 2200, "protein_g_target": 150},
        headers=headers,
    )

    resp = await client.post("/meal-plan/tomorrow", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    plan = body["plan"]
    assert plan["status"] == "proposed"
    assert plan["recipe"]["name"]
    plan_id = plan["id"]

    upcoming = await client.get("/meal-plan/upcoming", headers=headers)
    assert upcoming.status_code == 200
    listed = upcoming.json()
    assert any(p["id"] == plan_id for p in listed)

    async with SessionLocal() as db:
        row = (
            await db.execute(
                select(MealPlanModel).where(MealPlanModel.owner_id == user_id)
            )
        ).scalar_one()
        assert row.scheduled_for >= (datetime.now(UTC).date() + timedelta(days=0))


# ---------------------------------------------------------------------------
# Auto-log meals_consumed when an order goes paid
# ---------------------------------------------------------------------------


async def test_paid_order_creates_meal_consumed_row(
    client: AsyncClient,
) -> None:
    token = await signup_and_token(client, email="autolog@test.dev")
    user_id = decode_token(token)
    headers = {"Authorization": f"Bearer {token}"}

    gen = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "auto-log demo"}},
        headers=headers,
    )
    rid = gen.json()["id"]

    cart = (
        await client.post(
            "/cart/from-recipe",
            json={"recipe_id": rid, "people": 1},
            headers=headers,
        )
    ).json()
    await client.post(
        f"/cart/{cart['cart_id']}/select-store",
        json={"store": "ah"},
        headers=headers,
    )

    seen: list[str] = []

    async def consume() -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            seen.append(event.name + ":" + str(event.data.get("status")))
            if event.name == "order_status" and event.data.get("status") == "paid":
                return

    consumer = asyncio.create_task(consume())
    await asyncio.sleep(0.1)

    co = await client.post(
        "/order/checkout", json={"cart_id": cart["cart_id"]}, headers=headers
    )
    assert co.status_code == 200

    await asyncio.wait_for(consumer, timeout=3.0)

    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(MealConsumed).where(MealConsumed.owner_id == user_id)
            )
        ).scalars().all()

    assert len(rows) == 1
    assert rows[0].source == "order"
    assert rows[0].portion == 1.0
    assert rows[0].calories_computed > 0
    assert rows[0].recipe_id == uuid.UUID(rid)
