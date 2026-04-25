"""AWS Bedrock (Anthropic Claude) adapter.

Wraps four narrow LLM calls used by the recipe orchestrator:

  1. parse_transcript_to_constraints  — voice/text → constraints + proposed dish meta
  2. generate_ingredients              — proposed dish + constraints → ingredient list
  3. generate_steps                    — proposed dish → 5–8 cooking steps
  4. generate_macros                   — dish + ingredients → estimated macros (LLM)

Each call uses tool-use with a forced tool_choice so Claude always returns
strict structured JSON. The static system prompt is sent inside an array with
`cache_control: ephemeral` so we benefit from Anthropic's prompt cache once
the same prompt is hit repeatedly.

If `AWS_ACCESS_KEY_ID` is empty (local dev / tests), every helper returns a
deterministic stub so the rest of the orchestrator can be exercised without
hitting Bedrock. Production failures raise `BedrockError`; the orchestrator
catches that and emits an `error` SSE event without persisting anything.
"""

from __future__ import annotations

import asyncio
import functools
import json
import logging
from typing import Any

import boto3
from pydantic import BaseModel, ValidationError

from app.config import settings
from app.schemas.common import Macros
from app.schemas.profile import Profile
from app.schemas.recipe import RecipeConstraints, RecipeIngredient

log = logging.getLogger(__name__)


class BedrockError(RuntimeError):
    """Wraps any failure invoking Bedrock so the orchestrator can degrade."""


class ProposedDish(BaseModel):
    name: str
    summary: str
    prep_time_min: int


class NLUResult(BaseModel):
    constraints: RecipeConstraints
    dish: ProposedDish


# ---------------------------------------------------------------------------
# Tool schemas (JSON Schema, sent as the tool's `input_schema`)
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

# ---------------------------------------------------------------------------
# System prompt (cached). Keep this stable so prompt-cache hit rate stays high.
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
- Steps are 5 to 8 entries, each 1–2 sentences, sequential, no numbering.
- Macros are integer kcal / grams per serving (not for the whole batch).
- Refuse politely (but still via the tool) if the request is unsafe (e.g. an
  ingredient the user is allergic to). Use the `notes` field to flag any
  caveat.
"""


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------


def is_configured() -> bool:
    """True iff the adapter has enough config to call real Bedrock."""
    return bool(settings.aws_access_key_id and settings.aws_secret_access_key)


async def parse_transcript_to_constraints(
    transcript: str, profile: Profile
) -> NLUResult:
    """Step 1 of the chat flow: NLU on the user's transcript."""
    if not is_configured():
        return _stub_nlu(transcript)

    user_msg = (
        f"User profile:\n{_render_profile(profile)}\n\n"
        f"User said:\n\"\"\"{transcript}\"\"\"\n\n"
        "Call emit_constraints with the user's normalised constraints and a "
        "proposed dish that fits both the request and the profile."
    )
    payload = await _invoke_tool(_NLU_TOOL, user_msg)
    try:
        return NLUResult.model_validate(payload)
    except ValidationError as exc:
        raise BedrockError(f"emit_constraints returned invalid payload: {exc}") from exc


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
        raise BedrockError(f"emit_recipe_ingredients invalid: {exc}") from exc


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
        raise BedrockError("emit_recipe_steps did not return a list of strings")
    return steps


async def generate_macros(
    dish: ProposedDish, ingredients: list[RecipeIngredient]
) -> Macros:
    if not is_configured():
        return _stub_macros(dish)

    user_msg = (
        f"Dish: {dish.name}\n"
        f"Ingredients:\n{_render_ingredients(ingredients)}\n\n"
        "Call emit_macros with the estimated per-serving macros."
    )
    payload = await _invoke_tool(_MACROS_TOOL, user_msg)
    try:
        return Macros.model_validate(payload)
    except ValidationError as exc:
        raise BedrockError(f"emit_macros invalid: {exc}") from exc


# ---------------------------------------------------------------------------
# Bedrock plumbing
# ---------------------------------------------------------------------------


@functools.lru_cache(maxsize=1)
def _client() -> Any:
    return boto3.client(
        service_name="bedrock-runtime",
        region_name=settings.aws_region or settings.aws_default_region,
        aws_access_key_id=settings.aws_access_key_id or None,
        aws_secret_access_key=settings.aws_secret_access_key or None,
        aws_session_token=settings.aws_session_token or None,
    )


async def _invoke_tool(tool: dict[str, Any], user_msg: str) -> dict[str, Any]:
    """Invoke Bedrock-Anthropic with a forced tool_choice and return the tool input."""
    body = json.dumps(
        {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": settings.bedrock_max_tokens,
            "system": [
                {
                    "type": "text",
                    "text": _SYSTEM_PROMPT,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            "tools": [tool],
            "tool_choice": {"type": "tool", "name": tool["name"]},
            "messages": [{"role": "user", "content": user_msg}],
        }
    )

    try:
        response = await asyncio.wait_for(
            asyncio.to_thread(
                _client().invoke_model,
                modelId=settings.aws_bedrock_model_id,
                body=body,
                contentType="application/json",
                accept="application/json",
            ),
            timeout=settings.bedrock_timeout_seconds,
        )
    except TimeoutError as exc:  # asyncio.wait_for re-raises asyncio.TimeoutError
        raise BedrockError("Bedrock invoke_model timed out") from exc
    except Exception as exc:  # boto3 raises ClientError; treat any failure as opaque
        raise BedrockError(f"Bedrock invoke_model failed: {exc}") from exc

    try:
        result = json.loads(response["body"].read())
    except (KeyError, json.JSONDecodeError) as exc:
        raise BedrockError(f"Bedrock response malformed: {exc}") from exc

    for block in result.get("content", []):
        if block.get("type") == "tool_use" and block.get("name") == tool["name"]:
            value = block.get("input")
            if isinstance(value, dict):
                return value

    raise BedrockError(
        f"Bedrock did not return a tool_use block for {tool['name']}: {result}"
    )


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
# Stub responses (used when AWS creds aren't configured)
# ---------------------------------------------------------------------------


def _stub_nlu(transcript: str) -> NLUResult:
    name = _guess_dish_name(transcript)
    return NLUResult(
        constraints=RecipeConstraints(),
        dish=ProposedDish(
            name=name,
            summary=f"Stub-mode plate of {name.lower()}.",
            prep_time_min=25,
        ),
    )


def _stub_ingredients(dish: ProposedDish, people: int) -> list[RecipeIngredient]:
    base = max(1, people)
    return [
        RecipeIngredient(name="chicken breast", qty=200 * base, unit="g"),
        RecipeIngredient(name="jasmine rice", qty=100 * base, unit="g"),
        RecipeIngredient(name="lemon", qty=1 * base, unit="pc"),
        RecipeIngredient(name="garlic", qty=2 * base, unit="cloves"),
        RecipeIngredient(name="olive oil", qty=1 * base, unit="tbsp"),
        RecipeIngredient(name="parsley", qty=1, unit="bunch"),
    ]


def _stub_steps(dish: ProposedDish) -> list[str]:
    return [
        f"Prep the ingredients for {dish.name.lower()}.",
        "Heat oil in a pan and sear the protein 3 minutes per side.",
        "Add aromatics and cook 30 seconds until fragrant.",
        "Combine with the carbohydrate base and toss through.",
        "Plate and finish with fresh herbs.",
    ]


def _stub_macros(_: ProposedDish) -> Macros:
    return Macros(calories=560, protein_g=48, carbs_g=52, fat_g=16)


def _guess_dish_name(transcript: str) -> str:
    """Cheap heuristic so the stub is at least related to the user's prompt."""
    cleaned = transcript.lower().strip().rstrip(".!?")
    for stem in ("i want to make ", "i want ", "make me ", "let's cook ", "cook "):
        if cleaned.startswith(stem):
            cleaned = cleaned[len(stem) :]
            break
    if not cleaned:
        cleaned = "lemon herb chicken"
    return cleaned.title()
