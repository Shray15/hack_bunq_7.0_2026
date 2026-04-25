"""Pure ASGI middlewares.

Pure ASGI (not Starlette's BaseHTTPMiddleware) so streaming responses
like SSE pass through chunk-by-chunk instead of being buffered.
"""

from __future__ import annotations

import uuid
from contextvars import ContextVar
from typing import Any

from starlette.types import ASGIApp, Message, Receive, Scope, Send

request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

_REQUEST_ID_HEADER = b"x-request-id"


class RequestIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming: str | None = None
        for name, value in scope.get("headers", []):
            if name.lower() == _REQUEST_ID_HEADER:
                incoming = value.decode("latin-1")
                break
        rid = incoming or uuid.uuid4().hex
        token = request_id_var.set(rid)

        async def send_with_header(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers: list[tuple[bytes, bytes]] = list(message.get("headers", []))
                headers.append((_REQUEST_ID_HEADER, rid.encode("latin-1")))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_with_header)
        finally:
            request_id_var.reset(token)


__all__: list[Any] = ["RequestIdMiddleware", "request_id_var"]
