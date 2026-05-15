#!/usr/bin/env bash
# Build an autounattend ISO for fully automated Win11 install (UTM, other
# hypervisors, or a real USB install media).
#
# Reads the password for the Aurel local account interactively (masked,
# no shell history leak), encodes it the Microsoft way for unattend XML
# (base64 of UTF-16LE of password + literal "Password"), substitutes into
# the chosen template, and emits a small ISO via hdiutil.
#
# Usage:
#   ./build-iso.sh [arch] [output_iso]
#
#   arch        : "arm64" (default) or "x64"
#                 - arm64 → w11-arm-vm.xml  (Apple Silicon UTM, HVF accel)
#                 - x64   → w11-x64-vm.xml  (Intel Mac UTM, VMware, Parallels,
#                                             Hyper-V, or USB install media)
#   output_iso  : custom output path (default: ./autounattend-${arch}.iso)
#
# Examples:
#   ./build-iso.sh                     # arm64, ./autounattend-arm64.iso
#   ./build-iso.sh x64                 # x64, ./autounattend-x64.iso
#   ./build-iso.sh x64 /tmp/foo.iso    # x64, custom output
#
# Mounting in UTM:
#   Edit VM → Drives → New Drive → Removable, CD/DVD, Interface USB or IDE
#   Browse to the generated .iso → Save → Boot with Win11 ISO + autounattend ISO
#   both mounted. Windows installer auto-detects autounattend.xml at the root
#   of any removable media and applies it without intervention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="${1:-arm64}"
OUTPUT="${2:-$SCRIPT_DIR/autounattend-${ARCH}.iso}"

case "$ARCH" in
  arm64)
    TEMPLATE="$SCRIPT_DIR/w11-arm-vm.xml"
    ;;
  x64|amd64)
    TEMPLATE="$SCRIPT_DIR/w11-x64-vm.xml"
    ;;
  *)
    echo "Unknown arch: $ARCH (expected: arm64, x64)" >&2
    exit 1
    ;;
esac

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template missing: $TEMPLATE" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil not found — this script targets macOS." >&2
  exit 1
fi

# --- Prompt for password (masked, with confirmation) ---
echo "Building autounattend ISO for Win11 $ARCH"
echo "Template: $(basename "$TEMPLATE")"
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
echo "Next steps:"
echo "  1. Mount the ISO as a second CD/DVD in your VM (or burn to a USB"
echo "     install media for bare-metal)"
echo "  2. Boot. Windows installer auto-applies autounattend.xml."
echo "  3. After ~10-15 min, VM boots into Aurel session, runs first-logon"
echo "     commands (WinRM bootstrap + quotas + Tamper off), restarts."
echo "  4. Confirm IP via Get-NetIPAddress in the VM, or via macOS \`arp -a\`."
echo "  5. Update Ansible inventory connection.yml with the IP."
echo "  6. Make sure KeePass entry Local/w11-vm-user holds the same password."
echo "  7. Test: make ping-windows ARGS='--limit w11-vm-aurel'"
