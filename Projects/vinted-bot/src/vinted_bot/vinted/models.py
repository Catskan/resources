"""Pydantic models pour les payloads Vinted API.

Schéma minimal qu'on enrichira en Phase 2 après inspection runtime.
"""

from pydantic import BaseModel


class VintedPhoto(BaseModel):
    id: int
    url: str
    full_size_url: str | None = None


class VintedItem(BaseModel):
    id: int
    title: str
    description: str = ""
    price: float
    currency: str = "EUR"
    photos: list[VintedPhoto] = []
    brand_id: int | None = None
    size_id: int | None = None
    category_id: int
    status_id: int | None = None
    is_visible: bool = True
