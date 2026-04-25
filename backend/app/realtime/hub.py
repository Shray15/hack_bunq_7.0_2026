from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from app.config import settings
from app.realtime.events import EventName

log = logging.getLogger(__name__)

QUEUE_MAXSIZE = 256


@dataclass(frozen=True)
class Event:
    name: str
    data: dict[str, Any]

    def to_sse_dict(self) -> dict[str, str]:
        return {"event": self.name, "data": json.dumps(self.data, default=str)}


class RealtimeHub:
    """In-process per-user SSE fan-out.

    Multiple connections per user are supported: each subscribe() creates
    its own queue, and publish() fans an event to every active queue.
    """

    def __init__(self) -> None:
        self._subscribers: dict[uuid.UUID, list[asyncio.Queue[Event]]] = {}
        self._lock = asyncio.Lock()

    async def _attach(self, user_id: uuid.UUID) -> asyncio.Queue[Event]:
        queue: asyncio.Queue[Event] = asyncio.Queue(maxsize=QUEUE_MAXSIZE)
        async with self._lock:
            self._subscribers.setdefault(user_id, []).append(queue)
        return queue

    async def _detach(self, user_id: uuid.UUID, queue: asyncio.Queue[Event]) -> None:
        async with self._lock:
            queues = self._subscribers.get(user_id)
            if not queues:
                return
            with contextlib.suppress(ValueError):
                queues.remove(queue)
            if not queues:
                self._subscribers.pop(user_id, None)

    async def publish(self, user_id: uuid.UUID, name: str, data: dict[str, Any]) -> None:
        event = Event(name=name, data=data)
        async with self._lock:
            queues = list(self._subscribers.get(user_id, ()))
        for queue in queues:
            try:
                queue.put_nowait(event)
            except asyncio.QueueFull:
                log.warning("dropping event for slow subscriber user_id=%s name=%s", user_id, name)

    async def subscribe(self, user_id: uuid.UUID) -> AsyncIterator[Event]:
        """Yield events for this user. Emits PING on heartbeat timeout.

        Caller (the SSE endpoint) is responsible for closing the iterator
        on client disconnect; we drain the queue from the hub registry.
        """
        queue = await self._attach(user_id)
        heartbeat = settings.sse_heartbeat_seconds
        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=heartbeat)
                except TimeoutError:
                    yield Event(name=EventName.PING, data={"ts": _now_iso()})
                    continue
                yield event
        finally:
            await self._detach(user_id, queue)

    def subscriber_count(self, user_id: uuid.UUID) -> int:
        return len(self._subscribers.get(user_id, ()))


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


hub = RealtimeHub()
