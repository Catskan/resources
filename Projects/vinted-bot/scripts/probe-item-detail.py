#!/usr/bin/env python3
"""Sonde différentes variantes d'endpoints pour récupérer les détails complets d'un item.

Le wardrobe list ne renvoie PAS la description ni les IDs (brand_id, size_id, category_id).
On a besoin de ces données pour pouvoir republier un item.

Usage:
    python3 scripts/probe-item-detail.py
"""

import json
import re
import sys
import urllib.error
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
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def build_jar(raw: list[dict]) -> tuple[CookieJar, dict[str, str]]:
    jar = CookieJar()
    d = {}
    for c in raw:
        if not c.get("value"):
            continue
        domain = c.get("domain", ".vinted.fr")
        jar.set_cookie(Cookie(
            version=0, name=c["name"], value=c["value"],
            port=None, port_specified=False,
            domain=domain, domain_specified=bool(domain),
            domain_initial_dot=domain.startswith("."),
            path=c.get("path", "/"), path_specified=True,
            secure=c.get("secure", False), expires=c.get("expirationDate"),
            discard=False, comment=None, comment_url=None, rest={},
        ))
        d[c["name"]] = c["value"]
    return jar, d


def fetch(opener, url: str, headers: dict, max_bytes: int = 500) -> tuple[int, str]:
    try:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=20) as r:
            body = r.read().decode("utf-8", errors="ignore")
            return r.status, body
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="ignore")[:max_bytes]
    except Exception as e:
        return -1, str(e)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    env = load_env(root / ".env")
    user_id = int(env.get("VINTED_USER_ID", "0"))

    cookies_path = root / "data" / "cookies" / "vinted-cookies.json"
    raw = json.loads(cookies_path.read_text())
    jar, cookies_dict = build_jar(raw)
    bearer = cookies_dict.get("access_token_web", "")

    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    base = "https://www.vinted.fr"
    h_api = {
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "fr-FR,fr;q=0.9",
        "Authorization": f"Bearer {bearer}",
        "Referer": f"{base}/",
        "X-Anon-Id": cookies_dict.get("anon_id", ""),
    }

    # Récupère le premier item depuis le wardrobe
    status, body = fetch(opener, f"{base}/api/v2/wardrobe/{user_id}/items?per_page=1", h_api, 100000)
    data = json.loads(body)
    item = data["items"][0]
    item_id = item["id"]
    item_path = item["path"]  # /items/{id}-{slug}
    item_url = item["url"]    # https://www.vinted.fr/items/...
    print(f"Test sur item_id={item_id}, path={item_path}\n")

    # ─── Battery de variantes API ────────────────────────
    api_candidates = [
        ("/api/v2/items/{id}", f"/api/v2/items/{item_id}"),
        ("/api/v2/items/{id}/details", f"/api/v2/items/{item_id}/details"),
        ("/api/v2/items/{id}/edit", f"/api/v2/items/{item_id}/edit"),
        ("/api/v2/items/{id}/details_for_edit", f"/api/v2/items/{item_id}/details_for_edit"),
        ("/api/v2/items/{id}/photos", f"/api/v2/items/{item_id}/photos"),
        ("/api/v2/items/{id}.json", f"/api/v2/items/{item_id}.json"),
        ("/api/items/{id}", f"/api/items/{item_id}"),
        ("/api/v1/items/{id}", f"/api/v1/items/{item_id}"),
        ("/web/api/items/{id}", f"/web/api/items/{item_id}"),
        ("/web/api/v2/items/{id}", f"/web/api/v2/items/{item_id}"),
        ("/api/v2/wardrobe/{uid}/items/{id}", f"/api/v2/wardrobe/{user_id}/items/{item_id}"),
        # Variations sur le path web
        ("path-as-api ({path}.json)", f"{item_path}.json"),
        ("path-as-api ({path}/details.json)", f"{item_path}/details.json"),
    ]

    print(f"{'='*78}\n  Battery API endpoints\n{'='*78}")
    print(f"{'Variante':50} → {'HTTP':>5}  {'Bytes':>7}  Indice")
    print("─" * 78)
    for label, endpoint in api_candidates:
        url = f"{base}{endpoint}"
        status, body = fetch(opener, url, h_api, 200)
        size = len(body)
        is_json = body.strip().startswith(("{", "["))
        has_desc = "description" in body
        clue = []
        if is_json:
            clue.append("JSON")
        if has_desc:
            clue.append("a 'description'")
        clue_s = ", ".join(clue) if clue else ""
        print(f"  {label:50} → {status:>5}  {size:>7}  {clue_s}")

    # ─── Test : HTML de la page item ──────────────────
    print(f"\n{'='*78}\n  Page HTML item (pour extraire le JSON embedded)\n{'='*78}")
    h_html = {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "fr-FR,fr;q=0.9",
        # On enlève Authorization pour les pages HTML
    }
    status, html = fetch(opener, item_url, h_html, max_bytes=500000)
    print(f"GET {item_url} → {status}")
    if status == 200:
        # Cherche __INITIAL_STATE__, JSON-LD, ou autre blob JSON
        patterns = [
            ('__INITIAL_STATE__', r'__INITIAL_STATE__\s*=\s*(\{.+?\});'),
            ('window.app_data', r'window\.app_data\s*=\s*(\{.+?\});'),
            ('itemData', r'itemData\s*[:=]\s*(\{.+?\})\s*[,;]'),
            ('"description"', r'"description"\s*:\s*"([^"]{20,500})"'),
            ('og:description', r'<meta\s+property="og:description"\s+content="([^"]+)"'),
            ('JSON-LD', r'<script[^>]+type="application/ld\+json"[^>]*>(.+?)</script>'),
        ]
        for label, pat in patterns:
            m = re.search(pat, html, re.DOTALL)
            if m:
                snippet = m.group(1)[:300] if m.group(1) else ""
                print(f"  ✅ {label} trouvé — extrait: {snippet[:200]!r}...")
            else:
                print(f"  ❌ {label} absent")

    return 0


if __name__ == "__main__":
    sys.exit(main())
