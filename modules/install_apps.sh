#!/bin/bash
# Install system and Flatpak applications for supported distros
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

dtype=$(distribution)

# System packages; one list per family, only names that exist in that family's repos
fedora_packages=(
    git nano btop htop fzf fastfetch bat vim neovim
    python3 python3-pip nodejs npm gnupg2
    unzip wget curl xdg-utils
    gcc make cmake clang xdotool flatpak
    thunderbird bleachbit fish
    gnome-tweaks gnome-shell-extensions
    gnome-shell-extension-user-theme gnome-shell-extension-dash-to-dock
)

debian_packages=(
    git nano btop htop fzf fastfetch bat vim neovim
    python3 python3-pip nodejs npm gpg
    unzip wget curl xdg-utils
    gcc make cmake clang xdotool flatpak
    vlc thunderbird obs-studio bleachbit screenkey
    fish gnome-tweaks gnome-shell-extensions
)

arch_packages=(
    git nano btop htop fzf fastfetch bat vim neovim
    python python-pip nodejs gnupg
    unzip wget curl xdg-utils
    gcc make cmake clang xdotool flatpak
    vlc thunderbird obs-studio bleachbit
    fish gnome-tweaks gnome-shell-extensions
)

echo "Installing system packages..."
case "$dtype" in
    "redhat")
        if ! run_root dnf makecache; then
            echo "Error: dnf failed to refresh the package index (Fedora family)." >&2
            exit 1
        fi
        if ! run_root dnf install -y "${fedora_packages[@]}"; then
            echo "Error: dnf failed to install the Fedora package set." >&2
            exit 1
        fi
        ;;
    "debian")
        if ! run_root apt-get update; then
            echo "Error: apt-get failed to refresh the package index (Debian family)." >&2
            exit 1
        fi
        if ! run_root apt-get install -y "${debian_packages[@]}"; then
            echo "Error: apt-get failed to install the Debian package set." >&2
            exit 1
        fi
        ;;
    "arch")
        if ! run_root pacman -Syu --noconfirm "${arch_packages[@]}"; then
            echo "Error: pacman failed to refresh and install the Arch package set." >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown or unsupported distribution: $dtype" >&2
        exit 1
        ;;
esac

echo -e "\nInstalling Flatpak applications..."

if ! command -v flatpak >/dev/null 2>&1; then
    echo "Error: flatpak command not found (required to install Flatpak applications)." >&2
    exit 1
fi

if ! flatpak remotes --system | grep -qE '^flathub([[:space:]]|$)'; then
    if ! run_root flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
        echo "Error: failed to add the Flathub remote." >&2
        exit 1
    fi
fi

flatpak_apps=(
    com.brave.Browser
    com.discordapp.Discord
    com.bitwarden.desktop
    com.github.jeromerobert.pdfarranger
    com.github.rajsolai.textsnatcher
	org.strawberrymusicplayer.strawberry
    com.microsoft.Edge
    com.rtosta.zapzap
    com.spotify.Client
    net.nokyan.Resources
    org.nickvision.tubeconverter
    org.pipewire.Helvum
    com.github.joseexposito.touche
    com.mattjakeman.ExtensionManager
    io.gitlab.theevilskeleton.Upscaler
    org.gnome.Extensions
    org.gnome.NetworkDisplays
    org.kde.KStyle.Adwaita
    org.libreoffice.LibreOffice
    org.standardnotes.standardnotes
    org.localsend.localsend_app
    org.mozilla.Thunderbird
    org.qbittorrent.qBittorrent
)


# Install Flatpak apps
for app in "${flatpak_apps[@]}"; do
    if flatpak info "$app" > /dev/null 2>&1; then
        echo "$app is already installed."
    else
        if ! run_root flatpak install --system flathub "$app" -y; then
            echo "Error: failed to install Flatpak app $app" >&2
            exit 1
        fi
    fi
done

echo -e "\nInstalling Google Chrome and Visual Studio Code..."

# The vendor packages below are published for x86_64 only. The check runs only
# on a path that is about to download one, so an already-installed setup on
# other architectures still succeeds.
require_vendor_arch() {
    local vendor_arch
    vendor_arch=$(uname -m)
    case "$vendor_arch" in
        x86_64) ;;
        *)
            echo "Error: Chrome and VS Code vendor installs support x86_64 only (detected: $vendor_arch)." >&2
            exit 1
            ;;
    esac
}

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    case "$dtype" in
        "debian")
            echo "would run: download and install VS Code and Google Chrome via apt-get"
            ;;
        "redhat")
            echo "would run: download and install VS Code and Google Chrome via dnf"
            ;;
        "arch")
            echo "would run: install VS Code and Google Chrome via yay (AUR)"
            ;;
    esac
else
    if ! vendor_tmp=$(mktemp -d); then
        echo "Error: failed to create a temporary download directory." >&2
        exit 1
    fi
    cleanup_vendor_tmp() {
        if [ -n "$vendor_tmp" ]; then
            rm -rf "$vendor_tmp"
        fi
    }
    trap cleanup_vendor_tmp EXIT

    case "$dtype" in
    "debian")
        # VS Code
        if ! dpkg -s code &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/vscode.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"; then
                echo "Error: failed to download the VS Code .deb package." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "$vendor_tmp/vscode.deb"; then
                echo "Error: failed to install the VS Code .deb package." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! dpkg -s google-chrome-stable &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/chrome.deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"; then
                echo "Error: failed to download the Google Chrome .deb package." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "$vendor_tmp/chrome.deb"; then
                echo "Error: failed to install the Google Chrome .deb package." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "redhat")
        # VS Code (.rpm download; no repo file is written)
        if ! rpm -q code &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/vscode.rpm" "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"; then
                echo "Error: failed to download the VS Code .rpm package." >&2
                exit 1
            fi
            if ! run_root dnf install -y "$vendor_tmp/vscode.rpm"; then
                echo "Error: failed to install the VS Code .rpm package." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! rpm -q google-chrome-stable &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/chrome.rpm" "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"; then
                echo "Error: failed to download the Google Chrome .rpm package." >&2
                exit 1
            fi
            if ! run_root dnf install -y "$vendor_tmp/chrome.rpm"; then
                echo "Error: failed to install the Google Chrome .rpm package." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "arch")
        # AUR installs need the yay helper; bootstrapping it is intentionally
        # not done here, so a missing helper fails with instructions.
        if ! pacman -Qi visual-studio-code-bin &>/dev/null || ! pacman -Qi google-chrome &>/dev/null; then
            require_vendor_arch
            if ! command -v yay &>/dev/null; then
                echo "Error: yay is required to install VS Code and Chrome from the AUR, but it was not found." >&2
                echo "Install yay manually (https://wiki.archlinux.org/title/AUR_helper), then rerun this script." >&2
                exit 1
            fi
        fi
        # VS Code
        if ! pacman -Qi visual-studio-code-bin &>/dev/null; then
            if ! run yay -S --needed --noconfirm visual-studio-code-bin; then
                echo "Error: failed to install visual-studio-code-bin via yay." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! pacman -Qi google-chrome &>/dev/null; then
            if ! run yay -S --needed --noconfirm google-chrome; then
                echo "Error: failed to install google-chrome via yay." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    esac
fi

echo -e "\nAll system, Flatpak, Chrome, and VS Code steps processed.\n"
echo -e "\n#################### Done! ####################"
