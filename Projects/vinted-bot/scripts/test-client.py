#!/usr/bin/env python3
"""Test end-to-end du VintedClient en lecture seule (sans modif sur Vinted).

Vérifie que :
  - Les cookies / JWT chargent OK
  - Le X-CSRF-Token s'extrait de la home
  - On peut lister les items actifs
  - On peut récupérer les photos d'un item
  - On peut récupérer la description via le HTML

Aucune écriture n'est faite.

Usage:
    python3 scripts/test-client.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from vinted_bot.vinted.client import VintedClient  # noqa: E402


def main() -> int:
    print("→ Init VintedClient...")
    with VintedClient() as v:
        print(f"  ✓ Cookies + JWT bearer OK")

        print("\n→ Fetch X-CSRF-Token...")
        csrf = v._get_csrf_token()
        print(f"  ✓ csrf = {csrf[:8]}…")

        print("\n→ list_active_items(per_page=3)...")
        data = v.list_active_items(per_page=3)
        total = data.get("pagination", {}).get("total_entries", "?")
        items = data.get("items", [])
        print(f"  ✓ {total} items au total, {len(items)} dans cette page")
        if items:
            first = items[0]
            print(f"  ✓ Premier item: id={first['id']} | {first['title']!r}")

            print(f"\n→ get_item_photos({first['id']})...")
            photos = v.get_item_photos(first["id"])
            print(f"  ✓ {len(photos)} photos, première URL full_size: {photos[0]['full_size_url'][:80]}...")

            print(f"\n→ get_item_description(path={first['path']!r})...")
            desc = v.get_item_description(first["path"])
            if desc:
                print(f"  ✓ Description ({len(desc)} chars): {desc[:200]!r}...")
            else:
                print(f"  ⚠️  description = None")

    print("\n✅ Toutes les opérations en lecture ont réussi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
