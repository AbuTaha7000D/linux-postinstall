
# Modular Linux Postinstall Scripts

This directory contains modular scripts for post-installation setup on Linux systems. Each script performs a single, well-defined task and is compatible with Fedora, Debian, and CachyOS (and derivatives).


## Available Scripts

- `add_custom_shortcut.sh` — Add custom GNOME keyboard shortcuts
- `add_google_dns.sh` — Add Google DNS to your system
- `browse_gnome_extensions.sh` — Open recommended GNOME extensions in your browser
- `change_language.sh` — Set system language (English/Arabic)
- `gnome_themes.sh` — User-driven GNOME theme selection and application
- `icons_and_cursors.sh` — Set up user icons and cursor themes, copy icons, set cursor, set icon theme to Adwaita, and add ~/Github to the sidebar
- `install_apps.sh` — Install system, Flatpak, and AUR (Arch) applications, including Chrome and VS Code
- `install_atuin.sh` — Install and configure Atuin shell history manager
- `install_fonts.sh` — Install user fonts from the additions/fonts directory
- `set_aliases.sh` — Overwrite .bashrc with dynamic aliases (with backup)
- `set_favorite_apps.sh` — Set favorite apps in the GNOME dock
- `set_wallpaper.sh` — Set GNOME wallpaper from additions/wallpaper.jpg
- `terminal_themes.sh` — Install and configure Oh My Posh for Bash
- `utils.sh` — Shared utility functions (distro detection, etc.)

## Usage

Run any script directly, for example:

```bash
bash scripts/install_apps.sh
```

Or chain them in your main setup script for a full post-install experience:

```bash
bash scripts/change_language.sh
bash scripts/install_apps.sh
bash scripts/install_fonts.sh
bash scripts/gnome_themes.sh
bash scripts/set_wallpaper.sh
# ...etc.
```

**Note:** Some scripts (e.g., `set_aliases.sh`) will overwrite your `.bashrc` but create a backup as `.bashrc.bak`.

All scripts are designed to be idempotent and safe for repeated use. GNOME-specific scripts will skip execution if GNOME is not detected.
