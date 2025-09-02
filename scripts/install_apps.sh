#!/bin/bash
# Install system and Flatpak applications for supported distros
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/utils.sh"

dtype=$(distribution)

# System packages
apps=(
    git nano btop e2fsprogs sed htop fzf fastfetch bat vim neovim python3 python3-pip nodejs gpg unzip wget amixer curl xdg-utils npm gcc make cmake clang xdotool flatpak vlc thunderbird obs-studio bleachbit screenkey timeshift jupyter-notebook fish gnome-tweaks gnome-shell-extensions gnome-shell-extension-user-theme gnome-shell-extension-dash-to-dock
)

echo "Installing system packages..."
case "$dtype" in
    "redhat")
        sudo dnf update -y && sudo dnf upgrade -y
        for app in "${apps[@]}"; do
            if ! rpm -q "$app" &>/dev/null; then
                if ! sudo dnf install -y "$app"; then
                    echo "Error installing $app" | tee -a install_errors.log
                fi
            else
                echo "$app is already installed."
            fi
        done
        ;;
    "debian")
        sudo apt-get update -y && sudo apt-get upgrade -y
        for app in "${apps[@]}"; do
            if ! dpkg -s "$app" &>/dev/null; then
                if ! sudo apt-get install -y "$app"; then
                    echo "Error installing $app" | tee -a install_errors.log
                fi
            else
                echo "$app is already installed."
            fi
        done
        ;;
    "arch")
        sudo pacman -Syu --noconfirm
        for app in "${apps[@]}"; do
            if ! pacman -Qi "$app" &>/dev/null; then
                if ! sudo pacman -S --noconfirm "$app"; then
                    echo "Error installing $app" | tee -a install_errors.log
                fi
            else
                echo "$app is already installed."
            fi
        done
        ;;
    *)
        echo "Unknown distribution: $dtype" >&2
    echo "Unknown or unsupported distribution: $dtype" | tee -a install_errors.log
    exit 1
        ;;
esac

echo "\nInstalling Flatpak applications..."
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
        if ! sudo flatpak install flathub "$app" -y; then
            echo "Error installing flatpak $app" | tee -a install_errors.log
        fi
    fi
done

echo "\nInstalling Google Chrome and Visual Studio Code..."

case "$dtype" in
    "debian")
        # VS Code
        if ! dpkg -s code &>/dev/null; then
            wget -O /tmp/vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
            sudo apt-get install -y /tmp/vscode.deb && echo "VS Code installed." || echo "Error installing VS Code."
            rm -f /tmp/vscode.deb
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! dpkg -s google-chrome-stable &>/dev/null; then
            wget -O /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
            sudo apt-get install -y /tmp/chrome.deb && echo "Google Chrome installed." || echo "Error installing Chrome."
            rm -f /tmp/chrome.deb
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "redhat")
        # VS Code
        if ! rpm -q code &>/dev/null; then
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            sudo dnf check-update
            sudo dnf install -y code && echo "VS Code installed." || echo "Error installing VS Code."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! rpm -q google-chrome-stable &>/dev/null; then
            wget -O /tmp/chrome.rpm "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
            sudo dnf install -y /tmp/chrome.rpm && echo "Google Chrome installed." || echo "Error installing Chrome."
            rm -f /tmp/chrome.rpm
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "arch")
        # Ensure yay is installed
        if ! command -v yay &>/dev/null; then
            echo "yay not found. Installing yay AUR helper..."
            sudo pacman -S --needed --noconfirm base-devel git
            git clone https://aur.archlinux.org/yay.git /tmp/yay
            cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
        fi
        # VS Code
        if ! pacman -Qi visual-studio-code-bin &>/dev/null; then
            yay -S --needed --noconfirm visual-studio-code-bin && echo "VS Code installed." || { echo "Error installing VS Code." | tee -a install_errors.log; }
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! pacman -Qi google-chrome &>/dev/null; then
            yay -S --needed --noconfirm google-chrome && echo "Google Chrome installed." || { echo "Error installing Chrome." | tee -a install_errors.log; }
        else
            echo "Google Chrome is already installed."
        fi
        ;;
esac

echo -e "\nAll system, Flatpak, Chrome, and VS Code apps processed.\n"
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
