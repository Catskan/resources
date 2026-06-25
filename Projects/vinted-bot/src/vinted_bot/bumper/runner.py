"""Entry point principal du bumper.

Déclenché par DSM Task Scheduler toutes les heures de 12h à 22h, via :
    sudo docker exec vinted-bot python -m vinted_bot.bumper.runner --tick

Workflow d'un bump :
  1. should_bump_now() → décide si on doit bumper à ce tick
  2. sync_active_items() → refresh la DB depuis Vinted (cached 24h)
  3. pick_eligible() → choisit un article éligible aléatoirement
  4. GET item_upload/items/{id} → payload complet (brand_id, catalog_id, color_ids…)
  5. GET items/{id}/photos → URLs full_size de chaque photo
  6. Download + transform chaque photo via Pillow (anti-pHash)
  7. Upload chaque photo transformée → nouveaux photo_ids
  8. POST item_upload/items (création) → nouvel item_id
  9. POST items/{old_id}/delete → suppression de l'ancien
  10. DB : record_republication() + update_bumped_at()

En cas d'erreur après upload des photos :
  - On NE crée PAS le nouvel item (sinon orphelin)
  - On NE supprime PAS l'ancien (on annule proprement)
"""

from __future__ import annotations

import html
import random
import sys
import time
from datetime import datetime
from pathlib import Path

import click
from loguru import logger

from .. import db
from ..config import settings
from ..photos.transformer import transform
from ..vinted.client import VintedClient, new_upload_session_id
from ..vinted.errors import VintedError
from .scheduler import should_bump_now
from .selector import pick_eligible, sync_active_items


def execute_bump(client: VintedClient, vinted_item_id: int, dry_run: bool = False) -> int | None:
    """Exécute un bump complet : delete + recreate avec photos transformées.

    Retourne le nouvel item_id (ou None si dry_run/échec).
    """
    logger.info(f"[BUMP] Item {vinted_item_id} — fetch payload complet")
    item_full = client.get_item_for_edit(vinted_item_id)

    title = item_full.get("title", "(no title)")
    logger.info(f"[BUMP] '{title[:60]}' — fetch photos")
    photos = client.get_item_photos(vinted_item_id)

    if not photos:
        raise VintedError(f"item {vinted_item_id} : aucune photo trouvée, abort")
    logger.info(f"[BUMP] {len(photos)} photos à traiter")

    if dry_run:
        logger.info(f"[DRY-RUN] Stop avant upload/delete/create — item_id={vinted_item_id}")
        return None

    upload_session = new_upload_session_id()
    logger.info(f"[BUMP] upload_session_id = {upload_session}")

    new_photo_ids: list[int] = []
    for i, photo in enumerate(photos, 1):
        url = photo.get("full_size_url") or photo.get("url")
        if not url:
            logger.warning(f"[BUMP] photo #{i} sans url, skip")
            continue
        logger.info(f"[BUMP] photo #{i}/{len(photos)} : DL + transform + upload")

        raw = client.download_image(url)
        transformed = transform(raw)
        result = client.upload_photo(
            image_bytes=transformed,
            filename=f"photo_{i}.jpg",
            upload_session_id=upload_session,
        )
        new_id = result.get("id")
        if not new_id:
            raise VintedError(f"upload photo #{i} sans id: {result}")
        new_photo_ids.append(new_id)
        logger.info(f"[BUMP]   → nouveau photo_id = {new_id}")

    if not new_photo_ids:
        raise VintedError("Aucune photo uploadée — abort avant delete")

    # Reconstruire le payload pour la création
    payload = _build_create_payload(item_full, new_photo_ids)
    logger.info(f"[BUMP] DELETE ancien item {vinted_item_id}")
    client.delete_item(vinted_item_id)

    logger.info(f"[BUMP] CREATE nouvel item (titre='{title[:50]}')")
    create_resp = client.create_item(payload, upload_session_id=upload_session)
    new_id = create_resp.get("item", {}).get("id")
    if not new_id:
        raise VintedError(f"Création sans id retourné: {create_resp}")

    logger.success(f"[BUMP] ✅ {vinted_item_id} → {new_id}")
    return new_id


def _build_create_payload(item_full: dict, new_photo_ids: list[int]) -> dict:
    """Construit le payload de création à partir des données de l'item existant.

    Conserve tous les attributs (title, description, catalog, brand, color, size,
    condition, etc.) et remplace juste les photos.
    """
    color_ids = []
    for k in ("color1_id", "color2_id"):
        v = item_full.get(k)
        if v:
            color_ids.append(v)

    # item_attributes (condition, size, language_book…) — Vinted attend code+ids.
    # IMPORTANT : on AJOUTE condition/size depuis status_id/size_id s'ils ne sont
    # pas déjà présents dans item_attributes (ils sont parfois renvoyés à plat,
    # parfois imbriqués dans item_attributes selon la catégorie).
    item_attrs = list(item_full.get("item_attributes") or [])
    codes_present = {a.get("code") for a in item_attrs}
    if "condition" not in codes_present and item_full.get("status_id"):
        item_attrs.append({"code": "condition", "ids": [item_full["status_id"]]})
    if "size" not in codes_present and item_full.get("size_id"):
        item_attrs.append({"code": "size", "ids": [item_full["size_id"]]})

    # Le PUT capturé attend price en number, pas en {amount, currency}
    raw_price = item_full.get("price")
    if isinstance(raw_price, dict):
        try:
            price = float(raw_price.get("amount", 0))
            if price == int(price):
                price = int(price)
        except (TypeError, ValueError):
            price = None
    else:
        price = raw_price

    # status_id : Vinted attend la valeur au top-level pour certaines catégories
    # (livres notamment) et dans item_attributes pour d'autres (vêtements).
    # On envoie les DEUX pour max compatibilité. Si status_id=1 (legacy invalid
    # observé), on fallback à 2 ("Très bon état") qui est une valeur générique safe.
    raw_status = item_full.get("status_id")
    status_id = 2 if raw_status == 1 else raw_status
    if raw_status == 1:
        from loguru import logger as _lg
        _lg.warning("status_id=1 (legacy) override → 2 (Très bon état)")

    # Vinted renvoie certains titres/descriptions HTML-encoded (ex. 'H&amp;M')
    # On unescape pour éviter de re-pousser '&amp;' visible dans le nouveau listing
    title = html.unescape(item_full["title"])
    description = html.unescape(item_full.get("description") or "")

    payload = {
        "currency": item_full.get("currency") or "EUR",
        "title": title,
        "description": description,
        "brand_id": item_full.get("brand_id"),
        "brand": html.unescape(item_full.get("brand") or ""),
        "catalog_id": item_full.get("catalog_id"),
        "isbn": item_full.get("isbn"),
        "is_unisex": item_full.get("is_unisex", False),
        "ai_photo": False,
        "price": price,
        "package_size_id": item_full.get("package_size_id"),
        "shipment_prices": {
            "domestic": item_full.get("domestic_shipment_price"),
            "international": item_full.get("international_shipment_price"),
        },
        "color_ids": color_ids,
        "assigned_photos": [{"id": pid, "orientation": 0} for pid in new_photo_ids],
        "measurement_length": item_full.get("measurement_length"),
        "measurement_width": item_full.get("measurement_width"),
        "item_attributes": item_attrs,
        "manufacturer": item_full.get("manufacturer"),
        "manufacturer_labelling": item_full.get("manufacturer_labelling"),
    }
    # Top-level (pour livres et autres catégories non-vêtement)
    if status_id:
        payload["status_id"] = status_id
    if item_full.get("size_id"):
        payload["size_id"] = item_full["size_id"]

    return payload


@click.command()
@click.option("--tick", is_flag=True, help="Tick horaire (vérifie schedule avant d'agir)")
@click.option("--force", is_flag=True, help="Force un bump immédiat (ignore schedule)")
@click.option("--dry-run", is_flag=True, help="Ne fait pas les writes Vinted, log uniquement")
def main(tick: bool, force: bool, dry_run: bool) -> None:
    """Entry point du bumper, appelé par DSM Task Scheduler ou en local."""
    db.init_db()

    if not (tick or force):
        click.echo("Use --tick (probabiliste) ou --force (immédiat)", err=True)
        sys.exit(2)

    # 0. Jitter aléatoire (anti-pattern temporel)
    #    DSM tire le tick à HH:00 pile, le bot dort N min avant d'agir.
    #    Skip en --force et --dry-run pour permettre les tests immédiats.
    if tick and not force and not dry_run and settings.bump_jitter_max_min > 0:
        jitter_min = random.randint(
            settings.bump_jitter_min_min, settings.bump_jitter_max_min
        )
        logger.info(f"[JITTER] sleep {jitter_min} min avant le tick")
        time.sleep(jitter_min * 60)

    # 1. Décision de bump (sauf --force)
    if tick and not force:
        decision = should_bump_now()
        logger.info(f"[SCHEDULE] {decision.reason}")
        if not decision:
            sys.exit(0)

    # 2. Sync articles (cached 24h sauf --force)
    with VintedClient() as client:
        sync_active_items(client, force=force)

        # 3. Sélection
        chosen = pick_eligible()
        if not chosen:
            logger.warning("Aucun article éligible. Tu as peut-être 0 article actif "
                           "ou tous ont été bumped < 5j.")
            sys.exit(0)
        logger.info(f"[SELECTOR] Article choisi : {chosen['vinted_item_id']} — "
                    f"'{chosen['title'][:60]}'")

        # 4-9. Exécution du bump
        try:
            new_id = execute_bump(
                client, chosen["vinted_item_id"], dry_run=dry_run
            )
        except VintedError as e:
            logger.error(f"[BUMP] ÉCHEC : {e}")
            with db.connect() as conn:
                db.record_republication(
                    conn,
                    old_item_id=chosen["vinted_item_id"],
                    new_item_id=None,
                    success=False,
                    error=str(e),
                )
            sys.exit(1)

    # 10. Update DB (sauf dry-run)
    if not dry_run and new_id:
        with db.connect() as conn:
            db.record_republication(
                conn,
                old_item_id=chosen["vinted_item_id"],
                new_item_id=new_id,
                success=True,
            )
            db.update_bumped_at(conn, old_id=chosen["vinted_item_id"], new_id=new_id)
            count = db.increment_today_counter(conn)
        logger.success(f"[DB] Compteur du jour : {count}/{settings.bump_max_per_day}")

    sys.exit(0)


if __name__ == "__main__":
    main()
