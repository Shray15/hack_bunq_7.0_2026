# App Overview — One-Stop Cooking Companion

## What the app is

**The problem:** Eating well has 4 steps — decide what to eat, plan for the occasion, get the ingredients, track if you're actually on track. Right now those are 4 different apps and a lot of manual work.

**The app:** One place that handles all 4. You talk to it, it thinks for you, it orders for you, it tracks for you. Over time you stop opening AH, stop Googling recipes, stop counting calories manually.

**Who it's for:** Anyone who wants to eat intentionally — whether that's keto, high-protein, cooking for guests, or just not eating junk every night.

**The one-liner:** *"Tell us what's happening. We handle the food."*

---

## Screens

### Screen 1 — Home (open every morning)

The daily habit screen. The one people open with coffee.

- Today's planned meals — breakfast, lunch, dinner — with a food image for each
- Calorie bar: consumed vs daily target (e.g. 820 / 1,800 kcal)
- A subtle nudge: "You're 300g of protein short this week"
- Upcoming delivery banner if something is arriving today
- One big button at the bottom: **"Plan something"** — goes to the AI screen

Feels like a personal briefing. Clean, visual, fast to scan.

---

### Screen 2 — AI Planning (voice screen)

Where you talk to the app. Voice or text.

Examples:
- "4 friends coming over tomorrow, want to cook chicken"
- "Quick lunch, keto, under 500 calories"
- "Something impressive for a date on Saturday"

The app understands *who, how many, when, what constraints* and responds with recipe options — not one answer, but choices.

Chat interface at the bottom. Recipe cards appear above as you talk.

---

### Screen 3 — Recipe Selection

Full screen, visual. 4-5 recipe cards, each showing:

- AI-generated food image (big, beautiful)
- Dish name
- Calories per person
- Prep time
- Diet tags — Keto, High-Protein, etc.
- "Scaled for X people" (auto-calculated)

Swipe through, tap the one you want.

---

### Screen 4 — Order & Checkout

- Full scaled ingredient list for N people
- Items you already have crossed out (inferred from order history)
- Items being ordered with AH product name + price
- Total cost
- Delivery time: Today / Tomorrow / Pick a date
- Bottom CTA: **"Order — Pay €23.40 via bunq"**

This is where the "replace grocery shopping" promise gets delivered. Picked a recipe 10 seconds ago — groceries are now ordered.

---

### Screen 5 — Nutrition Tracker

- Today: calories eaten, protein, carbs, fat — simple bars
- Diet goal shapes what's highlighted (keto = net carbs front and center, high-protein = protein bar biggest)
- Meal log: each meal with image, name, and calories
- Weekly summary: were you on track?

Logging is nearly automatic — when you order and eat a recipe through the app, it logs itself.

---

### Screen 6 — Profile & Goals

Set once, shapes everything silently.

- Diet type: Keto / Paleo / Balanced / High-Protein / Vegan / Custom
- Daily calorie target
- Macro goals (auto-suggested based on diet type)
- Allergies and intolerances
- Default household size (pre-sets scaling)
- Connected bunq account

Every recipe suggestion, every macro bar, every portion size respects this profile automatically.

---

## Cut for hackathon (build later)

- Pantry as its own screen (infer from order history)
- Cook mode / step-by-step voice guidance
- Multi-store price comparison
- Social / share features
- Weekly calendar meal planning

---

## Hackathon demo priority

Build and demo: **Screens 1, 2, 3, 4**
Show as working but light: **Screens 5, 6**
