"""grocery-mcp: MCP HTTP server exposing search + bunq payment tools.

Listens on 0.0.0.0:8001. Backend connects via streamable HTTP transport
at http://grocery-mcp:8001/mcp.

Tools (all stateless):
- search_products(store, ingredients) -> {store, items, missing, total_eur}
- create_payment_request(amount_eur, description) -> {request_id, payment_url}
- get_payment_status(request_id) -> {request_id, status, paid_at}
"""
from __future__ import annotations

from pydantic import BaseModel, Field
from starlette.requests import Request
from starlette.responses import JSONResponse
from mcp.server.fastmcp import FastMCP

from matching import build_store_cart
import bunq_payment

mcp = FastMCP(
    "grocery-mcp",
    host="0.0.0.0",
    port=8001,
    json_response=True,  # plain JSON over HTTP — simpler for backend than SSE chunking
)


class IngredientInput(BaseModel):
    name: str = Field(description="Ingredient name in English or Dutch (e.g. 'chicken breast', 'kipfilet')")
    qty: float = Field(default=1, description="Numeric quantity")
    unit: str = Field(default="", description="Unit ('g', 'kg', 'pc', 'tbsp'). Gram-convertible units enable closest-pack matching.")


@mcp.tool(
    name="search_products",
    description=(
        "Search a Dutch grocery store for products that match a list of recipe "
        "ingredients. Returns the closest pack size by grams when the unit is "
        "gram-convertible, or the top search hit otherwise. Read-only — never "
        "writes to the user's real cart."
    ),
)
def search_products(
    store: str = Field(description="Either 'ah' or 'picnic'."),
    ingredients: list[IngredientInput] = Field(description="Ingredients to match."),
) -> dict:
    if store not in ("ah", "picnic"):
        raise ValueError(f"Unsupported store '{store}'. Use 'ah' or 'picnic'.")
    items, missing = build_store_cart(
        [i.model_dump() for i in ingredients],
        store,
    )
    total = round(sum(i["subtotal_eur"] for i in items), 2)
    return {"store": store, "items": items, "missing": missing, "total_eur": total}


@mcp.tool(
    name="create_payment_request",
    description=(
        "Mint a bunq sandbox payment request for the given EUR amount. "
        "Returns request_id (use with get_payment_status to poll completion) "
        "and payment_url (open in browser to pay)."
    ),
)
def create_payment_request(amount_eur: float, description: str = "Groceries") -> dict:
    return bunq_payment.create_payment_request(amount_eur, description)


@mcp.tool(
    name="get_payment_status",
    description=(
        "Look up the current status of a bunq payment request. "
        "status is one of 'pending' | 'paid' | 'rejected' | 'expired'. "
        "paid_at is non-null only when status == 'paid'."
    ),
)
def get_payment_status(request_id: str) -> dict:
    return bunq_payment.get_payment_status(request_id)


@mcp.custom_route("/health", methods=["GET"])
async def health(_request: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
