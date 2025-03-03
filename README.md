# Linux System Setup Script

## Overview

This script automates the initial setup and configuration of a Linux system, streamlining the process of installing common applications, configuring system settings, and customizing the desktop environment. It supports multiple distributions (Fedora-based, Debian-based, and Arch-based) and provides options for installing a wide range of tools and customizing the user experience.

## Features

- **Distribution Detection:** Automatically identifies the Linux distribution based on `/etc/os-release`.
- **Application Installation:**
  - Installs a set of essential applications (git, nano, btop, etc.).
  - Installs distribution-specific applications (VS Code, Chrome, Zoom).
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
- **Modular Design:** The script is organized into functions for easy maintenance and extensibility.
- **Error Handling:** Includes basic error handling and provides informative messages to the user.
- **Interactive Prompts:** Asks the user for confirmation and input during certain steps.

## Requirements

- A Linux system (Fedora-based, Debian-based, or Arch-based).
- Internet connection.
- (Optional) GNOME desktop environment for certain GNOME-specific features.

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

    Replace `<option>` with one of the following installation options:

    - `all`: Run all installation steps.
    - `apps`: Install basic applications.
    - `terminal`: Configure terminal settings (Fish, Oh My Posh).
    - `gnome`: Install GNOME-specific applications and settings.
    - `atuin`: Install and configure Atuin.
    - `flatpaks`: Install flatpak applications.
    - `dns`: Configure Google DNS.
    - `fonts`: Install fonts.
    - `themes`: Install GNOME themes.
    - `lang`: Configure system language to English.
    - `aliases`: Set aliases in shell configuration.
    - `shortcuts`: Configure custom keyboard shortcuts.
    - `help`: Display this help message.

    **Some Examples:**

    ```bash
    ./setup.sh all
    ./setup.sh help
    ./setup.sh apps terminal
    ```

## Additions Directory

The `additions` directory should contain the following files:

- **`/additions/fonts/`:** This directory should contain `.ttf` or `.otf` font files.
- **`/additions/lang`:** `lang` file that changes the default language settings
- **`/additions/themes`:** Themes directory

## Contributing

Contributions to this project are welcome! Feel free to submit bug reports, feature requests, or pull requests.
