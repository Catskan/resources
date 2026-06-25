#!/usr/bin/env python3
"""Test le pipeline de transformation de photos.

Usage:
    python3 scripts/test-transformer.py <input_image>

Génère 3 versions transformées dans /tmp/vinted-bot-test/ et imprime
les métriques de différence perceptuelle pour chaque version.

Pré-requis : `pip install pillow numpy loguru pydantic-settings` (ou utiliser le venv).
"""

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from vinted_bot.photos.transformer import (  # noqa: E402
    measure_perceptual_diff,
    transform,
)


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/test-transformer.py <input_image>")
        return 1

    input_path = Path(sys.argv[1])
    if not input_path.exists():
        print(f"❌ Fichier introuvable: {input_path}")
        return 1

    original = input_path.read_bytes()
    orig_md5 = hashlib.md5(original).hexdigest()
    print(f"Source: {input_path}")
    print(f"  Taille : {len(original):,} bytes")
    print(f"  MD5    : {orig_md5}")
    print()

    out_dir = Path("/tmp/vinted-bot-test")
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Génération de 3 versions transformées :\n")
    for i in range(1, 4):
        transformed = transform(original)
        md5 = hashlib.md5(transformed).hexdigest()
        metrics = measure_perceptual_diff(original, transformed)
        out_path = out_dir / f"transformed-{i}.jpg"
        out_path.write_bytes(transformed)

        size_pct = (len(transformed) - len(original)) / len(original) * 100
        print(f"  ─── Version #{i} ─── ({out_path})")
        print(f"    Taille     : {len(transformed):,} bytes  ({size_pct:+.1f}%)")
        print(f"    MD5        : {md5}  {'✅ DIFFÉRENT' if md5 != orig_md5 else '⚠️ IDENTIQUE'}")
        print(f"    dHash dist : {metrics['hamming_distance']}/64  "
              f"({'dHash voit différent' if metrics['hamming_distance'] >= 5 else 'dHash voit similaire'})")
        print()

    print("─" * 70)
    print("Ce qui compte pour Vinted :")
    print("  ✅ MD5 différent  → bypass de la dedup byte-level")
    print("  ℹ️  dHash souvent proche  → c'est par DESIGN : dHash est robuste aux petites")
    print("     modifs (rotation, crop, noise) pour détecter des vrais duplicats. Donc")
    print("     1-3/64 est attendu et acceptable. Vinted ne semble pas faire de dédup")
    print("     pHash agressif sur les republications de ses propres users.")
    print()
    print(f"Ouvre {out_dir}/ et compare visuellement avec l'original.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
