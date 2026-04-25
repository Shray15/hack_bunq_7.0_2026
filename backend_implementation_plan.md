# Backend Implementation Plan

Owner: backend dev. Companion to `backend_overview.md` (older, partly stale) and the two contract docs that ship alongside this one:

- `frontend_implementation.md` — what iOS sends and expects. iOS treats it as the source of truth.
- `mcp_implementation.md` — what `grocery-mcp` exposes over HTTP MCP transport.

If anything in `backend_overview.md` disagrees with this file, **this file wins**. The backend's job is to be the only thing iOS talks to and the only thing that orchestrates Bedrock + Nano Banana + grocery-mcp + bunq (via MCP).

---

## 0. The canonical workflow (memorise this)

This is the shape every endpoint, adapter, and SSE event has to serve. Keep it open while you code.

```
User (voice/text): "I want to make butter chicken"

[1] iOS  ── POST /chat {transcript} ─────────────►  Backend
                                                    │
                                                    │  Fan out THREE pure-LLM calls in parallel:
                                                    │  (a) Bedrock Claude → structured ingredients (name, qty, unit)
                                                    │  (b) Bedrock Claude → cooking steps (medium detail, ~5–8 steps)
                                                    │  (c) Gemini Nano-Banana → dish image of "butter chicken"
                                                    │
                                                    │  None of these talk to grocery-mcp yet.
                                                    │
[2] iOS  ◄─ 202 {chat_id, accepted: true} ─────────┤
                                                    │
[3] SSE  ◄═ recipe_complete {chat_id, recipe_id,    │  fired as soon as (a)+(b) join
            recipe: {name, ingredients[], steps[],
                     macros, …, image_status:
                     "pending"}}                    │
                                                    │
[4] SSE  ◄═ image_ready {recipe_id, image_url} ════ │  fired when (c) lands (best-effort,
                                                    │  may arrive after recipe_complete)

iOS renders the recipe card. User taps "Find ingredients".

[5] iOS  ── POST /cart/from-recipe {recipe_id, people} ──► Backend
                                                          │
                                                          │  MCP fan-out across BOTH stores in parallel:
                                                          │    grocery-mcp.search_products(store="ah",     ingredients=…)
                                                          │    grocery-mcp.search_products(store="picnic", ingredients=…)
                                                          │
                                                          │  Persist `carts` row + per-store `cart_items` rows
                                                          │  including the products' image_url and prices.
                                                          │
[6] iOS  ◄─ 200 {cart_id, recipe_id, comparison: [        │  iOS sees TOTALS ONLY here.
            {store:"ah",     total_eur, item_count,       │  No item list yet.
             missing_count},
            {store:"picnic", total_eur, item_count,
             missing_count}]} ────────────────────────────┤

User picks a store card.

[7] iOS  ── POST /cart/{cart_id}/select-store {store:"ah"} ──► Backend
                                                              │
                                                              │  Mark cart.selected_store=ah,
                                                              │  return the persisted item list with
                                                              │  product image_url, name, qty, price.
                                                              │
[8] iOS  ◄─ 200 {cart_id, selected_store:"ah", total_eur,
            items:[{product_id, ingredient, name,
                    image_url, qty, unit, price_eur}, …]} ───┤

User reviews the basket, optionally PATCHes line items, taps "Pay via bunq".

[9] iOS  ── POST /order/checkout {cart_id} ──► Backend
                                              │
                                              │  Call grocery-mcp.create_payment_request(amount, description)
                                              │  → {request_id, payment_url}
                                              │  Persist `orders` row in status=ready_to_pay.
                                              │  Spawn background poller for this request_id.
                                              │
[10] iOS ◄─ 200 {order_id, payment_url, amount_eur} ──────────┤
[11] iOS opens payment_url externally
                                              │
                                              │  Background loop polls grocery-mcp.get_payment_status(request_id)
                                              │  every ~2 s up to 5 min.
                                              │  On status="paid": persist paid_at, push order_status SSE.
                                              │
[12] SSE ◄═ order_status {order_id, status:"paid", paid_at} ══┤
[13] iOS shows the paid checkmark, completes order in AppState.
```

That's the demo path. Everything below maps onto pieces of this diagram.

---

## 1. Updated infrastructure decisions (supersede `backend_overview.md`)

- **Database:** Postgres 16 (Docker container on the same EC2), not SQLite.
- **Environment:** EC2 from day one. No local-only mode. The dev loop is `git push → GitHub Actions → EC2`.
- **EC2:** Ubuntu 24.04 LTS, `t3.small`, us-east-1, 30 GB gp3. SSH user `ubuntu`.
- **Networking:** No tunnel, no Cloudflare, no HTTPS. EC2 security group opens SSH (your IP) + TCP 4567 (public). Backend binds `0.0.0.0:4567` and is hit directly at `http://<ec2-ip>:4567`.
- **LLM:** AWS Bedrock (Claude via `boto3`), not the Anthropic SDK directly. Model: `us.anthropic.claude-sonnet-4-5-20250929-v1:0`.
- **Image gen:** Gemini Nano-Banana via `google-genai`. Image returned to iOS as a URL (S3 upload preferred, data URL acceptable for the demo).
- **Stores:** **AH + Picnic only**. Jumbo is gone. Drop every Jumbo reference (`Store` literal, stubs, comparison rows, store-priority defaults).
- **MCP server:** `grocery-mcp` is a **sibling container** in the same `deploy/docker-compose.yml` on the same docker network. Backend reaches it at `http://grocery-mcp:8001/mcp` (HTTP MCP transport, JSON-RPC). It is **not** publicly exposed.
- **bunq lives in grocery-mcp, not the backend.** Backend never imports the bunq SDK. It calls MCP tools `create_payment_request` and `get_payment_status`.
- **Registry:** GitHub Container Registry (GHCR). Two images now: `…-backend` and `…-grocery-mcp`.
- **Secrets:** GitHub Actions Secrets → written to `/opt/app/.env` (mode 600) on EC2 at deploy time. New ones: `PICNIC_AUTH_TOKEN` (or `PICNIC_EMAIL`+`PICNIC_PASSWORD`), `GROCERY_MCP_IMAGE` tag for the sibling.
- **Migrations:** Alembic, autogenerated, applied on container start.
- **Deploy gating:**
  - `main` push → automatic deploy
  - Any other branch → manual deploy via `workflow_dispatch`
- **No token streaming on `/chat`.** We do not stream LLM text tokens to iOS. The recipe lands as **one** structured `recipe_complete` SSE event after Claude finishes. The current canned `recipe_token` loop in `app/routers/chat.py` is a Phase-1 stub and must be retired in Phase 2.
- **Single SSE channel.** Every async update — `recipe_complete`, `image_ready`, `cart_ready` (informational), `substitution_proposed`, `order_status`, `error`, `ping` — fans out on `GET /events/stream?token=<jwt>`. iOS opens it once after login. Never make iOS poll a backend endpoint.

---

## 2. The exact wire contract iOS depends on

This is a **summary** — the binding spec is `frontend_implementation.md` §5. Skim that section before you change any router.

| Endpoint                                | Method | Returns immediately       | Async events                                |
|-----------------------------------------|--------|---------------------------|---------------------------------------------|
| `/auth/signup`, `/auth/login`           | POST   | `{access_token}`          | —                                           |
| `/user/profile`                         | GET/PATCH | full profile           | —                                           |
| `/events/stream?token=<jwt>`            | GET    | SSE stream                | `ping` every 15 s                           |
| `/chat`                                 | POST   | `202 {chat_id, accepted}` | `recipe_complete`, then `image_ready`       |
| `/recipes/generate` (internal)          | POST   | full Recipe               | —                                           |
| `/cart/from-recipe`                     | POST   | `{cart_id, comparison[]}` | `cart_ready` (informational, optional)      |
| `/cart/{cart_id}/select-store`          | POST   | `{cart_id, items[]}`      | —                                           |
| `/cart/{cart_id}/items/{item_id}`       | PATCH  | updated item              | —                                           |
| `/order/checkout`                       | POST   | `{order_id, payment_url}` | `order_status` when bunq flips `paid`       |
| `/orders/{order_id}`                    | GET    | full Order                | —                                           |

`Store` is the literal `"ah" | "picnic"`. Drop Jumbo from every schema. `comparison[].missing_count` is the integer the iOS card displays — keep the matching `missing[]` (list of ingredient names) on the persisted cart so the user can be told *which* ingredient is unavailable when they tap a store.

The `Macros` block sits **inside** `Recipe.macros` with `calories` as a member (not a top-level `Recipe.calories` sibling). The current schema is correct; iOS will be aligned to this in their next pass.

---

## 3. Modules to build

```
backend/app/
├── main.py                        ✓ exists
├── config.py                      ✓ exists — add GROCERY_MCP_URL, S3 bucket settings
├── db.py                          ✓ exists
├── dependencies.py                ✓ exists (CurrentUserId from JWT)
├── middleware.py                  ✓ exists
├── security.py                    ✓ exists
├── stubs.py                       ✗ retire piecewise as orchestrators land (drop Jumbo NOW)
├── models/
│   ├── user.py, profile.py        ✓ exists
│   ├── recipe.py                  ⊕ add — id, name, ingredients(JSON), steps(JSON),
│   │                                macros(JSON), validated_macros(JSON), image_url,
│   │                                image_status, source, parent_recipe_id, owner_id, created_at
│   ├── cart.py                    ⊕ add — Cart + CartItem (with image_url, store, missing[])
│   ├── order.py                   ⊕ add — Order (cart_id, store, total, bunq_request_id,
│   │                                payment_url, status, paid_at, fulfilled_at, owner_id)
│   ├── meal.py                    ⊕ add (Phase 4) — MealConsumed, MealPlan
│   └── food_db_cache.py           ⊕ add (Phase 4) — OFF cache
├── schemas/                       ✓ mostly exists — drop Jumbo from cart.Store; ensure
│                                   StoreComparison has `missing_count` AND `missing[]` separately
├── routers/                       ✓ all exist as stubs — re-wire to orchestrators
│   └── cart.py                    ⊕ add `POST /cart/{cart_id}/select-store`
├── orchestrator/
│   ├── __init__.py                ⊕ NEW
│   ├── chat_flow.py               ⊕ NEW — the three-fan-out coordinator (Claude×2 + Gemini)
│   ├── cart_flow.py               ⊕ NEW — MCP fan-out across AH+Picnic
│   ├── order_flow.py              ⊕ NEW — checkout + bunq poll lifecycle
│   ├── meal_flow.py               ⊕ NEW (Phase 4)
│   └── substitution_flow.py       ⊕ NEW (Phase 4)
├── adapters/
│   ├── __init__.py                ⊕ NEW
│   ├── claude.py                  ⊕ NEW — Bedrock client. Two helpers:
│   │                                generate_ingredients(prompt, profile) → list[Ingredient]
│   │                                generate_steps(prompt, profile)       → list[str]
│   │                                (and optionally parse_transcript_to_constraints for NLU)
│   ├── gemini.py                  ⊕ NEW — Nano-Banana. generate_image(name) → image_url
│   ├── grocery_mcp.py             ⊕ NEW — single MCP client, HTTP transport,
│   │                                connects once at startup. Methods:
│   │                                  search_products(store, ingredients) → {items, missing, total_eur}
│   │                                  create_payment_request(amount_eur, description) → {request_id, payment_url}
│   │                                  get_payment_status(request_id) → {status, paid_at}
│   │                                Note: NO direct bunq SDK in this repo.
│   └── nutrition.py               ⊕ NEW (Phase 4) — OpenFoodFacts + USDA fallback
├── background/
│   ├── __init__.py                ⊕ NEW
│   ├── images.py                  ⊕ NEW — Gemini call → update Recipe.image_url → push image_ready
│   ├── nutrition.py               ⊕ NEW (Phase 4) — OFF lookup → update validated_macros
│   ├── bunq_poll.py               ⊕ NEW — poll grocery-mcp.get_payment_status every 2 s, max 5 min
│   └── substitutions.py           ⊕ NEW (Phase 4)
└── realtime/                      ✓ hub.py and events.py exist; events.py already has the right names
```

`adapters/bunq.py` is **not** a file in this codebase. bunq stays inside `grocery-mcp` per the new architecture.

---

## 4. Phase guide

Each phase has: **goal**, **tasks**, **exit criteria**. Phases 1–5 are sequential; later phases assume the previous phase shipped. Phase 0 is one-time infra and is already done.

A phase is "done" when its exit criteria pass against the live EC2 deployment, not against a local laptop.

---

## Phase 0 — Foundation (one-time infra) ✅ DONE

**Goal:** A live EC2 instance reachable directly on port 4567, with GHA able to deploy a hello-world container automatically on `main` push.

**Tasks**

1. **EC2** ✅ done — `t3.small`, Ubuntu 24.04 LTS, us-east-1, 30 GB gp3. Elastic IP attached. SG: SSH (your IP) + TCP 4567 (0.0.0.0/0). Bootstrap via `deploy/setup-ec2.sh`; Docker 29.1.3 + compose v2.29.7; `/opt/app` and `/data/postgres` created. Add `/data/bunq` for the grocery-mcp volume.
2. **Deploy SSH key** ✅ done — `~/.ssh/cooking_deploy_key`, public key in `~ubuntu/.ssh/authorized_keys`.
3. **GitHub repo** — `backend/` and `mcp/` at repo root. Branch protection on `main`. Deploy SSH key in GHA secrets ✅.
4. **GHA secrets**:
   - `EC2_HOST`, `EC2_SSH_KEY`, `EC2_USER` (`ubuntu`) ✅
   - `POSTGRES_PASSWORD`, `JWT_SECRET` ✅
   - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`, `AWS_REGION`
   - `AGENTCORE_MEMORY_ROLE_ARN`
   - `GEMINI_API_KEY`
   - `BUNQ_API_KEY` (consumed by grocery-mcp at boot)
   - `PICNIC_AUTH_TOKEN` **or** `PICNIC_EMAIL` + `PICNIC_PASSWORD` (consumed by grocery-mcp)
   - `AWS_BEDROCK_MODEL_ID` is hardcoded in the workflow.
5. **GHCR** — two images now: `ghcr.io/<owner>/<repo>-backend` and `ghcr.io/<owner>/<repo>-grocery-mcp`. The MCP image is built+pushed by a new GHA job copied from the backend's pattern (Person C ships this in the MCP plan, but the workflow lives in this repo).
6. **`deploy/docker-compose.yml`** — services `postgres`, `backend`, `grocery-mcp`. Only `backend` exposes a host port (`4567:4567`). `grocery-mcp` lives on the docker network at `grocery-mcp:8001`, mounts `/data/bunq`, has a healthcheck on `/health`. **Delete the root-level `docker-compose.yml`** (it pre-dates this plan and conflicts).
7. **GHA workflow `deploy.yml`** — triggers `push:main` (auto) and `workflow_dispatch` (manual). Steps: build+push **both** images → SSH to EC2 → write `.env` (mode 600, includes the new `PICNIC_*` and `GROCERY_MCP_IMAGE` vars) → `docker compose pull && up -d` → poll `/healthz` for the new version string.

**Exit criteria**

- `http://<ec2-ip>:4567/healthz` → `{"ok": true, "version": "main-<sha>", "environment": "production"}`.
- `docker compose ps` on EC2 shows `postgres`, `backend`, `grocery-mcp` all healthy.
- Backend can reach `http://grocery-mcp:8001/health` from inside the docker network (verify with `docker compose exec backend curl …`).

---

## Phase 1 — Skeleton, auth, realtime stubs ✅ MOSTLY DONE

**Goal:** Every endpoint from §2 exists, returns realistic stub JSON shaped exactly like production responses, JWT auth works end-to-end, SSE works. iOS can build the full UI against stubs without waiting for the orchestrators.

**Tasks**

1. **Project scaffold** (`backend/app/`) — FastAPI app factory, `pydantic-settings`, SQLAlchemy 2.x async, Alembic running on container start. ✅ done.
2. **Dockerfile** (multi-stage, `uv`-based, slim runtime; entrypoint runs migrations then `uvicorn`). ✅ done.
3. **Models for Phase 1 only:** `users`, `profiles`. Other tables added in their own phases.
4. **Auth router** — `POST /auth/signup`, `POST /auth/login`, `GET /user/profile`, `PATCH /user/profile`. JWT HS256, argon2 passwords. ✅ done.
5. **Realtime hub (in-memory)** — per-user `asyncio.Queue`s. `GET /events/stream?token=<jwt>` SSE endpoint with JWT in query (frontend constraint — `URLSession.bytes()` cannot set custom headers on SSE). Heartbeat every 15 s. ✅ done.
6. **Stub routers** — every endpoint in §2 returns realistic JSON matching the documented shape. **Cleanup needed in Phase 1.5 (do this BEFORE Phase 2):**
   - Drop Jumbo from `schemas/cart.py:Store` and from `stubs.py:make_cart` comparison.
   - Add `POST /cart/{cart_id}/select-store` stub returning the items list.
   - Make `StoreComparison` carry both `missing: list[str]` (for backend persistence) and `missing_count: int` (for the iOS card).
   - Trim `recipe_token` SSE events from the canned `/chat` flow — emit only `recipe_complete` (with full recipe) and `image_ready`. iOS no longer expects per-token deltas; keep `RECIPE_TOKEN` in `realtime/events.py` only if you want to repurpose it later, otherwise delete the constant.
7. **CI checks** — GHA workflow runs `ruff`, `mypy`, `pytest` on every PR; required to pass before deploy.
8. **OpenAPI** — confirm `/docs` is accessible at `http://<ec2-ip>:4567/docs`; share URL with iOS.

**Exit criteria**

- New user can sign up, log in, fetch profile against `http://<ec2-ip>:4567` from `curl`.
- iOS opens `/events/stream?token=<jwt>` and receives the canned `/chat` event sequence (`recipe_complete` → `image_ready`) on demand.
- Every endpoint in §2 returns a 200/202 with stub JSON matching the documented shape — including the new `select-store`.
- `alembic upgrade head` runs at container boot.
- No code path in `app/` references `"jumbo"`.

---

## Phase 2 — Recipe brain (Bedrock + Nano Banana)

**Goal:** `/chat` runs the canonical fan-out: two Claude calls (ingredients + steps) plus one Gemini call (image). Recipe lands on SSE within ~2–3 s; image follows when ready. `/recipes/generate` works as the internal callable used by Phase 4's meal-plan flow.

**Tasks**

1. **DB:** add `recipes` table; migration applied. Columns per §3 plus `owner_id` (FK users) and indices on `(owner_id, created_at)` and `(owner_id, favorited_at)`.
2. **Claude adapter (`adapters/claude.py`)**
   - Uses AWS Bedrock via `boto3` (`bedrock-runtime` client). Single shared client.
   - Model from `AWS_BEDROCK_MODEL_ID` env var (default `us.anthropic.claude-sonnet-4-5-20250929-v1:0`).
   - System prompt with `cache_control: {"type": "ephemeral"}` on the static block (recipe JSON schema, dietary rules, refusal handling). Confirm cache hit rate ≥ 80% in logs.
   - Tools: `emit_recipe_ingredients(ingredients[])` (forced) and `emit_recipe_steps(steps[])` (forced).
   - Helpers:
     - `generate_ingredients(transcript, profile, people) → list[RecipeIngredient]`
     - `generate_steps(transcript, profile) → list[str]` (medium detail, 5–8 entries)
     - `generate_macros_estimate(ingredients, people) → Macros` (LLM-side estimate; Phase 4 replaces with OFF-validated values)
     - Optional: `parse_transcript_to_constraints(transcript, profile) → RecipeConstraints` for the NLU step
3. **Gemini adapter (`adapters/gemini.py`)** — `google-genai` Nano-Banana client. `generate_image(dish_name, key_ingredients?) → image_url`. For the demo, upload to S3 (preferred) or return a data URL (fallback). Time-cap at 8 s; on timeout, leave `image_url=None` and let iOS keep the placeholder.
4. **Recipe orchestration (`orchestrator/chat_flow.py`)**
   - `/chat` flow:
     1. Allocate `chat_id` and (provisional) `recipe_id`. Persist a "draft" Recipe row with `image_status="pending"`.
     2. **Run (a) `generate_ingredients` and (b) `generate_steps` concurrently with `asyncio.gather`.**
     3. Compose the full `Recipe` payload + LLM macros estimate. Persist.
     4. Push `recipe_complete` SSE.
     5. Schedule (c) the Gemini image task in the background. On success, update `recipes.image_url` + `image_status="ready"`, push `image_ready` SSE. On failure, set `image_status="failed"` and emit an `error` SSE event scoped to `recipe_id`.
     6. (Phase 4) schedule the nutrition validation task.
   - `/recipes/generate` flow: same as `/chat` minus the NLU step; payload is the structured `RecipeConstraints` directly.
5. **Recipe library endpoints (already stubbed; wire to DB now):** `GET /recipes/{id}`, `GET /recipes` (filters: `favorited`, `since`), `POST /recipes/{id}/favorite`, `POST /recipes/{id}/recook` (creates a fresh draft cart referencing this recipe — the cart itself materialises in Phase 3).
6. **Per-user rate limit** on `/chat` and `/recipes/generate` (in-memory token bucket, 5 req/min default) to control Bedrock cost.

**Exit criteria**

- `POST /chat {transcript: "I want to make butter chicken"}` returns 202 within ~300 ms.
- SSE pushes `recipe_complete` within ~2–3 s with a 6–10 ingredient list, 5–8 step list, and an LLM macros estimate.
- SSE pushes `image_ready` with a real Nano-Banana image URL within ~10 s of the request (best-effort; failures degrade gracefully).
- Bedrock cost per recipe < €0.05 with prompt caching active (verify in AWS Cost Explorer / Bedrock usage).
- Favorite + recook round-trip works against Postgres.
- The canned `recipe_token` loop is gone from `chat.py`.

---

## Phase 3 — Cart fan-out, store selection, bunq via MCP

**Goal:** From a generated recipe, produce a 2-store comparison (AH + Picnic), let the user pick one and see real product images, mint a bunq payment URL via grocery-mcp, and detect "paid" via polling — all surfaced over SSE. **This is the demo path.**

**Tasks**

1. **DB:** add `carts`, `cart_items`, `orders` tables. `cart_items.image_url` is non-null for any matched item. `cart_items.store` is `"ah" | "picnic"`. `cart_items.removed_at` supports the per-row toggle. `orders` tracks `bunq_request_id`, `payment_url`, `status`, `paid_at`, `fulfilled_at`.
2. **MCP client (`adapters/grocery_mcp.py`)**
   - Connect to `GROCERY_MCP_URL` (env: `http://grocery-mcp:8001/mcp`) over the official MCP Python SDK's HTTP client. Establish the session **once at app startup** (FastAPI lifespan event); reuse it.
   - Wrap the three tools we depend on:
     - `search_products(store: "ah"|"picnic", ingredients: list[{name, qty, unit}]) → {items, missing, total_eur}`
     - `create_payment_request(amount_eur, description) → {request_id, payment_url}`
     - `get_payment_status(request_id) → {status, paid_at}`
   - On tool errors, raise a typed `GroceryMCPError` so orchestrators can degrade (push an `error` SSE, don't 500).
3. **Cart flow (`orchestrator/cart_flow.py`)**
   - `POST /cart/from-recipe`:
     1. Load recipe → ingredients with qty/unit.
     2. **Parallel `asyncio.gather`**: `search_products(store="ah", …)` and `search_products(store="picnic", …)`.
     3. Persist `carts` row (`status="open"`, `selected_store=None`) and one `cart_items` row per matched product per store, including `image_url`.
     4. Build `comparison` = `[{store, total_eur, item_count, missing_count}, …]` and store the per-store `missing[]` list on the cart so it can be surfaced when the user selects.
     5. Return `{cart_id, recipe_id, comparison}`. Optionally fire `cart_ready` SSE for symmetry — iOS doesn't need it (the HTTP body has the same data).
   - `POST /cart/{cart_id}/select-store {store}`:
     1. Set `cart.selected_store = store`. Persist.
     2. Return the persisted `cart_items` rows for that store (with `image_url`, name, qty, unit, price). Sum totals from the persisted rows so removals stick.
   - `PATCH /cart/{cart_id}/items/{item_id}` — set `removed_at=now` or update `qty`. Recompute totals on read.
4. **Order flow (`orchestrator/order_flow.py`)**
   - `POST /order/checkout {cart_id}`:
     1. Refuse if `cart.selected_store is None`.
     2. Compute amount from active (non-removed) items at the selected store.
     3. Call `grocery_mcp.create_payment_request(amount, description=f"Groceries from {store.upper()}")` → `{request_id, payment_url}`.
     4. Persist `orders` row (`status="ready_to_pay"`, `bunq_request_id`, `payment_url`).
     5. Spawn the bunq poll task (Task 5). Push `order_status {status:"ready_to_pay"}` SSE for completeness.
     6. Return `{order_id, payment_url, amount_eur}`.
   - `GET /orders/{order_id}` and `GET /orders` — read from DB; respect ownership.
5. **bunq status poller (`background/bunq_poll.py`)** — `asyncio.create_task` per order. Loop: every 2 s call `grocery_mcp.get_payment_status(request_id)` for up to 5 min. On `paid` → set `orders.status="paid"`, `paid_at=now`, push `order_status {status:"paid", paid_at}` SSE. On `expired`/`rejected` → push `order_status` with that status. On 5-min timeout → `payment_failed`. Cancel cleanly if the order transitions out of `ready_to_pay` for any other reason.
6. **No MCP-side fulfilment yet.** `place_order` / store-side cart commit is a stretch. For the demo we mark `fulfilled` only if the MCP exposes a `place_order` tool we can wire up; otherwise the order stays at `paid` and that is the demo's terminal state.

**Exit criteria**

- End-to-end demo path on a real iPhone against the live EC2 backend: voice → recipe → 2-store comparison → pick AH → see basket with product images → bunq URL → paid status pops on iOS via SSE.
- `/cart/from-recipe` returns within ~3 s for an 8–10 ingredient recipe (parallel MCP fan-out, not serial).
- `/cart/{id}/select-store` returns within 200 ms (it's a DB read; no MCP traffic).
- bunq sandbox payment is detected as `paid` within ~5 s of completion in the bunq sandbox UI.
- Removing an item via `PATCH` updates the displayed total correctly on next `select-store` read.
- Backend has **zero** direct bunq SDK code.

---

## Phase 4 — Substitutions, meal logging, meal plan

**Goal:** Cart self-heals when stores miss ingredients, the calorie ring reflects real intake, and tomorrow's recipe is macro-aware.

**Tasks**

1. **DB:** add `meals_consumed`, `meal_plans`, `food_db_cache` tables.
2. **Substitution flow (`orchestrator/substitution_flow.py`)** — when MCP returns `missing`, fire async task that calls `claude.suggest_substitutions(ingredient, recipe_context)` for up to 3 alternatives. Retry MCP search per alternative. On first hit, replace the cart item silently and emit `substitution_proposed` (informational). Cap retry depth at 1 substitution per ingredient.
3. **Nutrition validation (`background/nutrition.py`)** — for each ingredient on a freshly persisted recipe, call `nutrition.lookup(name)`:
   - First check `food_db_cache`. On miss, query OpenFoodFacts. On miss again, fall back to USDA.
   - Persist per-100g macros into the cache.
   - Recompute `recipes.validated_macros` from cache + ingredient qty. Push `recipe_complete` again (or a follow-up event) so iOS shows the trustworthy numbers. Keep within 15% of LLM estimates on most recipes; log mismatches.
4. **Meal logging endpoints**
   - `GET /meals/options` — recipes the user has either ordered (`paid`+) or marked `prepared` recently. Used by iOS's "what did you eat" picker.
   - `POST /meals/log {recipe_id, portion}` — `calories_computed`/`macros_computed` = `recipes.validated_macros × portion`; persist.
   - `GET /meals/today` — sum of today's logged macros + `remaining = profile_target - sum`.
   - `GET /meals/history?from=&to=`.
5. **Meal plan flow (`orchestrator/meal_flow.py`)**
   - `POST /meal-plan/tomorrow` — gather profile + today's logged macros + remaining weekly delta → build a `RecipeConstraints` → call `chat_flow` internally (no MCP, no images necessarily) → persist `meal_plans` row → push `meal_plan_ready`.
   - `GET /meal-plan/upcoming` — next pending plan(s); schema returns a list so a weekly view becomes a UI-only extension.
6. **Order → ate mapping** — when an order goes `paid` (or `fulfilled` if Phase 3.6 lands), optionally auto-create a `meals_consumed` row with `portion=1.0, source="order"`. iOS can let the user adjust the portion in the UI.

**Exit criteria**

- Demo recipe with one deliberately exotic ingredient (e.g. galangal) produces a `substitution_proposed` event and the cart still totals successfully.
- Logging two meals at portions 1.0 and 0.5 on `/meals/today` produces correct sums and `remaining`.
- `/meal-plan/tomorrow` produces a recipe whose macros + already-logged macros stay within ~10% of profile target on 3+ sample profiles.

---

## Phase 5 — Polish, resilience, observability

**Goal:** Production-ready behaviour under all plausible demo paths, plus the operational hygiene to debug a failure live.

**Tasks**

1. **Resilience**
   - Retry policies (`tenacity`) on Bedrock, Gemini, OFF, MCP.
   - Per-adapter circuit breakers — after 3 consecutive failures, return a graceful `error` SSE event instead of stalling the orchestrator.
   - bunq poll task cleanly cancels on order state change to avoid orphaned tasks.
   - On MCP startup failure (`grocery-mcp` not yet healthy), backend retries the connection in the background instead of crashing — `/healthz` reports degraded.
2. **Observability**
   - `structlog` JSON logs to stdout; `docker compose logs -f backend` is the live view.
   - Request-id middleware (already exists); propagate to adapter logs and into the MCP tool-call metadata.
   - `/metrics` Prometheus endpoint (optional — only if a Grafana panel adds demo value).
3. **Backups**
   - `pg_dump` cron container, ships compressed dump to S3 daily, retains 7 days.
   - Document restore procedure in `backend/docs/runbook.md`.
4. **Demo seeding**
   - `scripts/seed_demo.py` — demo user, sample profile, sample meal history, one favorited recipe, one paid order. Idempotent.
   - GHA action runs seed only against a flag-protected env (do **not** auto-seed prod blindly).
5. **Performance tuning**
   - Confirm Bedrock prompt-cache hit rate > 80%.
   - Pre-warm OFF cache for the top ~200 ingredients.
   - Connection pooling on Postgres + the MCP HTTP client + httpx clients.
6. **Security review**
   - JWT secret rotated post-development.
   - Confirm `/opt/app/.env` is mode 600 owned by the docker user.
   - SG rule optionally restricting TCP 4567 to the team / demo venue once `/docs` and the API don't need to be public.
7. **Backup demo path**
   - Recorded video of the full happy path.
   - Settings flag `OFFLINE_DEMO=1` that flips every adapter to canned responses (Claude→fixture, Gemini→placeholder, MCP→fixture, bunq poll→auto-paid after 4 s) so a venue network outage doesn't kill the demo.

**Exit criteria**

- Cold-start of `docker compose up -d` to first successful `/chat` completes in under 30 s.
- Killing any single adapter (Bedrock / Gemini / MCP) and replaying the demo path produces a graceful, user-readable `error` SSE — no hung streams, no 500s.
- A clean `pg_dump` exists in S3 and a tested restore brings up an identical container.
- Logs trace one full demo request from `/chat` → `recipe_complete` → `image_ready` → `cart_ready` → `select-store` → `/order/checkout` → `order_status:paid` with a consistent request id.

---

## 5. Cross-phase conventions

- **Branching:** feature branches → PR → `main`. Non-main deploys only via `workflow_dispatch`. `main` deploys are auto, fast, and reversible by reverting the merge commit.
- **Migrations:** every schema change ships in the same PR as its model. CI runs `alembic upgrade head` on a throwaway Postgres.
- **Tests:** each adapter has a contract test with a recorded fixture (`respx` for HTTP, hand-rolled fakes for the MCP client). Orchestrator flows have integration tests against the test Postgres.
- **Adapters before orchestrators, orchestrators before routers:** routers only call orchestrators; orchestrators call adapters. Never call Bedrock or grocery-mcp from a router.
- **SSE first, polling never:** any feature that involves "wait for X" must surface progress on `/events/stream`. iOS should never poll.
- **No bunq, ever, in `backend/`.** All bunq access is via grocery-mcp tools.
- **No Jumbo, ever.** Two stores: AH and Picnic.

---

## 6. Coordination with the other two devs

- **iOS dev** is following `frontend_implementation.md`. Two breaking shifts they expect from us:
  - `/chat` returns 202; the recipe lands as **one** SSE `recipe_complete` (no token streaming).
  - Cart is **two HTTP steps** (`/cart/from-recipe` then `/cart/{id}/select-store`).
  Tell iOS the moment those are live so they can flip `useMockData = false`.
- **Person C** is reshaping `mcp/` per `mcp_implementation.md`. Backend's only dependency is the three MCP tools listed in §3 (`adapters/grocery_mcp.py`). Until those land, you can keep talking to the legacy REST `grocery_api.py` at `http://grocery-mcp:8001` as a fallback — but the goal is to switch to MCP transport before the demo so the "real MCP" claim holds.
- **Compose file ownership:** `deploy/docker-compose.yml` is the canonical compose file. Any change to it needs a heads-up to Person C (their `grocery-mcp` service definition lives there too). Delete the root-level `docker-compose.yml` to avoid drift.
- **New env vars** the deploy workflow must write to `/opt/app/.env`: `GROCERY_MCP_URL=http://grocery-mcp:8001/mcp`, `GROCERY_MCP_IMAGE`, `PICNIC_AUTH_TOKEN` (or `PICNIC_EMAIL` + `PICNIC_PASSWORD`). Existing `BUNQ_API_KEY` stays — grocery-mcp consumes it now, not the backend.

---

## 7. Sequencing summary

```
Phase 0 ──► Phase 1 ──► Phase 1.5 ──► Phase 2 ──► Phase 3 ──► Phase 4 ──► Phase 5
infra      skeleton    contract       AI brain     cart+pay     logging      polish
           (done)      cleanup        (Bedrock     (MCP fan-    (subs +      (resilience,
                       (drop Jumbo,    + Nano       out, bunq    nutrition    seed, demo
                       add select-     Banana)      via MCP)     + plan)      backup)
                       store, retire
                       token stream)
```

Each phase ends with the system in a demoable state. If we have to cut, we cut **inside** the latest phase, not by skipping a later one. The non-negotiable demo slice is **Phase 0 → 3**: chat → recipe → 2-store compare → pick store → pay → paid SSE event arrives on iOS.
