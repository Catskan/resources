#!/usr/bin/env python3
"""Étape 1 — prépare un bump live :
  - fetch payload complet de l'item
  - download + transform + upload de chaque photo (Vinted accepte)
  - construit le payload de création
  - dump le payload dans /tmp/vinted-bump-session.json
  - print le payload à l'écran pour validation

⚠️ À ce stade : les photos sont uploadées sur Vinted (= orphelines) mais
   l'item original n'est PAS supprimé ni recréé. Pas d'impact sur le dressing.

Usage:
    python3 scripts/live-bump-prepare.py            # item au hasard
    python3 scripts/live-bump-prepare.py 6078835619 # item id explicite
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from vinted_bot import db  # noqa: E402
from vinted_bot.bumper.runner import _build_create_payload  # noqa: E402
from vinted_bot.bumper.selector import pick_eligible, sync_active_items  # noqa: E402
from vinted_bot.photos.transformer import transform  # noqa: E402
from vinted_bot.vinted.client import VintedClient, new_upload_session_id  # noqa: E402

SESSION_FILE = Path("/tmp/vinted-bump-session.json")


def main() -> int:
    item_id_arg = int(sys.argv[1]) if len(sys.argv) > 1 else None

    db.init_db()

    with VintedClient() as client:
        sync_active_items(client, force=False)

        if item_id_arg:
            item_id = item_id_arg
            print(f"→ Item explicite : {item_id}")
        else:
            chosen = pick_eligible()
            if not chosen:
                print("❌ Aucun item éligible")
                return 1
            item_id = chosen["vinted_item_id"]
            print(f"→ Item picked (random) : {item_id} — '{chosen['title']}'")

        print(f"→ Fetch payload complet via GET /api/v2/item_upload/items/{item_id}")
        item_full = client.get_item_for_edit(item_id)
        print(f"  Title       : {item_full.get('title')}")
        print(f"  catalog_id  : {item_full.get('catalog_id')}")
        print(f"  brand_id    : {item_full.get('brand_id')}")
        print(f"  size_id     : {item_full.get('size_id')}")
        print(f"  color1_id   : {item_full.get('color1_id')}")
        print(f"  status      : {item_full.get('status_id')}")
        print(f"  price       : {item_full.get('price')}")

        photos = client.get_item_photos(item_id)
        print(f"\n→ {len(photos)} photos à transformer + uploader")

        upload_session = new_upload_session_id()
        print(f"  upload_session_id = {upload_session}")

        new_photo_ids: list[int] = []
        for i, photo in enumerate(photos, 1):
            url = photo.get("full_size_url") or photo.get("url")
            print(f"\n  Photo #{i}/{len(photos)}")
            print(f"    DL {url[:80]}...")
            raw = client.download_image(url)
            print(f"    {len(raw):,} bytes téléchargés")
            transformed = transform(raw)
            print(f"    {len(transformed):,} bytes après transform")
            result = client.upload_photo(
                image_bytes=transformed,
                filename=f"photo_{i}.jpg",
                upload_session_id=upload_session,
            )
            new_id = result.get("id")
            new_photo_ids.append(new_id)
            print(f"    ✓ Uploadé sous photo_id={new_id}")

        payload = _build_create_payload(item_full, new_photo_ids)

        # Sauvegarde la session pour l'étape commit
        SESSION_FILE.write_text(json.dumps({
            "old_item_id": item_id,
            "upload_session_id": upload_session,
            "new_photo_ids": new_photo_ids,
            "payload": payload,
        }, indent=2, ensure_ascii=False))

        print()
        print("═" * 70)
        print(f"  PAYLOAD CRÉATION (sera envoyé en POST /api/v2/item_upload/items)")
        print("═" * 70)
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        print()
        print("═" * 70)
        print(f"  Session sauvegardée : {SESSION_FILE}")
        print(f"  → Pour committer : python3 scripts/live-bump-commit.py")
        print(f"  → Pour annuler   : rm {SESSION_FILE}  (les photos uploadées seront orphelines, no-op)")
        print("═" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
