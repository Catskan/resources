#!/usr/bin/env bash
# Build a USB-ready autounattend tree for the bare-metal Aurel-Gaming Win11
# install. Prompts for the Aurel local-account password (masked), encodes
# it the Microsoft way for unattend XML, substitutes into the bare-metal
# template, and stages everything under dist/usb-baremetal/ ready to copy
# at the root of the Win11 install USB (after Rufus has burned the ISO).
#
# Output tree:
#   dist/usb-baremetal/
#     autounattend.xml      ← Setup picks this up automatically at the USB root
#     $OEM$/$1/Drivers/     ← copied to C:\Drivers during install
#                             FirstLogonCommand #1 then runs pnputil to
#                             auto-install every INF it finds, recursively
#     README.txt            ← copy-paste workflow reminder
#
# The $OEM$\$1\Drivers content comes from drivers-source/ (gitignored —
# raw driver bundles are big + licensed). Drop the extracted Asus B850
# motherboard driver pack there before running this script.
#
# Usage:
#   ./build-autounattend.sh
#   DRIVERS_FROM=/path/to/asus-extracted ./build-autounattend.sh
#
# Note: no ISO is produced. The old ISO-based workflow (build-iso.sh)
# was retired with the 2026-05-16 baremetal refactor — Windows Setup
# auto-detects autounattend.xml at the root of any removable media, so
# burning it to the USB root works just as well as bundling a 2nd CD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/w11-baremetal.xml"
DRIVERS_SRC="${DRIVERS_FROM:-$SCRIPT_DIR/drivers-source}"
OUT_DIR="$SCRIPT_DIR/dist/usb-baremetal"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template missing: $TEMPLATE" >&2
  exit 1
fi

# --- Prompt for password (masked, with confirmation) ---
echo "Building autounattend USB tree for Aurel-Gaming (Win11 x64 bare-metal)"
echo "Template: $(basename "$TEMPLATE")"
echo "Drivers source: $DRIVERS_SRC"
echo "Output: $OUT_DIR"
echo
read -rs -p "Password for the Aurel local account: " PASSWORD
echo
read -rs -p "Confirm: " PASSWORD_CONFIRM
echo

if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
  echo "Password mismatch." >&2
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  echo "Empty password not allowed (WinRM Basic auth rejects empty)." >&2
  exit 1
fi

# --- Microsoft unattend password encoding ---
# base64(UTF-16LE(password + element_name))
# For <LocalAccount><Password> and <AutoLogon><Password>, element_name = "Password".
ENCODED=$(printf '%s' "${PASSWORD}Password" | iconv -t UTF-16LE | base64)

# --- Stage the output tree ---
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/\$OEM\$/\$1/Drivers"

sed "s|%%PASSWORD_BASE64%%|$ENCODED|g" "$TEMPLATE" > "$OUT_DIR/autounattend.xml"

# --- Copy drivers if the source folder has any content ---
if [[ -d "$DRIVERS_SRC" ]] && [[ -n "$(ls -A "$DRIVERS_SRC" 2>/dev/null)" ]]; then
  echo "Copying drivers from $DRIVERS_SRC → \$OEM\$/\$1/Drivers/ …"
  # -L to follow symlinks (some Asus bundles use them), --exclude markdown
  # readmes so they don't pollute the install media.
  cp -RL "$DRIVERS_SRC"/* "$OUT_DIR/\$OEM\$/\$1/Drivers/"
  DRIVER_COUNT=$(find "$OUT_DIR/\$OEM\$/\$1/Drivers" -name '*.inf' | wc -l | tr -d ' ')
  echo "  $DRIVER_COUNT .inf file(s) staged."
else
  echo "No drivers found in $DRIVERS_SRC — output will install no drivers."
  echo "(Drop the extracted Asus B850 driver pack there to slipstream.)"
fi

# --- README reminder for the USB workflow ---
cat > "$OUT_DIR/README.txt" <<'EOF'
Aurel-Gaming Windows 11 USB workflow
=====================================

1. Download the Win11 x64 ISO from Microsoft.
2. Burn it to a USB stick with Rufus (or `dd` on macOS).
3. Copy the CONTENTS of this folder (autounattend.xml + $OEM$ tree) to the
   root of the USB drive, alongside the Windows install files.
   - autounattend.xml MUST end up at the USB root (not in a subfolder).
   - $OEM$ folder MUST also be at the USB root.
4. Boot the target machine from the USB.
5. Choose the system NVMe on the partition page (only manual step — the
   template intentionally leaves <DiskConfiguration> out so data drives are
   never accidentally wiped).
6. Walk away. After ~10 min Setup completes, autologin runs the
   FirstLogonCommands (install drivers from C:\Drivers, bootstrap WinRM,
   tune quotas, disable Tamper, write IP to C:\Aurel-Gaming-IP.txt).
7. Read the IP from C:\Aurel-Gaming-IP.txt on the screen, update
   Ansible/inventory/host_vars/aurelien-gaming/connection.yml accordingly.
8. From the Mac: `make windows` and the role takes over.
EOF

echo
echo "✅ Built: $OUT_DIR"
echo
echo "Next: burn the Win11 ISO to your USB, then copy the contents of"
echo "  $OUT_DIR"
echo "to the USB root. Read $OUT_DIR/README.txt for the full workflow."
