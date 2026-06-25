#!/usr/bin/env python3
"""Test end-to-end de la logique bumper Phase 11.

  1. Init DB
  2. Sync articles depuis Vinted (vrai appel API)
  3. Test scheduler.should_bump_now() (sur l'heure actuelle)
  4. Test selector.pick_eligible() (avec la DB sync)

Aucun bump réel n'est exécuté.

Usage:
    VINTED_COOKIES_PATH=... DB_PATH=... python3 scripts/test-bumper-logic.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from vinted_bot import db  # noqa: E402
from vinted_bot.bumper.scheduler import should_bump_now  # noqa: E402
from vinted_bot.bumper.selector import pick_eligible, sync_active_items  # noqa: E402
from vinted_bot.vinted.client import VintedClient  # noqa: E402


def main() -> int:
    print("─" * 70)
    print(" 1. Init DB")
    print("─" * 70)
    db.init_db()
    print("  ✓ Schema appliqué")

    print()
    print("─" * 70)
    print(" 2. Sync articles depuis Vinted")
    print("─" * 70)
    with VintedClient() as v:
        result = sync_active_items(v, force=True)
    print(f"  Résultat : {result}")

    with db.connect() as conn:
        total = conn.execute("SELECT COUNT(*) AS n FROM articles").fetchone()["n"]
        active = conn.execute(
            "SELECT COUNT(*) AS n FROM articles WHERE is_active=1"
        ).fetchone()["n"]
    print(f"  ✓ DB : {active}/{total} articles actifs en cache local")

    print()
    print("─" * 70)
    print(" 3. should_bump_now()")
    print("─" * 70)
    decision = should_bump_now()
    print(f"  Décision : {'BUMP' if decision else 'SKIP'}")
    print(f"  Raison   : {decision.reason}")

    print()
    print("─" * 70)
    print(" 4. pick_eligible()")
    print("─" * 70)
    picked = pick_eligible()
    if picked:
        print(f"  ✓ Article sélectionné :")
        print(f"      vinted_item_id : {picked['vinted_item_id']}")
        print(f"      title          : {picked['title']!r}")
        print(f"      last_bumped_at : {picked['last_bumped_at'] or '(jamais)'}")
    else:
        print(f"  ⚠️  Aucun article éligible (tous bumped récemment ?)")

    print()
    print("─" * 70)
    print(" Résumé")
    print("─" * 70)
    with db.connect() as conn:
        today = conn.execute(
            "SELECT date, n_republications, is_off_day FROM daily_counters "
            "ORDER BY date DESC LIMIT 1"
        ).fetchone()
    if today:
        off = " (jour OFF)" if today["is_off_day"] else ""
        print(f"  Aujourd'hui ({today['date']}) : {today['n_republications']}/5 bumps{off}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
