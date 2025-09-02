#!/bin/bash
# Browse GNOME Extensions to be installed
set -e

echo "Opening browser to browse GNOME Extensions..."
extensions=(
    "https://extensions.gnome.org/extension/5895/app-hider/"
    "https://extensions.gnome.org/extension/4648/desktop-cube/"
    "https://extensions.gnome.org/extension/3193/blur-my-shell/"
    "https://extensions.gnome.org/extension/517/caffeine/"
    "https://extensions.gnome.org/extension/97/coverflow-alt-tab/"
    "https://extensions.gnome.org/extension/4167/custom-hot-corners-extended/"
    "https://extensions.gnome.org/extension/779/clipboard-indicator/"
    "https://extensions.gnome.org/extension/307/dash-to-dock/"
    "https://extensions.gnome.org/extension/352/middle-click-to-close-in-overview/"
    "https://extensions.gnome.org/extension/7/removable-drive-menu/"
    "https://extensions.gnome.org/extension/2986/runcat/"
    "https://extensions.gnome.org/extension/6807/system-monitor/"
    "https://extensions.gnome.org/extension/7065/tiling-shell/"
    "https://extensions.gnome.org/extension/4356/top-bar-organizer/"
    "https://extensions.gnome.org/extension/19/user-themes/"
    "https://extensions.gnome.org/extension/4033/x11-gestures/"
    "https://extensions.gnome.org/extension/3628/arcmenu/"
    "https://extensions.gnome.org/extension/6997/athantimes/"
    "https://extensions.gnome.org/extension/1010/archlinux-updates-indicator/"
    "https://extensions.gnome.org/extension/6406/fedora-linux-update-indicator/"
)
if command -v xdg-open >/dev/null 2>&1; then
    for extension in "${extensions[@]}"; do
        xdg-open "$extension" >/dev/null 2>&1 &
    done
    echo -e "\nAll extensions opened in the browser."
else
    echo "xdg-open not found. Please open the following URLs manually:"
    printf '%s\n' "${extensions[@]}"
fi
read -p "After installing the extensions, Enter (Y) to continue or (N) to reopen the GNOME Extensions: " continue_choice
case "$continue_choice" in
    [Yy]*)
        echo -e "Continuing..."
        ;;
    *)
        bash "$0"
        ;;
esac

for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"