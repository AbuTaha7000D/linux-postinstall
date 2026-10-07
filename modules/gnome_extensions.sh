#!/bin/bash
# Browse GNOME Extensions to be installed
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# GNOME Shell extensions are of no use outside GNOME; skip everywhere else.
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
    echo "Skipping GNOME extensions: gsettings or GNOME desktop not detected."
    exit 0
fi

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

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: open ${#extensions[@]} GNOME extension pages in the browser and prompt to continue"
    exit 0
fi

if [ -t 0 ]; then
    if command -v xdg-open >/dev/null 2>&1; then
        for extension in "${extensions[@]}"; do
            xdg-open "$extension" >/dev/null 2>&1 &
        done
        echo -e "\nAll extensions opened in the browser."
    else
        echo "xdg-open not found. Please open the following URLs manually:"
        printf '%s\n' "${extensions[@]}"
    fi
    read -r -p "After installing the extensions, Enter (Y) to continue or (N) to stop: " continue_choice
    case "$continue_choice" in
        [Yy]*)
            echo "Continuing..."
            ;;
        *)
            echo "Stopped. Rerun './setup extensions' to reopen the extension pages."
            ;;
    esac
else
    echo "Non-interactive session: not opening a browser."
    echo "Open the following URLs manually when ready:"
    printf '%s\n' "${extensions[@]}"
fi
