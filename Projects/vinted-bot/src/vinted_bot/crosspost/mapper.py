"""Mapping catégories Vinted ↔ Leboncoin.

À constituer manuellement en Phase 4 (les IDs Leboncoin sont stables,
~30 catégories principales vs ~10 grandes catégories vêtements Vinted).
"""

VINTED_TO_LBC: dict[int, str] = {
    # ex. 5 ("Femmes - Hauts") → "vetements_chaussures_accessoires_femme"
    # TODO Phase 4
}
