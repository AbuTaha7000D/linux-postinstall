#!/bin/bash
# Add custom GNOME shortcuts
set -e

# Check for GNOME and gsettings
if ! command -v gsettings >/dev/null 2>&1 || [[ $XDG_CURRENT_DESKTOP != *GNOME* ]]; then
    echo "This script requires GNOME and gsettings. Skipping custom shortcut setup."
    exit 0
fi

add_shortcut() {
    local name="$1"
    local command="$2"
    local binding="$3"
    current_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    new_binding="custom$(echo "$current_bindings" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -n 1 | awk '{print $1+1}')"
    [ -z "$new_binding" ] && new_binding="custom0"
    if [[ "$current_bindings" != "@as []" ]]; then
        existing_bindings=$(echo "$current_bindings" | grep -o 'custom[0-9]*')
        for custom_binding in $existing_bindings; do
            existing_name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ name | sed "s/'//g")
            existing_command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ command | sed "s/'//g")
            existing_binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ binding | sed "s/'//g")
            if [[ "$existing_name" == "$name" ]] || [[ "$existing_command" == "$command" ]] || [[ "$existing_binding" == "$binding" ]]; then
                echo "Shortcut with name, command, or binding already exists, skipping."
                return 0
            fi
        done
    fi
    if [[ "$current_bindings" == "@as []" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/$new_binding/']"
    else
        updated_bindings=$(echo "$current_bindings" | sed "s/]$/, '\/\$new_binding\/'']/")
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_bindings"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ name "$name"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ command "$command"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ binding "$binding"
    if [ $? -ne 0 ]; then
        echo "Error creating shortcut: $name"
        return 1
    fi
}

add_shortcut "Resources" "flatpak run net.nokyan.Resources" "<Ctrl><Shift>Escape"
add_shortcut "Settings" "gnome-control-center" "<Super>I"
add_shortcut "Terminal" "gnome-terminal" "<Alt>T"
add_shortcut "Toggle Mic" "amixer set Capture toggle" "<Alt>1"

echo "Shortcuts added successfully."
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
