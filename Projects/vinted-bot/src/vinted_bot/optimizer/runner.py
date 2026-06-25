"""Entry point optimizer.

Deux modes :

1. --generate : WoL PC → query LLM pour ~20 articles éligibles →
   écrit data/proposals/proposals-YYYYMMDD.json → shutdown PC

2. --apply : lit le dernier proposals-*.json édité par l'utilisateur,
   applique les actions (apply / skip / edit) via PUT Vinted item_upload

Critères de sélection des articles à optimiser (--generate) :
  - is_active = 1
  - last_optimized_at NULL ou < (now - OPTIMIZER_MIN_DAYS_BETWEEN_OPTIMIZATIONS)
  - price >= OPTIMIZER_MIN_PRICE_EUR
  - Pondération saison via BUMP_PREFER_SEASON si configuré
  - Top OPTIMIZER_BATCH_SIZE items

Déclenché par DSM Task Scheduler (mensuel) ou manuellement.
"""

from __future__ import annotations

import json
import random
import sys
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path

import click
from loguru import logger

from .. import db
from ..bumper.seasonal import resolve_season_setting, score_for_season
from ..config import settings
from ..vinted.client import VintedClient
from ..vinted.errors import VintedError
from . import llm, proposals, wol


def select_items_to_optimize(client: VintedClient, batch_size: int | None = None) -> list[dict]:
    """Sélectionne les articles à optimiser, en excluant ceux déjà dans un proposals-*.json.

    Args:
        batch_size: override de OPTIMIZER_BATCH_SIZE. 0 ou -1 = pas de limite (--all).
    """
    cutoff = (
        datetime.now() - timedelta(days=settings.optimizer_min_days_between_optimizations)
    ).isoformat()

    already = proposals.all_proposed_item_ids()
    logger.info(f"  {len(already)} items déjà dans des proposals — seront exclus")

    with db.connect() as conn:
        rows = conn.execute(
            """
            SELECT vinted_item_id, title, price_cents, last_optimized_at
            FROM articles
            WHERE is_active = 1
              AND (last_optimized_at IS NULL OR last_optimized_at < ?)
              AND price_cents >= ?
            """,
            (cutoff, int(settings.optimizer_min_price_eur * 100)),
        ).fetchall()

    candidates = [dict(r) for r in rows if r["vinted_item_id"] not in already]
    logger.info(
        f"  {len(candidates)} candidats nouveaux (prix ≥ {settings.optimizer_min_price_eur}€, "
        f"jamais optimisés ou >90j, pas dans proposals)"
    )

    season = resolve_season_setting(settings.bump_prefer_season)
    if season:
        for c in candidates:
            c["_score"] = score_for_season(c["title"], season)
        candidates.sort(key=lambda c: (-c["_score"], random.random()))
        logger.info(f"  Pondération saison '{season}' active")
    else:
        random.shuffle(candidates)

    limit = batch_size if batch_size is not None else settings.optimizer_batch_size
    if limit > 0:
        top = candidates[:limit]
        logger.info(f"  Top {len(top)} retenus (batch_size={limit})")
    else:
        top = candidates
        logger.info(f"  Tous les {len(top)} candidats retenus (--all)")
    return top


def generate_proposals(client: VintedClient, batch_size: int | None = None) -> list[dict]:
    """Génère les propositions LLM pour le batch sélectionné."""
    items = select_items_to_optimize(client, batch_size=batch_size)
    if not items:
        logger.warning("Aucun item éligible")
        return []

    if not wol.ensure_llm_ready():
        raise RuntimeError("LM Studio injoignable (WoL + SSH start ont échoué)")

    proposals_list: list[dict] = []
    for i, candidate in enumerate(items, 1):
        item_id = candidate["vinted_item_id"]
        logger.info(f"[{i}/{len(items)}] Optimize item {item_id} — {candidate['title'][:60]!r}")

        # Fetch payload complet + photos
        try:
            item_full = client.get_item_for_edit(item_id)
            photos = client.get_item_photos(item_id)
        except VintedError as e:
            logger.warning(f"  Skip {item_id} : {e}")
            continue

        brand = (item_full.get("brand_dto") or {}).get("title") or item_full.get("brand")
        category = str(item_full.get("catalog_id") or "")
        color = item_full.get("color1")
        condition = item_full.get("status")
        size = None  # à enrichir via /attributes si besoin

        try:
            opt = llm.optimize_item(
                current_title=item_full["title"],
                current_description=item_full.get("description") or "",
                brand=brand,
                size=size,
                category=category,
                color=color,
                condition=condition,
            )
        except (ValueError, Exception) as e:
            logger.warning(f"  Skip {item_id} : LLM error : {e}")
            continue

        main_photo = next((p["url"] for p in photos if p.get("is_main")), photos[0]["url"] if photos else "")
        thumbs = [p["url"] for p in photos[:5]]

        price_value = item_full.get("price")
        if isinstance(price_value, dict):
            price_str = f"{price_value.get('amount')} {price_value.get('currency_code', 'EUR')}"
        else:
            price_str = f"{price_value} EUR" if price_value is not None else ""

        entry = proposals.build_entry(
            vinted_item_id=item_id,
            title_before=item_full["title"],
            title_after=opt["title"],
            description_before=item_full.get("description") or "",
            description_after=opt["description"],
            rationale=opt["rationale"],
            confidence=opt["confidence"],
            main_photo_url=main_photo,
            thumbnails=thumbs,
            category=category,
            brand=brand,
            price=price_str,
        )
        proposals_list.append(entry)
        logger.info(f"  ✓ confidence={opt['confidence']:.2f} | {opt['title'][:60]!r}")

    return proposals_list


def apply_proposals(client: VintedClient, path: Path | None = None) -> dict:
    """Applique les actions user — sur le fichier `path` ou TOUS les fichiers si None.

    Rate-limit : random.uniform(5, 20) sec entre chaque PUT pour ne pas déclencher
    DataDome (anti-bot Vinted). Si DataDome détecté (403 avec captcha-delivery),
    on arrête immédiatement pour préserver le cookie de session — le runner --apply
    est idempotent (skip applied_at) donc reprendra au prochain run.
    """
    counters = {"apply": 0, "edit": 0, "skip": 0, "pending": 0, "error": 0}
    datadome_blocked = False

    if path is not None:
        files_data = [(path, proposals.read(path))]
    else:
        files_data = proposals.read_all()
        logger.info(f"Apply sur {len(files_data)} fichier(s) proposals")

    n_processed = 0  # PUTs effectifs (pour skip le sleep avant le 1er)

    for current_path, data in files_data:
        if datadome_blocked:
            break
        modified = False
        for entry in data:
            if datadome_blocked:
                break
            item_id = entry["vinted_item_id"]
            action = (entry.get("user_action") or "").lower()

            # Skip si déjà appliqué (idempotent : retry après erreur partielle OK)
            if entry.get("applied_at"):
                continue

            if action in ("", "skip", "none"):
                counters["skip" if action == "skip" else "pending"] += 1
                continue

            if action == "apply":
                new_title = entry["title_after"]
                new_description = entry["description_after"]
            elif action == "edit":
                new_title = entry.get("edited_title") or entry["title_after"]
                new_description = entry.get("edited_description") or entry["description_after"]
            else:
                logger.warning(f"  Action inconnue {action!r} sur item {item_id}, skip")
                counters["error"] += 1
                continue

            # Rate-limit anti-DataDome : sleep aléatoire entre chaque PUT
            if n_processed > 0:
                sleep_sec = random.uniform(5, 20)
                logger.debug(f"  Sleep {sleep_sec:.1f}s avant prochain PUT")
                time.sleep(sleep_sec)

            logger.info(f"Apply {item_id} : {new_title[:60]!r}")
            try:
                item_full = client.get_item_for_edit(item_id)
                item_full["title"] = new_title
                item_full["description"] = new_description
                upload_session = str(uuid.uuid4())
                client.update_item(item_id, item_full, upload_session_id=upload_session)
                entry["applied_at"] = datetime.now().isoformat(timespec="seconds")
                modified = True
                n_processed += 1
                with db.connect() as conn:
                    conn.execute(
                        "UPDATE articles SET last_optimized_at = ? WHERE vinted_item_id = ?",
                        (datetime.now().isoformat(timespec="seconds"), item_id),
                    )
                counters[action] += 1
                logger.success(f"  ✓ {item_id} optimisé")
            except VintedError as e:
                err_str = str(e)
                # Détection DataDome — plusieurs signaux possibles :
                # 1. 403 avec URL captcha-delivery (PUT bloqué)
                # 2. "Aucun X-CSRF-Token trouvé" (home page = captcha, regex CSRF échoue)
                # 3. "datadome" dans le message
                is_datadome = (
                    "captcha-delivery" in err_str
                    or "datadome" in err_str.lower()
                    or "Aucun X-CSRF-Token" in err_str
                )
                if is_datadome:
                    logger.error(f"  ❌ {item_id} : DataDome détecté → arrêt immédiat pour préserver le cookie")
                    logger.warning(
                        f"  → Cookies probablement flag. Soit attends 4-12h, soit réexporte "
                        f"les cookies du compte concerné depuis le navigateur. Le --apply est idempotent."
                    )
                    counters["error"] += 1
                    datadome_blocked = True
                    break
                logger.error(f"  ❌ {item_id} : {e}")
                counters["error"] += 1

        if modified:
            current_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))

    return counters


@click.command()
@click.option("--generate", is_flag=True, help="Génère propositions LLM (WoL + shutdown PC)")
@click.option("--apply", "apply_flag", is_flag=True, help="Applique les propositions validées")
@click.option("--no-shutdown", is_flag=True, help="Ne shutdown pas le PC après --generate (debug)")
@click.option("--all", "all_items", is_flag=True, help="Génère pour TOUS les items éligibles (ignore batch size)")
@click.option("--batch-size", type=int, default=None, help="Override OPTIMIZER_BATCH_SIZE")
@click.option("--file", "file_path", type=click.Path(), help="Force le path du proposals.json (apply)")
def main(
    generate: bool,
    apply_flag: bool,
    no_shutdown: bool,
    all_items: bool,
    batch_size: int | None,
    file_path: str | None,
) -> None:
    db.init_db()

    if not settings.optimizer_enabled:
        logger.warning(f"OPTIMIZER_ENABLED=false dans .env → skip optimizer")
        sys.exit(0)

    if not (generate or apply_flag):
        click.echo("Use --generate ou --apply", err=True)
        sys.exit(2)

    with VintedClient() as client:
        if generate:
            logger.info("═══ MODE --generate ═══")
            effective_batch = -1 if all_items else batch_size
            try:
                props = generate_proposals(client, batch_size=effective_batch)
            finally:
                if not no_shutdown:
                    logger.info("Shutdown PC…")
                    wol.shutdown_pc()
            if props:
                # Append au fichier du jour (skip duplicates) — permet plusieurs runs/jour
                target = proposals.append_to_today(props)
                host_hint = str(target).replace(
                    "/app/data/", "/volume1/Aurelien/Scripts/vinted-bot/data-<compte>/"
                )
                logger.success(f"✅ {len(props)} propositions générées")
                logger.success(f"   📄 Container : {target}")
                logger.success(f"   📂 NAS host  : {host_hint}")
            else:
                logger.warning("Aucune proposition générée")

        if apply_flag:
            logger.info("═══ MODE --apply ═══")
            path = Path(file_path) if file_path else None  # None = tous les fichiers
            counters = apply_proposals(client, path)
            logger.success(
                f"✅ apply={counters['apply']} edit={counters['edit']} "
                f"skip={counters['skip']} pending={counters['pending']} error={counters['error']}"
            )


if __name__ == "__main__":
    main()
