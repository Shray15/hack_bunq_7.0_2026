import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel

CartStatus = Literal["open", "converted", "abandoned"]
Store = Literal["ah", "picnic"]


class CartItem(AppModel):
    id: uuid.UUID
    ingredient_name: str
    store: Store
    product_id: str
    product_name: str
    image_url: str | None = None
    qty: float
    unit: str | None = None
    unit_price_eur: float
    total_price_eur: float
    removed_at: datetime | None = None


class StoreComparison(AppModel):
    store: Store
    total_eur: float
    item_count: int
    # Names of ingredients that couldn't be matched at this store. Server-side
    # bookkeeping; iOS reads `missing_count` instead, but Phase 4 substitution
    # flow needs the names.
    missing: list[str] = []
    missing_count: int = 0


class Cart(AppModel):
    id: uuid.UUID
    recipe_id: uuid.UUID
    status: CartStatus
    selected_store: Store | None
    comparison: list[StoreComparison]
    items: list[CartItem]
    created_at: datetime


class CartFromRecipeRequest(AppModel):
    recipe_id: uuid.UUID
    people: int = Field(default=1, ge=1, le=20)


class CartComparisonResponse(AppModel):
    """Response for `POST /cart/from-recipe` — totals only, no items."""

    cart_id: uuid.UUID
    recipe_id: uuid.UUID
    comparison: list[StoreComparison]


class SelectStoreRequest(AppModel):
    store: Store


class CartItemsResponse(AppModel):
    """Response for `POST /cart/{cart_id}/select-store` — full basket for the chosen store."""

    cart_id: uuid.UUID
    selected_store: Store
    total_eur: float
    items: list[CartItem]


class CartItemPatch(AppModel):
    removed: bool | None = None
    qty: float | None = Field(default=None, gt=0)
