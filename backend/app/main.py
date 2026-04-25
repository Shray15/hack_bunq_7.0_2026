from __future__ import annotations

import logging
import uuid
from collections.abc import Awaitable, Callable
from contextvars import ContextVar
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import Response

from app.config import settings
from app.routers import (
    auth,
    cart,
    chat,
    events,
    meal_plan,
    meals,
    orders,
    profile,
    recipes,
)

request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


def create_app() -> FastAPI:
    app = FastAPI(
        title="Cooking Backend",
        version=settings.version,
        description="Voice-first cooking & health iOS app — backend orchestrator.",
    )

    @app.middleware("http")
    async def request_id_middleware(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex
        token = request_id_var.set(rid)
        try:
            response = await call_next(request)
        finally:
            request_id_var.reset(token)
        response.headers["x-request-id"] = rid
        return response

    @app.get("/healthz", tags=["health"])
    async def healthz() -> dict[str, Any]:
        return {
            "ok": True,
            "version": settings.version,
            "environment": settings.environment,
        }

    app.include_router(auth.router)
    app.include_router(profile.router)
    app.include_router(events.router)
    app.include_router(chat.router)
    app.include_router(recipes.router)
    app.include_router(cart.router)
    app.include_router(orders.router)
    app.include_router(meals.router)
    app.include_router(meal_plan.router)

    return app


app = create_app()
