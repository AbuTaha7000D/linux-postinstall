
# Modular Linux Postinstall Scripts

This directory contains the setup modules invoked by the `setup` launcher. Each module performs a single, well-defined task and is compatible with Fedora, Debian, and CachyOS (and derivatives).
Debian-family support requires Debian 13 (trixie) or newer, or Ubuntu 25.10 or newer; older releases such as Debian 12 and Ubuntu 24.04 are not supported because `fastfetch` is not in their archives.

Shared helpers (distribution/family detection, desktop-environment detection, `run`/`run_root` dry-run wrappers) live in `../lib/common.sh`.


## Available Scripts

- `add_custom_shortcut.sh` — Add custom GNOME keyboard shortcuts
- `change_language.sh` — Set system language (English/Arabic, 10-second interactive prompt)
- `dev.sh` — Development environment module (placeholder)
- `gnome_extensions.sh` — Open recommended GNOME extensions in your browser
- `gnome_themes.sh` — User-driven GNOME theme selection and application
- `icons_and_cursors.sh` — Set up user icons and cursor themes, copy icons, set cursor, set icon theme to Adwaita, and add ~/Github to the sidebar
- `install_apps.sh` — Install system, Flatpak, and AUR (Arch) applications, including Chrome, VS Code, and the Starship prompt (official installer)
- `install_atuin.sh` — Install and configure Atuin shell history manager
- `install_fonts.sh` — Install user fonts from the additions/fonts directory
- `set_aliases.sh` — Write the managed alias block (`# >>> linux-postinstall aliases >>>` … `# <<< linux-postinstall aliases <<<`) to Bash (and Zsh/Fish when present)
- `set_favorite_apps.sh` — Set favorite apps in the GNOME dock
- `set_wallpaper.sh` — Set GNOME wallpaper from additions/wallpaper.jpg
- `terminal_themes.sh` — Configure shell startup: `chsh` to Bash, Atuin, and Starship init for Bash/Zsh/Fish

## Usage

Modules are meant to be run through the launcher:

```bash
./setup install
./setup packages
./setup --dry-run install
```

Running a module directly also works, for example:

```bash
bash modules/install_apps.sh
```

**Note:** The aliases module does not overwrite `.bashrc`; it replaces only its own managed block, leaving the rest of your shell configuration untouched.

All modules are designed to be idempotent and safe for repeated use. GNOME-specific modules will skip execution if GNOME is not detected. `--dry-run` (via `./setup`) prints planned commands and writes nothing.
