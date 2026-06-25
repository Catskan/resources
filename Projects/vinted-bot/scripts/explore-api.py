#!/usr/bin/env python3
"""Phase 8a — Exploration en lecture seule de l'API Vinted.

Sonde une série d'endpoints GET pour reverse-engineer :
  - La structure d'un objet `item` complet (champs, types)
  - La structure des photos attachées
  - Les endpoints utilitaires (user, brands, catégories...)
  - Les paramètres de pagination, filtres, etc.

Sauvegarde chaque réponse JSON dans data/api-exploration/<endpoint>.json
pour qu'on puisse les analyser offline sans recommencer les calls.

Usage:
    python3 scripts/explore-api.py
"""

import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import Cookie, CookieJar
from pathlib import Path

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
)


def load_env(path: Path) -> dict[str, str]:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def decode_jwt_exp(token: str) -> float | None:
    try:
        _, payload_b64, _ = token.split(".", 2)
        padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        return json.loads(base64.urlsafe_b64decode(padded)).get("exp")
    except Exception:
        return None


def build_cookie_jar(raw: list[dict]) -> tuple[CookieJar, dict[str, str]]:
    jar = CookieJar()
    cookies_dict = {}
    for c in raw:
        if not c.get("value"):
            continue
        domain = c.get("domain", ".vinted.fr")
        jar.set_cookie(
            Cookie(
                version=0, name=c["name"], value=c["value"],
                port=None, port_specified=False,
                domain=domain, domain_specified=bool(domain),
                domain_initial_dot=domain.startswith("."),
                path=c.get("path", "/"), path_specified=True,
                secure=c.get("secure", False),
                expires=c.get("expirationDate"),
                discard=False, comment=None, comment_url=None, rest={},
            )
        )
        cookies_dict[c["name"]] = c["value"]
    return jar, cookies_dict


def get_json(opener, url: str, headers: dict) -> tuple[int, dict | str]:
    req = urllib.request.Request(url, headers=headers)
    try:
        with opener.open(req, timeout=20) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, body[:300]
    except Exception as e:
        return -1, str(e)


def summarize_keys(obj, depth: int = 0, max_depth: int = 3) -> str:
    """Affiche la structure récursive (types + clés) d'un objet JSON."""
    if depth > max_depth:
        return "…"
    if isinstance(obj, dict):
        lines = []
        for k, v in obj.items():
            if isinstance(v, dict):
                lines.append(f"{'  ' * depth}{k}: dict({len(v)})")
                lines.append(summarize_keys(v, depth + 1, max_depth))
            elif isinstance(v, list):
                inner = ""
                if v and isinstance(v[0], dict):
                    inner = f" → element keys: {list(v[0].keys())[:8]}"
                lines.append(f"{'  ' * depth}{k}: list({len(v)}){inner}")
            else:
                preview = repr(v)[:60]
                lines.append(f"{'  ' * depth}{k}: {type(v).__name__} = {preview}")
        return "\n".join(filter(None, lines))
    return repr(obj)[:200]


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    env = load_env(project_root / ".env")
    user_id = int(env.get("VINTED_USER_ID", "0"))
    if not user_id:
        print("❌ VINTED_USER_ID manquant dans .env")
        return 1

    cookies_path = project_root / "data" / "cookies" / "vinted-cookies.json"
    raw = json.loads(cookies_path.read_text())
    jar, cookies_dict = build_cookie_jar(raw)

    bearer = cookies_dict.get("access_token_web")
    if not bearer:
        print("❌ access_token_web manquant dans les cookies")
        return 2

    exp = decode_jwt_exp(bearer)
    if exp and exp < time.time():
        print(f"⚠️  JWT expiré depuis {(time.time() - exp)/60:.1f} min — réexporte les cookies.")
        return 3

    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    base = "https://www.vinted.fr"

    headers = {
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8",
        "Authorization": f"Bearer {bearer}",
        "Referer": f"{base}/",
        "X-Anon-Id": cookies_dict.get("anon_id", ""),
    }

    out_dir = project_root / "data" / "api-exploration"
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── Sélection d'endpoints à explorer ─────────────────────
    # 1. Wardrobe complet pour avoir un premier item_id
    print("═" * 70)
    print(" PHASE 1 — Récupération d'un échantillon depuis le wardrobe")
    print("═" * 70)

    status, data = get_json(
        opener,
        f"{base}/api/v2/wardrobe/{user_id}/items?per_page=3&page=1",
        headers,
    )
    print(f"\n[GET] /api/v2/wardrobe/{user_id}/items?per_page=3 → {status}")
    if status != 200 or not isinstance(data, dict):
        print(f"  Réponse: {data!r}")
        return 4

    (out_dir / "wardrobe-items-page1.json").write_text(
        json.dumps(data, indent=2, ensure_ascii=False)
    )

    items = data.get("items", [])
    pagination = data.get("pagination", {})
    print(f"  Total items: {pagination.get('total_entries')}")
    print(f"  Échantillon de {len(items)} item(s) reçu(s)")
    print(f"  Top-level keys de la réponse: {list(data.keys())}")
    if items:
        print(f"\n  Structure d'un item de la liste wardrobe (vue résumée):")
        print(summarize_keys(items[0], depth=1, max_depth=2))

    first_item_id = items[0]["id"] if items else None

    # 2. Détail complet d'un item
    print()
    print("═" * 70)
    print(f" PHASE 2 — Détail complet d'un item (id={first_item_id})")
    print("═" * 70)

    if first_item_id:
        status, item_detail = get_json(
            opener, f"{base}/api/v2/items/{first_item_id}", headers
        )
        print(f"\n[GET] /api/v2/items/{first_item_id} → {status}")
        if status == 200 and isinstance(item_detail, dict):
            (out_dir / f"item-{first_item_id}-full.json").write_text(
                json.dumps(item_detail, indent=2, ensure_ascii=False)
            )
            item_obj = item_detail.get("item", item_detail)
            print(f"  Top-level keys: {list(item_detail.keys())}")
            print(f"\n  Structure de l'item (clés principales) :")
            print(summarize_keys(item_obj, depth=1, max_depth=2))

            photos = item_obj.get("photos", [])
            if photos:
                print(f"\n  Photos: {len(photos)}")
                print(f"  Structure d'une photo :")
                print(summarize_keys(photos[0], depth=1, max_depth=2))
        else:
            print(f"  Réponse: {item_detail!r}")

    # 3. Endpoints utilitaires divers
    print()
    print("═" * 70)
    print(" PHASE 3 — Endpoints utilitaires")
    print("═" * 70)

    endpoints_to_probe = [
        ("user profile", f"/api/v2/users/{user_id}"),
        ("draft items", f"/api/v2/wardrobe/{user_id}/items?status=DRAFT&per_page=2"),
        ("sold items", f"/api/v2/wardrobe/{user_id}/items?status=SOLD&per_page=2"),
        ("user policy / settings", f"/api/v2/users/{user_id}/policy"),
        ("photo upload session", "/api/v2/photos/temporary"),
        ("conversations preview", "/api/v2/conversations?per_page=1"),
        ("notifications", "/api/v2/notifications?per_page=1"),
        ("messages dashboard", "/api/v2/users/me/menu_items"),
    ]

    for label, endpoint in endpoints_to_probe:
        url = f"{base}{endpoint}"
        status, data = get_json(opener, url, headers)
        size = len(json.dumps(data)) if isinstance(data, (dict, list)) else len(str(data))
        ok = "✅" if status == 200 else ("❌" if status >= 400 else "❓")
        print(f"  {ok} [GET] {endpoint:55} → {status:4} ({size:>6} bytes)")
        if status == 200 and isinstance(data, dict):
            slug = endpoint.replace("/", "_").strip("_")
            (out_dir / f"probe-{slug}.json").write_text(
                json.dumps(data, indent=2, ensure_ascii=False)
            )

    print()
    print("═" * 70)
    print(f" ✅ Exploration terminée. Réponses sauvegardées dans {out_dir.relative_to(project_root)}/")
    print("═" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
