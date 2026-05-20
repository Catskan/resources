#!/usr/bin/env bash
# Build a bootable Win11 ISO with autounattend.xml + $OEM$ tree baked in.
#
# Pipeline:
#   1. Mount the source Win11 ISO read-only (hdiutil).
#   2. Mirror its contents to a scratch directory under dist/.
#   3. Overlay dist/usb-baremetal/{autounattend.xml,$OEM$} at the root.
#   4. Repackage as a hybrid (BIOS + UEFI) ISO with xorriso, preserving
#      the El Torito boot images Setup needs:
#        - BIOS:  boot/etfsboot.com               (-no-emul-boot, 8 sectors)
#        - UEFI:  efi/microsoft/boot/efisys_noprompt.bin  (no "Press any key")
#      install.wim > 4 GB → UDF + -iso-level 4 are mandatory.
#
# Output: a single .iso ready for Rufus / Ventoy / `dd` / VM attach.
# Setup picks up autounattend.xml from the ISO root the same way it does
# from a USB root, so we keep parity with the USB workflow.
#
# Prereqs:
#   - xorriso       (brew install xorriso)
#   - hdiutil       (built-in macOS)
#   - dist/usb-baremetal/autounattend.xml present
#       → run build-autounattend.sh first (prompts for Aurel password).
#
# Usage:
#   ./build-iso.sh <source-iso> [output-iso]
#
# Defaults:
#   output-iso = ~/Downloads/<source-stem>_Aurel-baremetal.iso
#
# Examples:
#   ./build-iso.sh ~/Downloads/Win11_25H2_EnglishInternational_x64_v2.iso
#   ./build-iso.sh src.iso ~/Downloads/custom-name.iso

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USB_TREE="$SCRIPT_DIR/dist/usb-baremetal"
WORK_DIR="$SCRIPT_DIR/dist/.iso-work"
VOLUME_LABEL="WIN11_AUREL"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <source-iso> [output-iso]" >&2
  exit 1
fi

SRC_ISO="$1"
if [[ ! -f "$SRC_ISO" ]]; then
  echo "Source ISO not found: $SRC_ISO" >&2
  exit 1
fi

if [[ $# -ge 2 ]]; then
  OUT_ISO="$2"
else
  src_stem="$(basename "$SRC_ISO" .iso)"
  OUT_ISO="$HOME/Downloads/${src_stem}_Aurel-baremetal.iso"
fi

# Refuse to overwrite the source ISO.
if [[ "$(cd "$(dirname "$SRC_ISO")" && pwd)/$(basename "$SRC_ISO")" \
   == "$(cd "$(dirname "$OUT_ISO")" && pwd 2>/dev/null || dirname "$OUT_ISO")/$(basename "$OUT_ISO")" ]]; then
  echo "Output ISO path equals source ISO path — refusing to overwrite." >&2
  exit 1
fi

command -v xorriso >/dev/null || {
  echo "xorriso not found. Install with: brew install xorriso" >&2
  exit 1
}

if [[ ! -f "$USB_TREE/autounattend.xml" ]]; then
  echo "Missing $USB_TREE/autounattend.xml" >&2
  echo "Run ./build-autounattend.sh first to generate it." >&2
  exit 1
fi

echo "Source ISO     : $SRC_ISO"
echo "Output ISO     : $OUT_ISO"
echo "USB tree (input): $USB_TREE"
echo "Work dir       : $WORK_DIR"
echo "Volume label   : $VOLUME_LABEL"
echo

MOUNT_POINT="$SCRIPT_DIR/dist/.iso-mount"
cleanup() {
  if mount | grep -q " on $MOUNT_POINT "; then
    echo "Unmounting $MOUNT_POINT"
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# --- 1. Mount source ISO at an explicit, space-free mountpoint --------------
echo "Mounting source ISO at $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$SRC_ISO" >/dev/null

# --- 2. Mirror ISO contents to scratch dir ----------------------------------
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
echo "Mirroring ISO contents to $WORK_DIR (this can take a minute)..."
rsync -aL --no-perms --chmod=Du+rwx,Fu+rw "$MOUNT_POINT"/ "$WORK_DIR"/

# Done with the mount (cleanup() will rmdir the empty mountpoint on exit).
hdiutil detach "$MOUNT_POINT" >/dev/null

# --- 3. Overlay autounattend + $OEM$ ----------------------------------------
echo "Overlaying autounattend.xml + \$OEM\$ tree..."
cp "$USB_TREE/autounattend.xml" "$WORK_DIR/autounattend.xml"
if [[ -d "$USB_TREE/\$OEM\$" ]]; then
  rm -rf "$WORK_DIR/\$OEM\$"
  cp -R "$USB_TREE/\$OEM\$" "$WORK_DIR/\$OEM\$"
  inf_count=$(find "$WORK_DIR/\$OEM\$" -name '*.inf' 2>/dev/null | wc -l | tr -d ' ')
  echo "  \$OEM\$ tree copied ($inf_count .inf files inside)."
else
  echo "  No \$OEM\$ tree in $USB_TREE — skipping (autounattend only)."
fi

# Locate boot images. They must exist in the source ISO; abort otherwise so
# the resulting ISO is never silently un-bootable.
BIOS_BOOT="boot/etfsboot.com"
UEFI_BOOT="efi/microsoft/boot/efisys_noprompt.bin"
for img in "$BIOS_BOOT" "$UEFI_BOOT"; do
  if [[ ! -f "$WORK_DIR/$img" ]]; then
    echo "Missing boot image inside ISO: $img" >&2
    exit 1
  fi
done

# --- 4. Repackage with xorriso ----------------------------------------------
echo "Building ISO with xorriso..."
mkdir -p "$(dirname "$OUT_ISO")"
rm -f "$OUT_ISO"

# xorriso 1.5.8's `-as mkisofs` does not expose `-udf` or
# `-allow-limited-size`, so we rely on `-iso-level 3` (ISO-9660 with
# multi-extent files) to let install.wim cross the 4 GiB boundary.
# Windows Setup reads this fine. Fallback if a target ever refuses to
# boot the result: switch to xorriso native mode with UDF (not scripted).
xorriso -as mkisofs \
  -iso-level 3 \
  -joliet -joliet-long -relaxed-filenames \
  -V "$VOLUME_LABEL" \
  -o "$OUT_ISO" \
  -b "$BIOS_BOOT" -no-emul-boot -boot-load-size 8 -boot-info-table \
  -eltorito-alt-boot \
  -e "$UEFI_BOOT" -no-emul-boot \
  "$WORK_DIR"

# --- 5. Clean up scratch ----------------------------------------------------
echo "Cleaning scratch dir..."
chmod -R u+w "$WORK_DIR" 2>/dev/null || true
rm -rf "$WORK_DIR"

size=$(du -h "$OUT_ISO" | cut -f1)
echo
echo "✅ Built: $OUT_ISO ($size)"
echo
echo "Next:"
echo "  - Burn with Rufus / Ventoy / balenaEtcher, or"
echo "    sudo dd if='$OUT_ISO' of=/dev/rdiskN bs=4m status=progress"
echo "  - Boot the target machine. Setup will auto-pick autounattend.xml."
