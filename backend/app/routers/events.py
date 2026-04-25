from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse

from app.dependencies import CurrentUserIdQuery
from app.realtime import hub

router = APIRouter(tags=["events"])


@router.get("/events/stream")
async def stream(request: Request, user_id: CurrentUserIdQuery) -> EventSourceResponse:
    async def gen() -> AsyncIterator[dict[str, str]]:
        async for event in hub.subscribe(user_id):
            if await request.is_disconnected():
                break
            yield event.to_sse_dict()

    return EventSourceResponse(gen())
