# Cooking Companion

> *Tell us what's happening. We handle the food.*

Cooking Companion is a voice-first iOS app that collapses four separate daily tasks — deciding what to eat, building a shopping list, paying for groceries, and tracking nutrition — into a single conversational flow. You speak, the app thinks, groceries arrive, and your macros update automatically.

---

## The Problem

Eating well today requires juggling four separate tools:

1. A recipe app to find something suitable
2. A grocery app to build a list (manually, item by item)
3. A banking app to pay
4. A nutrition tracker to log the meal

None of them talk to each other. The result is friction and abandoned good intentions.

---

## What We Built

A single app that handles the full loop end to end.

```
You speak  →  AI generates a recipe  →  Groceries are priced and ordered
→  bunq handles payment  →  Meal is auto-logged to your nutrition diary
```

### Key Flows

**1. Conversational meal planning**
Speak or type naturally: *"Four friends coming over tonight, something Italian, nothing too heavy"* or *"Quick high-protein lunch under 600 calories"*. Claude interprets your intent alongside your stored dietary profile (diet type, allergies, macro targets) and streams a full recipe back in seconds.

**2. Instant grocery comparison**
The moment a recipe is confirmed, the app fans out across Albert Heijn and Picnic simultaneously, matches every ingredient to real products in their catalogues, and presents a side-by-side price comparison. Missing items are flagged with AI-suggested substitutes.

**3. bunq-powered checkout**
Pick your store and pay. Two payment paths are available:

- **bunq.me** — a fixed-amount payment link opens in your browser (iDEAL, card, bank transfer). The moment bunq confirms payment, the order status updates in real time via a server-sent event stream.
- **Meal Card** — a bunq virtual card tied to a monthly food budget you set yourself. Checkout is instant and synchronous; no browser redirect needed.

**4. Automatic nutrition tracking**
Every paid order auto-logs the meal to your diary. Macro bars on the home screen update immediately. No manual entry.

**5. Split the cost**
After checkout a single tap generates a bunq.me link pre-set to your friends' per-person share. Copy it, send it via iMessage or WhatsApp, done.

---

## Intelligence Layer

### Claude Sonnet 4.6 — via AWS Bedrock

All recipe intelligence runs through Claude Sonnet 4.6, accessed from AWS Bedrock in `us-east-1`. Claude handles five distinct tasks in the meal-generation pipeline:

| Task | What Claude does |
|------|-----------------|
| **Natural-language understanding** | Converts a spoken transcript + your dietary profile into structured constraints (max calories, min protein, must-avoid ingredients, vibe) |
| **Ingredient generation** | Produces a precise ingredient list in Dutch supermarket names (so AH/Picnic searches actually hit) with metric quantities |
| **Cooking steps** | Writes 5–8 clear, sequential steps scaled to the number of people |
| **Macro estimation** | Estimates kcal, protein, carbs, and fat per serving — scaled to your personal daily calorie target, so a 3 500 kcal/day athlete gets appropriately larger portions than a 1 800 kcal/day target |
| **Substitution suggestions** | When a grocery search misses an ingredient, Claude proposes up to three alternatives; the backend retries automatically before surfacing the gap to the user |

Prompts are cached with `cache_control: ephemeral` so repeated calls within a session reuse the Bedrock prompt cache, cutting latency and cost on the structured system context.

### Gemini 2.5 Flash (Nano-Banana) — image generation

Every recipe gets a generated food photograph. After Claude returns a recipe, the backend fires an async image-generation task against Gemini 2.5 Flash. The model receives the dish name and a one-line summary, and returns a base64-encoded PNG. The iOS app shows a loading placeholder until the `image_ready` server-sent event arrives, at which point the image snaps in without any user action.

---

## bunq Integration

Cooking Companion integrates with bunq at three levels.

### Payment requests (bunq.me)

The backend creates a `BunqMeTab` — a fixed-amount tab with a canonical `bunq.me/<handle>/<amount>/<description>` URL — whenever a user checks out via the standard payment path. The amount is locked on creation so the payer cannot edit it. The backend polls the tab status every two seconds for up to five minutes and transitions the order to *paid* the moment bunq confirms, firing an SSE event to the app.

### Meal Card (virtual card)

Users can set up a monthly meal budget backed by a real bunq virtual card:

1. The backend creates a `MonetaryAccountBank` sub-account under the user's bunq account
2. Funds are transferred from the primary account to the sub-account up to the chosen monthly budget (€100 / €200 / €300 / custom)
3. A `CardDebit` virtual card is issued against the sub-account
4. At checkout, selecting "Pay with Meal Card" deducts the grocery total directly from the sub-account — synchronously, no redirect
5. The card screen shows the IBAN, last four digits, current balance, and a full transaction history pulled live from bunq

### Cost sharing

After any order (via either payment method), the app can split the cost with friends. The backend mints a new bunq.me payment request locked to the per-person share amount. The iOS share sheet pre-fills an iMessage/WhatsApp message with the link.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                                  │
│  Voice → SpeechService → ChatView → APIService      │
│  SSE listener (RealtimeService) → reactive UI       │
└────────────────────┬────────────────────────────────┘
                     │ HTTP/SSE  :4567
┌────────────────────▼────────────────────────────────┐
│  Backend (FastAPI + Python 3.12)                    │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ Orchestrator│  │ SSE fan-out  │  │ Alembic DB │ │
│  │ chat_flow   │  │ per-user ch. │  │ PostgreSQL │ │
│  │ order_flow  │  └──────────────┘  └────────────┘ │
│  │ meal_flow   │                                    │
│  └──────┬──────┘                                    │
└─────────┼───────────────────────────────────────────┘
          │
   ┌──────┴──────────────────────────────────┐
   │  External APIs                          │
   │  ├── AWS Bedrock (Claude Sonnet 4.6)    │
   │  ├── Gemini 2.5 Flash (food images)     │
   │  ├── Albert Heijn product search        │
   │  ├── Picnic product search + cart       │
   │  └── bunq SDK (payments + virtual card) │
   └─────────────────────────────────────────┘
          │
   :8001  │
┌─────────▼────────────┐
│  MCP Server          │
│  FastMCP (HTTP)      │
│  grocery search      │
│  bunq payment tools  │
└──────────────────────┘
```

### Backend

- **FastAPI** with async SQLAlchemy ORM
- **PostgreSQL** for all persistent state (users, recipes, orders, meals, meal cards, shares)
- **Alembic** for schema migrations (8 versions in production)
- **Server-Sent Events** for real-time push — one long-lived connection per user carries all async events (recipe streaming, image ready, order paid, etc.)
- **JWT HS256** for stateless authentication

### MCP Server

A lightweight FastMCP HTTP server (port 8001, internal-only) wraps:
- Albert Heijn and Picnic product search with gram-aware ingredient matching and English→Dutch translation
- bunq payment request creation and status polling
- Picnic cart write operations (clear + add items at checkout)

The backend's cart orchestrator fans out to the MCP server for every ingredient in parallel, aggregates the price comparison, and surfaces missing items.

### iOS App

- **SwiftUI + MVVM**, iOS 16+
- **EnvironmentObject** for shared app state (auth, meal card, macros)
- **RealtimeService** — persistent SSE connection that delivers all async updates without polling
- **SpeechService** — AVFoundation + Speech framework for on-device voice transcription
- **HealthKit** integration for step count, calories burned, and post-workout window detection

---

## Deployment

### Infrastructure

The backend and MCP server run as Docker containers on a single AWS EC2 `t3.small` instance (2 vCPU, 2 GB RAM, 30 GB gp3). The iOS app connects directly to the EC2 instance at `http://<ec2-ip>:4567` — no load balancer, no reverse proxy.

```
EC2 (Ubuntu 22.04)
├── /opt/app/docker-compose.yml   ← production
├── /opt/app-staging/             ← staging (port 4568)
└── /data/
    ├── postgres/                 ← postgres volume
    └── bunq/                     ← bunq credentials shared between backend + MCP
```

### Docker Compose services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| `postgres` | postgres:16-alpine | 5432 (internal) | Primary database |
| `backend` | ghcr.io/…:main-{sha} | 4567 (public) | FastAPI app |
| `grocery-mcp` | ghcr.io/…-grocery-mcp:main-{sha} | 8001 (internal) | MCP server |

All three share a Docker bridge network. The MCP server is never exposed to the public internet.

### CI / CD

Every push to `main` runs a two-stage GitHub Actions pipeline:

**CI** (runs on every branch + PR):
- `ruff` lint and format check
- `mypy` type checking
- Alembic `upgrade head` against a live Postgres service
- `pytest` unit tests

**Deploy** (on merge to `main`):
1. Build and push `backend` and `grocery-mcp` images to GitHub Container Registry
2. SCP the updated `docker-compose.yml` and `.env` to EC2
3. `docker compose pull && docker compose up -d` on the remote
4. Poll `/healthz` until the new version string appears (≈ 90s timeout)

A parallel **staging** workflow deploys `feature/*` branches to port 4568 on the same instance for integration testing before merge.

### Environment variables (injected by GHA)

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | Token signing key |
| `AWS_ACCESS_KEY_ID / SECRET / TOKEN` | Bedrock credentials |
| `AWS_BEDROCK_MODEL_ID` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `GEMINI_API_KEY` | Gemini image generation |
| `BUNQ_API_KEY` | bunq SDK authentication |
| `BUNQ_ME_USERNAME` | bunq.me handle for payment URLs |
| `PICNIC_EMAIL / PASSWORD` | Picnic account credentials |

---

## Running Locally

**Backend**

```bash
cd backend
cp .env.example .env   # fill in keys
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 4567
```

**MCP server**

```bash
cd mcp
pip install -r requirements.txt
python server.py        # listens on :8001
```

**iOS**

Open `ios/CookingCompanion.xcodeproj` in Xcode. Set `APIService.baseURL` to your local machine's IP and run on a simulator or device (iOS 16+).

> Without AWS credentials the backend runs in stub mode — Claude calls return deterministic fixture JSON so the full UI flow can be exercised without Bedrock access.

---

## Project Structure

```
.
├── backend/
│   ├── app/
│   │   ├── adapters/       # claude.py, gemini.py, bunq_cards.py, bunq_me.py
│   │   ├── orchestrator/   # chat_flow, order_flow, meal_flow, meal_card_flow, …
│   │   ├── routers/        # auth, profile, chat, recipes, cart, orders, meals, …
│   │   ├── models/         # SQLAlchemy ORM models
│   │   └── schemas/        # Pydantic request/response schemas
│   └── alembic/versions/   # 8 migrations
├── mcp/
│   ├── server.py           # FastMCP HTTP server
│   ├── bunq_payment.py     # BunqMeTab create + poll
│   ├── matching.py         # ingredient → product matching, gram conversion
│   ├── ah_client.py        # Albert Heijn product search
│   └── picnic_client.py    # Picnic search + cart write
├── ios/
│   └── Sources/
│       ├── App/            # AppState, AppDesign, entry point
│       ├── Services/       # APIService, AuthService, RealtimeService, SpeechService, HealthKitService
│       ├── Views/          # Home, Chat, Recipe, Order, Wallet, Tracker, Profile
│       └── Models/         # Codable structs mirroring backend schemas
├── deploy/
│   ├── docker-compose.yml          # production
│   ├── docker-compose.staging.yml  # staging (port 4568)
│   └── setup-ec2.sh                # one-time EC2 bootstrap script
└── .github/workflows/
    ├── ci.yml              # lint + test on every push
    ├── deploy.yml          # build + deploy on main
    └── deploy-staging.yml  # staging deploy on feature branches
```

---

## Tech Stack at a Glance

| Layer | Technology |
|-------|-----------|
| iOS client | SwiftUI, MVVM, HealthKit, Speech framework |
| Backend | Python 3.12, FastAPI, SQLAlchemy 2.x async |
| Database | PostgreSQL 16 (production), SQLite (dev) |
| Migrations | Alembic |
| LLM | Claude Sonnet 4.6 via AWS Bedrock |
| Image generation | Gemini 2.5 Flash (Nano-Banana) |
| Payments | bunq SDK — BunqMeTab, MonetaryAccountBank, CardDebit |
| Grocery search | Albert Heijn REST API, Picnic (python-picnic-api2) |
| MCP layer | FastMCP (HTTP, port 8001) |
| Realtime | Server-Sent Events (SSE) |
| Auth | JWT HS256 |
| Containerisation | Docker Compose |
| CI/CD | GitHub Actions → EC2 (t3.small) |
