#!/usr/bin/env python3
"""Test end-to-end de la chaîne optimizer LLM : WoL + load + optimize + shutdown.

Pour 1 seul item au choix, ou demande à Mistral d'optimiser un titre dummy.

Usage:
    python3 scripts/test-optimizer-llm.py 5476110733   # un item existant
    python3 scripts/test-optimizer-llm.py              # test avec un titre dummy
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from loguru import logger  # noqa: E402

from vinted_bot.optimizer.llm import is_ready, optimize_item, wait_for_ready  # noqa: E402
from vinted_bot.optimizer.wol import boot_pc_and_wait_llm, shutdown_pc  # noqa: E402
from vinted_bot.vinted.client import VintedClient  # noqa: E402


def main() -> int:
    item_id_arg = int(sys.argv[1]) if len(sys.argv) > 1 else None

    if not is_ready():
        logger.info("LM Studio pas réveillé → WoL + attente")
        if not boot_pc_and_wait_llm():
            logger.error("Échec WoL/wait")
            return 1
    else:
        logger.info("LM Studio déjà prêt, pas de WoL nécessaire")

    if item_id_arg:
        # Optimise un VRAI item
        with VintedClient() as v:
            item_full = v.get_item_for_edit(item_id_arg)
        title = item_full.get("title", "")
        description = item_full.get("description", "")
        brand = item_full.get("brand_dto", {}).get("title") if item_full.get("brand_dto") else item_full.get("brand")
        size = None  # à enrichir si besoin
        category = str(item_full.get("catalog_id"))
        logger.info(f"Item {item_id_arg} : {title!r}")
    else:
        # Test avec dummy
        title = "Robe H&M"
        description = "Robe en coton, portée 2 fois, bon état."
        brand = "H&M"
        size = "S"
        category = "Robes"
        logger.info("Test dummy (pas d'item réel)")

    logger.info("→ Génération via Mistral…")
    result = optimize_item(
        current_title=title,
        current_description=description,
        brand=brand,
        size=size,
        category=category,
    )

    print()
    print("═" * 60)
    print(f"AVANT :  {title!r}")
    print(f"APRÈS :  {result['title']!r}")
    print()
    print(f"DESC AVANT  :  {description!r}")
    print(f"DESC APRÈS  :  {result['description']!r}")
    print()
    print(f"Rationale : {result['rationale']}")
    print(f"Confiance : {result['confidence']:.2f}")
    print("═" * 60)

    # Auto-shutdown du PC après le test
    if "--no-shutdown" not in sys.argv:
        logger.info("→ Shutdown du PC…")
        shutdown_pc()
    return 0


if __name__ == "__main__":
    sys.exit(main())
