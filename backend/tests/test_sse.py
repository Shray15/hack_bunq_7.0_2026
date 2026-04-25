"""Verifies POST /chat fans out the canned event sequence on the realtime hub.

We test the hub directly rather than going through `/events/stream` over HTTP.
httpx's `ASGITransport` buffers the entire ASGI response cycle before returning,
which means an infinite SSE stream hangs `aconnect_sse` forever — testing the
SSE wire format requires a real uvicorn process. The hub fan-out is the
behavior we actually own; the SSE serialization layer is a thin wrapper.
"""

from __future__ import annotations

import asyncio

from httpx import AsyncClient

from app.realtime import hub
from app.security import decode_token
from tests.conftest import signup_and_token


async def test_chat_publishes_canned_event_sequence(client: AsyncClient) -> None:
    token = await signup_and_token(client, email="sse@test.dev")
    user_id = decode_token(token)

    seen: list[str] = []

    async def consume() -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            seen.append(event.name)
            if event.name == "image_ready":
                return

    consumer_task = asyncio.create_task(consume())
    # Yield once so subscribe() runs and attaches the queue before /chat fires.
    await asyncio.sleep(0.1)

    resp = await client.post(
        "/chat",
        json={"transcript": "hi"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 202

    await asyncio.wait_for(consumer_task, timeout=10.0)

    assert "recipe_token" in seen
    assert "recipe_complete" in seen
    assert "image_ready" in seen
    # recipe_complete must arrive before image_ready
    assert seen.index("recipe_complete") < seen.index("image_ready")


async def test_hub_fanout_to_multiple_subscribers() -> None:
    """One publish reaches every subscriber for that user; other users get nothing."""
    import uuid

    user_a = uuid.uuid4()
    user_b = uuid.uuid4()

    a_seen: list[str] = []
    b_seen: list[str] = []

    async def sub(target: list[str], user_id: uuid.UUID, expect_count: int) -> None:
        async for event in hub.subscribe(user_id):
            if event.name == "ping":
                continue
            target.append(event.name)
            if len(target) >= expect_count:
                return

    a1 = asyncio.create_task(sub(a_seen, user_a, 2))
    a2_seen: list[str] = []
    a2 = asyncio.create_task(sub(a2_seen, user_a, 2))
    b1 = asyncio.create_task(sub(b_seen, user_b, 1))
    await asyncio.sleep(0.1)

    await hub.publish(user_a, "test_event_one", {})
    await hub.publish(user_a, "test_event_two", {})
    await hub.publish(user_b, "for_b_only", {})

    await asyncio.wait_for(asyncio.gather(a1, a2, b1), timeout=2.0)

    assert a_seen == ["test_event_one", "test_event_two"]
    assert a2_seen == ["test_event_one", "test_event_two"]
    assert b_seen == ["for_b_only"]
