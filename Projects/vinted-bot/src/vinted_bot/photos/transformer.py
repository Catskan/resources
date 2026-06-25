"""Pipeline de transformation de photos pour casser le perceptual hashing.

Chaque transformation modifie l'image juste assez pour que :
  - Le pHash / dHash perceptual change (distance Hamming > 10 sur hash 64-bit)
  - Le rendu visuel reste indiscernable pour l'œil humain

Pipeline (toutes les étapes avec params random à chaque appel) :
  1. Re-decode depuis bytes (strip EXIF + ICC profile)
  2. Crop léger (1..PHOTO_CROP_PX_MAX px par côté)
  3. Rotation infime (±PHOTO_ROTATION_MAX_DEG)
  4. Resize ±2-3 %
  5. Brightness + contrast ±PHOTO_BRIGHTNESS_PCT_MAX %
  6. Bruit gaussien (sigma = PHOTO_NOISE_SIGMA)
  7. Re-encode JPEG qualité random ∈ [PHOTO_JPEG_QUALITY_MIN, PHOTO_JPEG_QUALITY_MAX]
"""

from __future__ import annotations

import io
import random
from typing import Any

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

from ..config import settings


def _strip_metadata(img: Image.Image) -> Image.Image:
    """Re-crée l'image sans EXIF / ICC / aucune metadata."""
    data = list(img.getdata())
    clean = Image.new(img.mode, img.size)
    clean.putdata(data)
    return clean


def _random_crop(img: Image.Image, max_px: int) -> Image.Image:
    if max_px <= 0:
        return img
    w, h = img.size
    left = random.randint(0, max_px)
    top = random.randint(0, max_px)
    right = w - random.randint(0, max_px)
    bottom = h - random.randint(0, max_px)
    return img.crop((left, top, right, bottom))


def _random_rotate(img: Image.Image, max_deg: float) -> Image.Image:
    if max_deg <= 0:
        return img
    angle = random.uniform(-max_deg, max_deg)
    # expand=False : on accepte des coins coupés très légers
    return img.rotate(angle, resample=Image.BICUBIC, expand=False, fillcolor=None)


def _random_resize(img: Image.Image, pct_range: tuple[float, float] = (-3, 3)) -> Image.Image:
    pct = random.uniform(*pct_range) / 100.0
    w, h = img.size
    new_w = max(1, int(round(w * (1 + pct))))
    new_h = max(1, int(round(h * (1 + pct))))
    return img.resize((new_w, new_h), resample=Image.LANCZOS)


def _random_brightness_contrast(img: Image.Image, max_pct: float) -> Image.Image:
    if max_pct <= 0:
        return img
    b = 1.0 + random.uniform(-max_pct, max_pct) / 100.0
    c = 1.0 + random.uniform(-max_pct, max_pct) / 100.0
    img = ImageEnhance.Brightness(img).enhance(b)
    img = ImageEnhance.Contrast(img).enhance(c)
    return img


def _add_gaussian_noise(img: Image.Image, sigma: float) -> Image.Image:
    if sigma <= 0:
        return img
    arr = np.asarray(img, dtype=np.float32)
    noise = np.random.normal(0.0, sigma, arr.shape)
    arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode=img.mode)


def _slight_blur(img: Image.Image, radius_range: tuple[float, float] = (0.4, 0.8)) -> Image.Image:
    """Très léger flou gaussien — change significativement le dHash sans être visible."""
    radius = random.uniform(*radius_range)
    return img.filter(ImageFilter.GaussianBlur(radius=radius))


def transform(image_bytes: bytes) -> bytes:
    """Applique la pipeline complète. Renvoie des bytes JPEG.

    Args:
        image_bytes: bytes de l'image source (n'importe quel format Pillow).

    Returns:
        bytes JPEG transformés.
    """
    img = Image.open(io.BytesIO(image_bytes))
    img.load()
    if img.mode != "RGB":
        img = img.convert("RGB")

    img = _strip_metadata(img)
    img = _random_crop(img, settings.photo_crop_px_max)
    img = _random_rotate(img, settings.photo_rotation_max_deg)
    img = _random_resize(img)
    img = _random_brightness_contrast(img, settings.photo_brightness_pct_max)
    img = _slight_blur(img)
    img = _add_gaussian_noise(img, settings.photo_noise_sigma)

    quality = random.randint(
        settings.photo_jpeg_quality_min, settings.photo_jpeg_quality_max
    )
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality, optimize=True, subsampling=2)
    return buf.getvalue()


# ─────────────────────────────────────────────────────────────────
# Vérification : calcul d'un dHash simple pour mesurer la diff
# ─────────────────────────────────────────────────────────────────


def dhash(image_bytes: bytes, hash_size: int = 8) -> int:
    """Calcule un dHash (difference hash) en bits.

    Hash 64-bit (hash_size=8) standard pour la détection de duplicats.
    Distance Hamming > ~10 sur 64 bits = images considérées "différentes".
    """
    img = Image.open(io.BytesIO(image_bytes)).convert("L").resize(
        (hash_size + 1, hash_size), Image.LANCZOS
    )
    arr = np.asarray(img)
    diff = arr[:, 1:] > arr[:, :-1]
    bits = 0
    for b in diff.flatten():
        bits = (bits << 1) | int(b)
    return bits


def hamming_distance(a: int, b: int) -> int:
    """Distance Hamming entre deux dHash."""
    return bin(a ^ b).count("1")


def measure_perceptual_diff(original: bytes, transformed: bytes) -> dict[str, Any]:
    """Renvoie des métriques de 'à quel point l'image a changé'."""
    h_orig = dhash(original)
    h_new = dhash(transformed)
    return {
        "dhash_original": f"{h_orig:016x}",
        "dhash_transformed": f"{h_new:016x}",
        "hamming_distance": hamming_distance(h_orig, h_new),
        "considered_different": hamming_distance(h_orig, h_new) >= 5,
    }
