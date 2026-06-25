"""FastAPI WebUI pour valider les propositions LLM des 2 comptes.

Routes :
  GET  /                                            → dashboard
  GET  /proposals/{account}                         → liste des cards
  POST /proposals/{account}/{item_id}/apply         → action apply
  POST /proposals/{account}/{item_id}/skip          → action skip
  GET  /proposals/{account}/{item_id}/edit-form     → swap card en mode édition
  POST /proposals/{account}/{item_id}/save-edit     → save edit + retour card
  GET  /proposals/{account}/{item_id}/view          → retour mode view (cancel)

Accessible via http://nas.local:8089/ (port host).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

# ─────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────

ACCOUNTS = {
    "aurelien": Path("/app/data-aurelien/proposals"),
    "amandine": Path("/app/data-amandine/proposals"),
}

TEMPLATES_DIR = Path(__file__).parent / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

app = FastAPI(title="vinted-bot WebUI", version="0.1.0")


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def _proposals_dir(account: str) -> Path:
    if account not in ACCOUNTS:
        raise HTTPException(404, f"Compte inconnu : {account}")
    return ACCOUNTS[account]


def _all_files(account: str) -> list[Path]:
    """Tous les fichiers proposals-*.json triés par date ascendante."""
    d = _proposals_dir(account)
    if not d.exists():
        return []
    return sorted(d.glob("proposals-*.json"))


def _read(account: str) -> list[dict]:
    """Lit ET aggrège tous les fichiers proposals-*.json du compte."""
    items: list[dict] = []
    for f in _all_files(account):
        try:
            items.extend(json.loads(f.read_text()))
        except json.JSONDecodeError:
            continue
    return items


def _find_and_update(account: str, item_id: int, mutator) -> dict:
    """Cherche l'item dans n'importe quel fichier du compte, applique mutator, sauve.

    Retourne l'entry modifiée. Lève 404 si introuvable.
    """
    for f in _all_files(account):
        data = json.loads(f.read_text())
        for entry in data:
            if entry["vinted_item_id"] == item_id:
                mutator(entry)
                f.write_text(json.dumps(data, indent=2, ensure_ascii=False))
                return entry
    raise HTTPException(404, f"Item {item_id} introuvable pour {account}")


def _confidence_badge(conf: float) -> str:
    if conf >= 0.85:
        return "high"
    if conf >= 0.6:
        return "mid"
    return "low"


# ─────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    accounts_info: list[dict[str, Any]] = []
    for name in ACCOUNTS:
        data = _read(name)
        accounts_info.append({
            "name": name,
            "total": len(data),
            # En attente de décision utilisateur
            "pending": sum(1 for e in data if not e.get("user_action")),
            # Validés par l'user mais pas encore poussés sur Vinted (apply/edit sans applied_at)
            "validated": sum(1 for e in data
                             if e.get("user_action") in ("apply", "edit") and not e.get("applied_at")),
            # Déjà poussés sur Vinted (applied_at set)
            "done": sum(1 for e in data if e.get("applied_at")),
            # Skip par user
            "skipped": sum(1 for e in data if e.get("user_action") == "skip"),
        })
    return templates.TemplateResponse(
        request, "dashboard.html", {"accounts": accounts_info},
    )


PER_PAGE = 10


def _sort_key(e: dict) -> tuple:
    """Ordre : pending → validés en attente → done → skipped, par confidence décroissante."""
    action = e.get("user_action") or ""
    applied = e.get("applied_at") is not None
    if applied:
        bucket = 2  # Déjà appliqué — milieu (visible mais après pending et validated)
    elif action == "skip":
        bucket = 3
    elif action in ("apply", "edit"):
        bucket = 1  # Validé mais pas encore appliqué
    else:
        bucket = 0  # Pending — en premier
    return (bucket, -float(e.get("confidence", 0)))


@app.get("/proposals/{account}", response_class=HTMLResponse)
async def list_proposals(account: str, request: Request, page: int = 1):
    data = _read(account)
    data.sort(key=_sort_key)

    total = len(data)
    total_pages = max(1, (total + PER_PAGE - 1) // PER_PAGE)
    page = max(1, min(page, total_pages))
    start = (page - 1) * PER_PAGE
    end = start + PER_PAGE
    page_data = data[start:end]

    return templates.TemplateResponse(
        request,
        "proposals.html",
        {
            "account": account,
            "proposals": page_data,
            "badge_for": _confidence_badge,
            "page": page,
            "total_pages": total_pages,
            "total": total,
            "page_start": start + 1,
            "page_end": min(end, total),
        },
    )


@app.post("/proposals/{account}/{item_id}/apply", response_class=HTMLResponse)
async def action_apply(account: str, item_id: int, request: Request):
    def _set(e: dict) -> None:
        e["user_action"] = "apply"
    entry = _find_and_update(account, item_id, _set)
    return templates.TemplateResponse(
        request, "_card.html",
        {"account": account, "p": entry, "badge_for": _confidence_badge},
    )


@app.post("/proposals/{account}/{item_id}/skip", response_class=HTMLResponse)
async def action_skip(account: str, item_id: int, request: Request):
    def _set(e: dict) -> None:
        e["user_action"] = "skip"
    entry = _find_and_update(account, item_id, _set)
    return templates.TemplateResponse(
        request, "_card.html",
        {"account": account, "p": entry, "badge_for": _confidence_badge},
    )


@app.get("/proposals/{account}/{item_id}/edit-form", response_class=HTMLResponse)
async def edit_form(account: str, item_id: int, request: Request):
    # Read-only : on cherche juste l'entry, on n'écrit pas
    entry = _find_and_update(account, item_id, lambda e: None)
    return templates.TemplateResponse(
        request, "_card_edit.html",
        {"account": account, "p": entry},
    )


@app.post("/proposals/{account}/{item_id}/save-edit", response_class=HTMLResponse)
async def save_edit(
    account: str,
    item_id: int,
    request: Request,
    title: str = Form(...),
    description: str = Form(...),
):
    def _set(e: dict) -> None:
        e["user_action"] = "edit"
        e["edited_title"] = title
        e["edited_description"] = description
    entry = _find_and_update(account, item_id, _set)
    return templates.TemplateResponse(
        request, "_card.html",
        {"account": account, "p": entry, "badge_for": _confidence_badge},
    )


@app.get("/proposals/{account}/{item_id}/view", response_class=HTMLResponse)
async def back_to_view(account: str, item_id: int, request: Request):
    entry = _find_and_update(account, item_id, lambda e: None)
    return templates.TemplateResponse(
        request, "_card.html",
        {"account": account, "p": entry, "badge_for": _confidence_badge},
    )


@app.post("/proposals/{account}/{item_id}/reset", response_class=HTMLResponse)
async def reset_action(account: str, item_id: int, request: Request):
    """Annule l'action utilisateur — utile si on a cliqué par erreur."""
    def _set(e: dict) -> None:
        e["user_action"] = None
        e["edited_title"] = None
        e["edited_description"] = None
    entry = _find_and_update(account, item_id, _set)
    return templates.TemplateResponse(
        request, "_card.html",
        {"account": account, "p": entry, "badge_for": _confidence_badge},
    )


# ─────────────────────────────────────────────────────────────
# Entrypoint
# ─────────────────────────────────────────────────────────────

def main() -> None:
    uvicorn.run(
        "vinted_bot.webui.server:app",
        host="0.0.0.0",
        port=8089,
        log_level="info",
    )


if __name__ == "__main__":
    main()
