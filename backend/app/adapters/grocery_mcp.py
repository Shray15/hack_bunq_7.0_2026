"""grocery-mcp HTTP MCP transport adapter.

Wraps three tools the cart + order orchestrators depend on:

    search_products(store, ingredients) -> {store, items, missing, total_eur}
    create_payment_request(amount_eur, description) -> {request_id, payment_url}
    get_payment_status(request_id) -> {request_id, status, paid_at}

The adapter has two implementations:

  * RealGroceryMcpClient — opens a long-lived MCP session at FastAPI startup
    and reuses it for the lifetime of the process.
  * StubGroceryMcpClient — deterministic canned data for tests and offline
    local dev. Activated by `GROCERY_MCP_STUB=1`.

Connection policy:
  * `GROCERY_MCP_STUB=1`              → stub
  * `GROCERY_MCP_URL` set, stub off   → real connection; failure to connect
                                        at startup is fatal
  * URL empty AND stub off            → fatal; the backend won't boot

Public callers go through the module-level helpers (`search_products`, etc.)
so router code never sees the underlying client class.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import AsyncExitStack
from datetime import UTC, datetime
from typing import Any, Protocol

from app.config import settings

log = logging.getLogger(__name__)


class GroceryMcpError(RuntimeError):
    """Raised on any MCP-side failure the orchestrator should surface."""


class GroceryMcpClient(Protocol):
    async def search_products(
        self, store: str, ingredients: list[dict[str, Any]]
    ) -> dict[str, Any]: ...

    async def create_payment_request(
        self, amount_eur: float, description: str
    ) -> dict[str, Any]: ...

    async def get_payment_status(self, request_id: str) -> dict[str, Any]: ...

    async def aclose(self) -> None: ...


# ---------------------------------------------------------------------------
# Real client — talks to the MCP server over HTTP streamable transport.
# ---------------------------------------------------------------------------


class RealGroceryMcpClient:
    def __init__(self, url: str) -> None:
        self.url = url
        self._stack: AsyncExitStack | None = None
        self._session: Any = None
        self._lock = asyncio.Lock()

    async def connect(self) -> None:
        # Lazy imports keep stub-mode test runs from paying for SDK init.
        from mcp.client.session import ClientSession
        from mcp.client.streamable_http import streamablehttp_client

        stack = AsyncExitStack()
        try:
            transport = await asyncio.wait_for(
                stack.enter_async_context(streamablehttp_client(self.url)),
                timeout=settings.grocery_mcp_connect_timeout_seconds,
            )
            read, write, *_ = transport
            session = await stack.enter_async_context(ClientSession(read, write))
            await asyncio.wait_for(
                session.initialize(),
                timeout=settings.grocery_mcp_connect_timeout_seconds,
            )
        except Exception:
            await stack.aclose()
            raise

        self._stack = stack
        self._session = session
        log.info("grocery_mcp_connected: %s", self.url)

    async def aclose(self) -> None:
        if self._stack is not None:
            try:
                await self._stack.aclose()
            finally:
                self._stack = None
                self._session = None

    async def _call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if self._session is None:
            raise GroceryMcpError("grocery-mcp not connected")
        async with self._lock:
            try:
                result = await asyncio.wait_for(
                    self._session.call_tool(name, arguments),
                    timeout=settings.grocery_mcp_call_timeout_seconds,
                )
            except TimeoutError as exc:
                raise GroceryMcpError(f"{name} timed out") from exc
            except Exception as exc:  # noqa: BLE001
                raise GroceryMcpError(f"{name} failed: {exc}") from exc

        return _parse_tool_result(name, result)

    async def search_products(
        self, store: str, ingredients: list[dict[str, Any]]
    ) -> dict[str, Any]:
        return await self._call(
            "search_products", {"store": store, "ingredients": ingredients}
        )

    async def create_payment_request(
        self, amount_eur: float, description: str
    ) -> dict[str, Any]:
        return await self._call(
            "create_payment_request",
            {"amount_eur": round(amount_eur, 2), "description": description},
        )

    async def get_payment_status(self, request_id: str) -> dict[str, Any]:
        return await self._call("get_payment_status", {"request_id": request_id})


def _parse_tool_result(name: str, result: Any) -> dict[str, Any]:
    """Pull a JSON dict out of an MCP CallToolResult."""
    structured = getattr(result, "structuredContent", None)
    if isinstance(structured, dict):
        return structured

    content = getattr(result, "content", None) or []
    for block in content:
        text = getattr(block, "text", None)
        if not text:
            continue
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed

    raise GroceryMcpError(f"{name} returned no usable content: {result!r}")


# ---------------------------------------------------------------------------
# Stub client — for tests / local dev.
# ---------------------------------------------------------------------------


# Per-store canned product mapping. Names roughly match the demo recipes the
# Phase 2 stub adapter emits (chicken breast, jasmine rice, lemon, ...).
_STUB_PRODUCT_TEMPLATES: dict[str, dict[str, dict[str, Any]]] = {
    "ah": {
        "chicken breast": {
            "product_id": "ah-7421",
            "name": "AH Kipfilet 500g",
            "image_url": "https://placehold.co/240x240/png?text=Kipfilet",
            "unit": "500 g",
            "price_eur": 6.99,
        },
        "jasmine rice": {
            "product_id": "ah-1102",
            "name": "AH Jasmijnrijst 1kg",
            "image_url": "https://placehold.co/240x240/png?text=Rice",
            "unit": "1 kg",
            "price_eur": 2.49,
        },
        "lemon": {
            "product_id": "ah-9001",
            "name": "AH Citroen los",
            "image_url": "https://placehold.co/240x240/png?text=Lemon",
            "unit": "1 pc",
            "price_eur": 0.45,
        },
        "garlic": {
            "product_id": "ah-2233",
            "name": "AH Knoflook bol",
            "image_url": "https://placehold.co/240x240/png?text=Garlic",
            "unit": "1 pc",
            "price_eur": 0.69,
        },
        "olive oil": {
            "product_id": "ah-5566",
            "name": "AH Olijfolie extra vergine 500ml",
            "image_url": "https://placehold.co/240x240/png?text=Olive+Oil",
            "unit": "500 ml",
            "price_eur": 4.49,
        },
        "parsley": {
            "product_id": "ah-3344",
            "name": "AH Verse peterselie",
            "image_url": "https://placehold.co/240x240/png?text=Parsley",
            "unit": "1 bunch",
            "price_eur": 1.19,
        },
    },
    "picnic": {
        "chicken breast": {
            "product_id": "pic-7421",
            "name": "Kipfilet naturel 500g",
            "image_url": "https://placehold.co/240x240/png?text=Kipfilet",
            "unit": "500 g",
            "price_eur": 6.49,
        },
        "jasmine rice": {
            "product_id": "pic-1102",
            "name": "Jasmijnrijst 500g",
            "image_url": "https://placehold.co/240x240/png?text=Rice",
            "unit": "500 g",
            "price_eur": 1.79,
        },
        "lemon": {
            "product_id": "pic-9001",
            "name": "Citroen 4-pack",
            "image_url": "https://placehold.co/240x240/png?text=Lemons",
            "unit": "4 pc",
            "price_eur": 1.69,
        },
        "garlic": {
            "product_id": "pic-2233",
            "name": "Knoflook 2-pack",
            "image_url": "https://placehold.co/240x240/png?text=Garlic",
            "unit": "2 pc",
            "price_eur": 1.09,
        },
        "olive oil": {
            "product_id": "pic-5566",
            "name": "Olijfolie 750ml",
            "image_url": "https://placehold.co/240x240/png?text=Olive+Oil",
            "unit": "750 ml",
            "price_eur": 5.99,
        },
        # parsley deliberately missing at picnic to exercise missing-flow
    },
}


class StubGroceryMcpClient:
    def __init__(self) -> None:
        self._payment_status: dict[str, str] = {}

    async def connect(self) -> None:
        log.info("grocery_mcp_stub_active")

    async def aclose(self) -> None:
        return None

    async def search_products(
        self, store: str, ingredients: list[dict[str, Any]]
    ) -> dict[str, Any]:
        catalogue = _STUB_PRODUCT_TEMPLATES.get(store, {})
        items: list[dict[str, Any]] = []
        missing: list[str] = []
        for ing in ingredients:
            name = str(ing.get("name", "")).strip().lower()
            template = catalogue.get(name)
            if template is None:
                missing.append(ing.get("name", name))
                continue
            qty = 1
            items.append(
                {
                    "ingredient": ing.get("name", name),
                    "product_id": template["product_id"],
                    "name": template["name"],
                    "image_url": template["image_url"],
                    "unit": template["unit"],
                    "qty": qty,
                    "price_eur": template["price_eur"],
                }
            )
        total_eur = round(sum(i["price_eur"] * i["qty"] for i in items), 2)
        return {"store": store, "items": items, "missing": missing, "total_eur": total_eur}

    async def create_payment_request(
        self, amount_eur: float, description: str
    ) -> dict[str, Any]:
        request_id = uuid.uuid4().hex[:12]
        # Stub always reports "paid" the first time the poller checks. Lets
        # tests assert the full pay-detected path without real bunq traffic.
        self._payment_status[request_id] = "paid"
        return {
            "request_id": request_id,
            "payment_url": f"https://bunq.me/HackBunqDemo/{amount_eur:.2f}/{description}",
        }

    async def get_payment_status(self, request_id: str) -> dict[str, Any]:
        status = self._payment_status.get(request_id, "pending")
        return {
            "request_id": request_id,
            "status": status,
            "paid_at": datetime.now(UTC).isoformat() if status == "paid" else None,
        }


# ---------------------------------------------------------------------------
# Module-level singleton + lifespan helpers.
# ---------------------------------------------------------------------------


_client: GroceryMcpClient | None = None


def is_configured() -> bool:
    return _client is not None


def _resolve_client() -> GroceryMcpClient:
    if _client is None:
        raise GroceryMcpError(
            "grocery-mcp client not initialised; "
            "did the FastAPI lifespan handler run?"
        )
    return _client


async def connect() -> GroceryMcpClient:
    """Create and store the singleton; called from FastAPI's lifespan."""
    global _client
    if _client is not None:
        return _client

    if settings.grocery_mcp_stub:
        stub = StubGroceryMcpClient()
        await stub.connect()
        _client = stub
        return stub

    if not settings.grocery_mcp_url:
        raise RuntimeError(
            "GROCERY_MCP_URL is empty; set it (or GROCERY_MCP_STUB=1 for "
            "local dev) before starting the backend."
        )

    real = RealGroceryMcpClient(settings.grocery_mcp_url)
    await real.connect()
    _client = real
    return real


async def aclose() -> None:
    """Tear down the singleton; called from FastAPI's lifespan shutdown."""
    global _client
    if _client is None:
        return
    try:
        await _client.aclose()
    finally:
        _client = None


# Public façade used by orchestrators -----------------------------------------


async def search_products(
    store: str, ingredients: list[dict[str, Any]]
) -> dict[str, Any]:
    return await _resolve_client().search_products(store, ingredients)


async def create_payment_request(
    amount_eur: float, description: str
) -> dict[str, Any]:
    return await _resolve_client().create_payment_request(amount_eur, description)


async def get_payment_status(request_id: str) -> dict[str, Any]:
    return await _resolve_client().get_payment_status(request_id)
