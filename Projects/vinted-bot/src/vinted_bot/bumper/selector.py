"""Sélection du prochain article à republier.

Workflow :
  1. sync_active_items() : refresh la DB depuis l'API Vinted (1× par jour max)
  2. pick_eligible() : choisit aléatoirement un article éligible

Un article est éligible si :
  - is_active = 1 dans la DB
  - last_bumped_at NULL ou < (now - BUMP_MIN_DAYS_BETWEEN_REBUMP)
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta

from loguru import logger

from .. import db
from ..config import settings
from ..vinted.client import VintedClient


def sync_active_items(client: VintedClient, force: bool = False) -> dict[str, int]:
    """Sync les items actifs depuis Vinted vers la DB locale.

    Skip si dernier sync < 24h (sauf force=True).
    """
    KV_KEY = "last_articles_sync"

    with db.connect() as conn:
        last = db.kv_get(conn, KV_KEY)
        if last and not force:
            last_dt = datetime.fromisoformat(last)
            if (datetime.now() - last_dt) < timedelta(hours=24):
                logger.debug(f"sync skip (dernier sync à {last})")
                return {"added": 0, "updated": 0, "deactivated": 0, "skipped": True}

    logger.info("→ Sync articles depuis Vinted...")
    seen_ids: set[int] = set()
    added = 0

    with db.connect() as conn:
        existing_before = {
            row["vinted_item_id"]
            for row in conn.execute(
                "SELECT vinted_item_id FROM articles WHERE is_active = 1"
            )
        }

        for item in client.iter_all_active_items(per_page=50):
            vid = item["id"]
            seen_ids.add(vid)
            price = item.get("price", {})
            price_cents = None
            if price.get("amount"):
                try:
                    price_cents = int(float(price["amount"]) * 100)
                except (TypeError, ValueError):
                    pass

            db.upsert_article(
                conn,
                vinted_item_id=vid,
                title=item.get("title", "(no title)"),
                price_cents=price_cents,
                is_active=True,
            )
            if vid not in existing_before:
                added += 1

        disappeared = list(existing_before - seen_ids)
        db.mark_inactive(conn, disappeared)

        db.kv_set(conn, KV_KEY, datetime.now().isoformat(timespec="seconds"))

    logger.info(
        f"  ✓ {len(seen_ids)} items actifs vus, {added} nouveaux, "
        f"{len(disappeared)} disparus (marqués inactifs)"
    )
    return {
        "added": added,
        "updated": len(seen_ids) - added,
        "deactivated": len(disappeared),
        "skipped": False,
    }


def pick_eligible() -> dict | None:
    """Sélectionne un article éligible (random uniforme ou pondéré saison).

    Si BUMP_PREFER_SEASON='auto' (ou nom de saison explicite), applique un
    poids à chaque candidat basé sur les mots-clés saisonniers du titre :
      - matche strong de la saison cible → ×3
      - matche weak                       → ×1.5
      - neutre                            → ×1
      - matche weak de la saison opposée  → ×0.6
      - matche strong de la saison opposée → ×0.15

    Retourne {vinted_item_id, title, last_bumped_at}.
    """
    from .seasonal import resolve_season_setting, score_for_season

    with db.connect() as conn:
        rows = db.list_eligible_articles(
            conn, min_days_since_bump=settings.bump_min_days_between_rebump
        )
    if not rows:
        logger.warning("Aucun article éligible (tous bumped récemment ou aucun actif)")
        return None

    season = resolve_season_setting(settings.bump_prefer_season)
    if season is None:
        chosen = random.choice(rows)
        logger.debug(f"Sélection uniforme parmi {len(rows)} éligibles")
    else:
        weights = [score_for_season(row["title"], season) for row in rows]
        # random.choices accepte des poids positifs (somme>0 garantie par notre score min=0.15)
        chosen = random.choices(rows, weights=weights, k=1)[0]
        chosen_weight = score_for_season(chosen["title"], season)
        logger.info(
            f"Sélection pondérée saison '{season}' parmi {len(rows)} éligibles "
            f"(poids choisi={chosen_weight:.2f})"
        )

    return {
        "vinted_item_id": chosen["vinted_item_id"],
        "title": chosen["title"],
        "last_bumped_at": chosen["last_bumped_at"],
    }
