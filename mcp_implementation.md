# MCP Implementation — Person C

Owner: Person C. This supersedes `person_c_plan.md` (which stays for historical reference only).

The shipped code in `mcp/` works as a REST service. The plan now is to **reshape it as a real MCP server** that the backend connects to over HTTP MCP transport, plus a small set of changes to fit the deploy story (single EC2, sibling container, env-driven bunq bootstrap).

---

## TL;DR — what changes vs. what's already there

| Concern              | Today (`mcp/grocery_api.py`)                    | Target                                                       |
|----------------------|--------------------------------------------------|--------------------------------------------------------------|
| Protocol             | FastAPI REST                                     | **MCP server, HTTP transport**                               |
| Port                 | 8001 published to host                           | 8001 inside docker network only (no host port)               |
| Stores               | AH + Picnic (already correct — Jumbo dropped)    | unchanged                                                    |
| State                | per-store in-memory cart                         | **stateless tools** — backend persists carts in Postgres     |
| Picnic write-through | mutates real Picnic account on every search     | **read-only by default**; only writes to Picnic on checkout |
| bunq config          | manual `setup_bunq.py`, conf file on disk        | **bootstrapped at container boot from `BUNQ_API_KEY`**       |
| bunq status          | mints URL only                                   | also exposes `get_payment_status(request_id)` for polling    |
| Bedrock              | unused                                           | **optional** — for smarter ingredient → product matching     |
| Compose              | new `docker-compose.yml` at repo root            | **moves into `deploy/docker-compose.yml`** as a sibling     |

The directory `mcp/` is the right name now — make the contents match.

---

## 1. Architecture target

```
┌────────────────────┐            HTTP MCP             ┌────────────────────────┐
│   Backend          │  ─────────────────────────────► │   grocery-mcp          │
│   (FastAPI, 4567)  │  JSON-RPC over HTTP             │   (MCP server, 8001)   │
└────────────────────┘                                 │                        │
                                                       │   Tools:               │
                                                       │   - search_products    │
                                                       │   - fuzzy_match        │
                                                       │   - get_catalogue      │
                                                       │   - create_payment_    │
                                                       │     request            │
                                                       │   - get_payment_status │
                                                       │                        │
                                                       │   Adapters (internal): │
                                                       │   - ah_client.py       │
                                                       │   - picnic_client.py   │
                                                       │   - bunq_payment.py    │
                                                       │                        │
                                                       │   Optional: Bedrock    │
                                                       │   for fuzzy matching   │
                                                       └────────────────────────┘
```

Both containers run on the same EC2, same docker network. Only the backend exposes a host port (4567). grocery-mcp is reachable from the backend at `http://grocery-mcp:8001/mcp` and is **not exposed publicly**.

---

## 2. Tools to expose (MCP shape)

Use the [official MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) — `pip install mcp`. Use HTTP transport (not stdio) so the backend can connect over docker network.

### Tool 1 — `search_products`

Takes a list of ingredients, returns matched products at a single store.

```python
# Tool input schema
{
    "type": "object",
    "properties": {
        "store": {"type": "string", "enum": ["ah", "picnic"]},
        "ingredients": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},        # English or Dutch
                    "qty":  {"type": "number"},        # numeric
                    "unit": {"type": "string"}         # "g", "kg", "pc", "tbsp", ...
                },
                "required": ["name"]
            }
        }
    },
    "required": ["store", "ingredients"]
}
```

Return value (single tool call result):

```json
{
  "store": "ah",
  "items": [
    {
      "ingredient": "chicken breast",
      "product_id": "ah_wi450123",
      "name": "AH Kipfilet 500g",
      "image_url": "https://static.ah.nl/products/450123.jpg",
      "qty": 1,
      "unit": "500 g",
      "price_eur": 6.99
    }
  ],
  "missing": ["galangal"],
  "total_eur": 13.45
}
```

**Important:** `search_products` is **read-only**. Don't mutate the real Picnic cart here. The current `picnic_client.add_to_cart` call in `_build_store_cart` must be removed — it has no business firing during ingredient lookup.

### Tool 2 — `fuzzy_match` (optional, internal)

If you go the Bedrock route for smart matching, expose it as a separate tool the backend can call directly (or use it internally inside `search_products`). Not required for the demo path. Skip for now.

### Tool 3 — `get_catalogue` (optional)

```python
{"category": "fresh-produce"}  # → list of products
```

Useful if the backend wants to paginate or browse. Not on the critical path — defer until everything else works.

### Tool 4 — `create_payment_request`

Mints a bunq sandbox payment URL.

```python
# Input
{
    "amount_eur": {"type": "number"},
    "description": {"type": "string"}
}
```
```json
// Output
{
  "request_id": "12345",
  "payment_url": "https://bunq.me/HackBunqDemo/13.45/Groceries"
}
```

Wraps `bunq_payment.create_payment_request(...)`. Adds a `request_id` to the return so the backend can poll status later.

### Tool 5 — `get_payment_status`

Backend calls this every ~2 s after minting a payment URL until the user pays (or 5 minutes elapse).

```python
# Input
{"request_id": "12345"}
```
```json
// Output
{
  "request_id": "12345",
  "status": "pending",
  "paid_at": null
}
```

Status enum: `"pending" | "paid" | "rejected" | "expired"`. The bunq SDK's `RequestInquiryApiObject.get(request_inquiry_id=...)` returns enough info to derive this — read `status` and the `created` field. **This does not exist in `bunq_payment.py` today; please add it.**

---

## 3. Files to create / change

```
mcp/
├── Dockerfile                 ← update
├── requirements.txt           ← add `mcp`, `boto3` (if using Bedrock)
├── server.py                  ← NEW: MCP HTTP server, registers all tools
├── tools/
│   ├── __init__.py
│   ├── search_products.py     ← NEW: wraps ah_client + picnic_client (read-only)
│   ├── matcher.py             ← NEW: ingredient → product. Move logic out of grocery_api.py
│   ├── payments.py            ← NEW: thin wrapper, exposes both bunq tools
│   └── bedrock.py             ← OPTIONAL: Bedrock client for fuzzy matching
├── adapters/
│   ├── ah_client.py           ← keep (already real)
│   ├── picnic_client.py       ← drop write-through during search
│   └── bunq_payment.py        ← add get_payment_status; harden setup
├── scripts/
│   ├── entrypoint.sh          ← NEW: bootstrap bunq if needed, exec server
│   └── bootstrap_bunq.py      ← NEW: idempotent setup_bunq.py replacement
└── grocery_api.py             ← DELETE once server.py is live (keep through migration)
```

`grocery_api.py` stays during migration so the backend can fall back to REST while we wire MCP. Delete after the backend's `app/adapters/grocery_mcp.py` lands.

---

## 4. bunq bootstrap (deploy-critical)

Today: someone has to run `python setup_bunq.py` manually on a host that has `BUNQ_API_KEY` in the env, then commit `bunq_sandbox.conf` somewhere. Brittle.

Target: container starts → entrypoint checks for `bunq_sandbox.conf` on a mounted volume → if missing, runs `bootstrap_bunq.py` to create it from `BUNQ_API_KEY` → exec the server.

```bash
# scripts/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

BUNQ_CONF=/data/bunq/bunq_sandbox.conf

if [ ! -f "$BUNQ_CONF" ]; then
    echo "[entrypoint] no bunq config found, bootstrapping..."
    python /app/scripts/bootstrap_bunq.py
fi

exec uvicorn server:app --host 0.0.0.0 --port 8001
```

`bootstrap_bunq.py` does what `setup_bunq.py` does today, but:
- Reads `BUNQ_API_KEY` from env (fail loudly if missing).
- Writes the conf to `/data/bunq/bunq_sandbox.conf` (a mounted volume).
- Discovers the monetary account ID via `MonetaryAccountBankApiObject.list()` and writes it to a sidecar file `/data/bunq/account_id` so `bunq_payment.py` doesn't need an env var for it.
- Idempotent: if the conf already exists, no-op.

`bunq_payment.py` should read `BUNQ_ACCOUNT_ID` from the sidecar instead of env. That removes the manual "now copy the account ID into your `.env`" step.

---

## 5. Deploy story

### Move grocery-mcp into the canonical compose

Add a service entry to `deploy/docker-compose.yml` (the file GHA actually deploys to `/opt/app/`):

```yaml
services:
  postgres:
    # …existing…

  backend:
    # …existing…
    environment:
      # …existing env…
      GROCERY_MCP_URL: http://grocery-mcp:8001/mcp
    depends_on:
      postgres:
        condition: service_healthy
      grocery-mcp:
        condition: service_started

  grocery-mcp:
    image: ${GROCERY_MCP_IMAGE:?required}     # built + pushed to GHCR by a new GHA job
    restart: unless-stopped
    pull_policy: always
    environment:
      BUNQ_API_KEY: ${BUNQ_API_KEY:?required}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
      AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:-}
      AWS_REGION: ${AWS_REGION:-us-east-1}
      AWS_BEDROCK_MODEL_ID: ${AWS_BEDROCK_MODEL_ID:-us.anthropic.claude-sonnet-4-5-20250929-v1:0}
      PICNIC_AUTH_TOKEN: ${PICNIC_AUTH_TOKEN:-}
      PICNIC_EMAIL: ${PICNIC_EMAIL:-}
      PICNIC_PASSWORD: ${PICNIC_PASSWORD:-}
    volumes:
      - /data/bunq:/data/bunq        # persist bunq config across restarts
    networks:
      - cooking_net
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8001/health').status==200 else 1)"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 20s

networks:
  cooking_net:
    driver: bridge
```

Notes:
- **No `ports:` block.** grocery-mcp is private to the docker network. The backend reaches it at `http://grocery-mcp:8001/mcp` (service name = DNS).
- **`/data/bunq` host mount.** Same EC2 disk approach we use for postgres — survives restarts.
- **GHCR image.** GHA needs a job that builds `mcp/` and pushes to `ghcr.io/<owner>/<repo>-grocery-mcp:<tag>`. Backend's GHA already does this for itself; copy the pattern.

### Delete the root `docker-compose.yml`

The new top-level compose file added in PR #2 conflicts with `deploy/docker-compose.yml` (wrong port, no postgres, builds locally instead of pulling from GHCR). Delete it. If we want a laptop-dev compose, file it as `docker-compose.local.yml` with a clear comment that it's not the deploy target.

### Secrets that need to land in GHA

Person C provides these to the repo admin so the deploy workflow can pass them through:

- `BUNQ_API_KEY` — sandbox API key (already in)
- `PICNIC_AUTH_TOKEN` **or** `PICNIC_EMAIL` + `PICNIC_PASSWORD`
- `AWS_*` — already in repo secrets
- `AWS_BEDROCK_MODEL_ID` — already hardcoded in deploy.yml

The deploy workflow's `Stage .env file` step needs to also write the new secrets to `/opt/app/.env` so docker-compose can interpolate them. That's a backend-dev change, but mention it on PR review.

---

## 6. Bedrock — only if you want it

If you want to make ingredient matching smarter than the hardcoded EN→NL dictionary, here's the deal:

- **Don't roll a new LLM SDK.** Use `boto3.client("bedrock-runtime")` with the same model ID the backend uses (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`).
- **One use case, narrow scope:** given an ingredient string and a list of candidate products from AH/Picnic, return the index of the best match. Don't try to make Claude do multi-step planning here — that's the backend's job.
- **Prompt cache the system block.** Same pattern the backend uses. Saves cost.
- **Cap latency.** ≤1.5 s per match. If Bedrock is slow, fall back to the dictionary.

Skip this entirely if the dictionary works for the demo recipes. The backend doesn't depend on it.

---

## 7. Migration order — what to ship first

Person C: do these in order. Each step is independently shippable.

1. **bunq bootstrap** — `bootstrap_bunq.py` + `entrypoint.sh` + volume mount. Test by running the container with `BUNQ_API_KEY` set and verify `/data/bunq/bunq_sandbox.conf` materializes. Status: blocks deploy.
2. **`get_payment_status` in `bunq_payment.py`** — pure addition. Test by minting a request, hitting it, manually approving in bunq sandbox UI, hitting again, see status flip.
3. **Drop Picnic write-through during search** — remove `picnic_client.add_to_cart(...)` from `_build_store_cart`. Test by calling `/cart/from-recipe?store=picnic` repeatedly and verifying the real Picnic account is unchanged.
4. **Move grocery-mcp into `deploy/docker-compose.yml`** — coordinate with backend dev. Once deployed, backend can hit grocery-mcp via REST (`grocery_api.py`) at the docker-network URL.
5. **MCP server (`server.py`)** — wrap the existing functions as MCP tools, expose at `/mcp`. Backend switches its adapter from REST → MCP. Both can coexist briefly.
6. **Delete `grocery_api.py`** — once backend's MCP adapter is live and tested.
7. **Bedrock fuzzy matching** — only if time allows. The dictionary works fine for butter chicken / pasta / chicken bowl.

Steps 1–4 should fit in a few hours. Steps 5–6 are the bigger lift but unblock the "we use real MCP" demo claim.

---

## 8. Test recipes (use these for end-to-end verification)

Until the backend is wired, you can sanity-test with these:

```python
ingredients = [
    {"name": "chicken breast", "qty": 400, "unit": "g"},
    {"name": "jasmine rice",   "qty": 200, "unit": "g"},
    {"name": "lemon",          "qty": 1,   "unit": "pc"},
    {"name": "garlic",         "qty": 3,   "unit": "cloves"},
    {"name": "olive oil",      "qty": 2,   "unit": "tbsp"},
    {"name": "parsley",        "qty": 1,   "unit": "bunch"},
]

# Should return ~6 items at AH, total ~€12-14
# Should return ~5-6 items at Picnic, total ~€11-14, possibly with 1 missing
```

If `parsley` doesn't match at Picnic, that's expected — surface it as `missing: ["parsley"]` in the response. Don't crash.

---

## 9. Things that are NOT your problem

To save back-and-forth — these stay on the backend side:

- Per-user state (carts, orders) — backend has Postgres; grocery-mcp is stateless.
- JWT auth — grocery-mcp has no auth at all (it's only reachable from the backend on the docker network).
- Recipe generation — backend calls Bedrock directly for that, doesn't go through grocery-mcp.
- Image generation (Nano Banana / Gemini) — backend.
- SSE / iOS contract — backend.
- Substitution suggestions for missing ingredients — backend (it'll call grocery-mcp's `search_products` with alternatives).

If iOS asks you for an endpoint, redirect them to the backend. iOS only ever talks to the backend.

---

## 10. Open questions to confirm with backend dev

- Do we want grocery-mcp to expose **one** `search_products` tool that returns both stores in parallel internally? Or two separate calls (one per store) that the backend fan-outs? Default assumption: **one call per store**, backend fans out — gives backend visibility/timing per store and makes Bedrock-driven retries easier. Confirm.
- Should the missing-ingredient list include attempted alternatives? Default: no, just the original ingredient names. Backend handles substitution.
- For the demo: hardcode `monetary_account_id` from the bootstrap, or accept it as a tool parameter? Default: hardcode (one account per environment).
