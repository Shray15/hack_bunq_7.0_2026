from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI

from app.adapters import grocery_mcp
from app.config import settings
from app.middleware import RequestIdMiddleware
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

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    await grocery_mcp.connect()
    try:
        yield
    finally:
        await grocery_mcp.aclose()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Cooking Backend",
        version=settings.version,
        description="Voice-first cooking & health iOS app — backend orchestrator.",
        lifespan=_lifespan,
    )

    app.add_middleware(RequestIdMiddleware)

    @app.get("/healthz", tags=["health"])
    async def healthz() -> dict[str, Any]:
        return {
            "ok": True,
            "version": settings.version,
            "environment": settings.environment,
            "grocery_mcp_connected": grocery_mcp.is_configured(),
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
