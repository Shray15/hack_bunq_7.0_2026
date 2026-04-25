from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI

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


def create_app() -> FastAPI:
    app = FastAPI(
        title="Cooking Backend",
        version=settings.version,
        description="Voice-first cooking & health iOS app — backend orchestrator.",
    )

    app.add_middleware(RequestIdMiddleware)

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
