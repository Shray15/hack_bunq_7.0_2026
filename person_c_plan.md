# Person C — MCP + bunq: Step-by-Step Plan

**Your job:** Make grocery ordering and payment work. The backend (Person B) calls your code. You are done when `POST /cart/from-recipe` returns real AH products and `POST /order/checkout` returns a real bunq sandbox payment URL.

---

## Priority Order (do this, not another order)

1. bunq sandbox auth — **now, first 30 min**
2. AH product search — working Python script, no MCP yet
3. Ingredient → product matcher
4. Wrap AH into an MCP server
5. bunq payment request generation
6. Jumbo/Picnic stubs
7. Wire to backend (Person B imports your modules)

---

## Step 1 — bunq Sandbox Auth (H0–1) ⚡ DO THIS FIRST

**Why first:** bunq sandbox registration can have delays. If you hit a wall at H12, you have no payment. Hit the wall now.

### 1.1 Register
- Go to [https://developer.bunq.com](https://developer.bunq.com) → sign up for sandbox access
- Create a sandbox user account at `https://sandbox.public.api.bunq.com`
- You'll get an `API_KEY` — save it immediately in a `.env` file

### 1.2 Install SDK
```bash
pip install bunq-sdk-python
```

### 1.3 Create a sandbox context
```python
# setup_bunq.py — run once to generate bunq_sandbox.conf
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.context.bunq_context import BunqContext
from bunq.sdk.model.generated.endpoint import MonetaryAccountBank

API_KEY = "your-sandbox-api-key-here"
DEVICE_DESCRIPTION = "hack-bunq-demo"
PERMITTED_IPS = []  # empty = all IPs allowed in sandbox

ctx = ApiContext.create(
    bunq.sdk.context.api_environment_type.ApiEnvironmentType.SANDBOX,
    API_KEY,
    DEVICE_DESCRIPTION,
    PERMITTED_IPS,
)
ctx.save("bunq_sandbox.conf")
print("Context saved. Auth works.")

BunqContext.load_api_context(ctx)
accounts = MonetaryAccountBank.list().value
for acc in accounts:
    print(f"Account ID: {acc.id_}, Balance: {acc.balance}")
```

Run this. If it prints an account ID, auth works. Save that account ID — you need it for payment requests.

### 1.4 Generate a payment request URL
```python
# bunq_payment.py
import bunq.sdk.context.bunq_context as bunq_ctx
from bunq.sdk.context.api_context import ApiContext
from bunq.sdk.model.generated.endpoint import RequestInquiry
from bunq.sdk.model.generated.object_ import Amount, Pointer

def create_payment_request(amount_eur: float, description: str, monetary_account_id: int) -> str:
    ApiContext.restore("bunq_sandbox.conf")
    bunq_ctx.BunqContext.load_api_context(ApiContext.restore("bunq_sandbox.conf"))

    request = RequestInquiry.create(
        amount_inquired=Amount(str(round(amount_eur, 2)), "EUR"),
        counterparty_alias=Pointer("EMAIL", "sugardaddy@bunq.com"),  # sandbox test address
        description=description,
        allow_bunqme=True,
        monetary_account_id=monetary_account_id,
    )
    request_id = request.value

    # The deep link format for bunq pay requests
    payment_url = f"https://bunq.me/HackBunqDemo/{round(amount_eur, 2)}/{description.replace(' ', '%20')}"
    return payment_url

if __name__ == "__main__":
    url = create_payment_request(12.30, "Groceries from AH", YOUR_ACCOUNT_ID)
    print(url)
```

**Checkpoint:** You have a URL that opens bunq. Show Person B. Auth is done.

---

## Step 2 — AH Product Search (H1–3)

Albert Heijn has a semi-public mobile API. No key required.

### 2.1 Test the endpoint manually first
```bash
curl "https://api.ah.nl/mobile-services/product/search/v2?query=chicken+breast&size=5" \
  -H "x-clientid: appie"
```

Expected: JSON with a list of products, each having `id`, `title`, `price.now`, `images[]`.

### 2.2 Write the search module
```python
# ah_client.py
import requests

BASE_URL = "https://api.ah.nl/mobile-services/product/search/v2"
HEADERS = {"x-clientid": "appie"}

def search_product(query: str, max_results: int = 5) -> list[dict]:
    params = {"query": query, "size": max_results}
    resp = requests.get(BASE_URL, params=params, headers=HEADERS, timeout=5)
    resp.raise_for_status()
    products = resp.json().get("products", [])
    return [
        {
            "product_id": f"ah_{p['id']}",
            "name": p["title"],
            "price_eur": float(p["price"]["now"]),
            "unit": p.get("unitSize", ""),
            "image_url": p["images"][0]["url"] if p.get("images") else None,
        }
        for p in products
    ]

if __name__ == "__main__":
    results = search_product("kipfilet")
    for r in results:
        print(r)
```

Run it. If it returns real products, move on. If AH blocks you, use the stub data below and move on — don't spend more than 20 min fighting it.

**Fallback stub data (if AH API doesn't cooperate):**
```python
AH_STUB = {
    "chicken": {"product_id": "ah_101", "name": "AH Kipfilet 500g", "price_eur": 5.49},
    "rice": {"product_id": "ah_102", "name": "AH Zilvervliesrijst 500g", "price_eur": 1.89},
    "egg": {"product_id": "ah_103", "name": "AH Vrije uitloop eieren 6st", "price_eur": 2.49},
    "pasta": {"product_id": "ah_104", "name": "AH Penne 500g", "price_eur": 0.99},
    "tomato": {"product_id": "ah_105", "name": "AH Tomaten 500g", "price_eur": 1.49},
    "beef": {"product_id": "ah_106", "name": "AH Rundergehakt 500g", "price_eur": 4.99},
    "broccoli": {"product_id": "ah_107", "name": "AH Broccoli 400g", "price_eur": 1.29},
    "onion": {"product_id": "ah_108", "name": "AH Uien 1kg", "price_eur": 0.99},
    "garlic": {"product_id": "ah_109", "name": "AH Knoflook 3 bollen", "price_eur": 0.79},
    "salmon": {"product_id": "ah_110", "name": "AH Zalmfilet 300g", "price_eur": 5.99},
}
```

---

## Step 3 — Ingredient → Product Matcher (H2–3)

Takes `"200g minced beef"` and returns the right AH product. Fuzzy string match only — no ML needed.

```python
# matcher.py
from difflib import get_close_matches
from ah_client import search_product

KEYWORD_MAP = {
    "chicken breast": "kipfilet",
    "minced beef": "rundergehakt",
    "ground beef": "rundergehakt",
    "salmon": "zalmfilet",
    "brown rice": "zilvervliesrijst",
    "pasta": "penne",
    "broccoli": "broccoli",
    "egg": "eieren",
    "onion": "uien",
    "garlic": "knoflook",
    "tomato": "tomaten",
}

def normalize_ingredient(name: str) -> str:
    name = name.lower().strip()
    for key, dutch in KEYWORD_MAP.items():
        if key in name:
            return dutch
    return name  # fall back to searching in English

def match_ingredient_to_product(ingredient_name: str, qty: float, unit: str) -> dict:
    query = normalize_ingredient(ingredient_name)
    results = search_product(query, max_results=3)
    if not results:
        return None
    best = results[0]  # first result is usually best
    return {
        "ingredient": ingredient_name,
        "product_id": best["product_id"],
        "name": best["name"],
        "price_eur": best["price_eur"],
        "qty": 1,  # always order 1 pack; good enough for demo
    }
```

**Test it:**
```python
print(match_ingredient_to_product("chicken breast", 200, "g"))
# → {"ingredient": "chicken breast", "product_id": "ah_101", ...}
```

---

## Step 4 — Wrap into MCP Server (H3–5)

Install the MCP Python SDK:
```bash
pip install mcp
```

```python
# mcp_ah_server.py
import json
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
from matcher import match_ingredient_to_product

app = Server("ah-grocery")

_cart: list[dict] = []

@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="search_product",
            description="Search AH for a product by ingredient name and quantity",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "qty": {"type": "number"},
                    "unit": {"type": "string"},
                },
                "required": ["query"],
            },
        ),
        Tool(
            name="add_to_cart",
            description="Add a list of matched products to the cart",
            inputSchema={
                "type": "object",
                "properties": {
                    "items": {
                        "type": "array",
                        "items": {"type": "object"},
                    }
                },
                "required": ["items"],
            },
        ),
        Tool(
            name="get_total",
            description="Get all items in cart and total price in EUR",
            inputSchema={"type": "object", "properties": {}},
        ),
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict):
    global _cart

    if name == "search_product":
        result = match_ingredient_to_product(
            arguments["query"],
            arguments.get("qty", 1),
            arguments.get("unit", ""),
        )
        return [TextContent(type="text", text=json.dumps(result))]

    elif name == "add_to_cart":
        _cart.extend(arguments["items"])
        return [TextContent(type="text", text=json.dumps({"added": len(arguments["items"]), "cart_size": len(_cart)}))]

    elif name == "get_total":
        total = sum(item.get("price_eur", 0) * item.get("qty", 1) for item in _cart)
        return [TextContent(type="text", text=json.dumps({
            "items": _cart,
            "total_eur": round(total, 2),
            "store": "ah",
        }))]

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

---

## Step 5 — Jumbo & Picnic Stubs (H5–6)

Same interface, fake data. Judges just need to see the UI offer a store choice.

```python
# mcp_jumbo_server.py  (copy mcp_ah_server.py, change store name + prices slightly)
# Just change "ah" → "jumbo" in get_total output
# Adjust prices by ±10% to look real

JUMBO_PRICE_MULTIPLIER = 0.95  # Jumbo is slightly cheaper in the stub

# mcp_picnic_server.py — same pattern, store = "picnic"
```

These are copy-paste jobs. Do them last.

---

## Step 6 — Expose as HTTP for the Backend (H5–7)

Person B needs to call your stuff via HTTP. Give them a simple FastAPI wrapper (not MCP protocol — just REST, easier for B to call):

```python
# grocery_api.py
from fastapi import FastAPI
from pydantic import BaseModel
from matcher import match_ingredient_to_product
from bunq_payment import create_payment_request

app = FastAPI()

class Ingredient(BaseModel):
    name: str
    qty: float
    unit: str

class CartRequest(BaseModel):
    ingredients: list[Ingredient]
    monetary_account_id: int = YOUR_ACCOUNT_ID

@app.post("/cart/from-recipe")
def cart_from_recipe(req: CartRequest):
    items = []
    for ing in req.ingredients:
        product = match_ingredient_to_product(ing.name, ing.qty, ing.unit)
        if product:
            items.append(product)
    total = sum(i["price_eur"] * i.get("qty", 1) for i in items)
    return {"items": items, "total_eur": round(total, 2), "store": "ah"}

@app.post("/order/checkout")
def checkout(total_eur: float, description: str = "Groceries"):
    url = create_payment_request(total_eur, description, YOUR_ACCOUNT_ID)
    return {"payment_url": url, "amount_eur": total_eur}
```

Run with: `uvicorn grocery_api:app --port 8001`

Tell Person B: your base URL is `http://localhost:8001` (or the deployed URL).

---

## File Structure

```
mcp/
├── .env                   # API keys — never commit
├── requirements.txt
├── ah_client.py           # AH product search
├── matcher.py             # ingredient → product
├── bunq_payment.py        # bunq payment request
├── mcp_ah_server.py       # MCP server (for Claude tool use)
├── mcp_jumbo_server.py    # stub
├── mcp_picnic_server.py   # stub
├── grocery_api.py         # REST wrapper for Person B
└── setup_bunq.py          # run once to create bunq_sandbox.conf
```

**requirements.txt:**
```
fastapi
uvicorn
requests
mcp
bunq-sdk-python
python-dotenv
```

---

## Checkpoints

| Time | What you must have working |
|------|---------------------------|
| H1   | bunq sandbox auth — account ID in hand, payment URL prints |
| H3   | AH search returns real products from a Python script |
| H5   | Ingredient matcher: "chicken breast" → AH product, correct |
| H6   | `grocery_api.py` running, Person B can call it and get a cart |
| H8   | Full path: recipe ingredients in → cart + bunq URL out |
| H11  | Demo works end-to-end at least once |

---

## If Things Break

| Problem | Fix |
|---------|-----|
| AH API returns 403 | Switch to stub data (`AH_STUB` dict). Demo still works. |
| bunq sandbox slow | Use a hardcoded fake URL for demo: `bunq://request/demo123`. Replace at end. |
| MCP server not connecting | Skip MCP, use `grocery_api.py` REST directly. B calls HTTP. |
| Time running out at H10 | Skip Jumbo/Picnic stubs. AH alone is enough for the demo. |
