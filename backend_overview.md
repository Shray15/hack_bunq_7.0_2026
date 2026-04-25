# Backend Overview — Hackathon Cooking & Health App

This is the backend-side companion to `plan_draft.md`. It captures the decisions made during brainstorming and the contract everyone else can build against.

---

## 1. Mission

The backend is the **only** thing iOS talks to. It orchestrates:

- **Claude Sonnet 4.6** — recipe NLU + generation, ingredient substitution suggestions
- **Gemini Nano-Banana** — dish image generation
- **OpenFoodFacts (and USDA fallback)** — nutrition validation
- **MCP servers (AH, Jumbo, Picnic)** — product search and cart pricing
- **bunq sandbox** — payment request URL + status polling

If a model, MCP, or external API exists, it lives behind us. iOS sees a clean REST + SSE surface.

---

## 2. Stack

| Concern | Choice |
|---|---|
| Language / runtime | Python 3.12 |
| Web framework | FastAPI |
| Async | native `asyncio` + `FastAPI BackgroundTasks` (no Celery, no Redis) |
| Validation | Pydantic v2 |
| Database | SQLite (everywhere — local + EC2, on an EBS volume in prod) |
| ORM / migrations | SQLAlchemy 2.x async + Alembic |
| HTTP client | `httpx` (async) |
| LLM SDKs | `anthropic` (Claude), `google-genai` (Gemini) |
| MCP | official Python MCP client SDK (stdio + HTTP transports) |
| Auth | JWT (HS256) via `python-jose`, passwords via `passlib[argon2]` |
| Config | `pydantic-settings` reading `.env` |
| Logging | `structlog` → JSON |
| Server | `uvicorn` locally, `uvicorn` behind `nginx` on EC2 |
| Packaging | `uv` for env mgmt, Docker for prod image |

---

## 3. Architecture

```
┌──────────────────┐
│   iOS (SwiftUI)  │
└────────┬─────────┘
         │ REST + SSE  (JWT auth)
         ▼
┌─────────────────────────────────────────────────┐
│                FastAPI Backend                  │
│                                                 │
│  ┌──────────┐  ┌─────────────┐  ┌────────────┐  │
│  │  Auth /  │  │ Orchestrator│  │ Realtime   │  │
│  │  Profile │  │ (chat,      │  │ Hub        │  │
│  │          │  │  recipe,    │  │ (SSE fan-  │  │
│  └──────────┘  │  cart, plan)│  │  out)      │  │
│                └──────┬──────┘  └─────┬──────┘  │
│                       │               ▲         │
│  ┌────────────────────┴──────┐        │         │
│  │  Background tasks         │────────┘         │
│  │  (image gen, bunq poll,   │  pushes events   │
│  │   substitutions, OFF      │                  │
│  │   nutrition lookup)       │                  │
│  └────┬──────────┬───────────┘                  │
│       │          │                              │
│       ▼          ▼                              │
│   SQLite     ┌────────────┐                     │
│   (SQLA)     │ External   │                     │
│              │ adapters   │                     │
│              └──┬─┬─┬─┬─┬─┘                     │
└─────────────────┼─┼─┼─┼─┼───────────────────────┘
                  │ │ │ │ │
                  ▼ ▼ ▼ ▼ ▼
              Claude Gemini OFF MCP×3 bunq
```

**Single user-facing realtime channel:** `GET /events/stream` (SSE, JWT-authenticated). Every async event lands there: streamed recipe tokens, image ready, cart computed, substitution proposed, order status changes, payment paid.

---

## 4. Decisions Locked In (from brainstorm)

| Topic | Decision |
|---|---|
| `/chat` style | One-shot per request (no multi-turn history) |
| `/chat` vs `/recipes/generate` | Both kept. `/chat` does NLU + delegates internally to `/recipes/generate` |
| Image timing | Progressive — recipe streams first, image pushed via `image_ready` SSE event |
| MCP integration | Real MCP protocol; backend is an MCP client to all three stores |
| Auth | JWT with signup/login |
| DB tables | users + profiles, recipes, orders, meal_plans, plus carts, cart_items, meals_consumed, food_db_cache |
| Deployment | Local first → EC2 (eu-west-1) for prod |
| bunq flow | Mint payment URL **and** poll bunq sandbox for paid status |
| Realtime | Single persistent SSE channel `GET /events/stream` |
| Stores | All three (AH + Jumbo + Picnic) with side-by-side price comparison |
| Pantry | No persistent pantry. User edits cart line-items before checkout |
| Nutrition | Validate LLM macros against OpenFoodFacts; backend replaces hallucinated numbers |
| Recipe LLM | Claude Sonnet 4.6 (image still Gemini Nano-Banana) |
| Substitutions | Backend asks Claude for substitutes, retries MCP automatically (self-healing) |
| Calorie logging | User picks from "ordered or prepared" list, sets portion (e.g. 0.5), backend computes intake |
| Order states | `draft → ready_to_pay → paid → fulfilled` (+ failure transitions) |
| Background tasks | In-process asyncio + FastAPI BackgroundTasks |
| Recipe library | Full history + favorites + one-tap "cook again" |

**Deferred / TBD:** meal-plan horizon. Recommend launching with **tomorrow's meal, macro-aware** (uses today's logged meals + remaining daily macro budget). Schema accommodates a weekly view if we extend.

---

## 5. REST + SSE API Contract

All endpoints (except auth) require `Authorization: Bearer <jwt>`.

### Auth
- `POST /auth/signup` → `{ access_token }` (also creates profile)
- `POST /auth/login` → `{ access_token }`
- `GET  /user/profile`
- `PATCH /user/profile` — diet, allergies, daily macro targets, store priority

### Recipe pipeline
- `POST /chat` — `{ transcript: string }` → SSE-style streaming response (or returns immediately and pushes events to `/events/stream` — see §6). Internally:
  1. Claude NLU: transcript → constraints (calories, macros, dietary, vibe)
  2. Calls `/recipes/generate` with those constraints
  3. Fires async image-gen task
- `POST /recipes/generate` — `{ constraints, refine_of?: recipe_id }` → full Recipe JSON (synchronous; this is the workhorse)
- `GET  /recipes/{id}`
- `GET  /recipes?favorited=true&limit=20`
- `POST /recipes/{id}/favorite` (toggle)
- `POST /recipes/{id}/recook` → creates a new draft cart pre-filled from this recipe

### Cart + checkout
- `POST  /cart/from-recipe` — `{ recipe_id }` → cart with **price comparison across all 3 stores**
- `PATCH /cart/{cart_id}/items/{item_id}` — `{ removed: true }` or `{ qty: N }` (this is the pantry UX: "I already have rice, drop it")
- `POST  /cart/{cart_id}/checkout` — `{ store: "ah" | "jumbo" | "picnic" }` → `{ order_id, payment_url, amount_eur }`

### Orders
- `GET /orders/{id}`
- `GET /orders?status=paid&limit=50`

### Meal logging
- `POST /meals/log` — `{ recipe_id, portion: 0.5, eaten_at? }` (`portion` defaults to 1.0)
- `GET  /meals/today` → today's log + remaining macro budget vs target
- `GET  /meals/history?from=&to=`
- `GET  /meals/options` — recipes the user has either ordered or marked as prepared, ready to log

### Meal plan
- `POST /meal-plan/tomorrow` — generates macro-aware recipe for tomorrow
- `GET  /meal-plan/upcoming` — placeholder for weekly extension

### Realtime
- `GET /events/stream` — long-lived SSE; auth via `?token=` query param (iOS EventSource limitation)

---

## 6. SSE Event Schema

Every event has shape `event: <name>\ndata: <json>`. Per-user fan-out keyed on JWT subject.

| Event | Data | When |
|---|---|---|
| `recipe_token` | `{ chat_id, delta }` | While Claude is streaming a recipe |
| `recipe_complete` | `{ chat_id, recipe_id }` | LLM finished + nutrition validated + persisted |
| `image_ready` | `{ recipe_id, image_url }` | Nano Banana returned |
| `cart_ready` | `{ cart_id, comparison: [{store, total_eur, missing}] }` | `/cart/from-recipe` finished MCP fan-out |
| `substitution_proposed` | `{ cart_id, ingredient, alternatives: [...] }` | MCP missed, Claude suggested replacements |
| `order_status` | `{ order_id, status, paid_at? }` | State machine transition |
| `meal_plan_ready` | `{ recipe_id, scheduled_for }` | Tomorrow's plan generated |
| `error` | `{ scope, code, message }` | Anything user-facing failed |

`/chat` itself is non-streaming at the HTTP level: it returns `202 { chat_id }` and emits all subsequent events on `/events/stream`. Single channel = simpler client code.

---

## 7. Data Model (SQLite via SQLAlchemy)

```
users
  id, email UNIQUE, password_hash, created_at

profiles
  user_id PK FK, diet, allergies JSON, daily_calorie_target,
  protein_g_target, carbs_g_target, fat_g_target,
  store_priority JSON  -- e.g. ["ah","jumbo","picnic"]

recipes
  id, user_id FK, name, calories, macros JSON, ingredients JSON,
  steps JSON, prep_time_min, image_url NULLABLE, image_status,
  llm_model, llm_estimate JSON, validated_macros JSON,
  source ENUM('chat','meal_plan','recook'), parent_recipe_id NULLABLE,
  favorited_at NULLABLE, created_at

carts
  id, user_id FK, recipe_id FK, status ENUM('open','converted','abandoned'),
  store_comparison JSON,  -- snapshot from MCP fan-out
  selected_store NULLABLE, created_at

cart_items
  id, cart_id FK, ingredient_name, store, product_id, product_name,
  qty, unit_price_eur, total_price_eur, removed_at NULLABLE

orders
  id, user_id FK, cart_id FK, store, total_eur,
  bunq_payment_url, bunq_request_id,
  status ENUM('draft','ready_to_pay','paid','fulfilled','payment_failed','mcp_failed'),
  paid_at NULLABLE, fulfilled_at NULLABLE, created_at

meals_consumed
  id, user_id FK, recipe_id FK, portion FLOAT,
  calories_computed, macros_computed JSON,
  eaten_at, source ENUM('order','manual')

meal_plans
  id, user_id FK, recipe_id FK, scheduled_for DATE,
  status ENUM('proposed','accepted','skipped'), created_at

food_db_cache
  ingredient_query, normalized_name, per_100g JSON,
  source ENUM('off','usda'), fetched_at
```

---

## 8. Order State Machine

```
        ┌─────────┐  user opens cart
        │  draft  │
        └────┬────┘
             │ checkout: bunq URL minted
             ▼
       ┌──────────────┐
       │ready_to_pay │──── poller times out ──► payment_failed
       └────┬─────────┘
            │ bunq sandbox: paid
            ▼
         ┌──────┐
         │ paid │──── MCP placement fails ──► mcp_failed
         └──┬───┘
            │ MCP order_placed
            ▼
       ┌─────────────┐
       │ fulfilled   │
       └─────────────┘
```

Each transition emits `order_status` on the SSE channel.

---

## 9. Recipe Brain Architecture (Claude Sonnet 4.6)

- **Single Claude call per recipe.** Tool-use forced output; one tool: `emit_recipe(...)` with strict JSON schema matching §5 of `plan_draft.md`.
- **Prompt caching** on the system block (schema + dietary rules + JSON enforcement). User block is small and uncached: profile snapshot + today's logged macros + parsed constraints.
- **NLU pre-step in `/chat`:** a separate (small, cached) Claude call converts free-text transcript → constraints object. Avoids one giant prompt and keeps the recipe call deterministic.
- **Substitution suggestions:** when MCP search misses, a focused Claude call (`suggest_substitutions(ingredient, recipe_context)`) returns up to 3 alternatives. Backend retries MCP with each in priority order before giving up.
- **Nutrition post-processing:** for each ingredient, look up per-100g macros via OpenFoodFacts (cached in `food_db_cache`), recompute totals, store both `llm_estimate` and `validated_macros`. iOS shows validated. Mismatches > 15% logged but not exposed.

---

## 10. External Adapter Boundaries

Each external system gets its own module with a clean interface so the orchestrator stays thin.

| Module | Owner of integration | Responsibility |
|---|---|---|
| `app.adapters.claude` | Person D (prompts) + B (call site) | NLU, recipe gen, substitutions |
| `app.adapters.gemini` | Person D | Nano-Banana image gen |
| `app.adapters.nutrition` | Person B | OpenFoodFacts/USDA lookup + cache |
| `app.adapters.mcp` | Person C (servers) + B (client) | Stdio/HTTP MCP client wrapping all three stores |
| `app.adapters.bunq` | Person C | Sandbox payment request + status poll |

Person D delivers their adapter as an importable module (per §4 of `plan_draft.md`); Person C runs MCP servers as separate processes that we connect to.

---

## 11. Background Tasks (in-process asyncio)

| Task | Trigger | Emits |
|---|---|---|
| Image generation | `recipe_complete` | `image_ready` (5–15 s) |
| bunq status poller | order → `ready_to_pay` | `order_status` paid/payment_failed (poll every 2 s, max 5 min) |
| Substitution retry | MCP missing ingredient | `substitution_proposed`, then re-run MCP |
| OFF nutrition fetch | recipe generation, lazy per-ingredient | populates `food_db_cache` |
| Meal-plan precompute | nightly cron OR on-demand | `meal_plan_ready` |

All run in the FastAPI event loop. State lives in SQLite, so a restart is recoverable for everything except in-flight LLM/image calls (those just retry from the next user action).

---

## 12. Auth & Security

- JWT HS256, 30-day TTL, secret in `JWT_SECRET` env. Refresh tokens deferred — fine for hackathon scope.
- Argon2 password hashing.
- `/events/stream` reads JWT from query param (browsers / iOS `EventSource` cannot set custom headers); rotate `JWT_SECRET` if a stream URL ever leaks.
- Per-request rate limiting on `/chat` and `/recipes/generate` (simple in-memory token bucket per user) to control LLM cost.
- All external API keys via `pydantic-settings` from `.env` locally and AWS SSM Parameter Store on EC2.

---

## 13. Local Dev

```
backend/
  app/
    main.py            # FastAPI app, router mounting
    config.py          # pydantic-settings
    db.py              # SQLAlchemy engine, session
    models/            # ORM models
    schemas/           # Pydantic request/response
    routers/
      auth.py
      profile.py
      chat.py
      recipes.py
      cart.py
      orders.py
      meals.py
      meal_plan.py
      events.py
    orchestrator/
      chat_flow.py
      cart_flow.py
      order_flow.py
    adapters/
      claude.py
      gemini.py
      nutrition.py
      mcp.py
      bunq.py
    realtime/
      hub.py           # per-user event fan-out
      events.py        # event types
    background/
      images.py
      bunq_poll.py
      substitutions.py
  alembic/
  data/
    app.db             # gitignored
  tests/
  Dockerfile
  pyproject.toml
  .env.example
```

Run: `uv run uvicorn app.main:app --reload`. iOS hits the laptop via ngrok during dev.

---

## 14. EC2 Deployment

- Single t3.small in `eu-west-1` (NL grocery latency).
- Docker image built with `uv` in CI (or locally), pushed to ECR.
- `systemd` unit launches the container; mounts `/data` (EBS) for SQLite.
- `nginx` reverse proxy in front: TLS via Let's Encrypt (HTTPS is required for SSE on iOS).
- MCP servers: run as sibling docker containers on the same instance, backend connects via HTTP transport.
- Logs: `structlog` JSON → stdout → CloudWatch agent.
- Daily SQLite snapshot to S3.
- Secrets pulled from SSM Parameter Store at container boot.

---

## 15. Backend Build Phasing

1. **Skeleton + contracts** — FastAPI scaffold; every endpoint returns realistic stub JSON; JWT auth working signup→login→/me; `/events/stream` emits stub events on a timer; SQLite schema migrated. *(unblocks iOS immediately)*
2. **Recipe brain online** — Claude integration, structured tool output, OpenFoodFacts validation, image task firing.
3. **Cart + payment** — MCP client connected to all 3 stores, price comparison, bunq URL minting, status polling, substitution self-healing.
4. **Library + logging + plan** — favorites, recook, meal logging with portions, tomorrow's meal-plan generator.
5. **Polish** — retries/fallbacks for every external service, structured logging tuned, Dockerfile, EC2 deploy, CloudWatch, S3 backups.

---

## 16. Open Questions / Things to Re-decide Later

- **Meal-plan horizon** — start with tomorrow only; revisit weekly view after demo path is solid.
- **Push notifications (APNs)** — out of scope unless we want "tomorrow's meal is ready" reminders.
- **Refresh tokens** — deferred; demo lifetime fits inside 30-day access token.
- **Multi-user concurrency on SQLite** — fine for demo and early users; if real product, plan a Postgres swap (SQLAlchemy already abstracts it).
- **MCP transport** — defaulting to HTTP for easy EC2 sibling-container wiring; stdio if Person C prefers it locally.
