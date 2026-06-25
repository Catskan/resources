"""Gestion du fichier proposals-YYYYMMDD.json (génération + lecture des actions user).

Format d'une entrée :
{
  "vinted_item_id": 12345,
  "title_before": "...",
  "title_after": "...",
  "description_before": "...",
  "description_after": "...",
  "rationale": "...",
  "confidence": 0.85,
  "main_photo_url": "https://...",
  "thumbnails": ["https://...", ...],
  "category": "Robes",
  "brand": "H&M",
  "price": "12 EUR",
  "user_action": null,            # null | "apply" | "skip" | "edit"
  "edited_title": null,           # si user_action == "edit"
  "edited_description": null,
  "generated_at": "2026-06-22T14:00:00",
  "applied_at": null              # set par --apply quand transmis à Vinted
}

L'utilisateur édite via la WebUI (ou à la main) le champ `user_action`.
Le runner --apply lit le fichier et applique les actions.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from loguru import logger

from ..config import settings


def proposals_dir() -> Path:
    """Dossier des fichiers proposals (sans création — déléguée à write())."""
    return settings.optimizer_proposals_path


def today_filename() -> Path:
    """Chemin du fichier proposals du jour."""
    return proposals_dir() / f"proposals-{datetime.now():%Y%m%d}.json"


def latest_filename() -> Path | None:
    """Chemin du fichier proposals le plus récent. None si aucun."""
    d = proposals_dir()
    if not d.exists():
        return None
    files = sorted(d.glob("proposals-*.json"), reverse=True)
    return files[0] if files else None


def all_files() -> list[Path]:
    """Liste tous les fichiers proposals-*.json (triés par date ascendante)."""
    d = proposals_dir()
    if not d.exists():
        return []
    return sorted(d.glob("proposals-*.json"))


def write(proposals: list[dict[str, Any]], path: Path | None = None) -> Path:
    """Sérialise une liste de propositions dans le fichier du jour."""
    target = path or today_filename()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(proposals, indent=2, ensure_ascii=False))
    logger.info(f"Proposals écrites dans {target} ({len(proposals)} entrées)")
    return target


def append_to_today(new_proposals: list[dict[str, Any]]) -> Path:
    """Ajoute des propositions au fichier du jour (skip duplicates par item_id).

    Si le fichier du jour existe, lit + merge + écrit. Sinon crée.
    """
    target = today_filename()
    existing = []
    if target.exists():
        existing = json.loads(target.read_text())
    existing_ids = {e["vinted_item_id"] for e in existing}
    new_only = [p for p in new_proposals if p["vinted_item_id"] not in existing_ids]
    combined = existing + new_only
    write(combined, target)
    return target


def read(path: Path | None = None) -> list[dict[str, Any]]:
    """Lit UN fichier proposals (par défaut, le plus récent)."""
    target = path or latest_filename()
    if not target or not target.exists():
        return []
    return json.loads(target.read_text())


def read_all() -> list[tuple[Path, list[dict[str, Any]]]]:
    """Lit TOUS les fichiers proposals-*.json. Renvoie [(path, data), ...]."""
    out: list[tuple[Path, list[dict[str, Any]]]] = []
    for f in all_files():
        try:
            out.append((f, json.loads(f.read_text())))
        except json.JSONDecodeError as e:
            logger.warning(f"Skip parse error sur {f.name} : {e}")
    return out


def all_proposed_item_ids() -> set[int]:
    """Retourne l'ensemble de tous les vinted_item_id présents dans n'importe quel
    fichier proposals — utilisé pour exclure les déjà-proposés lors du --generate.
    """
    ids: set[int] = set()
    for _, data in read_all():
        ids.update(e["vinted_item_id"] for e in data)
    return ids


def find_entry(item_id: int) -> tuple[Path, dict] | None:
    """Cherche un item à travers TOUS les fichiers. Retourne (path, entry) ou None."""
    for path, data in read_all():
        for entry in data:
            if entry["vinted_item_id"] == item_id:
                return path, entry
    return None


def update_entry(item_id: int, mutator) -> dict | None:
    """Cherche l'item dans tous les fichiers, applique mutator(entry), sauve.

    mutator : fonction qui modifie l'entry en place.
    """
    for path, data in read_all():
        for entry in data:
            if entry["vinted_item_id"] == item_id:
                mutator(entry)
                path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
                return entry
    return None


def mark_applied(path: Path, vinted_item_id: int, new_item_id: int | None = None) -> None:
    """Met à jour applied_at sur une entrée donnée (et new_item_id si republi)."""
    data = read(path)
    now = datetime.now().isoformat(timespec="seconds")
    for entry in data:
        if entry["vinted_item_id"] == vinted_item_id:
            entry["applied_at"] = now
            if new_item_id and new_item_id != vinted_item_id:
                entry["new_item_id"] = new_item_id
            break
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def build_entry(
    vinted_item_id: int,
    title_before: str,
    title_after: str,
    description_before: str,
    description_after: str,
    rationale: str,
    confidence: float,
    main_photo_url: str,
    thumbnails: list[str],
    category: str,
    brand: str | None,
    price: str | None,
) -> dict[str, Any]:
    """Construit une entrée prête à sérialiser."""
    return {
        "vinted_item_id": vinted_item_id,
        "title_before": title_before,
        "title_after": title_after,
        "description_before": description_before,
        "description_after": description_after,
        "rationale": rationale,
        "confidence": confidence,
        "main_photo_url": main_photo_url,
        "thumbnails": thumbnails,
        "category": category,
        "brand": brand or "",
        "price": price or "",
        "user_action": None,
        "edited_title": None,
        "edited_description": None,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "applied_at": None,
    }
