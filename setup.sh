#!/bin/bash
################################################################################

# Check if the script is run as root
if [ "$EUID" -eq 0 ]; then
    echo "This script should not be run as root. Please run it as a regular user."
    exit 1
fi

# Global Variables (Make them configurable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDITIONS_DIR="$SCRIPT_DIR/additions"
FONT_DIR="$ADDITIONS_DIR/fonts"
THEME_DIR="$ADDITIONS_DIR/themes"
VERSION="v1.2.0"

# Helper function to check command line arguments
usage() {
    echo "Usage: $0 <options>"
    echo -e "Automate the initial setup and configuration of a Linux system.\n"
    echo "Options:"
    echo "  all        : Run all installation steps."
    echo "  apps       : Install basic applications."
    echo "  terminal   : Configure terminal settings (Fish, Oh My Posh)."
    echo "  gnome      : Install GNOME-specific applications and settings."
    echo "  atuin      : Install and configure Atuin."
    echo "  flatpaks   : Install flatpak applications."
    echo "  dns        : Configure Google DNS."
    echo "  fonts      : Install fonts."
    echo "  themes     : Install GNOME themes."
    echo "  lang       : Configure system language to English."
    echo "  aliases    : Set aliases in shell configuration."
    echo "  shortcuts  : Configure custom keyboard shortcuts."
    echo "  help       : Display this help message."
    echo "  version    : Display script version."
    exit 1
}

# Function to determine the distribution type
distribution() {
    local dtype="unknown"
    
    if [ -r /etc/os-release ]; then
        source /etc/os-release
        case "$ID" in
            fedora|rhel|centos)
                dtype="redhat"
            ;;
            ubuntu|debian)
                dtype="debian"
            ;;
            arch)
                dtype="arch"
            ;;
            *)
                if [ -n "$ID_LIKE" ]; then
                    case "$ID_LIKE" in
                        *fedora*|*rhel*|*centos*)
                            dtype="redhat"
                        ;;
                        *ubuntu*|*debian*)
                            dtype="debian"
                        ;;
                        *arch*)
                            dtype="arch"
                        ;;
                    esac
                fi
            ;;
        esac
    fi
    
    echo "$dtype"
}

# Function to install apps based on distribution
install_apps() {
    local dtype
    dtype=$(distribution)
    
    # List of apps to install
    local apps=(
        git
        nano
        btop
        sed
        htop
        fzf
        fastfetch
        bat
        vim
        neovim
        python3
        python3-pip
        nodejs
        gpg
        unzip
        wget
        amixer
        curl
        xdg-utils
        npm
        gcc
        make
        cmake
        clang
        xdotool
        flatpak
        vlc
        thunderbird
        obs-studio
        bleachbit
        screenkey
        timeshift
        jupyter-notebook
        fish
    )
    
    case "$dtype" in
        "redhat")
            echo "Detected Red Hat-based system. Installing apps..."
            sudo dnf update -y && sudo dnf upgrade -y
            if [ $? -ne 0 ]; then
                echo "Error updating package lists"
            fi
            
            # Install each app
            for app in "${apps[@]}"; do
                echo -e "Installing $app..."
                sudo dnf install -y "$app"
                if [ $? -ne 0 ]; then
                    echo "Error installing $app"
                fi
                echo "##############################################"
            done
            
            install_redhat
        ;;
        "debian")
            echo "Detected Debian-based system. Installing apps..."
            sudo apt-get update -y && sudo apt-get upgrade -y
            if [ $? -ne 0 ]; then
                echo "Error updating package lists"
            fi
            
            # Install each app
            for app in "${apps[@]}"; do
                echo -e "Installing $app..."
                sudo apt-get install -y "$app"
                if [ $? -ne 0 ]; then
                    echo "Error installing $app"
                fi
                echo "##############################################"
            done
            
            install_debian
        ;;
        "arch")
            echo "Detected Arch-based system. Installing apps..."
            sudo pacman -Syu
            if [ $? -ne 0 ]; then
                echo "Error updating package lists"
            fi
            
            # Install each app
            for app in "${apps[@]}"; do
                echo -e "Installing $app..."
                sudo pacman -S --noconfirm "$app"
                if [ $? -ne 0 ]; then
                    echo "Error installing $app"
                fi
                echo "##############################################"
            done
            
            install_arch
        ;;
        *)
            echo "Error: Unknown distribution: $dtype" >&2
            return 1
        ;;
    esac
    echo "##############################################"
}

# Function to install apps on Debian-based systems
install_debian() {
    # Install Visual Studio Code
    echo "Installing Visual Studio Code..."
    if dpkg -s code > /dev/null 2>&1; then
        echo "Visual Studio Code is already installed."
    else
        wget "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O $HOME/Downloads/vscode.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading VSCode"
        else
            echo "Installing VSCode..."
            sudo apt install -y $HOME/Downloads/vscode.deb
            if [ $? -ne 0 ]; then
                echo "Error installing VSCode"
            else
                echo "VSCode installed successfully"
            fi
        fi
    fi
    echo "##############################################"
    
    # Install Google Chrome
    echo "Installing Google Chrome..."
    if dpkg -s google-chrome-stable > /dev/null 2>&1; then
        echo "Google Chrome is already installed."
    else
        wget "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O $HOME/Downloads/chrome.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading Chrome"
        else
            echo "Installing Chrome..."
            sudo apt install -y $HOME/Downloads/chrome.deb
            if [ $? -ne 0 ]; then
                echo "Error installing Chrome"
            else
                echo "Chrome installed successfully"
            fi
        fi
    fi
    echo "##############################################"
    
    # Install Zoom
    echo "Installing Zoom..."
    if dpkg -s zoom > /dev/null 2>&1; then
        echo "Zoom is already installed."
    else
        wget "https://zoom.us/client/latest/zoom_amd64.deb" -O $HOME/Downloads/zoom.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading Zoom"
        else
            echo "Installing Zoom..."
            sudo apt install -y $HOME/Downloads/zoom.deb
            if [ $? -ne 0 ]; then
                echo "Error installing Zoom"
            else
                echo "Zoom installed successfully"
            fi
        fi
    fi
    echo "##############################################"
}

# Function to install apps on Red Hat-based systems
install_redhat() {
    # Install Visual Studio Code
    echo "Installing Visual Studio Code..."
    if rpm -q code > /dev/null 2>&1; then
        echo "Visual Studio Code is already installed."
    else
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        if [ $? -ne 0 ]; then
            echo "Error importing VSCode key"
        else
            echo "Creating VSCode repo..."
            echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
            if [ $? -ne 0 ]; then
                echo "Error creating VSCode repo"
            else
                echo "Installing VSCode..."
                sudo dnf check-update
                sudo dnf install -y code
                if [ $? -ne 0 ]; then
                    echo "Error installing VSCode"
                else
                    echo "VSCode installed successfully"
                fi
            fi
        fi
    fi
    echo "##############################################"
    
    # Install Google Chrome
    echo "Installing Google Chrome..."
    if rpm -q google-chrome-stable > /dev/null 2>&1; then
        echo "Google Chrome is already installed."
    else
        wget "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm" -O $HOME/Downloads/google-chrome-stable_current_x86_64.rpm
        if [ $? -ne 0 ]; then
            echo "Error downloading Chrome"
        else
            echo "Installing Chrome..."
            sudo dnf install -y $HOME/Downloads/google-chrome-stable_current_x86_64.rpm
            if [ $? -ne 0 ]; then
                echo "Error installing Chrome"
            else
                echo "Chrome installed successfully"
            fi
        fi
    fi
    echo "##############################################"
    
    # Install Zoom
    echo "Installing Zoom..."
    if rpm -q zoom > /dev/null 2>&1; then
        echo "Zoom is already installed."
    else
        wget "https://zoom.us/client/latest/zoom_x86_64.rpm" -O $HOME/Downloads/zoom_x86_64.rpm
        if [ $? -ne 0 ]; then
            echo "Error downloading Zoom"
        else
            echo "Installing Zoom..."
            sudo dnf install -y $HOME/Downloads/zoom_x86_64.rpm
            if [ $? -ne 0 ]; then
                echo "Error installing Zoom"
            else
                echo "Zoom installed successfully"
            fi
        fi
    fi
    echo "##############################################"
}

# Function to install apps on Arch-based systems
install_arch() {
    # Install Yay AUR Helper
    echo "Installing Yay AUR Helper..."
    if pacman -Q yay > /dev/null 2>&1; then
        echo "Yay AUR Helper is already installed."
    else
        sudo pacman -S --needed --noconfirm base-devel git
        if [ $? -ne 0 ]; then
            echo "Error installing base-devel and git"
        else
            git clone https://aur.archlinux.org/yay.git $HOME/Downloads
            if [ $? -ne 0 ]; then
                echo "Error cloning yay repository"
            else
                cd $HOME/Downloads/yay
                makepkg -si --noconfirm
                if [ $? -ne 0 ]; then
                    echo "Error building and installing yay"
                else
                    cd $SCRIPT_DIR
                    rm -rf $HOME/Downloads/yay
                    if command -v yay &>/dev/null; then
                        echo "Yay has been successfully installed!"
                    else
                        echo "Yay installation failed. Please check the logs for more details."
                    fi
                fi
            fi
        fi
    fi
    echo "##############################################"
    
    echo "Installing Visual Studio Code..."
    yay -S --needed --noconfirm visual-studio-code-bin || echo "Failed to install Visual Studio Code."
    echo "##############################################"
    
    echo "Installing Google Chrome..."
    yay -S --needed --noconfirm google-chrome || echo "Failed to install Google Chrome."
    echo "##############################################"
    
    echo "Installing Zoom..."
    yay -S --needed --noconfirm zoom || echo "Failed to install Zoom."
    echo "##############################################"
    
}

# Function to install flatpak applications
install_flatpaks() {
    echo "Installing flatpak applications..."
    
    local apps=(
        "com.brave.Browser"
        "com.discordapp.Discord"
        "com.bitwarden.desktop"
        "com.github.jeromerobert.pdfarranger"
        "com.github.rajsolai.textsnatcher"
        "com.microsoft.Edge"
        "io.appflowy.AppFlowy"
        "com.rtosta.zapzap"
        "com.spotify.Client"
        "net.nokyan.Resources"
        "org.nickvision.tubeconverter"
        "org.pipewire.Helvum"
    )
    
    for app in "${apps[@]}"; do
        if flatpak info "$app" > /dev/null 2>&1; then
            echo "$app is already installed."
        else
            echo "Installing $app..."
            sudo flatpak install flathub "$app" -y
            if [ $? -ne 0 ]; then
                echo "Error installing $app"
            else
                echo "$app installed successfully"
            fi
        fi
    done
}

# Function to install atuin
install_atuin() {
    # Detect current shell
    CURRENT_SHELL=$(basename "$SHELL")
    
    # Determine shell config file and init command
    case $CURRENT_SHELL in
        bash)
            CONFIG_FILE="$HOME/.bashrc"
            INIT_CMD="atuin init bash"
        ;;
        fish)
            CONFIG_FILE="$HOME/.config/fish/config.fish"
            INIT_CMD="atuin init fish | source"
        ;;
        zsh)
            CONFIG_FILE="$HOME/.zshrc"
            INIT_CMD="atuin init zsh"
        ;;
        *)
            echo "Unsupported shell: $CURRENT_SHELL"
            return 1
        ;;
    esac
    
    # Ensure the config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating missing config file: $CONFIG_FILE"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        touch "$CONFIG_FILE"
    fi
    
    # Check if Atuin is installed
    if ! command -v atuin &>/dev/null; then
        echo "Installing Atuin..."
        bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
        if [ $? -ne 0 ]; then
            echo "Error installing Atuin"
            return 1
        fi
    else
        echo "Atuin already installed"
    fi
    
    # Configure Atuin for current shell if needed
    if [ "$CURRENT_SHELL" = "fish" ]; then
        # For Fish, check if Atuin is already initialized
        if ! grep -q "atuin init fish" "$CONFIG_FILE"; then
            echo "Configuring Atuin for Fish..."
            echo "atuin init fish | source" >> "$CONFIG_FILE"
            # Apply configuration immediately
            source "$CONFIG_FILE"
        else
            echo "Atuin already configured for Fish"
        fi
    else
        # For Bash/Zsh, append the init command to the config file
        if ! grep -q "atuin init $CURRENT_SHELL" "$CONFIG_FILE"; then
            echo "Configuring Atuin for $CURRENT_SHELL..."
            echo "$INIT_CMD" >> "$CONFIG_FILE"
            # Apply configuration immediately
            eval "$INIT_CMD"
        else
            echo "Atuin already configured for $CURRENT_SHELL"
        fi
    fi
    
    # Check if user needs to register
    ATUIN_CONFIG="$HOME/.local/share/atuin/config.toml"
    if [ ! -f "$ATUIN_CONFIG" ] || ! grep -q "username" "$ATUIN_CONFIG"; then
        read -p "Enter Atuin username: " ATUIN_USERNAME
        read -p "Enter Atuin email: " ATUIN_EMAIL
        
        echo "Registering Atuin account..."
        atuin register -u "$ATUIN_USERNAME" -e "$ATUIN_EMAIL"
        if [ $? -ne 0 ]; then
            echo "Registration failed. Check your credentials or network connection."
            return 1
        fi
    else
        echo "Atuin user already registered"
    fi
    
    # Import history and sync
    echo "Importing shell history..."
    atuin import auto || { echo "History import failed"; return 1; }
    
    echo "Syncing with Atuin server..."
    atuin sync || { echo "Sync failed"; return 1; }
    
    echo "Atuin setup complete for $CURRENT_SHELL!"
}

# Function to add Google DNS
add_google_dns() {
    echo "Adding Google DNS..."
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak
    if [ $? -ne 0 ]; then
        echo "Error backing up resolve.conf"
        return 1
    fi
    sudo rm /etc/resolv.conf
    if [ $? -ne 0 ]; then
        echo "Error removing resolve.conf"
        return 1
    fi
    echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee /etc/resolv.conf > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error writing nameserver to resolve.conf"
        return 1
    fi
    sudo chattr +i /etc/resolv.conf
    if [ $? -ne 0 ]; then
        echo "Error locking resolve.conf"
        return 1
    fi
    echo "Google DNS added to /etc/resolv.conf"
    echo "Restarting NetworkManager..."
    sudo systemctl restart NetworkManager
    if [ $? -ne 0 ]; then
        echo "Error restarting Network Manager"
        return 1
    fi
    echo "Done."
}

# Function to install fonts
install_fonts() {
    echo "Installing fonts..."
    mkdir -p $HOME/.fonts/
    if [ ! -d "$FONT_DIR" ]; then
        echo "Error: Font directory '$FONT_DIR' does not exist." >&2
        return 1
    fi
    cp -r "$FONT_DIR"/* $HOME/.fonts/
    if [ $? -ne 0 ]; then
        echo "Error copying fonts to user directory"
        return 1
    fi
    
    # Update font cache
    fc-cache -f -v
    if [ $? -ne 0 ]; then
        echo "Error updating font cache"
        return 1
    else
        echo "Fonts installed successfully!"
    fi
}

# Function to change language to English
change_language() {
    echo "Changing language to English..."
    if [ -f "/etc/locale.conf" ]; then
        sudo cp /etc/locale.conf /etc/locale.conf.bak
        if [ $? -ne 0 ]; then
            echo "Error backing up locale config"
            return 1
        fi
        echo "Backup of /etc/locale.conf created as /etc/locale.conf.bak"
    fi
    sudo localectl set-locale LANG=en_US.UTF-8
    sudo cp "$ADDITIONS_DIR"/lang /etc/locale.conf
    if [ $? -ne 0 ]; then
        echo "Error copying the lang file"
        return 1
    fi
    echo "Locale updated successfully!"
    source /etc/locale.conf
    if [ $? -ne 0 ]; then
        echo "Error reloading locale config"
        return 1
    fi
    echo "Locale reloaded. Current settings:"
    locale
}

# Function to set terminal theme
terminal_theme() {
    # Check if Fish is installed
    if ! command -v fish >/dev/null 2>&1; then
        echo "Error: Fish shell is required. Please install Fish and try again." >&2
        return 1
    fi
    
    # Check for curl, wget and unzip
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required. Please install curl and try again." >&2
        return 1
    fi
    
    if ! command -v wget >/dev/null 2>&1; then
        echo "Error: wget is required. Please install wget and try again." >&2
        return 1
    fi
    
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Error: unzip is required. Please install unzip and try again." >&2
        return 1
    fi
    
    CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "/usr/bin/fish" ] && [ "$CURRENT_SHELL" != "$(which fish)" ]; then
        echo "Changing default shell to Fish..."
        chsh -s "$(which fish)"
        echo "Default shell changed to Fish."
    else
        echo "Fish is already the default shell."
    fi
    
    # Install Oh My Posh
    echo "Installing Oh My Posh..."
    sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
    sudo chmod +x /usr/local/bin/oh-my-posh
    mkdir -p ~/.poshthemes
    wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O ~/.poshthemes/themes.zip
    unzip ~/.poshthemes/themes.zip -d ~/.poshthemes
    chmod u+rw ~/.poshthemes/*.json
    rm ~/.poshthemes/themes.zip
    sudo echo -e "######################################################\noh-my-posh init fish --config $HOME/.poshthemes/montys.omp.json | source" >> $HOME/.config/fish/config.fish
    bash -c  "$(wget -qO- https://git.io/vQgMr)"
}

# Function to set aliases
set_aliases() {
    CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
    SHELL_CONFIG="$HOME/.config/fish/config.fish"
    if [ "$CURRENT_SHELL" != "/usr/bin/fish" ] && [ "$CURRENT_SHELL" != "$(which fish)" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    else
        SHELL_CONFIG="$HOME/.config/fish/config.fish"
    fi
    
	cat <<EOF >> "$HOME/.config/fish/config.fish"

######################################################
# ALIASES AND SCRIPTS BY ME
######################################################
alias pingo='ping 8.8.8.8'
alias ff='fastfetch'
alias refresh='source $SHELL_CONFIG'
alias resources='flatpak run net.nokyan.Resources'
alias helvum='flatpak run org.pipewire.Helvum'
alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
alias efrc='vim $HOME/.config/fish/config.fish'
alias ebrc='vim $HOME/.bashrc'
alias terminal-theme='bash -c  "$(wget -qO- https://git.io/vQgMr)"'
EOF
    
    local dtype
    dtype=$(distribution)
    
    case "$dtype" in
        "redhat")
        	cat <<EOF >> "$HOME/.config/fish/config.fish"
alias supdate='sudo dnf update -y && sudo dnf upgrade -y && sudo dnf autoremove'
alias install='sudo dnf install'
alias remove='sudo dnf remove'
######################################################
EOF
        ;;
        "debian")
			cat <<EOF >> "$HOME/.config/fish/config.fish"
alias supdate='sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get autoremove -y'
alias install='sudo apt-get install'
alias remove='sudo apt-get remove'
######################################################
EOF
        ;;
        "arch")
			cat <<EOF >> "$HOME/.config/fish/config.fish"
alias supdate='sudo pacman -Syu'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'
######################################################
EOF
        ;;
        *)
            echo "Error: Unknown distribution: $dtype" >&2
            return 1
        ;;
    esac
    echo "Aliases set successfully!"
}

# Function to install GNOME-specific apps
install_gnome_apps() {
    echo "Installing GNOME-specific apps..."
    # Install flatpak applications
    local flatpak_apps=(
        "com.github.joseexposito.touche"
        "com.mattjakeman.ExtensionManager"
        "org.gnome.Extensions"
        "org.gnome.NetworkDisplays"
    )
    for app in "${flatpak_apps[@]}"; do
        sudo flatpak install flathub -y "$app"
        if [ $? -ne 0 ]; then
            echo "Error installing flatpak $app"
        fi
    done
    
    local apps=(
        "gnome-tweaks"
        "gnome-shell-extensions"
        "gnome-shell-extension-user-theme"
        "gnome-shell-extension-dash-to-dock"
    )
    
    local dtype COMMAND
    dtype=$(distribution)
    case "$dtype" in
        "redhat")
            COMMAND="dnf install -y"
        ;;
        "debian")
            COMMAND="apt-get install -y"
        ;;
        "arch")
            COMMAND="pacman -S --noconfirm"
        ;;
        *)
            echo "Error: Unknown distribution: $dtype" >&2
            return 1
        ;;
    esac
    for app in "${apps[@]}"; do
        sudo $COMMAND "$app"
        if [ $? -ne 0 ]; then
            echo "Error installing $app"
        fi
    done
    echo -e "The GNOME-specific apps installed successfully!"
}

# Browse Gnome Extensions to be installed
browse_gnome_extensions() {
    echo "Opening browser to browse GNOME Extensions..."
    
    local extensions=(
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
            browse_gnome_extensions
        ;;
    esac
}

# Function to install themes
install_themes() {
    local theme_names=(
        "Graphite-teal-Dark-nord"
        "Graphite-teal-Dark-nord-rimless"
        "Graphite-teal-Light-nord"
        "Graphite-teal-Light-nord-rimless"
        "Graphite-teal-nord"
        "Graphite-teal-nord-rimless"
    )
    
    echo "Please choose a theme:"
    for i in "${!theme_names[@]}"; do
        echo "$((i + 1)) - ${theme_names[$i]}"
    done
    
    read -p "Enter your choice (1-${#theme_names[@]}, press enter for default): " theme_choice
    if [[ -z "$theme_choice" ]]; then
        GTK_THEME="Graphite-teal-Dark-nord"
        SHELL_THEME="Graphite-teal-Dark-nord"
        echo "Default theme selected"
    else
        
        # Validate user choice
        if ! [[ "$theme_choice" =~ ^[0-9]+$ ]]; then
            echo "Invalid input: Please enter a number" >&2
            install_themes
            return 1
        fi
        
        
        if [[ "$theme_choice" -lt 1 || "$theme_choice" -gt "${#theme_names[@]}" ]]; then
            echo "Invalid choice. Please enter a number between 1 and ${#theme_names[@]}." >&2
            install_themes
            return 1
        fi
    fi
    
    GTK_THEME="${theme_names[$((theme_choice - 1))]}"
    SHELL_THEME="${theme_names[$((theme_choice - 1))]}"
    echo "Theme set to: $GTK_THEME"
    
    echo "Installing themes..."
    mkdir -p ~/.themes/
    if [ ! -d "$THEME_DIR" ]; then
        echo "Error: Theme directory '$THEME_DIR' does not exist." >&2
        return 1
    fi
    
    cp -r "$THEME_DIR"/* ~/.themes/
    if [ $? -ne 0 ]; then
        echo "Error copying themes"
        return 1
    fi
    
    mkdir -p $HOME/Pictures/
    cp -p "$ADDITIONS_DIR"/wallpaper.jpg $HOME/Pictures/
    if [ $? -ne 0 ]; then
        echo "Error copying wallpaper"
        return 1
    fi
    
    gsettings set org.gnome.desktop.background picture-uri "file://$HOME/Pictures/wallpaper.jpg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/Pictures/wallpaper.jpg"
    
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
    if [ $? -ne 0 ]; then
        echo "Error setting gtk theme"
        return 1
    fi
    
    gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME"
    if [ $? -ne 0 ]; then
        echo "Error setting shell theme"
        return 1
    fi
    
    # Check if the user-theme extension exists
    if gnome-extensions list | grep -q "user-theme@gnome-shell-extensions.gcampax.github.com"; then
        gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
        if [ $? -ne 0 ]; then
            echo "Error enabling gnome-extension user theme"
            return 1
        fi
    else
        echo "Warning: The user-theme extension is not installed. Please install it manually."
    fi
    
    echo "Themes installed successfully!"
}

# Function to add custom shortcuts
add_custom_shortcut() {
    add_shortcut() {
        local name="$1"
        local command="$2"
        local binding="$3"
        
        # Get the current list of custom keybindings
        local current_bindings
        current_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        
        # Find the next available custom keybinding slot
        local new_binding
        new_binding="custom$(echo "$current_bindings" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -n 1 | awk '{print $1+1}')"
        [ -z "$new_binding" ] && new_binding="custom0"
        
        # Check if a shortcut with the same name or command or binding already exists
        if [[ "$current_bindings" != "@as []" ]]; then
            local existing_bindings=$(echo "$current_bindings" | grep -o 'custom[0-9]*')
            for custom_binding in $existing_bindings; do
                local existing_name
                existing_name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ name | sed "s/'//g")
                
                local existing_command
                existing_command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ command | sed "s/'//g")
                
                local existing_binding
                existing_binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ binding | sed "s/'//g")
                
                if [[ "$existing_name" == "$name" ]]; then
                    echo "Shortcut with name '$name' already exists, skipping."
                    return 0
                    elif [[ "$existing_command" == "$command" ]]; then
                    echo "Shortcut with command '$command' already exists, skipping."
                    return 0
                    elif [[ "$existing_binding" == "$binding" ]]; then
                    echo "Shortcut with binding '$binding' already exists, skipping."
                    return 0
                fi
            done
        fi
        
        # Update the list of custom keybindings
        if [[ "$current_bindings" == "@as []" ]]; then
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/$new_binding/']"
        else
            updated_bindings=$(echo "$current_bindings" | sed "s/]$/, '\/$new_binding\/']/")
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_bindings"
        fi
        
        # Set the details for the new shortcut
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ name "$name"
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ command "$command"
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ binding "$binding"
        
        if [ $? -ne 0 ]; then
            echo "Error creating shortcut: $name"
            return 1
        fi
    }
    
    # Adding shortcuts
    add_shortcut "Resources" "flatpak run net.nokyan.Resources" "<Ctrl><Shift>Escape"
    add_shortcut "Settings" "gnome-control-center" "<Super>I"
    add_shortcut "Terminal" "gnome-terminal" "<Alt>T"
    add_shortcut "Toggle Mic" "amixer set Capture toggle" "<Alt>1"
    
    echo "Shortcuts added successfully."
}

# Function to set favorite apps in the dock
set_favorite_apps() {
    echo "Setting favorite apps in the dock..."
    
    local favorite_apps=(
        'org.gnome.Nautilus.desktop'
        'code.desktop'
        'org.mozilla.firefox.desktop'
        'com.rtosta.zapzap.desktop'
        'google-chrome.desktop'
        'com.bitwarden.desktop.desktop'
        'io.appflowy.AppFlowy.desktop'
        'com.spotify.Client.desktop'
        'com.discordapp.Discord.desktop'
    )
    
    local installed_apps=()
    
    for app in "${favorite_apps[@]}"; do
        # Extract the flatpak app id if is a flatpak app, otherwise use the desktop name.
        if [[ "$app" == *.desktop ]] && flatpak info "${app%.desktop}" > /dev/null 2>&1; then
            installed_apps+=("$app")
            elif [ -f "/usr/share/applications/$app" ] || [ -f "$HOME/.local/share/applications/$app" ]; then
            installed_apps+=("$app")
        fi
    done
    
    # Convert the array into a comma-separated string with single quotes
    local gsettings_value="['$( IFS=","; echo "${installed_apps[*]}" | sed "s/,/','/g" )']"
    
    gsettings set org.gnome.shell favorite-apps "$gsettings_value"
    
    if [ $? -ne 0 ]; then
        echo "Error setting favorite apps in the dock"
        return 1
    fi
    
    echo "Favorite apps set successfully!"
    
}

# Main execution
main() {
    if [ -z "$1" ]; then
        usage
        exit 1
    else
        case "$1" in
            "all"| "apps" | "terminal" | "gnome" | "atuin" | "flatpaks" | "dns" | "fonts" | "themes" | "lang" | "aliases" | "shortcuts")
                echo "Running installation for: $1"
            ;;
            "help" | "-h" | "--help")
                usage
                exit 1
            ;;
            "version" | "-v" | "--version")
                echo "setup.sh $VERSION"
                exit 1
            ;;
            *)
                echo -e "Error: Invalid install option ..." >&2
                echo -e "For more information, run './setup.sh help'\n"
                exit 1
            ;;
        esac
    fi
    
    
    # Backup the current timestamp_timeout value
    original_timeout=$(sudo grep '^Defaults\s\+timestamp_timeout=' /etc/sudoers)
    
    # Check if 'Defaults timestamp_timeout=-1' already exists
    if sudo grep -q '^Defaults\s\+timestamp_timeout=-1' /etc/sudoers; then
        echo "timestamp_timeout is already set to -1. No changes needed."
        elif [ -n "$original_timeout" ]; then
        # If the line exists but has a different value, modify it to -1
        sudo sed -i 's/^Defaults\s\+timestamp_timeout=.*/Defaults timestamp_timeout=-1/' /etc/sudoers
    else
        # If the line does not exist, add it
        echo "Defaults timestamp_timeout=-1" | sudo tee -a /etc/sudoers > /dev/null
    fi
    
    # Run the main function
    case "$1" in
        "all")
            add_google_dns
            change_language
            install_apps
            install_flatpaks
            install_fonts
            terminal_theme
            install_atuin
            set_aliases
            if [[ $XDG_CURRENT_DESKTOP == *"GNOME"* || $DESKTOP_SESSION == *"gnome"* ]]; then
                install_gnome_apps
                browse_gnome_extensions
                add_custom_shortcut
                set_favorite_apps
                install_themes
            fi
            
            # Restore the original timeout value after running the main code
            if [ -n "$original_timeout" ]; then
                # Restore the original value if it existed
                sudo sed -i "s/^Defaults\s\+timestamp_timeout=.*/$original_timeout/" /etc/sudoers
            else
                # If no original line existed, remove the added line
                sudo sed -i '/^Defaults\s\+timestamp_timeout=-1/d' /etc/sudoers
            fi
            
            echo -e "Installation complete. Reboot your system to apply changes.\n"
            echo -e "##############################################\n"
            read -p "Do you want to reboot now? (Y/N): " reboot_choice
            case "$reboot_choice" in
                [Yy]*)
                    sudo reboot
                ;;
                *)
                    echo "Reboot skipped. Please reboot manually to apply changes."
                ;;
            esac
        ;;
        "shortcuts")
            add_custom_shortcut
        ;;
        "terminal")
            terminal_theme
        ;;
        "gnome")
            install_gnome_apps
            browse_gnome_extensions
            add_custom_shortcut
            set_favorite_apps
            install_themes
        ;;
        "apps")
            install_apps
            install_flatpaks
            if [[ $XDG_CURRENT_DESKTOP == *"GNOME"* || $DESKTOP_SESSION == *"gnome"* ]]; then
                install_gnome_apps
            fi
        ;;
        "atuin")
            install_atuin
        ;;
        "flatpaks")
            install_flatpaks
        ;;
        "dns")
            add_google_dns
        ;;
        "fonts")
            install_fonts
        ;;
        "themes")
            install_themes
        ;;
        "lang")
            change_language
        ;;
        "aliases")
            set_aliases
        ;;
        *)
            echo "Error: Invalid install option..." >&2
            exit 1
        ;;
    esac
    
    # Restore the original timeout value after running the main code
    if [ -n "$original_timeout" ]; then
        # Restore the original value if it existed
        sudo sed -i "s/^Defaults\s\+timestamp_timeout=.*/$original_timeout/" /etc/sudoers
    else
        # If no original line existed, remove the added line
        sudo sed -i '/^Defaults\s\+timestamp_timeout=-1/d' /etc/sudoers
    fi
    
    echo -e "Installation complete.\n"
}

# Run the main function
main "$@"
