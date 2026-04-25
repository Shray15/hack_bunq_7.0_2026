import os
import time
import requests
from dotenv import load_dotenv

load_dotenv()

AH_BASE_URL = "https://www.ah.nl/producten/product"
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

_AH_STUB: dict[str, dict] = {
    "chicken": {"product_id": "wi531825", "name": "AH Scharrel Kipfilet", "price_eur": 5.49, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi531825/ah-scharrel-kipfilet"},
    "kipfilet": {"product_id": "wi531825", "name": "AH Scharrel Kipfilet", "price_eur": 5.49, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi531825/ah-scharrel-kipfilet"},
    "rice": {"product_id": "wi162513", "name": "AH Zilvervliesrijst", "price_eur": 1.89, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi162513/ah-zilvervliesrijst"},
    "zilvervliesrijst": {"product_id": "wi162513", "name": "AH Zilvervliesrijst", "price_eur": 1.89, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi162513/ah-zilvervliesrijst"},
    "egg": {"product_id": "wi130273", "name": "AH Verse Scharreleieren M", "price_eur": 2.49, "unit": "6 stuks", "product_url": f"{AH_BASE_URL}/wi130273/ah-verse-scharreleieren-m"},
    "eieren": {"product_id": "wi130273", "name": "AH Verse Scharreleieren M", "price_eur": 2.49, "unit": "6 stuks", "product_url": f"{AH_BASE_URL}/wi130273/ah-verse-scharreleieren-m"},
    "pasta": {"product_id": "wi58168", "name": "AH Biologisch Volkoren Penne", "price_eur": 0.99, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi58168/ah-biologisch-volkoren-penne"},
    "tomato": {"product_id": "wi436200", "name": "Looye Honingtomaten", "price_eur": 1.49, "unit": "250g", "product_url": f"{AH_BASE_URL}/wi436200/looye-honingtomaten"},
    "tomaten": {"product_id": "wi436200", "name": "Looye Honingtomaten", "price_eur": 1.49, "unit": "250g", "product_url": f"{AH_BASE_URL}/wi436200/looye-honingtomaten"},
    "beef": {"product_id": "wi4011", "name": "AH Rundergehakt", "price_eur": 4.99, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi4011/ah-rundergehakt"},
    "rundergehakt": {"product_id": "wi4011", "name": "AH Rundergehakt", "price_eur": 4.99, "unit": "500g", "product_url": f"{AH_BASE_URL}/wi4011/ah-rundergehakt"},
    "broccoli": {"product_id": "wi466127", "name": "AH Biologisch Broccoli", "price_eur": 1.29, "unit": "400g", "product_url": f"{AH_BASE_URL}/wi466127/ah-biologisch-broccoli"},
    "onion": {"product_id": "wi525847", "name": "AH Gele Uien", "price_eur": 0.99, "unit": "1kg", "product_url": f"{AH_BASE_URL}/wi525847/ah-gele-uien"},
    "uien": {"product_id": "wi525847", "name": "AH Gele Uien", "price_eur": 0.99, "unit": "1kg", "product_url": f"{AH_BASE_URL}/wi525847/ah-gele-uien"},
    "garlic": {"product_id": "wi4160", "name": "AH Knoflook", "price_eur": 0.79, "unit": "3 bollen", "product_url": f"{AH_BASE_URL}/wi4160/ah-knoflook"},
    "knoflook": {"product_id": "wi4160", "name": "AH Knoflook", "price_eur": 0.79, "unit": "3 bollen", "product_url": f"{AH_BASE_URL}/wi4160/ah-knoflook"},
    "salmon": {"product_id": "wi612623", "name": "AH Zalmfilet Smokey", "price_eur": 5.99, "unit": "300g", "product_url": f"{AH_BASE_URL}/wi612623/ah-zalmfilet-smokey"},
    "zalmfilet": {"product_id": "wi612623", "name": "AH Zalmfilet Smokey", "price_eur": 5.99, "unit": "300g", "product_url": f"{AH_BASE_URL}/wi612623/ah-zalmfilet-smokey"},
    "spinach": {"product_id": "wi474803", "name": "Iglo Biologische Spinazie", "price_eur": 1.99, "unit": "450g", "product_url": f"{AH_BASE_URL}/wi474803/iglo-biologische-spinazie"},
    "spinazie": {"product_id": "wi474803", "name": "Iglo Biologische Spinazie", "price_eur": 1.99, "unit": "450g", "product_url": f"{AH_BASE_URL}/wi474803/iglo-biologische-spinazie"},
    "cheese": {"product_id": "wi202113", "name": "Parrano Geraspte Kaas", "price_eur": 1.79, "unit": "150g", "product_url": f"{AH_BASE_URL}/wi202113/parrano-geraspte-kaas-snippers-originale"},
    "kaas": {"product_id": "wi202113", "name": "Parrano Geraspte Kaas", "price_eur": 1.79, "unit": "150g", "product_url": f"{AH_BASE_URL}/wi202113/parrano-geraspte-kaas-snippers-originale"},
    "milk": {"product_id": "wi1525", "name": "AH Halfvolle Melk", "price_eur": 1.19, "unit": "1L", "product_url": f"{AH_BASE_URL}/wi1525/ah-halfvolle-melk"},
    "melk": {"product_id": "wi1525", "name": "AH Halfvolle Melk", "price_eur": 1.19, "unit": "1L", "product_url": f"{AH_BASE_URL}/wi1525/ah-halfvolle-melk"},
    "butter": {"product_id": "wi429627", "name": "Kerrygold Pure Ierse Boter", "price_eur": 2.49, "unit": "250g", "product_url": f"{AH_BASE_URL}/wi429627/kerrygold-pure-ierse-boter-ongezouten"},
    "olive oil": {"product_id": "wi429755", "name": "Bertolli Bio Olijfolie Extra Vierge", "price_eur": 3.99, "unit": "500ml", "product_url": f"{AH_BASE_URL}/wi429755/bertolli-bio-originale-extra-vierge-olijfolie"},
    "olijfolie": {"product_id": "wi429755", "name": "Bertolli Bio Olijfolie Extra Vierge", "price_eur": 3.99, "unit": "500ml", "product_url": f"{AH_BASE_URL}/wi429755/bertolli-bio-originale-extra-vierge-olijfolie"},
    "lemon": {"product_id": "wi518946", "name": "AH Citroenen", "price_eur": 1.09, "unit": "4 stuks", "product_url": f"{AH_BASE_URL}/wi518946/ah-citroenen"},
    "citroen": {"product_id": "wi518946", "name": "AH Citroenen", "price_eur": 1.09, "unit": "4 stuks", "product_url": f"{AH_BASE_URL}/wi518946/ah-citroenen"},
}

_DEFAULT = {"product_id": None, "name": "AH Huismerk product", "price_eur": 2.49, "unit": "1 stuk", "product_url": None}


def _live_search(query: str, max_results: int) -> list[dict] | None:
    token = _get_token()
    if not token:
        return None
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
        return out or None
    except Exception as e:
        print(f"AH API error: {e}")
        return None


def search_product(query: str, max_results: int = 3) -> list[dict]:
    results = _live_search(query, max_results)
    if results:
        return results

    # Fall back to stub (AH API unreachable or auth failed)
    query_lower = query.lower().strip()
    matches = [p for k, p in _AH_STUB.items() if k in query_lower or query_lower in k]
    return matches[:max_results] if matches else [_DEFAULT]
