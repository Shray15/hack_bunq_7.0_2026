# Bunq Integration Plan — Meal Card + Share-Cost

> Phased implementation plan for two new bunq integrations on top of the existing checkout flow. Each phase is independently demoable; the milestones at the end group them into checkpoints.

## Context

This app is built for bunq customers, so demonstrating deep bunq integration is the strongest pitch differentiator. Today the only bunq touchpoint is a one-shot bunq.me payment link minted at checkout (`mcp/bunq_payment.py` → `create_payment_request`). We're adding two new bunq features that exercise more of bunq's actual product surface:

1. **Monthly Meal Card** — A persistent virtual debit card backed by a real bunq sandbox sub-account (`MonetaryAccountBank` + `CardDebit type=VIRTUAL`). User funds it once a month with a grocery budget; every grocery checkout can be paid from this card and the balance decrements live. Surfaced as a tile on Home plus a dedicated wallet screen.
2. **Post-checkout bunq.me share-cost link** — After a user pays for a "cooking for friends" meal, generate a bunq.me personal payment link with a per-person share that the user shares via iMessage/WhatsApp; friends pay via iDEAL/card/bank. Reuses the existing MCP `create_payment_request` infrastructure, so this is mostly UX work.

Both features hook into the existing checkout pipeline — they don't replace bunq.me payment, they extend it.

---

## Architecture overview

- **Backend**: FastAPI (Python 3.12) on EC2 `:4567`. Bunq SDK is `bunq-sdk-python` and is already authenticated in `mcp/bunq_sandbox.conf` via `mcp/scripts/bootstrap_bunq.py`.
- **MCP server (port 8001)**: Keeps current `create_payment_request` / `get_payment_status` tools. Reused as-is for the share-cost link. We do NOT add card APIs to MCP — cards aren't an LLM-callable tool, they're a user-facing feature, so they go in a new backend adapter that talks to bunq directly.
- **iOS**: SwiftUI, hooks into existing `OrderReviewView` checkout flow and adds a new Wallet screen + Home tile.
- **bunq sandbox model**: Each user gets one sub-account per month (`MonetaryAccountBank`) with the budget transferred in via `Payment` from the primary account; one `CardDebit type=VIRTUAL` is issued against that sub-account. Paying with the card = `Payment` from the sub-account back to the primary (simulates a merchant charge in sandbox).

---

## Phase 0 — Pre-req: Fix bunq amount-precision bug

**File**: `mcp/bunq_payment.py` (per existing doc `bunq_payment_amount_fix.md`)

- Switch from `RequestInquiry` to `BunqMeTab` so the amount is locked into the URL (currently a fallback URL `https://bunq.me/pay/{id}` lets the payer enter any amount — broken for both checkout and share-cost).
- Remove the generic fallback URL entirely.
- Update `get_payment_status` to read `BunqMeTab.status` instead of `RequestInquiry.status`.
- This phase is **mandatory before Phase 8** because the share-cost feature relies on bunq.me URLs locking the per-person amount.

**Verification**: existing checkout still works end-to-end; payment URL on bunq.me web shows non-editable amount.

---

## Phase 1 — Backend bunq cards adapter

**New file**: `backend/app/adapters/bunq_cards.py`

Loads the same `bunq_sandbox.conf` (path via env `BUNQ_DATA_DIR`) that the MCP server uses. Functions (all sync, wrapped in `asyncio.to_thread` at the router layer):

- `create_sub_account(label: str, currency="EUR") -> {monetary_account_id: int, iban: str, status: str}` — `MonetaryAccountBank.create`
- `fund_sub_account(monetary_account_id: int, amount_eur: Decimal, description: str) -> {payment_id, balance_after}` — `Payment.create` from primary account to sub-account
- `issue_virtual_card(monetary_account_id: int, name_on_card: str) -> {card_id, last_4, status}` — `CardDebit.create` with `type="VIRTUAL"`, linked monetary account = sub-account
- `get_balance(monetary_account_id: int) -> Decimal` — `MonetaryAccountBank.get`
- `charge_card(monetary_account_id: int, amount_eur: Decimal, description: str) -> {payment_id, balance_after}` — `Payment.create` sub-account → primary, simulates merchant charge
- `list_card_transactions(monetary_account_id: int, count=50) -> [Transaction]` — `Payment.list` filtered to this MA

**Risks**: bunq sandbox `CardDebit` may need a real card order in some sandbox configurations. Validate empirically in Phase 1; if it requires PIN/physical-card flow, fall back to creating just the sub-account and treating it as the "card" (still real bunq money flow, just no plastic-card UUID). Document in code with `# TODO: revisit if sandbox card creation requires PIN`.

---

## Phase 2 — MealCard model + Alembic migration

**New file**: `backend/app/models/meal_card.py`

```
meal_cards table:
  id (UUID PK)
  owner_id (FK users.id)
  bunq_monetary_account_id (BigInteger)   -- bunq sub-account ID
  bunq_card_id (BigInteger nullable)      -- nullable in case sandbox cards fail
  iban (string)
  last_4 (string nullable)
  monthly_budget_eur (Numeric 10,2)
  current_balance_eur (Numeric 10,2)      -- cached; refreshed via balance endpoint
  month_year (string, "YYYY-MM")
  status (string: "active"|"expired"|"cancelled")
  created_at (datetime)
  expires_at (datetime)                   -- last day of month_year, 23:59
  UNIQUE (owner_id, month_year)
```

**Alembic migration**: `backend/alembic/versions/<rev>_add_meal_cards.py` — `op.create_table(...)`.

**New file**: `backend/app/schemas/meal_card.py` — Pydantic shapes (`MealCardOut`, `MealCardCreate`, `MealCardTopUp`, `MealCardTransactionOut`).

---

## Phase 3 — Meal card endpoints

**New file**: `backend/app/routers/meal_card.py` (mounted in `backend/app/main.py`)

- `POST /meal-card` — body `{monthly_budget_eur: float}`. Creates sub-account → funds it from primary → issues virtual card → persists `MealCard` row. Returns `MealCardOut`. Idempotent for the current month (returns existing if found).
- `GET /meal-card/current` — current month's active card. Refreshes balance via `bunq_cards.get_balance` before returning.
- `GET /meal-card/transactions?limit=50` — recent payments from the sub-account. Maps bunq `Payment` objects to `MealCardTransactionOut` with merchant-style descriptions.
- `POST /meal-card/topup` — body `{amount_eur: float}`. Reuses `bunq_cards.fund_sub_account`. Returns updated card.

All endpoints require JWT (existing `Depends(get_current_user)` pattern).

---

## Phase 4 — Backend checkout integration

**Modify**: `backend/app/schemas/orders.py` (or wherever `CheckoutRequest` lives) — add `payment_method: Literal["bunq_me", "meal_card"] = "bunq_me"`.

**Modify**: `backend/app/orchestrator/order_flow.py` `checkout()` (lines 39–113):

```python
if payment_method == "meal_card":
    card = await get_active_meal_card(owner_id)
    if not card or card.current_balance_eur < cart_total:
        raise HTTPException(400, "insufficient meal-card balance")
    # Charge the card (sub-account → primary)
    result = await bunq_cards.charge_card(
        card.bunq_monetary_account_id,
        cart_total,
        f"Order {order_id} — {recipe_name}",
    )
    # Persist Order with status="paid" immediately
    order.status = "paid"
    order.paid_at = utcnow()
    order.payment_method = "meal_card"
    order.bunq_payment_id = result["payment_id"]
    # Refresh cached balance
    card.current_balance_eur = result["balance_after"]
    # Emit SSE order_status: paid
    # Auto-log meal (existing logic from bunq_poll.py)
    return CheckoutResponse(order_id, payment_url=None, amount_eur=cart_total)
else:
    # existing bunq_me flow unchanged
```

**Modify**: `backend/app/models/order.py` — add `payment_method` column (string, nullable for back-compat) + `bunq_payment_id` (BigInteger nullable, used when paid via meal card).

**Migration**: alembic add columns.

---

## Phase 5 — iOS MealCard model + APIService

**New file**: `ios/Sources/Models/MealCard.swift`

```swift
struct MealCard: Codable, Identifiable {
    let id: String
    let monthYear: String         // "2026-04"
    let monthlyBudgetEur: Double
    let currentBalanceEur: Double
    let last4: String?
    let iban: String
    let status: String            // active|expired|cancelled
    let expiresAt: Date
}

struct MealCardTransaction: Codable, Identifiable {
    let id: String
    let amountEur: Double         // negative = charge, positive = topup
    let description: String
    let createdAt: Date
}
```

**Modify**: `ios/Sources/Services/APIService.swift`

- `func getCurrentMealCard() async throws -> MealCard?`
- `func createMealCard(budgetEur: Double) async throws -> MealCard`
- `func topUpMealCard(amountEur: Double) async throws -> MealCard`
- `func getMealCardTransactions(limit: Int) async throws -> [MealCardTransaction]`
- Extend existing `checkout(cartId:)` → `checkout(cartId:, paymentMethod: PaymentMethod)` where `PaymentMethod` is `enum { case bunqMe, mealCard }`.

---

## Phase 6 — iOS Home tile

**Modify**: `ios/Sources/Views/Home/HomeView.swift` + `HomeViewModel`

- New `MealCardTile` view: compact 3:1 horizontal card, gradient background (reuse `AppDesign` palette), shows:
  - Title: "Meal Card · April"
  - Big balance: "€230.40"
  - Progress bar: 230/300 (filled portion = remaining)
  - Tap → push `MealCardScreen`
- If no active card for the current month: tile shows "Set up your monthly meal card →" CTA → push `MealCardSetupView`.
- HomeViewModel: load on appear via `APIService.getCurrentMealCard()`, refresh on pull-to-refresh.

---

## Phase 7 — iOS dedicated meal-card screen

**New folder**: `ios/Sources/Views/Wallet/`

- `MealCardScreen.swift` — top: hero virtual-card visual (gradient, last_4 as `•••• 1234`, "BUNQ MEAL CARD" branding, IBAN footer, lock icon). Below: balance/budget row, "Top up" button, transactions list (`MealCardTransactionRow`), "About this card" disclosure (explains monthly card, sandbox note).
- `MealCardSetupView.swift` — first-run sheet: stepper / preset buttons (€100/€200/€300/custom), "Create card" button → loading state → success animation → dismiss back to Home with refreshed tile.
- `MealCardTransactionRow.swift` — date, description, amount (red for charge, green for topup).

Card visual is the demo's centerpiece — invest in polish (gradient, subtle motion, shadow). Don't cut polish for stated hackathon deadlines.

---

## Phase 8 — iOS checkout payment-method picker

**Modify**: `ios/Sources/Views/Order/OrderReviewView.swift` and its `OrderViewModel`

- Above the "Pay" button: `PaymentMethodPicker` (segmented control or two large radio cards):
  - **Bunq.me** (default): existing flow.
  - **Meal Card**: shows current balance + projected post-payment balance ("After this: €207.00 remaining"). Disabled with subtitle "Insufficient balance" if balance < cart total.
- "Pay" button label adapts: `"Pay €23.40 with Meal Card"` vs `"Pay €23.40 with bunq.me"`.
- On meal-card payment:
  - Call `APIService.checkout(cartId, paymentMethod: .mealCard)`.
  - Backend returns success synchronously (status=paid).
  - Show full-screen success animation: "Order placed" with new balance "€207.00 remaining".
  - Sandbox disclaimer footer: "Sandbox demo — no real order placed at AH/Picnic. In production, AH/Picnic would charge this card directly."

OrderViewModel: still listen for SSE `order_status` for the bunq.me path; for meal-card, transition synchronously without waiting for SSE.

---

## Phase 9 — Backend bunq.me share-cost endpoint

**New file**: `backend/app/models/meal_share.py`

```
meal_shares table:
  id (UUID PK)
  order_id (FK orders.id)
  owner_id (FK users.id)
  participant_count (int)         -- e.g. 4 means 4 friends, 5 total people, owner pays 1/5
  per_person_eur (Numeric 10,2)
  total_collected_eur (Numeric 10,2 default 0)
  bunq_request_id (string)        -- from create_payment_request
  share_url (string)
  status (string: "open"|"closed")
  created_at (datetime)
  closed_at (datetime nullable)
```

**Migration**: alembic add table.

**New router**: `backend/app/routers/meal_share.py`

- `POST /orders/{order_id}/share-cost` — body `{participant_count: int, include_self: bool=true}`. Computes per-person share = total / (participant_count + (1 if include_self else 0)). Calls existing `grocery_mcp.create_payment_request(per_person_share, f"Your share of {recipe_name}")` — REUSES Phase 0 fixed bunq.me. Persists `MealShare`. Returns `{share_url, per_person_eur, total_eur, participant_count}`.
- `GET /orders/{order_id}/share-cost` — current share state (poll bunq for paid status optionally).

No new MCP work — we reuse existing tooling. The Phase 0 fix is what makes this feature usable (otherwise the per-person amount would be editable on bunq.me).

---

## Phase 10 — iOS post-checkout share UI

**Modify**: `OrderReviewView.swift` post-payment-success state (works for both bunq_me and meal_card paths)

- After order is `paid`, append a new card: "Cooking with friends? Split the cost".
- Tap → sheet `ShareCostSheet`:
  - Stepper: "How many friends are joining?" (default 1, max 10).
  - Preview: "You: €23.40 ÷ 4 = €5.85 each".
  - "Generate link" button → calls `/orders/{id}/share-cost` → shows share URL.
- After link generated:
  - Display the bunq.me URL with copy button.
  - Native iOS share sheet (`ShareLink` / `UIActivityViewController`) with prefilled message: "Hey! Here's your €5.85 share for tonight's dinner: https://bunq.me/...".
- Optional polish: a "X of N paid back" indicator that polls `GET /orders/{id}/share-cost` (skip for v1 if time-tight).

---

## Critical files to modify

- `mcp/bunq_payment.py` — Phase 0 BunqMeTab fix
- `backend/app/orchestrator/order_flow.py` — Phase 4 checkout payment-method branching
- `backend/app/models/order.py` — Phase 4 add `payment_method`, `bunq_payment_id` columns
- `backend/app/main.py` — mount new routers
- `ios/Sources/Services/APIService.swift` — Phases 5, 8
- `ios/Sources/Views/Home/HomeView.swift` + `HomeViewModel` — Phase 6 tile
- `ios/Sources/Views/Order/OrderReviewView.swift` — Phases 8, 10

## New files to create

**Backend**:
- `backend/app/adapters/bunq_cards.py` (Phase 1)
- `backend/app/models/meal_card.py` (Phase 2)
- `backend/app/schemas/meal_card.py` (Phase 2)
- `backend/app/routers/meal_card.py` (Phase 3)
- `backend/app/models/meal_share.py` (Phase 9)
- `backend/app/schemas/meal_share.py` (Phase 9)
- `backend/app/routers/meal_share.py` (Phase 9)
- 3 alembic migrations (Phases 2, 4, 9)

**iOS**:
- `ios/Sources/Models/MealCard.swift` (Phase 5)
- `ios/Sources/Views/Wallet/MealCardScreen.swift` (Phase 7)
- `ios/Sources/Views/Wallet/MealCardSetupView.swift` (Phase 7)
- `ios/Sources/Views/Wallet/MealCardTransactionRow.swift` (Phase 7)
- `ios/Sources/Views/Wallet/MealCardTile.swift` (Phase 6)
- `ios/Sources/Views/Order/PaymentMethodPicker.swift` (Phase 8)
- `ios/Sources/Views/Order/ShareCostSheet.swift` (Phase 10)

## Reused existing code

- `mcp/bunq_payment.py` `create_payment_request` / `get_payment_status` — share-cost reuses these (after Phase 0 fix).
- `backend/app/adapters/grocery_mcp.py` — share-cost calls through this existing wrapper, no new MCP plumbing.
- `bunq_sandbox.conf` + `bootstrap_bunq.py` — meal card adapter loads the same auth context, no re-bootstrap needed.
- Existing JWT `Depends(get_current_user)` — all new endpoints reuse.
- Existing SSE event hub (`backend/app/realtime/`) — emit `order_status: paid` from meal-card path same as existing bunq.me path.
- `AppDesign.swift` — palette/typography for card visual.

---

## Implementation order & milestones

The phases are ordered so you can demo incrementally. Recommended grouping:

- **Milestone A (backend bunq cards working)**: Phase 0 → 1 → 2 → 3. Verify in bunq sandbox web UI: sub-account exists, virtual card issued, balance correct.
- **Milestone B (meal card payable)**: Phase 4. Curl-test end-to-end: create cart → checkout with `payment_method=meal_card` → balance decrements.
- **Milestone C (iOS meal card visible)**: Phase 5 → 6 → 7. App shows tile + screen, can create + top up.
- **Milestone D (full meal-card payment loop)**: Phase 8. Pay-with-card flow works in app.
- **Milestone E (share-cost)**: Phase 9 → 10. Generate bunq.me share link from completed order.

Each milestone is independently demoable.

---

## Verification

**Backend (per phase, before iOS work):**
- Phase 0: existing checkout still works; `curl POST /order/checkout` then open returned URL — bunq.me page shows fixed amount, no edit field.
- Phase 1–3: `pytest backend/tests/test_meal_card.py` (new), plus manual `curl POST /meal-card` → check bunq sandbox web UI for new sub-account + card.
- Phase 4: `curl POST /order/checkout` with `payment_method=meal_card` → response status=paid, no payment_url. Check `GET /meal-card/current` → balance decremented.
- Phase 9: `curl POST /orders/{id}/share-cost` with `participant_count=3` → returns bunq.me URL; opening it shows the per-person amount locked.

**iOS (Xcode simulator):**
- Phase 6: Home shows tile with current balance; tap navigates to MealCardScreen.
- Phase 7: Setup flow creates a card; transactions list populates after a few payments.
- Phase 8: Order checkout shows both payment options; meal-card path completes synchronously with success animation; balance on Home tile reflects the deduction.
- Phase 10: Post-payment, "Split the cost" sheet generates a link; native share sheet opens with prefilled text.

**End-to-end demo path:**
1. Open app → Home shows "Set up your meal card" CTA → tap → set €300 budget → card created.
2. Plan a recipe via chat → recipe screen → "Order now" → store comparison → review.
3. On OrderReview: select "Pay with Meal Card" → tap pay → "Order placed!" → balance now €276.60 on Home tile.
4. From the paid order screen: tap "Split the cost" → 3 friends → bunq.me link generated → share via Messages.
5. Open the link in browser (or another device) → bunq.me page shows €5.85 fixed.

---

## Open risks & decisions deferred

- **bunq sandbox CardDebit type=VIRTUAL availability**: validated empirically in Phase 1. If unavailable, document and ship sub-account-only (still real bunq money rails, no card UUID).
- **Apple Wallet PassKit**: explicitly out of scope for v1 (you didn't request it; it requires .pkpass cert plumbing). Add as future enhancement.
- **Card monthly rollover**: when month_year changes, old card is marked `expired` lazily on next `GET /meal-card/current`. No background cron needed.
- **Concurrency**: meal-card payments aren't strictly atomic against `current_balance_eur`. For sandbox demo, fine. For prod, would need `SELECT FOR UPDATE` on the card row before charging.
- **Share-cost paid tracking**: v1 just polls bunq once when iOS opens the order detail. Real-time SSE updates of "X of N paid" deferred unless time permits.
