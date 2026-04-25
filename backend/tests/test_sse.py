"""Verifies the canned /chat → SSE event sequence reaches the subscriber."""

from __future__ import annotations

import asyncio

from httpx import AsyncClient
from httpx_sse import aconnect_sse

from tests.conftest import signup_and_token


async def test_chat_emits_canned_sse_sequence(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="sse@test.dev")

    seen_events: list[str] = []

    async def consume() -> None:
        async with aconnect_sse(
            client,
            "GET",
            "/events/stream",
            params={"token": token},
            timeout=10.0,
        ) as es:
            async for sse in es.aiter_sse():
                seen_events.append(sse.event)
                if sse.event == "image_ready":
                    return

    consumer_task = asyncio.create_task(consume())
    # Let the subscriber attach before we trigger the producer.
    await asyncio.sleep(0.3)

    resp = await client.post(
        "/chat",
        json={"transcript": "hi"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 202

    await asyncio.wait_for(consumer_task, timeout=10.0)

    assert "recipe_token" in seen_events
    assert "recipe_complete" in seen_events
    assert "image_ready" in seen_events
    # recipe_complete must arrive before image_ready
    assert seen_events.index("recipe_complete") < seen_events.index("image_ready")
