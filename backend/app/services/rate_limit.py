"""Per-user in-memory token bucket.

Used to cap how often a single user can hit Bedrock-backed endpoints
(/chat, /recipes/generate). Reset on process restart — fine for the demo,
swap for Redis when we need durability across replicas.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from threading import Lock

from fastapi import HTTPException, status

from app.config import settings


@dataclass
class _Bucket:
    tokens: float
    last_refill: float


class TokenBucket:
    """Per-key bucket: `capacity` tokens, refilled at `capacity / window_s` per second."""

    def __init__(self, capacity: int, window_s: float) -> None:
        self.capacity = capacity
        self.refill_per_s = capacity / window_s
        self._buckets: dict[str, _Bucket] = {}
        self._lock = Lock()

    def consume(self, key: str, cost: float = 1.0) -> bool:
        now = time.monotonic()
        with self._lock:
            b = self._buckets.get(key)
            if b is None:
                b = _Bucket(tokens=self.capacity, last_refill=now)
                self._buckets[key] = b
            else:
                elapsed = now - b.last_refill
                b.tokens = min(self.capacity, b.tokens + elapsed * self.refill_per_s)
                b.last_refill = now
            if b.tokens < cost:
                return False
            b.tokens -= cost
            return True


_chat_bucket = TokenBucket(
    capacity=settings.chat_rate_limit_per_minute,
    window_s=60.0,
)


def enforce_chat_rate_limit(user_id: uuid.UUID) -> None:
    """FastAPI dependency-friendly check. Raises 429 when exceeded."""
    if not _chat_bucket.consume(str(user_id)):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"chat rate limit reached "
                f"({settings.chat_rate_limit_per_minute}/min); slow down."
            ),
        )
