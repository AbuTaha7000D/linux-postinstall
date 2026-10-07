#!/bin/bash
# Set GNOME wallpaper
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ADDITIONS_DIR="$SCRIPT_DIR/additions"

# This module configures the GNOME desktop background; skip everywhere else.
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
    echo "Skipping wallpaper: gsettings or GNOME desktop not detected."
    exit 0
fi

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: copy additions/wallpaper.jpg to ~/Pictures and set the GNOME wallpaper (gsettings)"
    exit 0
fi

run mkdir -p "$HOME/Pictures/"
run cp -p "$ADDITIONS_DIR/wallpaper.jpg" "$HOME/Pictures/"
run gsettings set org.gnome.desktop.background picture-uri "file://$HOME/Pictures/wallpaper.jpg"
run gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/Pictures/wallpaper.jpg"
echo "Wallpaper set."
