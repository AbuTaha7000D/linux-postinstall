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
  - Sets the system language to English (US) or Arabic, with a 5-second interactive prompt.
  - Installs fonts for improved visual appearance.
  - Configures the terminal: selects your default shell (Bash, Zsh, or Fish), installs it if missing (falling back to Bash when the install cannot be verified), and configures Atuin and Starship for that shell.
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
    - `language`     : Set system language (English/Arabic, 5-second prompt; verifies the locale is installed before applying)
    - `fonts`        : Install user fonts from assets/fonts
    - `aliases`      : Write the managed alias block to Bash (and Zsh/Fish when present)
    - `terminal`     : Select the default shell (Bash/Zsh/Fish), install it if missing (falling back to Bash if the install cannot be verified), configure Atuin and Starship for it, and set it as the default shell (chsh)
    - `dev`          : Install the development environment (system toolchain including the OpenSSH client and server, VS Code, DBeaver, mise-managed Python 3.13, JupyterLab, Codex, OpenCode) and write the managed dev shell configuration block
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

## Development environment

`./setup dev` is fully standalone: it works without running `./setup packages` first, reruns are safe (every install stage skips what is already installed and verifies what it installs), sudo is used only through the same lazy `ensure_sudo`/`run_root` path as the rest of setup, and `--dry-run` only prints what would run. It installs the system development toolchain (including the OpenSSH client and server), VS Code, DBeaver, mise with Python 3.13, JupyterLab, Codex, OpenCode, and a managed dev shell block (PATH and mise activation).

The SSH server is installed but deliberately never enabled or started by the script — no sshd configuration, firewall, or authentication changes are made, and sign-in remains manual. To activate it:

- Fedora/Arch: `sudo systemctl enable --now sshd`
- Debian/Ubuntu: `sudo systemctl enable --now ssh`

After `./setup dev`, open a new shell (or run `exec bash`) so `~/.local/bin` and mise activation are picked up.

## Assets and Configuration

Static assets live under `assets/`, and the editable alias data lives under `config/aliases/`:

- **`assets/fonts/`** — Place your `.ttf` or `.otf` font files here.
- **`assets/icons/`** — Place any custom icon files (e.g., `folder-github.svg`) here.
- **`assets/wallpaper/wallpaper.jpg`** — Your preferred wallpaper image.
- **`config/aliases/`** — Alias definitions applied by `./setup aliases`: one file per shell (`bash`, `zsh`, `fish`) plus shared `distro/` fragments (`debian`, `redhat`, `arch`); the selected shell file and matching distro fragment are concatenated into the managed block. Existing rc files keep their permission mode, ACLs, extended attributes, and SELinux context; newly created files are owner-only (`0600`).

## Contributing

Contributions to this project are welcome! Feel free to submit bug reports, feature requests, or pull requests.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
