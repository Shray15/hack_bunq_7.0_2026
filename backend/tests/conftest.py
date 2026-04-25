from __future__ import annotations

import os

# Configure env before app is imported.
os.environ.setdefault(
    "DATABASE_URL", "postgresql+asyncpg://cooking:cooking@localhost:5432/cooking_test"
)
os.environ.setdefault("JWT_SECRET", "test-secret-not-for-prod")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("VERSION", "test")
# grocery-mcp / bunq are stubbed in the test process — no real MCP server.
os.environ.setdefault("GROCERY_MCP_STUB", "true")
os.environ.setdefault("BUNQ_POLL_INTERVAL_SECONDS", "0.1")
os.environ.setdefault("BUNQ_POLL_MAX_SECONDS", "5.0")

from collections.abc import AsyncIterator  # noqa: E402

import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.adapters import grocery_mcp  # noqa: E402
from app.db import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Base  # noqa: E402


@pytest_asyncio.fixture(scope="session", autouse=True)
async def _create_schema() -> AsyncIterator[None]:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    # `ASGITransport` doesn't fire FastAPI lifespan, so we manually wire up the
    # MCP stub client once per session.
    await grocery_mcp.connect()
    try:
        yield
    finally:
        await grocery_mcp.aclose()
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
        await engine.dispose()


@pytest_asyncio.fixture(autouse=True)
async def _wipe_tables() -> AsyncIterator[None]:
    async with engine.begin() as conn:
        await conn.execute(text("TRUNCATE users RESTART IDENTITY CASCADE"))
    yield


@pytest_asyncio.fixture
async def client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def signup_and_token(client: AsyncClient, email: str = "alice@test.dev") -> str:
    resp = await client.post("/auth/signup", json={"email": email, "password": "supersecret"})
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]
