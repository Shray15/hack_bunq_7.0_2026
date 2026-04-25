import time
import requests
from dotenv import load_dotenv

load_dotenv()

_AUTH_URL = "https://api.ah.nl/mobile-auth/v1/auth/token/anonymous"
_SEARCH_URL = "https://api.ah.nl/mobile-services/product/search/v2"
_UA = "Appie/8.22.3"

_token: str | None = None
_token_expires_at: float = 0.0


def _get_token() -> str | None:
    global _token, _token_expires_at
    now = time.time()
    if _token and now < _token_expires_at:
        return _token
    try:
        r = requests.post(
            _AUTH_URL,
            json={"clientId": "appie"},
            headers={"User-Agent": _UA},
            timeout=8,
        )
        r.raise_for_status()
        data = r.json()
        _token = data["access_token"]
        _token_expires_at = now + int(data.get("expires_in", 3600)) - 60
        return _token
    except Exception as e:
        print(f"AH auth error: {e}")
        return None


def search_product(query: str, max_results: int = 3) -> list[dict]:
    token = _get_token()
    if not token:
        return []
    try:
        r = requests.get(
            _SEARCH_URL,
            params={"query": query, "size": max_results},
            headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": _UA,
                "x-clientid": "appie",
                "x-application": "AHWEBSHOP",
            },
            timeout=8,
        )
        r.raise_for_status()
        products = r.json().get("products", [])
        out = []
        for p in products[:max_results]:
            current = p.get("currentPrice")
            before = p.get("priceBeforeBonus")
            price = current if current is not None else before
            wid = p.get("webshopId")
            if price is None or wid is None:
                continue
            out.append({
                "product_id": f"ah_wi{wid}",
                "name": p.get("title", ""),
                "price_eur": float(price),
                "unit": p.get("salesUnitSize", ""),
                "image_url": (p.get("images") or [{}])[0].get("url"),
            })
        return out
    except Exception as e:
        print(f"AH API error: {e}")
        return []
