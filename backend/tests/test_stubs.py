"""Smoke tests that every §5 stub returns 200 with expected shape."""

from __future__ import annotations

import uuid

from httpx import AsyncClient

from tests.conftest import signup_and_token


async def _auth(client: AsyncClient) -> dict[str, str]:
    token = await signup_and_token(client, email="stubs@test.dev")
    return {"Authorization": f"Bearer {token}"}


async def test_chat_accepts_and_returns_202(client: AsyncClient) -> None:
    headers = await _auth(client)
    resp = await client.post(
        "/chat", json={"transcript": "high protein under 600 kcal"}, headers=headers
    )
    assert resp.status_code == 202, resp.text
    body = resp.json()
    assert "chat_id" in body
    uuid.UUID(body["chat_id"])  # parses


async def test_recipes_generate_returns_recipe(client: AsyncClient) -> None:
    headers = await _auth(client)
    resp = await client.post(
        "/recipes/generate",
        json={"constraints": {"calories_max": 600, "protein_g_min": 40}},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert {"id", "name", "ingredients", "steps", "macros"} <= set(body)
    assert body["macros"]["calories"] > 0


async def test_cart_from_recipe_returns_comparison(client: AsyncClient) -> None:
    headers = await _auth(client)
    rid = str(uuid.uuid4())
    resp = await client.post(
        "/cart/from-recipe", json={"recipe_id": rid}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["recipe_id"] == rid
    stores = {row["store"] for row in body["comparison"]}
    assert stores == {"ah", "jumbo", "picnic"}


async def test_checkout_returns_payment_url(client: AsyncClient) -> None:
    headers = await _auth(client)
    cart_id = str(uuid.uuid4())
    resp = await client.post(
        f"/cart/{cart_id}/checkout", json={"store": "ah"}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["payment_url"].startswith("https://")
    assert body["amount_eur"] > 0


async def test_meals_today_returns_target_and_remaining(client: AsyncClient) -> None:
    headers = await _auth(client)
    resp = await client.get("/meals/today", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "consumed" in body and "target" in body and "remaining" in body


async def test_meal_plan_tomorrow(client: AsyncClient) -> None:
    headers = await _auth(client)
    resp = await client.post("/meal-plan/tomorrow", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["plan"]["recipe"]["name"]
