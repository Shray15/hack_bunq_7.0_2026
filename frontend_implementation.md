# Frontend Implementation — iOS

Owner: iOS dev. Read top-to-bottom; pick up the current branch from `ios/` and move it onto the contracts below.

This doc is the **single source of truth** for what iOS sends and expects. If anything here disagrees with old comments in `APIService.swift`, this doc wins.

---

## TL;DR

- `APIService.useMockData` → flip to **false** when ready. Update `baseURL` to `http://<ec2-ip>:4567` (no Cloudflare, no HTTPS for the demo).
- Add **real signup + login screens**. Persist JWT in Keychain. Send `Authorization: Bearer <jwt>` on every request except `/auth/*`.
- Replace the current "stream tokens on `/chat`" pattern. The new model is: `POST /chat` returns 202 immediately; the recipe lands as an SSE event on a separate long-lived `GET /events/stream` channel.
- Recipe → Cart is **two steps**, not one:
  1. `POST /cart/from-recipe` → returns store totals only (AH and Picnic), no items yet.
  2. `POST /cart/{cart_id}/select-store` → returns the full item list with product images for the chosen store.
- Bunq paid state arrives as an SSE `order_status` event. No polling needed in iOS.
- Three stores → **two stores**. Jumbo is gone. UI must accommodate AH + Picnic only.

---

## 1. Architecture overview

```
┌──────────────────┐     REST + SSE        ┌──────────────────┐
│   iOS (SwiftUI)  │ ◄───────────────────► │   Backend        │
│                  │   JWT auth on header  │   (FastAPI)      │
└──────────────────┘                        └────────┬─────────┘
                                                     │
                                  Bedrock (Claude)   │   HTTP MCP
                                  Nano Banana         │   ┌──────────────────┐
                                                     ├──►│   grocery-mcp    │
                                                     │   │   AH + Picnic    │
                                                     │   │   bunq           │
                                                     │   └──────────────────┘
```

iOS only ever talks to the **backend**. Never directly to grocery-mcp, never directly to AWS, never directly to bunq.

---

## 2. Auth flow

### Signup screen (one-time)

`POST /auth/signup`
```json
// request
{ "email": "alice@bunq.demo", "password": "supersecret" }
```
```json
// 201 response
{ "access_token": "<jwt>", "token_type": "bearer" }
```
Errors: `409 {"detail": "email already registered"}`, `422` for validation.

Password rule: **min 8 chars, max 128**. Show that on the form.

### Login screen

`POST /auth/login`
```json
// request
{ "email": "alice@bunq.demo", "password": "supersecret" }
```
```json
// 200 response
{ "access_token": "<jwt>", "token_type": "bearer" }
```
Errors: `401 {"detail": "invalid email or password"}`.

### Token storage

- Persist `access_token` in **Keychain** under a single account name (e.g., `cooking-companion`).
- TTL is 30 days. If a request returns `401`, route the user back to login.
- Add a Bearer-injecting wrapper on `URLSession`. Do not re-implement auth on each call site.

```swift
// APIService.swift — add this
private var bearer: String? { KeychainStore.read("cooking-companion") }
private func authedRequest(_ url: URL) -> URLRequest {
    var req = URLRequest(url: url)
    if let token = bearer { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return req
}
```

### SSE auth quirk

`EventSource` (and our `URLSession.bytes()` SSE) cannot set custom headers. Backend reads the JWT from a query parameter for `/events/stream` only:

```
GET /events/stream?token=<jwt>
```

Use this exact form for the SSE connection. All other endpoints use the `Authorization` header.

---

## 3. The end-to-end flow (sequence)

```
User: "I want to make butter chicken"

[1] iOS  ─── POST /chat ───────────►  Backend
                                       │ async: Claude (Bedrock) → ingredients + steps
                                       │ async: Nano Banana → dish image (best-effort)
[2] iOS  ◄─── 202 {chat_id, recipe_id} ──┤
                                          │
[3] SSE  ◄═══ recipe_complete {recipe_id, recipe} ═════ Backend
[4] (optional) SSE ◄═══ image_ready {recipe_id, image_url} ════ Backend

User taps "Find ingredients"

[5] iOS ─── POST /cart/from-recipe {recipe_id} ──► Backend
                                                    │ MCP fan-out: AH + Picnic
[6] iOS ◄─── 200 {cart_id, comparison: [{store, total_eur, item_count}]} ──┤

User picks "AH"

[7] iOS ─── POST /cart/{cart_id}/select-store {store: "ah"} ──► Backend
[8] iOS ◄─── 200 {cart_id, items: [{product_id, name, image_url, qty, price_eur, ...}]} ──┤

User taps "Pay via bunq"

[9] iOS  ─── POST /order/checkout {cart_id} ──► Backend
                                                  │ MCP: bunq mint URL
[10] iOS ◄─── 200 {order_id, payment_url, amount_eur} ──┤
[11] iOS opens payment_url externally
                                                  │ background poller hits bunq
[12] SSE ◄═══ order_status {order_id, status: "paid", paid_at} ════ Backend
[13] iOS shows paid checkmark, completes order in AppState
```

That's the entire happy path. Hold this diagram in your head.

---

## 4. SSE — the realtime channel

Open exactly one SSE connection per app session, right after login. Keep it alive until logout / app death. Reconnect with exponential backoff if it drops.

### Connect

```swift
let url = URL(string: "\(baseURL)/events/stream?token=\(jwt)")!
var req = URLRequest(url: url)
req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
let (bytes, _) = try await URLSession.shared.bytes(for: req)
for try await line in bytes.lines {
    // parse `event:` and `data:` per SSE spec
}
```

### Event types iOS must handle

| Event              | Data shape                                                            | Action                                                             |
|--------------------|-----------------------------------------------------------------------|--------------------------------------------------------------------|
| `ping`             | `{ "ts": ISO8601 }`                                                   | ignore (heartbeat, every 15 s)                                     |
| `recipe_complete`  | `{ chat_id, recipe_id, recipe }` — `recipe` is the full Recipe object | render the recipe view                                             |
| `image_ready`      | `{ recipe_id, image_url }`                                            | swap the placeholder dish image                                    |
| `cart_ready`       | `{ cart_id, comparison }` — same shape as `/cart/from-recipe` body    | informational; iOS can ignore (the HTTP response already has it)   |
| `order_status`     | `{ order_id, status, paid_at? }`                                      | when `status == "paid"`, mark order complete and dismiss bunq view |
| `error`            | `{ scope, code, message }`                                            | toast/banner                                                       |

Events are JSON-encoded after `data:`. Treat unknown event types as no-ops.

---

## 5. Endpoints — exact shapes

All examples are JSON bodies. All requests except `/auth/*` and `/events/stream` require `Authorization: Bearer <jwt>`.

### `POST /chat`
Triggers the recipe brain. Returns 202 immediately; recipe arrives via SSE.

```json
// request
{ "transcript": "I want to make butter chicken" }
```
```json
// 202 response
{ "chat_id": "uuid", "accepted": true }
```

The recipe lands on `/events/stream` as `recipe_complete` within ~2–3 s. Show a "Cooking up your recipe…" placeholder in the meantime.

⚠️ **Breaking change vs. current iOS code.** Today `streamChat()` reads tokens off `/chat` itself. Stop doing that. The new chat flow does **not** stream text tokens — it returns the full structured recipe in a single SSE event. Delete the `[DONE]` parsing logic.

### `POST /recipes/generate`
*Optional/internal.* Same shape as `recipe_complete.recipe`. iOS does not need to call this directly for the demo flow. Keep it out of the iOS code unless we add a "generate variation" feature.

### `GET /user/profile`
```json
// 200
{
  "diet": "high-protein",
  "allergies": ["peanut"],
  "daily_calorie_target": 2400,
  "protein_g_target": 180,
  "carbs_g_target": 250,
  "fat_g_target": 70,
  "store_priority": ["ah", "picnic"]
}
```

### `PATCH /user/profile`
Send only the fields you want to change. Any subset of the GET response above. Returns the updated profile.

### `POST /cart/from-recipe`
Builds carts at AH and Picnic in parallel. Returns **totals only** — no items yet.

```json
// request
{ "recipe_id": "uuid", "people": 2 }
```
```json
// 200 response
{
  "cart_id": "uuid",
  "recipe_id": "uuid",
  "comparison": [
    { "store": "ah",     "total_eur": 13.45, "item_count": 6, "missing_count": 0 },
    { "store": "picnic", "total_eur": 12.97, "item_count": 6, "missing_count": 1 }
  ]
}
```

`store` is one of `"ah" | "picnic"`. `missing_count` > 0 means some ingredients couldn't be matched at that store — surface this in the UI ("1 ingredient unavailable at Picnic").

`people` defaults to 1 if omitted. Keep the existing servings stepper.

### `POST /cart/{cart_id}/select-store`
The user has chosen. Returns the full item list for that store with product images.

```json
// request
{ "store": "ah" }
```
```json
// 200 response
{
  "cart_id": "uuid",
  "selected_store": "ah",
  "total_eur": 13.45,
  "items": [
    {
      "product_id": "ah_wi450123",
      "ingredient": "chicken breast",
      "name": "AH Kipfilet 500g",
      "image_url": "https://static.ah.nl/products/450123.jpg",
      "qty": 1,
      "unit": "500 g",
      "price_eur": 6.99
    }
    // …more items
  ]
}
```

This is the screen the user sees before paying. Show product images. Keep the per-row "skip" toggle from the current `OrderCheckoutView`.

### `POST /order/checkout`
Mints a bunq sandbox payment URL.

```json
// request
{ "cart_id": "uuid" }
```
```json
// 200 response
{
  "order_id": "uuid",
  "payment_url": "https://bunq.me/HackBunqDemo/13.45/Groceries",
  "amount_eur": 13.45
}
```

Open `payment_url` with `UIApplication.shared.open(...)`. Then **wait for the SSE `order_status: paid`** event. Do not poll.

### `GET /orders/{order_id}`
For the receipt screen after paid.

```json
// 200
{
  "id": "uuid",
  "cart_id": "uuid",
  "store": "ah",
  "total_eur": 13.45,
  "status": "paid",
  "paid_at": "2026-04-25T14:30:00Z",
  "fulfilled_at": null,
  "created_at": "2026-04-25T14:25:00Z"
}
```

---

## 6. Required iOS changes — checklist

Order matters: do (1) before anything else, then (2)–(5) can run in parallel.

### (1) Auth + JWT plumbing
- [ ] New screens: `SignupView`, `LoginView`. Wire to `/auth/signup`, `/auth/login`.
- [ ] `KeychainStore` helper for the access token.
- [ ] `APIService` injects `Authorization: Bearer <jwt>` on every authed call.
- [ ] On 401 from any endpoint, navigate to `LoginView`.
- [ ] First-launch routing: `if Keychain has token → Home, else → LoginView`.

### (2) SSE consumer
- [ ] New `RealtimeService` actor that opens `GET /events/stream?token=<jwt>` on app start (post-login).
- [ ] Parse `event:` / `data:` lines per SSE spec.
- [ ] Publish typed events: `RecipeComplete`, `ImageReady`, `OrderStatus`, etc.
- [ ] Reconnect on disconnect with exponential backoff (start at 1 s, cap at 30 s).
- [ ] Survive app foreground/background transitions: tear down on background, reopen on foreground.

### (3) Chat flow rewrite
- [ ] `ChatViewModel.send()`:
  - [ ] POST `/chat`, get `chat_id` back, show "thinking" state.
  - [ ] Subscribe to `RealtimeService` for `recipe_complete` matching that `chat_id`.
  - [ ] On event: render recipe.
  - [ ] On `image_ready` for that `recipe_id`: replace the placeholder dish image.
- [ ] Delete the existing token-streaming logic in `streamChat()`. The recipe is **not** streamed text anymore.

### (4) New screen: 2-store comparison
- [ ] New `StoreComparisonView`. After `POST /cart/from-recipe`, show two cards:
  - "AH €13.45 — 6 items"
  - "Picnic €12.97 — 5 of 6 items (1 unavailable)"
- [ ] Tapping a card calls `POST /cart/{cart_id}/select-store` and pushes the existing `OrderCheckoutView`.

### (5) OrderCheckoutView updates
- [ ] Replace `buildCart(from:people:)` call with `selectStore(...)`. Source of truth is the `/cart/{id}/select-store` response.
- [ ] Display `image_url` per item.
- [ ] On "Pay via bunq" tap: `POST /order/checkout {cart_id}`, open the returned `payment_url`, then wait for `order_status: paid` over SSE.
- [ ] When paid event arrives: show success, dismiss, call `appState.completeOrder(...)`.
- [ ] **Drop the demo `bunq://request/...` URL.** The real URL is `https://bunq.me/...` and opens in the bunq app or mobile Safari fallback.

### (6) Profile screen
- [ ] On launch (after login), `GET /user/profile` to populate the existing `ProfileView`.
- [ ] On any field change, `PATCH /user/profile` with just the changed fields.
- [ ] Drop the `bunqConnected` field from `UserProfile` — bunq auth is server-side now, iOS doesn't manage it.

### (7) Models — JSON shape sync
The `Recipe` model's macros field must match the backend exactly. Backend returns:
```json
"macros": {"calories": 560, "protein_g": 48, "carbs_g": 52, "fat_g": 16}
```
Note the **`calories` field is inside `macros`**, not a sibling. Update `Recipe` accordingly:
```swift
struct Macros: Codable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}
```
Drop the existing top-level `calories: Int` on `Recipe`. Use `recipe.macros.calories` everywhere.

`CartItem` rename: `priceEur` stays, but the JSON field is the same (`price_eur`). Add an `imageURL: URL?` field — the backend sends `image_url` in the select-store response, and iOS displays it in the basket.

### (8) Drop Jumbo references
Search the codebase for `jumbo` / `Jumbo` and remove. Stores are `"ah"` and `"picnic"`. The `storeLabel(for:)` helper should map both.

### (9) Remove `useMockData = true`
Last step. Flip to `false` once everything above lands and the backend is live. Until then, keep mocks shaped exactly like the new contracts so dev iteration doesn't depend on the backend deploying first.

---

## 7. Mock data alignment (do this first)

Update `MockData.swift` to match the **new** contract shapes before flipping `useMockData`. That way you develop against realistic shapes from day one and the cutover is a one-line change.

- `MockData.recipes` → new `macros` block with `calories` inside.
- New `MockData.comparison` for the two-store view.
- New `MockData.itemList` for the post-selection view (with `image_url` placeholders).
- New `MockData.orderStatusEvents` to simulate the SSE paid flow in mock mode.

---

## 8. Open contract questions iOS may surface

If anything below comes up during integration, message the backend dev — don't guess:

- Bunq sandbox `payment_url` opens `https://bunq.me/...` — does this work in the iOS Simulator, or only on a real device with the bunq app installed? (Test early.)
- What's the right "no recipe found" failure mode? Currently backend should send an `error` SSE event; iOS shows a toast + lets user retry.
- Should signup auto-fill a default profile (`store_priority: ["ah","picnic"]`, no diet)? Yes — backend creates a default profile on signup. Display it in `ProfileView` as editable from the start.
- Logout: there's no `/auth/logout` (JWT is stateless). iOS just discards the Keychain entry and shows `LoginView`.

---

## 9. Backend base URL

For the demo: `http://<ec2-ip>:4567` (no Cloudflare, no HTTPS). Final IP comes from the backend dev — ask before flipping `useMockData`.

For local backend dev (if iOS dev wants to run against laptop): `http://localhost:4567`. Backend exposes the same shapes locally as on EC2.

---

## 10. Out of scope for the demo

These exist in the original plan but iOS does **not** need to wire them for the hackathon:

- Recipe library / favorites / recook (`/recipes`, `/recipes/{id}/favorite`)
- Meal logging + nutrition tracker network calls (UI exists with mock data — keep using `MockData` for the Track tab)
- Meal plan / "tomorrow's meal" (`/meal-plan/*`)

If we have time at the end, swap the Tracker tab to live data — but the demo path is **chat → recipe → cart compare → pick store → pay → paid**. That's all that needs to work end-to-end.
