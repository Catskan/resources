#!/usr/bin/env python3
"""Étape 2 — commit du bump live :
  - lit /tmp/vinted-bump-session.json
  - DELETE l'ancien item
  - CREATE le nouvel item avec le payload sauvegardé
  - update la DB locale

⚠️ Cette étape modifie ton compte Vinted.

Usage:
    python3 scripts/live-bump-commit.py
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from loguru import logger  # noqa: E402

from vinted_bot import db  # noqa: E402
from vinted_bot.vinted.client import VintedClient  # noqa: E402
from vinted_bot.vinted.errors import VintedError  # noqa: E402

SESSION_FILE = Path("/tmp/vinted-bump-session.json")


def main() -> int:
    if not SESSION_FILE.exists():
        print(f"❌ Session introuvable : {SESSION_FILE}")
        print("   Lance d'abord : python3 scripts/live-bump-prepare.py")
        return 1

    session = json.loads(SESSION_FILE.read_text())
    old_id = session["old_item_id"]
    upload_session = session["upload_session_id"]
    payload = session["payload"]

    print(f"→ old_item_id        : {old_id}")
    print(f"→ upload_session_id  : {upload_session}")
    print(f"→ payload.title      : {payload.get('title')}")
    print(f"→ {len(payload['assigned_photos'])} photos déjà uploadées")
    print()

    with VintedClient() as client:
        try:
            print(f"→ DELETE /api/v2/items/{old_id}/delete")
            client.delete_item(old_id)
            print("  ✓ Ancien item supprimé")

            print(f"\n→ POST /api/v2/item_upload/items (create)")
            resp = client.create_item(payload, upload_session_id=upload_session)
            new_id = resp.get("item", {}).get("id")
            if not new_id:
                raise VintedError(f"Création sans id retourné : {resp}")
            print(f"  ✓ Nouvel item créé : id={new_id}")

        except VintedError as e:
            logger.error(f"❌ ÉCHEC : {e}")
            with db.connect() as conn:
                db.record_republication(
                    conn, old_item_id=old_id, new_item_id=None, success=False, error=str(e)
                )
            return 2

    # Update DB
    with db.connect() as conn:
        db.record_republication(
            conn, old_item_id=old_id, new_item_id=new_id, success=True
        )
        db.update_bumped_at(conn, old_id=old_id, new_id=new_id)
        count = db.increment_today_counter(conn)

    print()
    print("═" * 70)
    print(f"  ✅ Bump LIVE réussi  :  {old_id} → {new_id}")
    print(f"  DB compteur du jour :  {count}/6")
    print(f"  URL du nouvel item  :  https://www.vinted.fr/items/{new_id}")
    print("═" * 70)

    # Cleanup session file
    SESSION_FILE.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
