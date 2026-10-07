# Linux System Setup Script

## Overview

This script automates the initial setup and configuration of a Linux system, streamlining the process of installing common applications, configuring system settings, and customizing the desktop environment. It supports multiple distributions (Fedora-based, Debian-based, and Arch-based) and provides options for installing a wide range of tools and customizing the user experience.

<p align="center">
  <img src="https://img.shields.io/github/license/abutaha7000d/linux-postinstall?label=license" alt="License"/>
  <img src="https://img.shields.io/badge/release-v2.1.1-blue" alt="Release"/>
  <img src="https://img.shields.io/github/repo-size/abutaha7000d/linux-postinstall?label=code%20size" alt="Code Size"/>
</p>

## Features

- **Distribution Detection:** Automatically identifies the Linux distribution based on `/etc/os-release`.
- **Application Installation:**
  - Installs a set of essential applications (git, nano, btop, etc.).
  - Installs distribution-specific applications (VS Code, Chrome).
  - Installs flatpak applications (Brave Browser, Discord, etc.).
- **System Configuration:**
  - Sets the system language to English (US) or Arabic, with a 10-second interactive prompt.
  - Installs fonts for improved visual appearance.
  - Configures the terminal (Atuin and the Starship prompt for Bash, Zsh, and Fish).
  - Sets up aliases for common commands as a managed block in your shell configuration.
  - Configures custom keyboard shortcuts.
  - Sets favorite applications in the GNOME Shell dock (if applicable).
  - Installs GNOME themes for a customized desktop experience (if applicable).
  - Sets up user icons and cursor themes, with Adwaita fallback and sidebar integration (if applicable).
- **Modular Design:** Setup operations live in `modules/`, shared helpers in `lib/common.sh`, and the `setup` launcher owns the CLI and step order.
- **Error Handling:** Required failures stop the run and name the failed step; no success is reported after a failure.
- **Interactive Prompts:** Asks the user for confirmation and input during certain steps (skipped when run non-interactively).
- **Dry Run:** `--dry-run` prints the commands that would run without executing them.

## Requirements

- A Linux system (Fedora-based, Debian-based, or Arch-based).
- Internet connection.
- GNOME desktop environment for certain GNOME-specific features.

Debian-family support expects Debian 13 (trixie) or newer, or Ubuntu 25.10 or newer. Older releases such as Debian 12 (bookworm) and Ubuntu 24.04 (noble) are not supported, because `fastfetch`, which is part of the package list, is not in their archives.

## Usage

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/AbuTaha7000D/linux-postinstall.git
    cd linux-postinstall
    ```

2.  **Run the setup:**

    ```bash
    ./setup [--dry-run] [command]
    ```

    With no arguments, `install` runs (the same code path as `./setup install`).

    Commands:

    - `install`      : Full setup in fixed order: packages, language, fonts, aliases, terminal, dev, then the GNOME group (wallpaper, gnome_themes, icons_and_cursors, favorites, shortcuts, extensions) when the desktop is GNOME
    - `packages`     : Install system, Flatpak, and vendor applications
    - `language`     : Set system language (English/Arabic, 10-second prompt)
    - `fonts`        : Install user fonts from additions/fonts
    - `aliases`      : Write the managed alias block to Bash (and Zsh/Fish when present)
    - `terminal`     : Configure shell startup (chsh, Atuin, Starship init)
    - `dev`          : Development environment module (placeholder)
    - `gnome`        : Run the GNOME group (wallpaper, themes, icons/cursors, favorites, shortcuts, extensions)
    - `shortcuts`    : Add custom GNOME keyboard shortcuts
    - `favorites`    : Set favorite apps in the GNOME dock
    - `extensions`   : Open recommended GNOME extensions in your browser
    - `help`         : Show help
    - `version`      : Show version

    Options:

    - `--dry-run`    : Print the commands that would run; execute nothing (usable in any position)
    - `-h`, `--help` : Show help
    - `-v`, `--version` : Show version

    **Examples:**

    ```bash
    ./setup install
    ./setup --dry-run
    ./setup packages
    ./setup language
    ./setup gnome
    ./setup aliases
    ```

## Additions Directory

The `additions` directory should contain the following:

- **`additions/fonts/`** — Place your `.ttf` or `.otf` font files here.
- **`additions/icons/`** — Place any custom icon files (e.g., `folder-github.svg`) here.
- **`additions/shell_conf`** — Legacy reference for the managed alias block (not applied directly).
- **`additions/wallpaper.jpg`** — Your preferred wallpaper image.

## Contributing

Contributions to this project are welcome! Feel free to submit bug reports, feature requests, or pull requests.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
