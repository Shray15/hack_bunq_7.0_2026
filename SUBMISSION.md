## Inspiration

Most people ask the same question at least once a week: *what do I actually eat this week?* Answering it properly means opening four separate apps (recipe, grocery, banking, nutrition), none of which share information. The friction is real enough that most people don't bother. They order takeaway instead.

When we looked at bunq's API we realised the infrastructure to fix this already exists. Sub-accounts, virtual cards, payment tabs, real-time events. bunq isn't just a payment rail, it's a programmable financial layer. It already has your money. It just needed to care about your dinner.

---

## How We Built It

The backend is a Python FastAPI service with a layered orchestrator. A voice request travels through Claude Sonnet 4.6 (via AWS Bedrock) for natural-language understanding, then three parallel Claude calls generate ingredients (in Dutch supermarket names so AH and Picnic searches actually work), cooking steps, and macro estimates. A FastMCP server fans the ingredient list out to Albert Heijn and Picnic simultaneously and returns a price comparison. Payment is handled via `BunqMeTab`, a fixed-amount tab the payer cannot edit, polled every two seconds until bunq confirms. The paid order auto-logs the meal. No manual entry anywhere.

Macro estimates are scaled to the user's personal daily calorie target so portions are personalised rather than generic:

$$\text{calories\_per\_meal} \approx \frac{C_{\text{daily}}}{3}, \qquad \text{per\_person\_share} = \frac{\text{total}}{n_{\text{friends}} + 1}$$

The second formula powers the cost-sharing flow: after checkout, one tap mints a new bunq.me link locked to the per-person amount.

All async events (recipe tokens streaming in, image generation finishing, payment confirmed) travel over a single server-sent event connection per user. No polling anywhere in the app.

The Meal Card is a real bunq virtual card. The backend creates a `MonetaryAccountBank` sub-account, funds it from the primary account, and issues a `CardDebit` card against it. Checkout via Meal Card is synchronous: no redirect, no polling, just an immediate `paid`.

Food photography is handled by Gemini 2.5 Flash. After Claude returns a recipe, a background task fires at Gemini and returns a styled food photograph via an `image_ready` SSE event. It never blocks the main flow.

The whole stack runs on a single EC2 `t3.small`, deployed via GitHub Actions on every push to `main`.

---

## Challenges

**Fixed-amount payment links.** We initially used `RequestInquiry`, then discovered it lets the payer edit the amount before paying. For a grocery checkout that's a critical flaw. Switching to `BunqMeTab` fixed it; the amount is locked into the URL and cannot be changed.

**Dutch catalogue names.** AH and Picnic return Dutch product names. Claude defaults to English. We built a translation dictionary for common ingredients and instructed Claude to output Dutch names in its system prompt. Getting the constraint right, without Claude hallucinating Dutch words, took several iterations.

**Virtual card sequencing.** Creating a Meal Card is three sequential bunq calls: create sub-account, fund it, issue card. Each can fail independently. We wrapped the sequence in a compensating pattern so that if card issuance fails, the sub-account is refunded and a clean error is surfaced rather than leaving the user with a funded account and no card.

---

## What We Learned

bunq's API has the primitives to build genuinely new financial experiences; we used maybe 20% of what's available. Claude's prompt caching makes multi-call pipelines economical: the structured system prompt is served from cache after the first call, cutting both latency and cost. MCP is the right abstraction for agentic tool use, giving us a clean boundary between the orchestrator and external APIs. And voice changes what people ask for: spoken requests surface social and contextual constraints ("we're a bit tired tonight") that a search box would never capture.
