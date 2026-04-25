import re
from math import inf
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from bunq_payment import create_payment_request
import ah_client
import picnic_client

load_dotenv()

app = FastAPI(title="Grocery + Payment API")

SUPPORTED_STORES = ["ah", "picnic"]

STORE_CLIENTS = {
    "ah": ah_client,
    "picnic": picnic_client,
}

# In-memory cart — one cart per store per session (keyed by store name for demo)
_carts: dict[str, list[dict]] = {"ah": [], "picnic": []}


# English ingredient terms search better when translated to Dutch first.
# Longest phrases first so "chicken breast" matches before "chicken".
_EN_TO_NL = {
    "chicken breast": "kipfilet",
    "chicken thigh":  "kipdijfilet",
    "ground beef":    "rundergehakt",
    "minced beef":    "rundergehakt",
    "brown rice":     "zilvervliesrijst",
    "white rice":     "rijst",
    "olive oil":      "olijfolie",
    "chicken":        "kip",
    "beef":           "rundvlees",
    "salmon":         "zalm",
    "rice":           "rijst",
    "tomatoes":       "tomaten",
    "tomato":         "tomaat",
    "eggs":           "eieren",
    "egg":            "ei",
    "onions":         "uien",
    "onion":          "ui",
    "garlic":         "knoflook",
    "spinach":        "spinazie",
    "cheese":         "kaas",
    "milk":           "melk",
    "butter":         "boter",
    "lemons":         "citroenen",
    "lemon":          "citroen",
    "potatoes":       "aardappelen",
    "potato":         "aardappel",
    "carrots":        "wortels",
    "carrot":         "wortel",
    "apples":         "appels",
    "apple":          "appel",
    "bread":          "brood",
}


def _translate_to_dutch(name: str) -> str:
    lowered = name.lower().strip()
    for en, nl in _EN_TO_NL.items():
        if en in lowered:
            return nl
    return name


_GRAM_UNITS = {"g": 1.0, "gr": 1.0, "gram": 1.0, "grams": 1.0, "kg": 1000.0, "kilogram": 1000.0}
# Matches "400 gram", "2 x 110 gram", "1.5 kg". Non-gram units (ml, stuks, etc.) return None.
_PACK_PATTERN = re.compile(
    r"(?:(\d+(?:\.\d+)?)\s*x\s*)?(\d+(?:\.\d+)?)\s*(gram|grams|gr|kg|kilogram|g)\b",
    re.IGNORECASE,
)


def _ingredient_to_grams(qty: float, unit: str) -> float | None:
    factor = _GRAM_UNITS.get((unit or "").lower().strip())
    return qty * factor if factor else None


def _pack_to_grams(unit_quantity: str) -> float | None:
    if not unit_quantity:
        return None
    m = _PACK_PATTERN.search(unit_quantity)
    if not m:
        return None
    multiplier = float(m.group(1)) if m.group(1) else 1.0
    amount = float(m.group(2))
    factor = _GRAM_UNITS.get(m.group(3).lower(), 1.0)
    return multiplier * amount * factor


def _pick_closest_pack(candidates: list[dict], target_grams: float | None) -> dict:
    """Candidate whose pack size is closest to target_grams.
    Falls back to candidates[0] when target is unknown or no candidate exposes grams."""
    if target_grams is None:
        return candidates[0]
    best = candidates[0]
    best_diff = inf
    for c in candidates:
        pg = _pack_to_grams(c.get("unit", ""))
        if pg is None:
            continue
        diff = abs(pg - target_grams)
        if diff < best_diff:
            best = c
            best_diff = diff
    return best


def _build_store_cart(ingredients: list[dict], store: str) -> tuple[list[dict], list[str]]:
    """Match each ingredient to a product at the given store.

    Read-only: this never mutates the user's real store cart. Real-cart writes
    happen at checkout, via a separate code path.

    Returns (items, missing) where missing is the list of ingredient names
    that produced no usable match.
    """
    store_client = STORE_CLIENTS[store]
    items: list[dict] = []
    missing: list[str] = []
    for ing in ingredients:
        candidates = store_client.search_product(_translate_to_dutch(ing["name"]), max_results=10)
        if not candidates:
            missing.append(ing["name"])
            continue
        target_grams = _ingredient_to_grams(
            float(ing.get("qty", 0) or 0),
            str(ing.get("unit", "") or ""),
        )
        best = _pick_closest_pack(candidates, target_grams)
        pid = best.get("product_id")
        if not pid:
            missing.append(ing["name"])
            continue

        qty = 1
        price = best.get("price_eur", 0.0)
        items.append({
            "ingredient": ing["name"],
            "product_id": pid,
            "name": best["name"],
            "image_url": best.get("image_url"),
            "unit": best.get("unit", ""),
            "price_eur": price,
            "qty": qty,
            "subtotal_eur": round(price * qty, 2),
        })
    return items, missing


class Ingredient(BaseModel):
    name: str
    qty: float = 1
    unit: str = ""

class CartRequest(BaseModel):
    ingredients: list[Ingredient]
    store: str = "ah"

class CheckoutRequest(BaseModel):
    store: str = "ah"
    description: str = "Groceries"


def _validate_store(store: str) -> str:
    s = store.lower()
    if s not in SUPPORTED_STORES:
        raise HTTPException(status_code=400, detail=f"Unknown store '{s}'. Choose from: {SUPPORTED_STORES}")
    return s


@app.get("/health")
def health():
    return {"status": "ok", "stores": SUPPORTED_STORES}


@app.post("/cart/from-recipe")
def cart_from_recipe(req: CartRequest):
    store = _validate_store(req.store)
    ingredients = [i.model_dump() for i in req.ingredients]
    items, missing = _build_store_cart(ingredients, store)
    _carts[store] = items
    total = round(sum(i["subtotal_eur"] for i in items), 2)
    return {"items": items, "missing": missing, "total_eur": total, "store": store}


@app.post("/cart/add")
def add_to_cart(req: CartRequest):
    store = _validate_store(req.store)
    ingredients = [i.model_dump() for i in req.ingredients]
    new_items, missing = _build_store_cart(ingredients, store)
    _carts[store].extend(new_items)
    total = round(sum(i["subtotal_eur"] for i in _carts[store]), 2)
    return {"items": _carts[store], "missing": missing, "total_eur": total, "store": store}


@app.get("/cart/{store}")
def get_cart(store: str):
    store = _validate_store(store)
    items = _carts[store]
    total = round(sum(i["subtotal_eur"] for i in items), 2)
    return {"items": items, "total_eur": total, "store": store}


@app.delete("/cart/{store}")
def clear_cart(store: str):
    store = _validate_store(store)
    _carts[store] = []
    return {"message": f"{store} cart cleared"}


@app.post("/cart/checkout")
def checkout(req: CheckoutRequest):
    store = _validate_store(req.store)
    items = _carts[store]
    if not items:
        raise HTTPException(status_code=400, detail="Cart is empty. Call /cart/from-recipe first.")
    total = round(sum(i["subtotal_eur"] for i in items), 2)
    payment_url = create_payment_request(total, req.description)
    return {
        "payment_url": payment_url,
        "amount_eur": total,
        "store": store,
        "items": items,
    }
