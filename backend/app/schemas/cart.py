import uuid
from datetime import datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import AppModel

CartStatus = Literal["open", "converted", "abandoned"]
Store = Literal["ah", "jumbo", "picnic"]


class CartItem(AppModel):
    id: uuid.UUID
    ingredient_name: str
    store: Store
    product_id: str
    product_name: str
    qty: float
    unit_price_eur: float
    total_price_eur: float
    removed_at: datetime | None = None


class StoreComparison(AppModel):
    store: Store
    total_eur: float
    missing: list[str] = []
    item_count: int


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


class CartItemPatch(AppModel):
    removed: bool | None = None
    qty: float | None = Field(default=None, gt=0)
