#!/usr/bin/env bash
# Build an autounattend ISO for fully automated Win11 ARM VM install on UTM.
#
# Reads the password for the Aurel local account interactively (masked,
# no shell history leak), encodes it the Microsoft way for unattend XML
# (base64 of UTF-16LE of password + literal "Password"), substitutes into
# w11-arm-vm.xml, and emits a small ISO via hdiutil.
#
# Usage:
#   ./build-iso.sh                    # output: ./autounattend.iso
#   ./build-iso.sh /path/to/out.iso   # output: custom path
#
# Then in UTM:
#   Edit VM → Drives → New Drive → Interface: USB or IDE, Removable, CD/DVD
#   Browse to the generated autounattend.iso → Save
#   Boot with BOTH Win11 ARM ISO AND autounattend.iso mounted.
#   Windows installer auto-detects autounattend.xml at the root of any
#   removable media and applies it without intervention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/w11-arm-vm.xml"
OUTPUT="${1:-$SCRIPT_DIR/autounattend.iso}"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template missing: $TEMPLATE" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil not found — this script targets macOS." >&2
  exit 1
fi

# --- Prompt for password (masked, with confirmation) ---
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

# --- Build a temp staging dir with autounattend.xml at the ISO root ---
TMPDIR="$(mktemp -d -t autounattend.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

sed "s|%%PASSWORD_BASE64%%|$ENCODED|g" "$TEMPLATE" > "$TMPDIR/autounattend.xml"

# --- Emit ISO ---
# hybrid Joliet ensures Windows installer can read it.
# default-volume-name uppercase per ISO 9660 convention.
hdiutil makehybrid -iso -joliet \
  -default-volume-name "AUTOUNATTEND" \
  -o "$OUTPUT" "$TMPDIR" >/dev/null

echo
echo "✅ Created: $OUTPUT"
echo
echo "Next steps in UTM:"
echo "  1. Create new Win11 ARM VM from UTM Gallery (or your existing Win11 ARM ISO)"
echo "  2. Edit VM → Drives → New Drive → Removable, CD/DVD, Interface: USB"
echo "     Path: $OUTPUT"
echo "  3. Boot the VM. Windows installer auto-applies autounattend.xml."
echo "  4. After ~10-15 min (depending on host), VM boots into Aurel session,"
echo "     runs the first-logon commands (WinRM bootstrap + quotas), then restarts."
echo "  5. Confirm IP via Get-NetIPAddress in the VM or via macOS \`arp -a\`."
echo "  6. Update host_vars/w11-vm-aurel/connection.yml with the new IP."
echo "  7. Make sure KeePass entry Local/w11-vm-user holds this same password."
echo "  8. Test: make ping-windows ARGS='--limit w11-vm-aurel'"
