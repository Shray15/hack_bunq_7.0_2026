"""Stub data factories for Phase 1.

Returns plausible Pydantic objects so iOS can build against the wire shape
of every endpoint before the real orchestrators land.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

from app.schemas import (
    Cart,
    CartItem,
    MealLog,
    MealOption,
    MealPlan,
    Order,
    Recipe,
    RecipeIngredient,
    StoreComparison,
)
from app.schemas.cart import Store
from app.schemas.common import Macros
from app.schemas.order import OrderStatus


def _now() -> datetime:
    return datetime.now(UTC)


def make_recipe(*, recipe_id: uuid.UUID | None = None, name: str = "Lemon Herb Chicken") -> Recipe:
    rid = recipe_id or uuid.uuid4()
    return Recipe(
        id=rid,
        name=name,
        summary="Pan-seared chicken with lemon, garlic, and herbs over jasmine rice.",
        prep_time_min=25,
        ingredients=[
            RecipeIngredient(name="chicken breast", qty=400, unit="g"),
            RecipeIngredient(name="jasmine rice", qty=200, unit="g"),
            RecipeIngredient(name="lemon", qty=1, unit="pc"),
            RecipeIngredient(name="garlic", qty=3, unit="cloves"),
            RecipeIngredient(name="olive oil", qty=2, unit="tbsp"),
            RecipeIngredient(name="parsley", qty=1, unit="bunch"),
        ],
        steps=[
            "Rinse rice and start it with 400 ml water on low heat.",
            "Slice chicken into cutlets, season with salt and pepper.",
            "Sear chicken 3 min per side in olive oil until golden.",
            "Add minced garlic, juice of one lemon, deglaze 30 s.",
            "Plate over rice, finish with chopped parsley.",
        ],
        macros=Macros(calories=560, protein_g=48, carbs_g=52, fat_g=16),
        validated_macros=Macros(calories=572, protein_g=49, carbs_g=51, fat_g=17),
        image_url=None,
        image_status="pending",
        source="chat",
        parent_recipe_id=None,
        favorited_at=None,
        created_at=_now(),
    )


def make_cart_items(*, store: Store = "ah") -> list[CartItem]:
    return [
        CartItem(
            id=uuid.uuid4(),
            ingredient_name="chicken breast",
            store=store,
            product_id=f"{store}-7421",
            product_name="Kipfilet 500g",
            image_url="https://placehold.co/240x240/png?text=Kipfilet",
            qty=1,
            unit="500 g",
            unit_price_eur=6.99,
            total_price_eur=6.99,
        ),
        CartItem(
            id=uuid.uuid4(),
            ingredient_name="jasmine rice",
            store=store,
            product_id=f"{store}-1102",
            product_name="Jasmijnrijst 1kg",
            image_url="https://placehold.co/240x240/png?text=Rice",
            qty=1,
            unit="1 kg",
            unit_price_eur=2.49,
            total_price_eur=2.49,
        ),
        CartItem(
            id=uuid.uuid4(),
            ingredient_name="lemon",
            store=store,
            product_id=f"{store}-9001",
            product_name="Citroen los",
            image_url="https://placehold.co/240x240/png?text=Lemon",
            qty=1,
            unit="1 pc",
            unit_price_eur=0.45,
            total_price_eur=0.45,
        ),
    ]


def make_comparison() -> list[StoreComparison]:
    return [
        StoreComparison(
            store="ah",
            total_eur=13.45,
            item_count=6,
            missing=[],
            missing_count=0,
        ),
        StoreComparison(
            store="picnic",
            total_eur=12.97,
            item_count=5,
            missing=["parsley"],
            missing_count=1,
        ),
    ]


def make_cart(*, recipe_id: uuid.UUID, cart_id: uuid.UUID | None = None) -> Cart:
    cid = cart_id or uuid.uuid4()
    return Cart(
        id=cid,
        recipe_id=recipe_id,
        status="open",
        selected_store=None,
        comparison=make_comparison(),
        items=make_cart_items(store="ah"),
        created_at=_now(),
    )


def make_order(
    *,
    cart_id: uuid.UUID,
    store: Store = "ah",
    order_id: uuid.UUID | None = None,
    status: OrderStatus = "ready_to_pay",
) -> Order:
    oid = order_id or uuid.uuid4()
    return Order(
        id=oid,
        cart_id=cart_id,
        store=store,
        total_eur=12.83,
        bunq_payment_url=f"https://bunq.test/payment/{oid}",
        bunq_request_id=f"req-{oid.hex[:12]}",
        status=status,
        paid_at=None,
        fulfilled_at=None,
        created_at=_now(),
    )


def make_meal_log(*, recipe_id: uuid.UUID, portion: float = 1.0) -> MealLog:
    macros_full = Macros(calories=572, protein_g=49, carbs_g=51, fat_g=17)
    return MealLog(
        id=uuid.uuid4(),
        recipe_id=recipe_id,
        recipe_name="Lemon Herb Chicken",
        portion=portion,
        calories_computed=int(macros_full.calories * portion),
        macros_computed=Macros(
            calories=int(macros_full.calories * portion),
            protein_g=int(macros_full.protein_g * portion),
            carbs_g=int(macros_full.carbs_g * portion),
            fat_g=int(macros_full.fat_g * portion),
        ),
        eaten_at=_now(),
        source="manual",
    )


def make_meal_options() -> list[MealOption]:
    return [
        MealOption(
            recipe_id=uuid.uuid4(),
            name="Lemon Herb Chicken",
            macros=Macros(calories=572, protein_g=49, carbs_g=51, fat_g=17),
            last_seen_at=_now() - timedelta(hours=3),
            reason="ordered",
        ),
        MealOption(
            recipe_id=uuid.uuid4(),
            name="Greek Yogurt Bowl",
            macros=Macros(calories=320, protein_g=24, carbs_g=38, fat_g=8),
            last_seen_at=_now() - timedelta(hours=18),
            reason="favorite",
        ),
    ]


def make_meal_plan(*, recipe: Recipe, scheduled_for: date | None = None) -> MealPlan:
    return MealPlan(
        id=uuid.uuid4(),
        recipe_id=recipe.id,
        scheduled_for=scheduled_for or (date.today() + timedelta(days=1)),
        status="proposed",
        created_at=_now(),
        recipe=recipe,
    )
