#!/bin/bash

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
            *)
                if [ -n "$ID_LIKE" ]; then
                    case "$ID_LIKE" in
                        *fedora*|*rhel*|*centos*)
                            dtype="redhat"
                        ;;
                        *ubuntu*|*debian*)
                            dtype="debian"
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
    
    case "$dtype" in
        "redhat")
            install_redhat
        ;;
        "debian")
            install_debian
        ;;
        *)
            echo "Error: Unknown distribution: $dtype" >&2
            exit 1
        ;;
    esac
    install_flatpaks
    install_atuin
}

# Function to install apps on Debian-based systems
install_debian() {
    echo "Detected Debian-based system. Installing apps..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    if [ $? -ne 0 ]; then
        echo "Error updating package lists"
    fi
    
    # List of apps to install
    apps=(
        git
        nano
        btop
        sed
        gnome-tweaks
        htop
        fzf
        gnome-shell-extension-dash-to-dock
        gnome-shell-extensions
        gnome-shell-extension-user-theme
        fastfetch
        bat
        neovim
        python3
        python3-pip
        nodejs
        gpg
        wget
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
        gpaste
        jupyter-notebook
    )
    
    # Install each app
    for app in "${apps[@]}"; do
        echo -e "Installing $app..."
        sudo dnf install -y "$app"
        if [ $? -ne 0 ]; then
            echo "Error installing $app"
        fi
    done
    echo "##############################################"
    
    # Install Visual Studio Code
    echo "Installing Visual Studio Code..."
    if dpkg -s code > /dev/null 2>&1; then
        echo "Visual Studio Code is already installed."
    else
        wget "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O ~/Downloads/vscode.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading VSCode"
        else
            echo "Installing VSCode..."
            sudo apt install -y ~/Downloads/vscode.deb
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
        wget "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O ~/Downloads/chrome.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading Chrome"
        else
            echo "Installing Chrome..."
            sudo apt install -y ~/Downloads/chrome.deb
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
        wget "https://zoom.us/client/latest/zoom_amd64.deb" -O ~/Downloads/zoom.deb
        if [ $? -ne 0 ]; then
            echo "Error downloading Zoom"
        else
            echo "Installing Zoom..."
            sudo apt install -y ~/Downloads/zoom.deb
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
    echo "Detected Red Hat-based system. Installing apps..."
    sudo dnf update -y && sudo dnf upgrade -y
    if [ $? -ne 0 ]; then
        echo "Error updating package lists"
    fi
    
    # List of apps to install
    apps=(
        git
        nano
        btop
        sed
        gnome-tweaks
        htop
        fzf
        gnome-shell-extension-dash-to-dock
        gnome-shell-extensions
        gnome-shell-extension-user-theme
        fastfetch
        bat
        neovim
        python3
        python3-pip
        nodejs
        gpg
        wget
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
        gpaste
        jupyter-notebook
    )
    
    # Install each app
    for app in "${apps[@]}"; do
        echo -e "Installing $app..."
        sudo dnf install -y "$app"
        if [ $? -ne 0 ]; then
            echo "Error installing $app"
        fi
    done
    echo "##############################################"
    
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
        wget "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm" -O ~/Downloads/google-chrome-stable_current_x86_64.rpm
        if [ $? -ne 0 ]; then
            echo "Error downloading Chrome"
        else
            echo "Installing Chrome..."
            sudo dnf install -y ~/Downloads/google-chrome-stable_current_x86_64.rpm
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
        wget "https://zoom.us/client/latest/zoom_x86_64.rpm" -O ~/Downloads/zoom_x86_64.rpm
        if [ $? -ne 0 ]; then
            echo "Error downloading Zoom"
        else
            echo "Installing Zoom..."
            sudo dnf install -y ~/Downloads/zoom_x86_64.rpm
            if [ $? -ne 0 ]; then
                echo "Error installing Zoom"
            else
                echo "Zoom installed successfully"
            fi
        fi
    fi
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
        "com.github.joseexposito.touche"
        "com.github.rajsolai.textsnatcher"
        "com.mattjakeman.ExtensionManager"
        "com.microsoft.Edge"
        "io.appflowy.AppFlowy"
        "com.rtosta.zapzap"
        "com.spotify.Client"
        "net.nokyan.Resources"
        "org.gnome.Extensions"
        "org.gnome.NetworkDisplays"
        "org.nickvision.tubeconverter"
        "org.pipewire.Helvum"
    )
    
    for app in "${apps[@]}"; do
        if flatpak info "$app" > /dev/null 2>&1; then
            echo "$app is already installed."
        else
            install_flatpak_app "$app"
        fi
    done
}

# Function to install a single flatpak application
install_flatpak_app() {
    local app_id="$1"
    echo "Installing $app_id..."
    sudo flatpak install flathub "$app_id" -y
    if [ $? -ne 0 ]; then
        echo "Error installing $app_id"
    else
        echo "$app_id installed successfully"
    fi
}

# Function to install atuin
install_atuin() {
    read -p "Enter your Atuin username: " ATUIN_USERNAME
    read -p "Enter your Atuin email: " ATUIN_EMAIL
    
    echo "Installing atuin"
    bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
    if [ $? -ne 0 ]; then
        echo "Error downloading and installing atuin"
        return 1
    fi
    atuin register -u "$ATUIN_USERNAME" -e "$ATUIN_EMAIL"
    if [ $? -ne 0 ]; then
        echo "Error registering atuin"
        return 1
    fi
    atuin import auto
    if [ $? -ne 0 ]; then
        echo "Error importing atuin"
        return 1
    fi
    atuin sync
    if [ $? -ne 0 ]; then
        echo "Error syncing atuin"
        return 1
    fi
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
    mkdir -p ~/.fonts/
    if [ ! -d "./additions/fonts/" ]; then
        echo "Error: Font directory './additions/fonts/' does not exist." >&2
        return 1
    fi
    cp -r ./additions/fonts/* ~/.fonts/
    if [ $? -ne 0 ]; then
        echo "Error copying the fonts"
        return 1
    fi
    fc-cache -f -v
    if [ $? -ne 0 ]; then
        echo "Error updating font cache"
        return 1
    fi
    echo "Fonts installed successfully!"
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
    if [ ! -d "./additions/themes/" ]; then
        echo "Error: Theme directory './additions/themes/' does not exist." >&2
        return 1
    fi
    
    cp -r ./additions/themes/* ~/.themes/
    if [ $? -ne 0 ]; then
        echo "Error copying themes"
        return 1
    fi
    
    CURRENT_DIR=$(pwd)
    gsettings set org.gnome.desktop.background picture-uri "file://$CURRENT_DIR/additions/wallpaper.jpg"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$CURRENT_DIR/additions/wallpaper.jpg"
    
    gsettings set org.gnome.desktop.interface gtk-theme $GTK_THEME
    if [ $? -ne 0 ]; then
        echo "Error setting gtk theme"
        return 1
    fi
    
    gsettings set org.gnome.shell.extensions.user-theme name $SHELL_THEME
    if [ $? -ne 0 ]; then
        echo "Error setting shell theme"
        return 1
    fi
    
    gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
    if [ $? -ne 0 ]; then
        echo "Error enabling gnome-extension user theme"
        return 1
    fi
    echo "Themes installed successfully!"
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
    sudo cp ./additions/lang /etc/locale.conf
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

# Function to set aliases
set_aliases() {
    local dtype
    dtype=$(distribution)
    case "$dtype" in
        "redhat")
            grep -qxF "alias supdate='sudo dnf update -y && sudo dnf upgrade -y && sudo dnf autoremove'" ./additions/add_to_bashrc || \
            sed -i "5ialias supdate='sudo dnf update -y && sudo dnf upgrade -y && sudo dnf autoremove'" ./additions/add_to_bashrc
            
            grep -qxF "alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg; sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg'" ./additions/add_to_bashrc || \
            sed -i "5ialias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg; sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg'" ./additions/add_to_bashrc
            
            if [ $? -ne 0 ]; then
                echo "Error adding alias to file"
                return 1
            fi
            sed -i '2r ./additions/add_to_bashrc' ~/.bashrc
            if [ $? -ne 0 ]; then
                echo "Error adding alias to bashrc"
                return 1
            fi
        ;;
        "debian")
            grep -qxF "alias supdate='sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get autoremove'" ./additions/add_to_bashrc || \
            sed -i "5ialias supdate='sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get autoremove'" ./additions/add_to_bashrc
            
            grep -qxF "alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'" ./additions/add_to_bashrc || \
            sed -i "5ialias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'" ./additions/add_to_bashrc
            
            if [ $? -ne 0 ]; then
                echo "Error adding alias to file"
                return 1
            fi
            sed -i '2r ./additions/add_to_bashrc' ~/.bashrc
            if [ $? -ne 0 ]; then
                echo "Error adding alias to bashrc"
                return 1
            fi
        ;;
        *)
            echo "Error: Unknown distribution: $dtype" >&2
            return 1
        ;;
    esac
    echo "Aliases set successfully!"
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
    }
    
    # Adding shortcuts
    add_shortcut "Resources" "flatpak run net.nokyan.Resources" "<Ctrl><Shift><Escape>"
    add_shortcut "Settings" "gnome-control-center" "<Super>I"
    add_shortcut "Terminal" "gnome-terminal" "<Alt>T"
    
    echo "Shortcuts added successfully."
}

# Function to set favorite apps in the dock
set_favorite_apps() {
    echo "Setting favorite apps in the dock..."
    
    local favorite_apps=(
        'org.gnome.Nautilus.desktop'
        'code.desktop'
        'com.brave.Browser.desktop'
        'com.rtosta.zapzap.desktop'
        'google-chrome.desktop'
        'io.appflowy.AppFlowy.desktop'
        'com.bitwarden.desktop'
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
        echo "Error: Please specify an install option. Options: 'all', 'apps', 'atuin', 'flatpaks', 'dns', 'fonts', 'themes', 'lang', 'aliases', 'shortcuts'" >&2
        exit 1
    fi
    
    # Backup the current timestamp_timeout value
    original_timeout=$(sudo grep 'timestamp_timeout' /etc/sudoers)
    
    # Set timestamp_timeout to -1 (so it asks for the password only once per session)
    sudo sed -i '/Defaults.*timestamp_timeout/ c\Defaults timestamp_timeout=-1' /etc/sudoers
    
    # Run the main function
    sudo sed -i '/Defaults.*timestamp_timeout/ c\Defaults timestamp_timeout=-1' /etc/sudoers
    case "$1" in
        "all")
            add_google_dns
            install_apps
            install_fonts
            install_themes
            change_language
            set_aliases
            add_custom_shortcut
            set_favorite_apps
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
        "apps")
            install_apps
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
            echo "Error: Invalid install option: $1. Options: 'all', 'apps', 'atuin', 'flatpaks', 'dns', 'fonts', 'themes', 'lang', 'aliases', 'shortcuts'" >&2
            exit 1
        ;;
    esac
    
    # Restore the original timestamp_timeout value if it was set
    if [ -n "$original_timeout" ]; then
        sudo sed -i "s|Defaults timestamp_timeout=-1|$original_timeout|" /etc/sudoers
    else
        # If no timestamp_timeout line was found, remove the modification
        sudo sed -i '/Defaults.*timestamp_timeout/ d' /etc/sudoers
    fi
    echo -e "Installation complete.\n"
}

# Run the main function
main "$@"
