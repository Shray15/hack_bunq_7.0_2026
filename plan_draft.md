# Hackathon Plan — Health & Cooking iOS App

**Time remaining: 15 hours. Team size: 4.**

This is a survival plan, not a dream plan. Every hour has a checkpoint. If a checkpoint slips, cut scope — do not push the deadline.

---

## 1. The Idea (one-liner)

A voice-first iOS cooking companion: tells you what to cook based on your diet and calorie goals, generates the recipe and an AI image of the dish, lets you plan tomorrow's meal, and orders the groceries straight from AH/Jumbo/Picnic via MCP, paid through bunq.

## 2. Demo Goal (the single path we MUST ship)

> User taps mic → says "I'm hungry, something high-protein under 600 calories" → app streams back a recipe with an AI-generated image → user taps "Order ingredients" → AH cart populates → bunq payment request opens → done.

Everything else is a bonus. If it doesn't support this path in the first 11 hours, cut it.

---

## 3. Architecture

```
┌─────────────────┐
│   iOS App       │  SwiftUI
│   (Person A)    │  - Speech framework (STT, on-device)
└────────┬────────┘  - AVSpeechSynthesizer (TTS)
         │ REST + SSE
         ▼
┌──────────────────────────────────────────┐
│   Backend — FastAPI  (Person B)          │
│   - Orchestrator: chat → model → MCP     │
│   - SQLite for user + recipe store       │
│   - JWT auth (or hardcoded demo user)    │
└────┬──────────────┬──────────────────┬───┘
     │              │                  │
     ▼              ▼                  ▼
┌──────────┐  ┌───────────────┐  ┌──────────────┐
│ Models   │  │ MCP Servers   │  │ bunq API     │
│ (Person  │  │ (Person C)    │  │ (Person C)   │
│  D)      │  │ - AH (real)   │  │ - sandbox    │
│ Gemini   │  │ - Jumbo (stub)│  │ - payment    │
│ Nano-B   │  │ - Picnic(stub)│  │   request    │
│ Claude   │  └───────────────┘  └──────────────┘
│ Whisper  │
└──────────┘
```

**Rule:** iOS only talks to backend. Backend is the only place that knows about models, MCP, or bunq.

---

## 4. Role Splits

### Person A — iOS (SwiftUI)
Owns the demo surface. Most visible role.

Screens (in build order):
1. **Chat / Home** — voice button, text fallback, streaming bubbles, recipe card with image. *(build first, this is the demo)*
2. **Recipe detail** — ingredients, steps, "Order ingredients" button.
3. **Onboarding** — diet, allergies, calorie target. *(hardcode if short on time)*
4. **Meal plan tomorrow** — single screen, tap to regenerate. *(stretch)*
5. **Calorie ring** — visual only, no real logging. *(stretch)*

Tech:
- `Speech` for STT (on-device, fast, free).
- `URLSession` + `AsyncSequence` for SSE streaming.
- `AsyncImage` for Nano-Banana-generated images.
- Build against fake JSON fixtures for hours 0–6. Do not wait for backend.

### Person B — Backend (FastAPI)
Owns the API contract. Unblocks everyone.

Endpoints (finalize in hour 1, share in the team doc):
```
POST /chat                 → SSE stream of recipe JSON
POST /recipes/generate     → { name, ingredients[], steps[], calories, macros, image_url }
POST /cart/from-recipe     → calls MCP, returns store products + total
POST /order/checkout       → returns bunq payment URL
POST /meal-plan/tomorrow   → stretch
GET  /user/profile         → hardcoded is fine for demo
```

Other:
- SQLite. No migrations, no ORM ceremony. Just a few tables.
- Deploy to **Fly.io or Railway in hour 2**. Not hour 14.
- Return realistic stub JSON from hour 1 so Person A is never blocked.

### Person C — MCP + bunq
Owns grocery integration and payment.

Deliverables:
1. **AH MCP server** (real, or as real as you can get). Tools: `search_product(query, qty)`, `add_to_cart(items[])`, `get_total()`. Use their semi-public product search endpoint if you can; scrape if not.
2. **Jumbo / Picnic MCP** — stub with realistic data. Same tool interface. Judges won't fail you for this.
3. **Ingredient → product matcher**: "200g minced beef" → AH product. Fuzzy string match is fine. Do not over-engineer.
4. **bunq sandbox** — register early, generate payment request URL, return deep link. **Test auth in hour 1, not hour 12.**

### Person D — Models
Owns LLM, voice, image generation.

Deliverables:
1. **Recipe chat brain** — Claude or GPT-4o with a tight system prompt. Forced JSON output (schema below). Expose as a Python module Person B imports.
2. **Nano Banana (Gemini)** — given `{name, key_ingredients}`, return an image URL. Cache by recipe hash.
3. **Voice** — STT on-device (iOS Speech framework, Person A handles). TTS: iOS native unless time for ElevenLabs.
4. **Prompt engineering** — this is where demo magic lives. Iterate on outputs until they feel right.

---

## 5. Shared Contracts (agree in hour 0–1)

### Recipe JSON
```json
{
  "id": "string",
  "name": "High-Protein Chicken Bowl",
  "calories": 540,
  "macros": { "protein_g": 45, "carbs_g": 40, "fat_g": 18 },
  "ingredients": [
    { "name": "chicken breast", "qty": 200, "unit": "g" },
    { "name": "brown rice", "qty": 80, "unit": "g" }
  ],
  "steps": ["Season chicken...", "Cook rice..."],
  "image_url": "https://.../img.png",
  "prep_time_min": 20
}
```

### MCP tool output
```json
{
  "items": [
    { "ingredient": "chicken breast", "product_id": "ah_123", "name": "AH Kipfilet 500g", "price_eur": 5.49, "qty": 1 }
  ],
  "total_eur": 12.30,
  "store": "ah"
}
```

### bunq checkout output
```json
{ "payment_url": "bunq://request/...", "amount_eur": 12.30 }
```

---

## 6. Hour-by-Hour Plan (15h)

### H0–1 — Contracts & setup (everyone together, 1 hour MAX)
- Agree on the JSON above.
- Create repo folders: `ios/`, `backend/`, `mcp/`, `models/`.
- Shared Notion/Google Doc with endpoint list.
- **C registers bunq sandbox account now. D gets Gemini + Anthropic API keys now.**

### H1–6 — Parallel build with mocks (5h)
- **A**: Chat screen + voice button + recipe card rendering from hardcoded JSON.
- **B**: FastAPI scaffold, all endpoints return static JSON matching the contract. **Deploy by hour 3.**
- **C**: AH product search working from a Python script. bunq sandbox auth working.
- **D**: Recipe generation working in a notebook with forced JSON output. Nano Banana returning an image.

**Checkpoint H6:** A calls deployed B, sees fake recipe render end-to-end. All 4 subsystems work in isolation.

### H6–11 — Real wiring (5h)
- **B** imports D's model module → `/chat` and `/recipes/generate` return real AI output.
- **B** calls C's MCP → `/cart/from-recipe` returns real AH products.
- **B** wires bunq → `/order/checkout` returns real sandbox payment URL.
- **A** wires real streaming, image loading, order button.

**Checkpoint H11:** Full demo path works once, end-to-end, on a real iPhone. Even if rough.

### H11–13 — Polish (2h)
- Fix the 3 ugliest UI issues.
- Add loading skeletons for the 5–15s image gen.
- Tune the system prompt so recipes feel premium.
- Add onboarding screen IF and ONLY IF everything above works.

### H13–14 — Demo prep (1h)
- **Record a backup video.** Do this at H13 even if the live demo is perfect. Live demos fail at hackathons.
- Write the 2-min pitch: problem → demo → what's novel (voice + MCP + bunq combo).
- One person rehearses; others watch and cut filler.

### H14–15 — Buffer (1h)
- Fix the thing that broke in rehearsal.
- Stop coding 30 min before submission. No new features in the last hour. Ever.

---

## 7. Scope Discipline

**Must have (cut everything else before cutting these):**
- Voice in → recipe with image → AH cart → bunq payment URL.

**Nice to have:**
- Meal plan for tomorrow.
- Onboarding flow.
- Multi-store comparison (only if C finishes early).

**Cut if behind at H6:**
- Calorie logging (show a pretty static ring, don't build real logging).
- Auth (hardcode a demo user).
- Jumbo/Picnic MCPs (AH alone is enough).
- TTS (let the user read).

---

## 8. Risk Register

| Risk | Mitigation |
|---|---|
| AH API blocks us | Have stub data ready from H1. Demo still works. |
| bunq sandbox auth quirks | Person C tests auth in H1, not H12. |
| Image gen latency (5–15s) | Generate async, show skeleton, swap when ready. |
| Voice flaky on simulator | Test on a real iPhone from H1. |
| Person B bottleneck | B ships stubs in H1, correctness later. Never block A or D on B. |
| Last-minute merge conflicts | Feature branches, merge to main every 2h. |

---

## 9. Definition of Done for the Demo

- [ ] Real iPhone, real backend on Fly.io, real AH product data.
- [ ] Voice input works without crashing.
- [ ] Recipe JSON renders with AI image.
- [ ] "Order ingredients" opens bunq with the right amount.
- [ ] Backup video recorded.
- [ ] 2-min pitch rehearsed once.

---

## 10. First Actions (do these in the next 15 minutes)

- [ ] C: register bunq sandbox, share credentials in team vault.
- [ ] D: confirm Gemini + Anthropic API keys work, share with B.
- [ ] B: `fastapi new`, push empty repo, deploy to Fly.io.
- [ ] A: new Xcode project, SwiftUI, push to repo.
- [ ] All: agree on the Recipe JSON in section 5. Freeze it.
