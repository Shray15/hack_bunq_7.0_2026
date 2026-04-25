import os
from dotenv import load_dotenv
from python_picnic_api2 import PicnicAPI

load_dotenv()

_client = None


def _get_client() -> PicnicAPI:
    global _client
    if _client is None:
        token = os.getenv("PICNIC_AUTH_TOKEN")
        if token:
            _client = PicnicAPI(auth_token=token, country_code="NL")
        else:
            _client = PicnicAPI(
                username=os.getenv("PICNIC_EMAIL"),
                password=os.getenv("PICNIC_PASSWORD"),
                country_code="NL",
            )
    return _client


def search_product(query: str, max_results: int = 3) -> list[dict]:
    try:
        results = _get_client().search(query)
        items = results[0]["items"] if results else []
        products = []
        for it in items[:max_results]:
            price_cents = it.get("display_price") or 0
            products.append({
                "product_id": f"pic_{it.get('id', 'unknown')}",
                "name": it.get("name", "Unknown"),
                "price_eur": round(price_cents / 100, 2),
                "unit": it.get("unit_quantity", ""),
                "image_url": it.get("image_id"),
            })
        return products
    except Exception as e:
        print(f"Picnic API error: {e}")
        return []


def _strip_prefix(product_id: str) -> str:
    return product_id.removeprefix("pic_")


def add_to_cart(product_id: str, count: int = 1) -> dict:
    return _get_client().add_product(_strip_prefix(product_id), count=count)


def clear_cart() -> dict:
    return _get_client().clear_cart()


def get_cart() -> dict:
    return _get_client().get_cart()


if __name__ == "__main__":
    tests = ["kipfilet", "broccoli", "zalm", "eieren", "rijst"]
    for q in tests:
        results = search_product(q, max_results=2)
        print(f"\n'{q}':")
        for r in results:
            print(f"  {r['name']} - EUR {r['price_eur']} ({r['unit']})")
