#!/bin/bash
# Set favorite apps in the GNOME dock
set -e

# Check for GNOME and gsettings
if ! command -v gsettings >/dev/null 2>&1 || [[ $XDG_CURRENT_DESKTOP != *GNOME* ]]; then
    echo "This script requires GNOME and gsettings. Skipping favorite apps setup."
    exit 0
fi

echo "Setting favorite apps in the dock..."
favorite_apps=(
    'org.gnome.Nautilus.desktop'
    'code.desktop'
    'org.mozilla.firefox.desktop'
    'com.rtosta.zapzap.desktop'
    'google-chrome.desktop'
    'com.bitwarden.desktop.desktop'
    'com.spotify.Client.desktop'
    'org.strawberrymusicplayer.strawberry.desktop'
    'com.discordapp.Discord.desktop'
    'org.mozilla.Thunderbird.desktop'
)
installed_apps=()
for app in "${favorite_apps[@]}"; do
    if [[ "$app" == *.desktop ]] && flatpak info "${app%.desktop}" > /dev/null 2>&1; then
        installed_apps+=("$app")
    elif [ -f "/usr/share/applications/$app" ] || [ -f "$HOME/.local/share/applications/$app" ]; then
        installed_apps+=("$app")
    fi
}
gsettings_value="['$( IFS=","; echo "${installed_apps[*]}" | sed "s/,/','/g" )']"
gsettings set org.gnome.shell favorite-apps "$gsettings_value"
if [ $? -ne 0 ]; then
    echo "Error setting favorite apps in the dock"
    exit 1
fi

echo "Favorite apps set successfully!"
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"