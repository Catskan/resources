#!/usr/bin/env python3
"""Diagnostic KeePass — vérifie que les chemins attendus par test_keepass.yml
existent réellement dans la DB et dumpe l'arborescence complète.

Utilise les mêmes variables d'environnement que scripts/run.sh :
  KEEPASS_LOCATION  (défaut : ~/Vault/Aurel-vault.kdbx)
  KEEPASS_PSW       (prompt interactif si vide)

Usage :
  ./scripts/inspect_keepass.py            # check + dump complet
  ./scripts/inspect_keepass.py --check    # uniquement la vérif des paths
  ./scripts/inspect_keepass.py --tree     # uniquement l'arbo
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

try:
    import yaml
    from pykeepass import PyKeePass
    from pykeepass.exceptions import CredentialsError
except ImportError as exc:
    print(f"Dépendance manquante : {exc.name}", file=sys.stderr)
    print("Installe avec : pip install pykeepass pyyaml", file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
PLAYBOOK = REPO_ROOT / "playbooks" / "test_keepass.yml"


def load_expected_paths() -> list[dict]:
    """Lit test_keepass.yml et retourne les entrées keepass_entries."""
    with PLAYBOOK.open() as f:
        doc = yaml.safe_load(f)
    return doc[0]["vars"]["keepass_entries"]


def open_kdbx() -> PyKeePass:
    # Défaut aligné sur run.sh et keepass_apply_autotype.py : le partage SMB
    # `home` du NAS Synology monté sous /Volumes/home. Override via KEEPASS_LOCATION.
    location = os.environ.get(
        "KEEPASS_LOCATION", "/Volumes/home/Drive/Vault/Aurel-vault.kdbx"
    )
    if not Path(location).is_file():
        print(f"KeePass DB introuvable : {location}", file=sys.stderr)
        sys.exit(1)

    password = os.environ.get("KEEPASS_PSW") or getpass.getpass(
        f"KeePass master password ({location}) : "
    )

    try:
        return PyKeePass(location, password=password)
    except CredentialsError:
        print("Master password incorrect.", file=sys.stderr)
        sys.exit(1)


def check_paths(kp: PyKeePass, expected: list[dict]) -> int:
    """Vérifie chaque path attendu. Retourne le nombre de paths manquants."""
    print("\n== Vérification des chemins attendus ==\n")
    print(f"{'OK':<4} {'PATH':<48} {'FIELD':<10} LABEL")
    print("-" * 100)

    missing = 0
    for entry in expected:
        path = entry["path"]
        field = entry["field"]
        label = entry["label"]
        parts = path.split("/")

        found = kp.find_entries(path=parts, first=True)
        if found is None:
            mark = "❌"
            missing += 1
        else:
            value = getattr(found, field, None)
            if not value:
                mark = "⚠️ "
                missing += 1
            else:
                mark = "✅"
        print(f"{mark:<4} {path:<48} {field:<10} {label}")

    print()
    print(f"Total : {len(expected)} entrées vérifiées, {missing} en échec.")
    return missing


def _path_str(node) -> str:
    """Retourne le chemin pykeepass au format slash-séparé, sans la racine.

    pykeepass.Group.path et pykeepass.Entry.path retournent une liste de
    segments. Pour la racine ("/" ou []), on renvoie "".
    """
    parts = getattr(node, "path", None) or []
    # Filtre les None éventuels et les segments vides
    return "/".join(p for p in parts if p)


def dump_tree(kp: PyKeePass) -> None:
    """Affiche tous les groupes et entrées avec le chemin complet utilisable
    tel quel dans lookup('viczem.keepass.keepass', '<chemin>', ...)."""
    print("\n== Arborescence complète de la DB ==\n")

    for group in sorted(kp.groups, key=_path_str):
        gpath = _path_str(group)
        if not gpath:
            continue
        print(f"[GROUP] {gpath}/")

    print()
    for entry in sorted(kp.entries, key=_path_str):
        epath = _path_str(entry)
        has_user = bool(entry.username)
        has_pw = bool(entry.password)
        flags = ("u" if has_user else "-") + ("p" if has_pw else "-")
        print(f"[ENTRY {flags}] {epath}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="Vérifie uniquement les paths attendus."
    )
    parser.add_argument(
        "--tree", action="store_true", help="Dumpe uniquement l'arborescence."
    )
    args = parser.parse_args()

    do_check = args.check or not args.tree
    do_tree = args.tree or not args.check

    kp = open_kdbx()
    print(f"DB ouverte : {kp.filename}")

    missing = 0
    if do_check:
        expected = load_expected_paths()
        missing = check_paths(kp, expected)

    if do_tree:
        dump_tree(kp)

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
