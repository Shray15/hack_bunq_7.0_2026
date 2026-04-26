"""DeepSeek (OpenAI-compatible) adapter.

Wraps four narrow LLM calls used by the recipe orchestrator:

  1. parse_transcript_to_constraints  — voice/text → constraints + proposed dish meta
  2. generate_ingredients              — proposed dish + constraints → ingredient list
  3. generate_steps                    — proposed dish → 5–8 cooking steps
  4. generate_macros                   — dish + ingredients → estimated macros (LLM)

Each call uses function/tool calling with a forced tool_choice so DeepSeek always
returns strict structured JSON.

If `DEEPSEEK_API_KEY` is empty (local dev / tests), every helper returns a
deterministic stub so the rest of the orchestrator can be exercised without
hitting the API. Production failures raise `DeepSeekError`; the orchestrator
catches that and emits an `error` SSE event without persisting anything.
"""

from __future__ import annotations

import asyncio
import functools
import json
import logging
import random
from datetime import UTC, datetime
from typing import Any

from openai import AsyncOpenAI
from pydantic import BaseModel, ValidationError

from app.config import settings
from app.schemas.common import Macros
from app.schemas.profile import Profile
from app.schemas.recipe import RecipeConstraints, RecipeIngredient

log = logging.getLogger(__name__)


class DeepSeekError(RuntimeError):
    """Wraps any failure invoking DeepSeek so the orchestrator can degrade."""


class ProposedDish(BaseModel):
    name: str
    summary: str
    prep_time_min: int


class NLUResult(BaseModel):
    constraints: RecipeConstraints
    dish: ProposedDish


# ---------------------------------------------------------------------------
# Tool schemas (JSON Schema, sent as the function's `parameters`)
# ---------------------------------------------------------------------------

_CONSTRAINTS_PROPS: dict[str, Any] = {
    "calories_max": {"type": "integer"},
    "protein_g_min": {"type": "integer"},
    "carbs_g_max": {"type": "integer"},
    "fat_g_max": {"type": "integer"},
    "diet": {"type": "string"},
    "allergies": {"type": "array", "items": {"type": "string"}},
    "vibe": {"type": "string"},
    "must_use": {"type": "array", "items": {"type": "string"}},
    "avoid": {"type": "array", "items": {"type": "string"}},
}

_NLU_TOOL = {
    "name": "emit_constraints",
    "description": (
        "Emit a normalised recipe constraint object plus a proposed dish "
        "(name + 1-line summary + prep_time_min) that fits the user's "
        "request and profile."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "constraints": {
                "type": "object",
                "properties": _CONSTRAINTS_PROPS,
            },
            "dish": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "summary": {"type": "string"},
                    "prep_time_min": {"type": "integer"},
                },
                "required": ["name", "summary", "prep_time_min"],
            },
        },
        "required": ["constraints", "dish"],
    },
}

_INGREDIENTS_TOOL = {
    "name": "emit_recipe_ingredients",
    "description": (
        "Emit the ingredient list for the proposed dish, "
        "scaled for the requested number of people."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "ingredients": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "qty": {"type": "number"},
                        "unit": {"type": "string"},
                        "notes": {"type": "string"},
                    },
                    "required": ["name", "qty", "unit"],
                },
            },
        },
        "required": ["ingredients"],
    },
}

_STEPS_TOOL = {
    "name": "emit_recipe_steps",
    "description": "Emit 5–8 cooking steps in order; medium detail (1–2 sentences each).",
    "input_schema": {
        "type": "object",
        "properties": {
            "steps": {"type": "array", "items": {"type": "string"}, "minItems": 3},
        },
        "required": ["steps"],
    },
}

_MACROS_TOOL = {
    "name": "emit_macros",
    "description": "Emit estimated per-serving macros for the dish.",
    "input_schema": {
        "type": "object",
        "properties": {
            "calories": {"type": "integer"},
            "protein_g": {"type": "integer"},
            "carbs_g": {"type": "integer"},
            "fat_g": {"type": "integer"},
        },
        "required": ["calories", "protein_g", "carbs_g", "fat_g"],
    },
}

_SUBSTITUTIONS_TOOL = {
    "name": "emit_substitutions",
    "description": (
        "Emit up to 3 culinary substitutes for the missing ingredient, ordered "
        "by how well they preserve the dish's character. Use canonical Dutch "
        "names that an AH or Picnic catalogue would carry."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "alternatives": {
                "type": "array",
                "items": {"type": "string"},
                "maxItems": 3,
            }
        },
        "required": ["alternatives"],
    },
}

# ---------------------------------------------------------------------------
# System prompt. Keep stable to benefit from DeepSeek's server-side KV cache.
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT = """You are the recipe brain of a voice-first cooking app.

You ALWAYS reply by calling exactly the tool the user asks for. Never reply with
plain prose. Your output must satisfy these rules:

- Honor the user's profile (diet, allergies, calorie/protein/carb/fat targets).
- If the user names a dish (e.g. "butter chicken"), the proposed dish.name is
  that dish in canonical English Title Case.
- If the user is vague ("I'm hungry, high-protein"), propose a concrete dish
  that fits.
- prep_time_min is a realistic integer between 10 and 90.
- Ingredient quantities are numeric in metric units (g, kg, ml, l, tsp, tbsp,
  pc, cloves, bunch). Never "to taste" or ranges.
- Ingredient NAMES must be in canonical Dutch — the names AH and Picnic use in
  their catalogues. Examples: "kipfilet" (not "chicken breast"), "knoflook"
  (not "garlic"), "olijfolie" (not "olive oil"), "jasmijnrijst", "citroen",
  "peterselie", "rundergehakt", "zalm". The substitutions tool also returns
  Dutch names.
- DO NOT include basic pantry seasonings the user already has at home:
  zout (salt), peper (pepper), suiker (sugar), water, ijs. These should never
  appear in the ingredient list.
- Steps are 5 to 8 entries, each 1–2 sentences, sequential, no numbering. Steps
  may freely reference salt/pepper/water — those are cooking instructions, not
  shopping items.
- Macros are integer kcal / grams per serving (not for the whole batch).
- **Meal sizing scales with the user's daily calorie target.** Treat one meal
  as roughly one third of the daily target unless the user requests otherwise.
  An athlete on 3500 kcal/day expects ~1100 kcal per meal; a cut on 1800
  kcal/day expects ~600 kcal. Do NOT default to 400–500 kcal for everyone.
  Scale ingredient quantities and macro estimates accordingly — bigger
  portions of protein, carbs, and fat for higher targets, not the same plate
  with bigger numbers attached.
- Refuse politely (but still via the tool) if the request is unsafe (e.g. an
  ingredient the user is allergic to). Use the `notes` field to flag any
  caveat.
"""


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------


def is_configured() -> bool:
    """True iff the adapter has enough config to call the real DeepSeek API."""
    return bool(settings.deepseek_api_key)


async def parse_transcript_to_constraints(
    transcript: str, profile: Profile
) -> NLUResult:
    """Step 1 of the chat flow: NLU on the user's transcript."""
    if not is_configured():
        return _stub_nlu(transcript, profile)

    now = datetime.now(UTC)
    variety_seed = random.randint(1, 9999)
    per_meal_target = (
        profile.daily_calorie_target // 3 if profile.daily_calorie_target else None
    )
    sizing_hint = (
        f"This user's daily calorie target is {profile.daily_calorie_target} kcal, "
        f"so size this single meal at roughly {per_meal_target} kcal "
        f"(set constraints.calories_max near this value unless the user said otherwise).\n\n"
        if per_meal_target
        else ""
    )
    user_msg = (
        f"User profile:\n{_render_profile(profile)}\n\n"
        f"{sizing_hint}"
        f"User said:\n\"\"\"{transcript}\"\"\"\n\n"
        f"Context: {now.strftime('%A')} {now.strftime('%H:%M')} UTC, seed={variety_seed}. "
        "Propose a creative, varied dish — avoid defaulting to grilled chicken "
        "or quinoa bowls unless the user specifically asks for them. Pick "
        "something interesting that fits the request.\n\n"
        "Call emit_constraints with the user's normalised constraints and a "
        "proposed dish that fits both the request and the profile."
    )
    payload = await _invoke_tool(_NLU_TOOL, user_msg)
    try:
        return NLUResult.model_validate(payload)
    except ValidationError as exc:
        raise DeepSeekError(f"emit_constraints returned invalid payload: {exc}") from exc


async def generate_ingredients(
    dish: ProposedDish,
    constraints: RecipeConstraints,
    people: int,
) -> list[RecipeIngredient]:
    if not is_configured():
        return _stub_ingredients(dish, people)

    user_msg = (
        f"Proposed dish: {dish.name}\nSummary: {dish.summary}\n"
        f"People: {people}\n"
        f"Constraints:\n{_render_constraints(constraints)}\n\n"
        "Call emit_recipe_ingredients with the full ingredient list scaled "
        "for this number of people. Use metric units."
    )
    payload = await _invoke_tool(_INGREDIENTS_TOOL, user_msg)
    items = payload.get("ingredients") or []
    try:
        return [RecipeIngredient.model_validate(i) for i in items]
    except ValidationError as exc:
        raise DeepSeekError(f"emit_recipe_ingredients invalid: {exc}") from exc


async def generate_steps(dish: ProposedDish) -> list[str]:
    if not is_configured():
        return _stub_steps(dish)

    user_msg = (
        f"Proposed dish: {dish.name}\nSummary: {dish.summary}\n"
        f"Target prep time: {dish.prep_time_min} minutes.\n\n"
        "Call emit_recipe_steps with 5 to 8 sequential cooking steps."
    )
    payload = await _invoke_tool(_STEPS_TOOL, user_msg)
    steps = payload.get("steps") or []
    if not isinstance(steps, list) or not all(isinstance(s, str) for s in steps):
        raise DeepSeekError("emit_recipe_steps did not return a list of strings")
    return steps


async def generate_macros(
    dish: ProposedDish,
    ingredients: list[RecipeIngredient],
    constraints: RecipeConstraints | None = None,
) -> Macros:
    if not is_configured():
        return _stub_macros(constraints)

    target_hint = (
        f"Target per-serving calories: ~{constraints.calories_max} kcal "
        f"(do not undershoot; this user expects this portion size).\n"
        if constraints and constraints.calories_max
        else ""
    )
    user_msg = (
        f"Dish: {dish.name}\n"
        f"Ingredients:\n{_render_ingredients(ingredients)}\n"
        f"{target_hint}\n"
        "Call emit_macros with the estimated per-serving macros."
    )
    payload = await _invoke_tool(_MACROS_TOOL, user_msg)
    try:
        return Macros.model_validate(payload)
    except ValidationError as exc:
        raise DeepSeekError(f"emit_macros invalid: {exc}") from exc


async def suggest_substitutions(
    *, ingredient: str, dish_name: str, store: str
) -> list[str]:
    """Up to 3 substitute names for a missing ingredient.

    Stub mode (no API key) returns an empty list — the substitution flow then
    no-ops, leaving the original `missing` entry in place.
    """
    if not is_configured():
        return []

    user_msg = (
        f"Dish: {dish_name}\n"
        f"Store the user is shopping at: {store.upper()}\n"
        f"Missing ingredient: {ingredient}\n\n"
        "Call emit_substitutions with up to 3 alternatives that the user could "
        "buy at this store and that preserve the dish's character."
    )
    payload = await _invoke_tool(_SUBSTITUTIONS_TOOL, user_msg)
    alts = payload.get("alternatives") or []
    if not isinstance(alts, list):
        return []
    return [str(a).strip() for a in alts if isinstance(a, str) and a.strip()]


# ---------------------------------------------------------------------------
# DeepSeek plumbing
# ---------------------------------------------------------------------------


@functools.lru_cache(maxsize=1)
def _client() -> AsyncOpenAI:
    return AsyncOpenAI(
        api_key=settings.deepseek_api_key,
        base_url="https://api.deepseek.com",
    )


async def _invoke_tool(tool: dict[str, Any], user_msg: str) -> dict[str, Any]:
    """Call DeepSeek with a forced function/tool_choice and return the parsed arguments."""
    openai_tool = {
        "type": "function",
        "function": {
            "name": tool["name"],
            "description": tool["description"],
            "parameters": tool["input_schema"],
        },
    }
    try:
        response = await asyncio.wait_for(
            _client().chat.completions.create(
                model=settings.deepseek_model,
                max_tokens=settings.deepseek_max_tokens,
                messages=[
                    {"role": "system", "content": _SYSTEM_PROMPT},
                    {"role": "user", "content": user_msg},
                ],
                tools=[openai_tool],
                tool_choice={"type": "function", "function": {"name": tool["name"]}},
            ),
            timeout=settings.deepseek_timeout_seconds,
        )
    except TimeoutError as exc:
        raise DeepSeekError("DeepSeek API call timed out") from exc
    except Exception as exc:
        raise DeepSeekError(f"DeepSeek API call failed: {exc}") from exc

    try:
        tool_call = response.choices[0].message.tool_calls[0]
        return json.loads(tool_call.function.arguments)
    except (IndexError, AttributeError, json.JSONDecodeError, TypeError) as exc:
        raise DeepSeekError(f"DeepSeek response malformed: {exc}") from exc


# ---------------------------------------------------------------------------
# Prompt rendering helpers
# ---------------------------------------------------------------------------


def _render_profile(p: Profile) -> str:
    parts: list[str] = []
    if p.diet:
        parts.append(f"diet: {p.diet}")
    if p.allergies:
        parts.append(f"allergies: {', '.join(p.allergies)}")
    if p.daily_calorie_target:
        parts.append(f"daily calorie target: {p.daily_calorie_target} kcal")
    if p.protein_g_target:
        parts.append(f"protein target: {p.protein_g_target} g/day")
    if p.carbs_g_target:
        parts.append(f"carbs target: {p.carbs_g_target} g/day")
    if p.fat_g_target:
        parts.append(f"fat target: {p.fat_g_target} g/day")
    return "\n".join(f"- {x}" for x in parts) if parts else "- (no preferences set)"


def _render_constraints(c: RecipeConstraints) -> str:
    return c.model_dump_json(exclude_none=True, exclude_defaults=True)


def _render_ingredients(items: list[RecipeIngredient]) -> str:
    return "\n".join(f"- {i.qty} {i.unit} {i.name}" for i in items)


# ---------------------------------------------------------------------------
# Stub responses (used when DEEPSEEK_API_KEY isn't configured)
# ---------------------------------------------------------------------------


def _stub_nlu(transcript: str, profile: Profile) -> NLUResult:
    name = _guess_dish_name(transcript)
    per_meal = (
        profile.daily_calorie_target // 3 if profile.daily_calorie_target else None
    )
    return NLUResult(
        constraints=RecipeConstraints(calories_max=per_meal),
        dish=ProposedDish(
            name=name,
            summary=f"Stub-mode plate of {name.lower()}.",
            prep_time_min=25,
        ),
    )


def _stub_ingredients(dish: ProposedDish, people: int) -> list[RecipeIngredient]:
    base = max(1, people)
    return [
        RecipeIngredient(name="kipfilet", qty=200 * base, unit="g"),
        RecipeIngredient(name="jasmijnrijst", qty=100 * base, unit="g"),
        RecipeIngredient(name="citroen", qty=1 * base, unit="pc"),
        RecipeIngredient(name="knoflook", qty=2 * base, unit="cloves"),
        RecipeIngredient(name="olijfolie", qty=1 * base, unit="tbsp"),
        RecipeIngredient(name="peterselie", qty=1, unit="bunch"),
    ]


def _stub_steps(dish: ProposedDish) -> list[str]:
    return [
        f"Prep the ingredients for {dish.name.lower()}.",
        "Heat oil in a pan and sear the protein 3 minutes per side.",
        "Add aromatics and cook 30 seconds until fragrant.",
        "Combine with the carbohydrate base and toss through.",
        "Plate and finish with fresh herbs.",
    ]


def _stub_macros(constraints: RecipeConstraints | None) -> Macros:
    """Profile-aware stub: scale macros to the per-meal target if known."""
    target = (constraints.calories_max if constraints else None) or 600
    return Macros(
        calories=target,
        protein_g=int(target * 0.30 / 4),
        carbs_g=int(target * 0.40 / 4),
        fat_g=int(target * 0.30 / 9),
    )


def _guess_dish_name(transcript: str) -> str:
    """Cheap heuristic so the stub is at least related to the user's prompt."""
    cleaned = transcript.lower().strip().rstrip(".!?")
    for stem in ("i want to make ", "i want ", "make me ", "let's cook ", "cook "):
        if cleaned.startswith(stem):
            cleaned = cleaned[len(stem):]
            break
    if not cleaned:
        cleaned = "lemon herb chicken"
    return cleaned.title()
