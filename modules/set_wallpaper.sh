#!/bin/bash
# Set GNOME wallpaper
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ASSETS_DIR="$SCRIPT_DIR/assets"

# This module configures the GNOME desktop background; skip everywhere else.
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
    echo "Skipping wallpaper: gsettings or GNOME desktop not detected."
    exit 0
fi

wallpaper="$ASSETS_DIR/wallpaper/wallpaper.jpg"
if [ ! -r "$wallpaper" ]; then
    echo "Error: required wallpaper asset is missing or unreadable: $wallpaper" >&2
    exit 1
fi

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: copy assets/wallpaper/wallpaper.jpg to ~/Pictures and set the GNOME wallpaper (gsettings)"
    exit 0
fi

if ! run mkdir -p "$HOME/Pictures/"; then
    echo "Error: could not create $HOME/Pictures." >&2
    exit 1
fi
if ! run cp -p "$wallpaper" "$HOME/Pictures/"; then
    echo "Error: could not copy wallpaper to $HOME/Pictures/wallpaper.jpg." >&2
    exit 1
fi

failures=0
for key in picture-uri picture-uri-dark; do
    if ! run gsettings set org.gnome.desktop.background "$key" "file://$HOME/Pictures/wallpaper.jpg"; then
        echo "Error: could not set GNOME background property '$key'." >&2
        failures=$((failures + 1))
    fi
done
if [ "$failures" -gt 0 ]; then
    echo "Wallpaper configuration incomplete: $failures GNOME background property/properties failed." >&2
    exit 1
fi
echo "Wallpaper set."
