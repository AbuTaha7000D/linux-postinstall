#!/bin/bash
# Set up user icons and cursor themes (GNOME only)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ICON_SRC_DIR="$SCRIPT_DIR/additions/icons"
BOOKMARKS_FILE="$HOME/.config/gtk-3.0/bookmarks"
GITHUB_BOOKMARK="file://$HOME/Github"

# This module configures GNOME Shell integration; skip everywhere else.
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
    echo "Skipping icons and cursors: gsettings or GNOME desktop not detected."
    exit 0
fi

# Dry-run: report planned work, write nothing
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: create ~/.icons, copy additions/icons, create ~/Github, add the Files sidebar bookmark"
    echo "would run: select cursor theme and set cursor-theme/icon-theme (gsettings)"
    exit 0
fi

# 1. Create ~/.icons if it doesn't exist
run mkdir -p "$HOME/.icons"

echo "Browse GNOME cursor themes: https://www.gnome-look.org/browse?cat=107&ord=rating"
echo "My favorite cursor theme: https://www.gnome-look.org/p/1393084"
echo "You can open these links in your browser to find and download cursor themes."

if [ -t 0 ]; then
    echo "Please add your favorite cursor themes (folders) to ~/.icons."
    echo "You can download them from GNOME-Look, GitHub, etc. and extract them here."
    read -r -p "Type 'y' when you are done: " confirm_cursors
    if [ "$confirm_cursors" != "y" ] && [ "$confirm_cursors" != "Y" ]; then
        echo "Cursor theme setup skipped."
    else
        # List cursor themes (folders in ~/.icons)
        cursor_themes=( $(ls -1d "$HOME"/.icons/*/ 2>/dev/null | xargs -n1 basename) )
        if [ ${#cursor_themes[@]} -eq 0 ]; then
            echo "No cursor themes found in ~/.icons. Skipping cursor theming."
        else
            echo "Available cursor themes:"
            select SELECTED_CURSOR in "${cursor_themes[@]}"; do
                if [ -n "$SELECTED_CURSOR" ]; then
                    break
                else
                    echo "Invalid selection. Please choose a valid theme number."
                fi
            done
            echo "Selected cursor theme: $SELECTED_CURSOR"
            run gsettings set org.gnome.desktop.interface cursor-theme "$SELECTED_CURSOR"
            echo "Cursor theme set to $SELECTED_CURSOR."
        fi
    fi
else
    echo "Non-interactive session: skipping cursor theme selection."
fi

# Check current icon theme
current_icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
echo "Current icon theme: $current_icon_theme"
if [[ "$current_icon_theme" != "Adwaita" ]]; then
    echo "Icon theme is not Adwaita. Setting it to Adwaita."
    run gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
    echo "Icon theme set to Adwaita."
else
    echo "Icon theme is already Adwaita."
fi

# Copy all icons from additions/icons/ to ~/.icons
if [ -d "$ICON_SRC_DIR" ]; then
    run cp -r "$ICON_SRC_DIR"/* "$HOME/.icons/"
    echo "All icons from additions/icons/ copied to ~/.icons."
else
    echo "No additions/icons/ directory found, skipping icon copy."
fi

# Create ~/Github/ if it doesn't exist and add to sidebar
run mkdir -p "$HOME/Github"
# Add to GNOME Files (Nautilus) sidebar if gio is available
if command -v gio >/dev/null 2>&1; then
    if [ -f "$BOOKMARKS_FILE" ] && grep -qF "$GITHUB_BOOKMARK" "$BOOKMARKS_FILE"; then
        echo "~/Github is already in the Files (Nautilus) sidebar."
    else
        run mkdir -p "$(dirname "$BOOKMARKS_FILE")"
        printf '%s\n' "$GITHUB_BOOKMARK" >> "$BOOKMARKS_FILE"
        echo "Added ~/Github to the Files (Nautilus) sidebar."
    fi
else
    echo "gio not found, skipping sidebar addition."
fi

echo "Icons and cursor setup complete."
