#!/usr/bin/env python3
"""Apply KeePassXC Auto-Type window associations to launcher entries.

Walks every entry in the central kdbx (NAS-hosted, shared with the Windows
Aurel-Gaming machine via SMB), matches them against a curated launcher list
by title (case-insensitive contains), and ensures each matched entry has the
right Window Association so KeePassXC's global Auto-Type shortcut
(Ctrl+Shift+V — see roles/windows_gaming/templates/keepassxc.ini.j2) types
the credentials into the focused launcher login field.

Idempotent: re-running adds nothing if associations are already present.

Reads master pw the same way scripts/inspect_keepass.py does — via
KEEPASS_PSW env var (set by scripts/run.sh) or interactive prompt.

Usage:
  ./scripts/keepass_apply_autotype.py            # dry-run (default)
  ./scripts/keepass_apply_autotype.py --apply    # write changes
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

from lxml import etree
from pykeepass import PyKeePass
from pykeepass.exceptions import CredentialsError

# Per-launcher mapping: which kdbx entries to match (by title contains,
# case-insensitive), which window titles to associate, and the keystroke
# sequence. Sequences with {DELAY 3000}{TOTP}{ENTER} type the TOTP code
# after a 3-second pause — works if the 2FA prompt grabs focus
# automatically after submitting username+password.
LAUNCHERS = [
    {
        "name": "Steam",
        "candidates": ["steam", "valve.steam", "valve - steam"],
        "associations": [
            ("Steam", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "Epic Games Launcher",
        "candidates": ["epicgames.epicgameslauncher", "epic games", "epic"],
        "associations": [
            ("Epic Games Launcher", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "Ubisoft Connect",
        "candidates": ["ubisoft.connect", "ubisoft connect", "ubisoft"],
        "associations": [
            ("Ubisoft Connect", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "GOG Galaxy",
        "candidates": ["gog.galaxy", "gog galaxy", "gog"],
        "associations": [
            ("GOG GALAXY", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "EA Desktop",
        "candidates": ["electronicarts.eadesktop", "ea desktop", "ea app", "electronic arts"],
        "associations": [
            ("EA app", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
            ("EA Desktop", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "Rockstar Games Launcher",
        "candidates": ["rockstargames.launcher", "rockstar games", "rockstar"],
        "associations": [
            ("Rockstar Games Launcher", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
    {
        "name": "Microsoft account / Store",
        "candidates": ["microsoft account", "microsoft store", "ms account", "microsoft"],
        "associations": [
            ("Microsoft account", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
            ("Sign in", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
            ("Microsoft Store", "{USERNAME}{TAB}{PASSWORD}{ENTER}{DELAY 3000}{TOTP}{ENTER}"),
        ],
    },
]


def open_kdbx() -> PyKeePass:
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
        sys.exit(2)


def find_entry(kp: PyKeePass, candidates: list[str]):
    """Return first entry whose title contains any candidate (case-insensitive)."""
    candidates_lower = [c.lower() for c in candidates]
    for entry in kp.entries:
        title = (entry.title or "").lower()
        if any(c in title for c in candidates_lower):
            return entry
    return None


def existing_associations(entry) -> list[tuple[str, str]]:
    autotype_el = entry._element.find("AutoType")
    if autotype_el is None:
        return []
    return [
        (a.findtext("Window") or "", a.findtext("KeystrokeSequence") or "")
        for a in autotype_el.findall("Association")
    ]


def add_association(entry, window: str, sequence: str) -> bool:
    """Ensure (window, sequence) is on the entry. Returns True if newly added."""
    existing = existing_associations(entry)
    if (window, sequence) in existing:
        return False
    if any(w == window for w, _ in existing):
        # Window already mapped with a different sequence — don't clobber a
        # user-customised one.
        return False

    autotype_el = entry._element.find("AutoType")
    if autotype_el is None:
        autotype_el = etree.SubElement(entry._element, "AutoType")
        etree.SubElement(autotype_el, "Enabled").text = "True"
        etree.SubElement(autotype_el, "DataTransferObfuscation").text = "0"

    enabled_el = autotype_el.find("Enabled")
    if enabled_el is None:
        etree.SubElement(autotype_el, "Enabled").text = "True"
    else:
        enabled_el.text = "True"

    assoc_el = etree.SubElement(autotype_el, "Association")
    etree.SubElement(assoc_el, "Window").text = window
    etree.SubElement(assoc_el, "KeystrokeSequence").text = sequence
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write changes to the kdbx (default: preview / dry-run)",
    )
    args = parser.parse_args()

    kp = open_kdbx()
    print(f"Opened {kp.filename}")
    print()

    planned_adds: list[tuple] = []
    for launcher in LAUNCHERS:
        entry = find_entry(kp, launcher["candidates"])
        if entry is None:
            print(
                f"  [no-match    ] {launcher['name']:25s}  candidates={launcher['candidates']}"
            )
            continue
        existing = existing_associations(entry)
        for window, seq in launcher["associations"]:
            if (window, seq) in existing:
                action = "already-present"
            elif any(w == window for w, _ in existing):
                action = "skip-window-taken"
            else:
                action = "WOULD-ADD"
                planned_adds.append((entry, window, seq))
            print(
                f"  [{action:16s}] {launcher['name']:25s}  entry='{entry.title}'  window='{window}'"
            )

    print()
    print(f"Total adds planned: {len(planned_adds)}")

    if not args.apply:
        print("(dry-run; re-run with --apply to write)")
        return 0

    if not planned_adds:
        print("Nothing to do.")
        return 0

    for entry, window, seq in planned_adds:
        add_association(entry, window, seq)

    kp.save()
    print(f"Saved {kp.filename}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
