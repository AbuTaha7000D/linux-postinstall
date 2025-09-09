#!/bin/bash

################################################################################
# Modular Linux Postinstall Setup Script
# Delegates all tasks to scripts/ sub-scripts. Each option runs a modular script.

# Version
VERSION="v2.1.1"

# Check if the script is run as root
if [ "$EUID" -eq 0 ]; then
    echo "This script should not be run as root. Please run it as a regular user."
    exit 1
fi

# Check for updates from GitHub before running the setup
REPO_URL="https://github.com/abutaha7000d/linux-postinstall.git"
BRANCH="main"

# Fetch latest commit hash from GitHub
latest_commit=$(git ls-remote $REPO_URL refs/heads/$BRANCH | awk '{print $1}')
local_commit=$(git rev-parse HEAD)

if [ "$latest_commit" != "$local_commit" ]; then
    echo "A newer version is available on GitHub. Updating repo..."
    git pull origin $BRANCH
    echo "Repo updated. Please re-run the script."
    exit 0
fi

# Prevent repeated sudo password prompts for the duration of the script
# (Set sudo timestamp_timeout to -1 for this session, then restore after)
original_timeout=$(sudo grep '^Defaults\s\+timestamp_timeout=' /etc/sudoers)

if sudo grep -q '^Defaults\s\+timestamp_timeout=-1' /etc/sudoers; then
    echo "timestamp_timeout is already set to -1. No changes needed."
elif [ -n "$original_timeout" ]; then
    # If the line exists but has a different value, modify it to -1
    sudo sed -i 's/^Defaults\s\+timestamp_timeout=.*/Defaults timestamp_timeout=-1/' /etc/sudoers
else
    # If the line does not exist, add it
    echo "Defaults timestamp_timeout=-1" | sudo tee -a /etc/sudoers > /dev/null
fi

# Print usage/help
usage() {
    echo "Usage: $0 <option>"
    echo "Options:"
    echo "  all                      Run all setup steps (recommended)"
    echo "  add_custom_shortcut      Add custom GNOME keyboard shortcuts"
    echo "  add_google_dns           Add Google DNS to your system"
	echo "  gnome_extensions         Open recommended GNOME extensions in your browser"
    echo "  change_language          Set system language (English/Arabic)"
    echo "  install_apps             Install system, Flatpak, and AUR applications"
    echo "  install_atuin            Install and configure Atuin shell history manager"
    echo "  install_fonts            Install user fonts from additions/fonts"
    echo "  set_aliases              Overwrite .bashrc with dynamic aliases (with backup)"
    echo "  set_favorite_apps        Set favorite apps in the GNOME dock"
    echo "  themes                   Install and configure icons, cursers, terminal, and gnome themes"
    echo "  help | -h | --help       Show this help message"
    echo "  version | -v | --version Show version"
}


# Main execution
main() {
    if [ -z "$1" ]; then
        usage
        exit 1
    fi
    case "$1" in
        all)
            bash scripts/change_language.sh
            bash scripts/install_fonts.sh
            bash scripts/install_apps.sh
            bash scripts/add_google_dns.sh
            bash scripts/set_aliases.sh
            bash scripts/add_custom_shortcut.sh
            bash scripts/install_atuin.sh
            bash scripts/set_wallpaper.sh
            bash scripts/gnome_themes.sh
            bash scripts/icons_and_cursors.sh
            bash scripts/terminal_themes.sh
            bash scripts/set_favorite_apps.sh
            bash scripts/gnome_extensions.sh
            ;;
        install_apps)
            bash scripts/install_apps.sh
            ;;
        add_custom_shortcut)
            bash scripts/add_custom_shortcut.sh
            ;;
        add_google_dns)
            bash scripts/add_google_dns.sh
            ;;
        gnome_extensions)
            bash scripts/gnome_extensions.sh
            ;;
        change_language)
            bash scripts/change_language.sh
            ;;
        install_atuin)
            bash scripts/install_atuin.sh
            ;;
        install_fonts)
            bash scripts/install_fonts.sh
            ;;
        set_aliases)
            bash scripts/set_aliases.sh
            ;;
        set_favorite_apps)
            bash scripts/set_favorite_apps.sh
            ;;
        themes)
            bash scripts/set_wallpaper.sh
            bash scripts/gnome_themes.sh
            bash scripts/icons_and_cursors.sh
            bash scripts/terminal_themes.sh
            ;;
        help|-h|--help)
            usage
            ;;
        version|-v|--version)
            echo "setup.sh $VERSION"
            ;;
        *)
            echo -e "Error: Invalid install option ..." >&2
            echo -e "For more information, run './setup.sh help'\n"
			# Restore original sudo timestamp_timeout value
			if [ -n "$original_timeout" ]; then
				sudo sed -i "s/^Defaults\s\+timestamp_timeout=-1.*/$original_timeout/" /etc/sudoers
			fi
            exit 1
            ;;
    esac
    echo -e "Installation complete.\n"
}

# Run the main function
main "$@"

# Restore original sudo timestamp_timeout value
if [ -n "$original_timeout" ]; then
    sudo sed -i "s/^Defaults\s\+timestamp_timeout=-1.*/$original_timeout/" /etc/sudoers
fi
