"""End-to-end Phase-2 chat flow tests, exercised in adapter stub mode.

Bedrock + Gemini are unconfigured in the test env (`AWS_ACCESS_KEY_ID`,
`GEMINI_API_KEY` empty), so each adapter returns a deterministic stub. That
lets us assert orchestrator behaviour — DB persistence, SSE event order, the
shape of the persisted recipe — without ever calling a real LLM.
"""

from __future__ import annotations

import asyncio
import uuid

from httpx import AsyncClient
from sqlalchemy import select

from app.db import SessionLocal
from app.models import Recipe
from app.realtime import hub
from app.security import decode_token
from tests.conftest import signup_and_token


async def _drain_until(
    user_id: uuid.UUID, last_event: str
) -> tuple[list[str], asyncio.Task[None]]:
    seen: list[str] = []

    async def consume() -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            seen.append(event.name)
            if event.name == last_event:
                return

    task = asyncio.create_task(consume())
    # Yield long enough for subscribe() to attach its queue before the
    # orchestrator starts publishing.
    await asyncio.sleep(0.1)
    return seen, task


async def test_chat_persists_recipe_and_emits_sse_in_order(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="phase2@test.dev")
    user_id = decode_token(token)

    seen, task = await _drain_until(user_id, last_event="image_ready")

    resp = await client.post(
        "/chat",
        json={"transcript": "I want to make butter chicken"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 202, resp.text
    chat_id = resp.json()["chat_id"]

    await asyncio.wait_for(task, timeout=5.0)

    assert "recipe_complete" in seen
    assert "image_ready" in seen
    assert seen.index("recipe_complete") < seen.index("image_ready")
    assert "recipe_token" not in seen

    async with SessionLocal() as db:
        rows = (
            await db.execute(select(Recipe).where(Recipe.owner_id == user_id))
        ).scalars().all()

    assert len(rows) == 1
    persisted = rows[0]
    assert persisted.name  # NLU stub picks up "butter chicken" → titlecase
    assert "butter chicken" in persisted.name.lower()
    assert persisted.ingredients
    assert len(persisted.steps) >= 3
    assert persisted.macros["calories"] > 0
    # The image task ran and either set a placeholder URL (unconfigured Gemini)
    # or marked failed. In stub mode it should be ready.
    assert persisted.image_status == "ready"
    assert persisted.image_url is not None
    # chat_id is a uuid, not the recipe_id
    uuid.UUID(chat_id)
    assert chat_id != str(persisted.id)


async def test_recipes_generate_returns_persisted_recipe(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="generate@test.dev")
    user_id = decode_token(token)

    resp = await client.post(
        "/recipes/generate",
        json={"constraints": {"calories_max": 600, "protein_g_min": 40, "vibe": "quick weeknight"}},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["macros"]["calories"] > 0
    assert body["ingredients"]
    assert len(body["steps"]) >= 3

    async with SessionLocal() as db:
        rows = (
            await db.execute(select(Recipe).where(Recipe.owner_id == user_id))
        ).scalars().all()
    assert len(rows) == 1
    assert str(rows[0].id) == body["id"]


async def test_recipe_library_filters_by_favorite(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="library@test.dev")
    headers = {"Authorization": f"Bearer {token}"}

    r1 = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "comfort food"}},
        headers=headers,
    )
    r2 = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "light salad"}},
        headers=headers,
    )
    assert r1.status_code == 200 and r2.status_code == 200
    fav_id = r1.json()["id"]

    fav = await client.post(f"/recipes/{fav_id}/favorite", headers=headers)
    assert fav.status_code == 200
    assert fav.json()["favorited"] is True

    fav_only = await client.get("/recipes?favorited=true", headers=headers)
    assert fav_only.status_code == 200
    fav_recipes = fav_only.json()["recipes"]
    assert {r["id"] for r in fav_recipes} == {fav_id}

    all_recipes = await client.get("/recipes", headers=headers)
    assert all_recipes.status_code == 200
    assert len(all_recipes.json()["recipes"]) == 2


async def test_chat_rate_limit_returns_429(client: AsyncClient) -> None:
    """Sixth /chat in a row trips the 5/min default bucket."""
    token = await signup_and_token(client, email="ratelimit@test.dev")
    headers = {"Authorization": f"Bearer {token}"}

    statuses = []
    for _ in range(6):
        r = await client.post("/chat", json={"transcript": "hi"}, headers=headers)
        statuses.append(r.status_code)

    assert statuses[:5] == [202] * 5
    assert statuses[5] == 429


async def test_recipe_404_for_other_users_recipe(client: AsyncClient) -> None:
    alice = await signup_and_token(client, email="alice2@test.dev")
    bob = await signup_and_token(client, email="bob2@test.dev")

    gen = await client.post(
        "/recipes/generate",
        json={"constraints": {"vibe": "anything"}},
        headers={"Authorization": f"Bearer {alice}"},
    )
    rid = gen.json()["id"]

    other = await client.get(f"/recipes/{rid}", headers={"Authorization": f"Bearer {bob}"})
    assert other.status_code == 404
