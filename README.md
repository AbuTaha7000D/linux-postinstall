# Linux System Setup Script

## Overview

This script automates the initial setup and configuration of a Linux system, streamlining the process of installing common applications, configuring system settings, and customizing the desktop environment. It supports multiple distributions (Fedora-based, Debian-based, and Arch-based) and provides options for installing a wide range of tools and customizing the user experience.

## Features

- **Distribution Detection:** Automatically identifies the Linux distribution based on `/etc/os-release`.
- **Application Installation:**
  - Installs a set of essential applications (git, nano, btop, etc.).
  - Installs distribution-specific applications (VS Code, Chrome).
  - Installs flatpak applications (Brave Browser, Discord, etc.).
- **System Configuration:**
  - Configures Google DNS for improved DNS resolution.
  - Sets the system language to English (US).
  - Installs fonts for improved visual appearance.
  - Configures terminal (Fish shell and Oh My Posh).
  - Sets up aliases for common commands.
  - Configures custom keyboard shortcuts.
  - Sets favorite applications in the GNOME Shell dock (if applicable).
  - Installs GNOME themes for a customized desktop experience (if applicable).
  - Sets up user icons and cursor themes, with Adwaita fallback and sidebar integration (if applicable).
- **Modular Design:** The script is organized into functions for easy maintenance and extensibility.
- **Error Handling:** Includes basic error handling and provides informative messages to the user.
- **Interactive Prompts:** Asks the user for confirmation and input during certain steps.

## Requirements

- A Linux system (Fedora-based, Debian-based, or Arch-based).
- Internet connection.
- GNOME desktop environment for certain GNOME-specific features.

## Usage

1.  **Download the script:**

    ```bash
    git clone https://github.com/AbuTaha7000D/linux-postinstall.git
    cd linux-postinstall
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x setup.sh
    ```

3.  **Run the script:**

    ```bash
    ./setup.sh <option>
    ```


  Replace `<option>` with one of the following installation options (each runs a modular script):

  - `all`                   : Run all setup steps (recommended)
  - `add_custom_shortcut`   : Add custom GNOME keyboard shortcuts
  - `add_google_dns`        : Add Google DNS to your system
  - `gnome_extensions`      : Open recommended GNOME extensions in your browser
  - `change_language`       : Set system language (English/Arabic)
  - `install_apps`          : Install system, Flatpak, and AUR applications
  - `install_atuin`         : Install and configure Atuin shell history manager
  - `install_fonts`         : Install user fonts from additions/fonts
  - `set_aliases`           : Overwrite .bashrc with dynamic aliases (with backup)
  - `set_favorite_apps`     : Set favorite apps in the GNOME dock
  - `themes`                : Install and configure icons, cursors, terminal, and GNOME themes
  - `help`                  : Show this help message
  - `version`               : Show version

  **Some Examples:**

  ```bash
  ./setup.sh all
  ./setup.sh help
  ./setup.sh install_apps
  ./setup.sh themes
  ```

    **Some Examples:**

    ```bash
    ./setup.sh all
    ./setup.sh help
    ./setup.sh apps terminal
    ```


## Sudo Password Prompt Suppression

To avoid being prompted for your password multiple times, the script temporarily sets `sudo`'s `timestamp_timeout` to `-1` for the duration of the setup. This is reverted at the end if possible.

## Additions Directory

The `additions` directory should contain the following files:

- **`/additions/fonts/`:** This directory should contain `.ttf` or `.otf` font files.
- **`/additions/lang`:** `lang` file that changes the default language settings
- **`/additions/themes`:** Themes directory

## Contributing

Contributions to this project are welcome! Feel free to submit bug reports, feature requests, or pull requests.
