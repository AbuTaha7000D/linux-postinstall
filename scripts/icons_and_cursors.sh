#!/bin/bash
# Set up user icons and cursor themes
set -e

# 1. Create ~/.icons if it doesn't exist
mkdir -p "$HOME/.icons"

echo "Browse GNOME cursor themes: https://www.gnome-look.org/browse?cat=107&ord=rating"
echo "My favorite cursor theme: https://www.gnome-look.org/p/1393084"
echo "You can open these links in your browser to find and download cursor themes."

if command -v gsettings >/dev/null 2>&1 && [[ $XDG_CURRENT_DESKTOP == *GNOME* ]]; then

    echo "Please add your favorite cursor themes (folders) to ~/.icons."
    echo "You can download them from GNOME-Look, GitHub, etc. and extract them here."
    read -p "Type 'y' when you are done: " confirm_cursors
    if [ "$confirm_cursors" != "y" ] && [ "$confirm_cursors" != "Y" ]; then
        echo "Cursor theme setup skipped."
    else
        # List cursor themes (folders in ~/.icons)
        cursor_themes=( $(ls -1d $HOME/.icons/*/ 2>/dev/null | xargs -n1 basename) )
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
            gsettings set org.gnome.desktop.interface cursor-theme "$SELECTED_CURSOR"
            echo "Cursor theme set to $SELECTED_CURSOR."
        fi
    fi
    # Check current icon theme
    current_icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
    echo "Current icon theme: $current_icon_theme"
    if [[ "$current_icon_theme" != "Adwaita" ]]; then
        echo "Icon theme is not Adwaita. Setting it to Adwaita."
        gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        echo "Icon theme set to Adwaita."
    else
        echo "Icon theme is already Adwaita."
    fi	
else
    echo "Skipping cursor theming: gsettings or GNOME desktop not detected."
fi

# 4. Copy all icons from additions/icons/ to ~/.icons
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS_SRC="$SCRIPT_DIR/additions/icons"
if [ -d "$ICONS_SRC" ]; then
    cp -r "$ICONS_SRC"/* "$HOME/.icons/"
    echo "All icons from additions/icons/ copied to ~/.icons."
else
    echo "No additions/icons/ directory found, skipping icon copy."
fi


# 5. Create ~/Github/ if it doesn't exist and add to sidebar
mkdir -p "$HOME/Github"
# Add to GNOME Files (Nautilus) sidebar if gio is available
if command -v gio >/dev/null 2>&1; then
    echo "file://$HOME/Github" >> ~/.config/gtk-3.0/bookmarks
    echo "Added ~/Github to the Files (Nautilus) sidebar."
else
    echo "gio not found, skipping sidebar addition."
fi

echo "Icons and cursor setup complete."
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
