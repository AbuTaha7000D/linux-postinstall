#!/bin/bash
# Set GNOME wallpaper
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDITIONS_DIR="$SCRIPT_DIR/additions"

mkdir -p "$HOME/Pictures/"
cp -p "$ADDITIONS_DIR/wallpaper.jpg" "$HOME/Pictures/"

if command -v gsettings >/dev/null 2>&1 && [[ $XDG_CURRENT_DESKTOP == *GNOME* ]]; then
    gsettings set org.gnome.desktop.background picture-uri "file://$HOME/Pictures/wallpaper.jpg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/Pictures/wallpaper.jpg"
    echo "Wallpaper set."
else
    echo "Skipping wallpaper: gsettings or GNOME desktop not detected."
fi

for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"