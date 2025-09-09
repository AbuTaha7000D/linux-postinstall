#!/bin/bash
# Configure GNOME theme from ~/.themes
set -e

echo "Browse GNOME themes: https://www.gnome-look.org/browse?cat=134&ord=rating"
echo "My favorite theme: https://www.gnome-look.org/p/2014493"

echo "You can open these links in your browser to find and download themes."


if command -v gsettings >/dev/null 2>&1 && [[ $XDG_CURRENT_DESKTOP == *GNOME* ]]; then
    mkdir -p ~/.themes/
    echo "Please add your favorite GNOME themes (folders) to ~/.themes."
    echo "You can download them from GNOME-Look, GitHub, etc. and extract them here."
    read -p "Type 'y' when you are done: " confirm_themes
    if [ "$confirm_themes" != "y" ] && [ "$confirm_themes" != "Y" ]; then
        echo "Theme installation skipped."
        exit 0
    fi

    # Extract compressed theme files and delete the archives
    for archive in ~/.themes/*.{zip,tar.gz,tar.xz,tar.bz2,tar}; do
        [ -e "$archive" ] || continue
        case "$archive" in
            *.zip)
                unzip -q "$archive" -d ~/.themes && rm -f "$archive"
                ;;
            *.tar.gz|*.tgz)
                tar -xzf "$archive" -C ~/.themes && rm -f "$archive"
                ;;
            *.tar.xz)
                tar -xJf "$archive" -C ~/.themes && rm -f "$archive"
                ;;
            *.tar.bz2)
                tar -xjf "$archive" -C ~/.themes && rm -f "$archive"
                ;;
            *.tar)
                tar -xf "$archive" -C ~/.themes && rm -f "$archive"
                ;;
        esac
    done

    theme_count=$(find ~/.themes -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$theme_count" -eq 0 ]; then
        echo "No themes found in ~/.themes. Skipping GNOME theming."
        exit 0
    fi

    echo "Available themes:"
    select SELECTED_THEME in $(ls -1 ~/.themes); do
        if [ -n "$SELECTED_THEME" ]; then
            break
        else
            echo "Invalid selection. Please choose a valid theme number."
        fi
    done
    echo "Selected theme: $SELECTED_THEME"

    gsettings set org.gnome.desktop.interface gtk-theme "$SELECTED_THEME"
    gsettings set org.gnome.shell.extensions.user-theme name "$SELECTED_THEME"
    echo "GNOME theme set to $SELECTED_THEME."
else
    echo "Skipping GNOME theming: gsettings or GNOME desktop not detected."
fi

for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
