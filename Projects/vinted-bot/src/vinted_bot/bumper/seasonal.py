"""Scoring saisonnier des articles pour la sélection pondérée.

Calcule un poids ∈ [0.1, 3.0] pour chaque article selon que son titre matche
des mots-clés saisonniers (été, hiver, mi-saison). En entrant l'hiver, on
augmente le score des manteaux et on pénalise les maillots, et inversement.

Articles "neutres" (pas de mot-clé saisonnier) gardent un poids 1.0, donc
restent dans le pool — c'est juste leur probabilité relative qui baisse vs
les items très-saisonniers.
"""

from __future__ import annotations

import unicodedata
from datetime import datetime
from typing import Literal

Season = Literal["summer", "winter", "spring", "autumn"]

# Mots-clés (en lowercase, sans accent — on normalise le titre avant comparaison)
STRONG_SEASONAL: dict[Season, list[str]] = {
    "summer": [
        "maillot", "bikini", "tongs", "sandales", "pareo", "robe d'ete",
        "short de bain", "ete", "plage", "soleil", "tropical", "hawaii",
    ],
    "winter": [
        "manteau", "doudoune", "polaire", "moufles", "bonnet", "echarpe",
        "fourrure", "hiver", "ski", "neige", "thermique", "anorak",
    ],
    "spring": [
        "printemps", "pastel", "fleuri",
    ],
    "autumn": [
        "automne", "trench", "carreaux",
    ],
}

WEAK_SEASONAL: dict[Season, list[str]] = {
    "summer": [
        "robe", "debardeur", "short", "jupe", "lin", "leger", "bretelles",
        "decollete", "fluide", "sans manches", "t-shirt", "tshirt", "tee-shirt",
        "polo", "manche courte", "manches courtes", "espadrille", "claquette",
    ],
    "winter": [
        "pull", "gants", "bottes", "laine", "epais", "chaud", "col roule",
        "cachemire", "velours", "chausson", "sweat", "hoodie", "sweat-shirt",
        "manche longue", "manches longues", "doublure",
    ],
    "spring": [
        "veste legere", "trench leger",
    ],
    "autumn": [
        "pull", "gilet", "cardigan", "bottines",
    ],
}

OPPOSITE: dict[Season, Season] = {
    "summer": "winter",
    "winter": "summer",
    "spring": "autumn",
    "autumn": "spring",
}


def normalize(text: str) -> str:
    """Lowercase + retire les accents pour matcher 'été' = 'ete'."""
    nfkd = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def current_season(now: datetime | None = None) -> Season:
    """Détermine la saison en cours (hémisphère nord)."""
    now = now or datetime.now()
    m = now.month
    if m in (6, 7, 8):
        return "summer"
    if m in (12, 1, 2):
        return "winter"
    if m in (3, 4, 5):
        return "spring"
    return "autumn"


def score_for_season(title: str, target_season: Season) -> float:
    """Renvoie un poids pour cet article selon la saison cible.

    Valeurs typiques :
      3.0  : matche strong de la saison cible (ex. "maillot" en été)
      1.5  : matche weak de la saison cible (ex. "robe" en été)
      1.0  : neutre, pas de mot-clé saisonnier
      0.6  : matche weak de la saison opposée (ex. "pull" en été)
      0.15 : matche strong de la saison opposée (ex. "doudoune" en été)
    """
    norm_title = normalize(title)
    opp = OPPOSITE[target_season]

    if any(kw in norm_title for kw in STRONG_SEASONAL.get(target_season, [])):
        return 3.0
    if any(kw in norm_title for kw in STRONG_SEASONAL.get(opp, [])):
        return 0.15
    if any(kw in norm_title for kw in WEAK_SEASONAL.get(target_season, [])):
        return 1.5
    if any(kw in norm_title for kw in WEAK_SEASONAL.get(opp, [])):
        return 0.6
    return 1.0


def resolve_season_setting(setting: str) -> Season | None:
    """Convertit la valeur d'env var BUMP_PREFER_SEASON en saison concrète.

    Valeurs supportées : 'auto' (saison du jour), 'summer', 'winter',
    'spring', 'autumn', 'off' (None = désactivé).
    """
    s = (setting or "off").strip().lower()
    if s in ("off", "", "none", "false", "0"):
        return None
    if s == "auto":
        return current_season()
    if s in ("summer", "winter", "spring", "autumn"):
        return s  # type: ignore[return-value]
    return None  # valeur inconnue → désactivé
