#!/usr/bin/env python3
"""Validation des cookies Vinted exportés.

Vérifie que les cookies dans data/cookies/vinted-cookies.json :
  1. Contiennent les cookies critiques (_vinted_fr_session, access_token_web, v_uid)
  2. Permettent de décoder l'access_token JWT et d'en sortir le user_id
  3. Permettent d'appeler l'API authentifiée et lister un item du dressing

Usage:
    python3 scripts/test-cookies.py

Stdlib uniquement (pas besoin du venv pour ce test).
"""

import base64
import json
import sys
import urllib.error
import urllib.request
from http.cookiejar import Cookie, CookieJar
from pathlib import Path

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
)

CRITICAL_COOKIES = {
    "_vinted_fr_session",
    "access_token_web",
    "v_uid",
    "cf_clearance",
}


def decode_jwt_payload(token: str) -> dict:
    """Décode le payload d'un JWT sans vérifier la signature."""
    try:
        _, payload_b64, _ = token.split(".", 2)
        padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception as e:
        return {"__error__": str(e)}


def main() -> int:
    import os
    project_root = Path(__file__).resolve().parent.parent
    # Respecte VINTED_COOKIES_PATH si fourni (utile pour valider compte2, etc.)
    env_path = os.environ.get("VINTED_COOKIES_PATH")
    if env_path and Path(env_path).exists():
        cookies_path = Path(env_path)
    else:
        cookies_path = project_root / "data" / "cookies" / "vinted-cookies.json"

    if not cookies_path.exists():
        print(f"❌ Cookies introuvables à {cookies_path}")
        return 1
    print(f"→ Lecture cookies depuis : {cookies_path}")

    raw = json.loads(cookies_path.read_text())
    cookies = {c["name"]: c for c in raw if c.get("value")}

    print(f"✓ {len(cookies)} cookies chargés depuis {cookies_path.name}")

    # 1. Présence des cookies critiques
    missing = CRITICAL_COOKIES - set(cookies)
    if missing:
        print(f"❌ Cookies critiques manquants : {', '.join(missing)}")
        return 2
    print(f"✓ Tous les cookies critiques présents : {', '.join(sorted(CRITICAL_COOKIES))}")

    # 2. Décodage du JWT access_token_web
    token = cookies["access_token_web"]["value"]
    payload = decode_jwt_payload(token)
    if "__error__" in payload:
        print(f"❌ Impossible de décoder access_token_web : {payload['__error__']}")
        return 3

    # Le JWT `sub` est le user_id authentifié — source de vérité (le cookie v_uid
    # peut être stale après un switch de compte côté navigateur).
    user_id = (
        payload.get("sub")
        or payload.get("sub_id")
        or payload.get("user_id")
        or None
    )
    # v_uid en fallback ultime
    if not user_id:
        try:
            user_id = int(cookies["v_uid"]["value"])
        except (ValueError, KeyError):
            pass

    if not user_id:
        print(f"❌ user_id introuvable dans le JWT ni dans v_uid. Payload: {payload}")
        return 4

    try:
        user_id = int(user_id)
    except (ValueError, TypeError):
        print(f"❌ user_id n'est pas un entier : {user_id!r}")
        return 4

    print(f"✓ user_id détecté : {user_id}")
    if "exp" in payload:
        import datetime as _dt

        exp_dt = _dt.datetime.fromtimestamp(payload["exp"])
        now = _dt.datetime.now()
        delta = exp_dt - now
        if delta.total_seconds() < 0:
            print(f"⚠️  access_token_web EXPIRÉ depuis {-delta}. Refresh les cookies.")
        else:
            print(f"✓ access_token_web valide encore {delta} (jusqu'au {exp_dt:%Y-%m-%d %H:%M})")

    # 3. Test API authentifié
    jar = CookieJar()
    for c in raw:
        if not c.get("value"):
            continue
        domain = c.get("domain", ".vinted.fr")
        jar.set_cookie(
            Cookie(
                version=0,
                name=c["name"],
                value=c["value"],
                port=None,
                port_specified=False,
                domain=domain,
                domain_specified=bool(domain),
                domain_initial_dot=domain.startswith("."),
                path=c.get("path", "/"),
                path_specified=True,
                secure=c.get("secure", False),
                expires=c.get("expirationDate"),
                discard=False,
                comment=None,
                comment_url=None,
                rest={},
            )
        )

    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    api_url = f"https://www.vinted.fr/api/v2/wardrobe/{user_id}/items?per_page=1&page=1"
    req = urllib.request.Request(
        api_url,
        headers={
            "User-Agent": UA,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8",
            "X-Anon-Id": cookies.get("anon_id", {}).get("value", ""),
            "Referer": "https://www.vinted.fr/",
            # CRUCIAL : l'API v2 attend le JWT dans le header Authorization
            "Authorization": f"Bearer {token}",
        },
    )

    print(f"\n→ Test API : GET /api/v2/wardrobe/{user_id}/items?per_page=1")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode("utf-8")
            data = json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        print(f"❌ HTTP {e.code} : {body[:300]}")
        return 5
    except Exception as e:
        print(f"❌ Connexion échouée : {e}")
        return 5

    total = data.get("pagination", {}).get("total_entries")
    items = data.get("items", [])
    print(f"✅ API OK — {total} articles actifs dans ton dressing")

    if items:
        first = items[0]
        print(
            f"   Premier article (échantillon) : "
            f"id={first.get('id')} | {first.get('title', '?')[:50]!r}"
        )

    print()
    print("─" * 60)
    print(f"  ➡️  À ajouter dans ton .env :  VINTED_USER_ID={user_id}")
    print("─" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
