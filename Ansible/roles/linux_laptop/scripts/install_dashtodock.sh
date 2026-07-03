#!/bin/bash
# Install the GNOME extension DashToDock into the current user's profile.
set -euo pipefail

ZIP="$HOME/Downloads/dash-to-dock.shell-extension.zip"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"

uuid=$(unzip -c "$ZIP" metadata.json | grep uuid | cut -d '"' -f4)

if [ -d "$EXT_DIR/$uuid" ]; then
    echo "$uuid already exists"
else
    mkdir -p "$EXT_DIR/$uuid"
    unzip -q "$ZIP" -d "$EXT_DIR/$uuid"
fi
