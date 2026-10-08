
# Modular Linux Postinstall Scripts

This directory contains the setup modules invoked by the `setup` launcher. Each module performs a single, well-defined task and is compatible with Fedora, Debian, and CachyOS (and derivatives).
Debian-family support requires Debian 13 (trixie) or newer, or Ubuntu 25.10 or newer; older releases such as Debian 12 and Ubuntu 24.04 are not supported because `fastfetch` is not in their archives.

Shared helpers (distribution/family detection, desktop-environment detection, `run`/`run_root` dry-run wrappers) live in `../lib/common.sh`.


## Available Scripts

- `add_custom_shortcut.sh` — Add custom GNOME keyboard shortcuts
- `change_language.sh` — Set system language (English/Arabic, 10-second interactive prompt)
- `dev.sh` — Development environment: install missing system development packages (binary-presence matrix, OpenSSH client and server included) in a single family-specific transaction with post-verification, then VS Code (official vendor builds on Fedora/Debian, AUR on Arch), DBeaver via Flatpak, mise with Python 3.13, JupyterLab via pipx, Codex into the npm user prefix, and the OpenCode CLI via the official installer; finally the Debian `fdfind` → `fd` symlink in `~/.local/bin` and the managed dev block (`# >>> linux-postinstall dev >>>` … `# <<< linux-postinstall dev <<<`) with PATH and mise activation for Bash (and Zsh/Fish when present), ending with reload guidance. Standalone (no `packages` prerequisite) and idempotent; the SSH server is installed but never enabled or started
- `gnome_extensions.sh` — Open recommended GNOME extensions in your browser
- `gnome_themes.sh` — User-driven GNOME theme selection and application
- `icons_and_cursors.sh` — Set up user icons and cursor themes, copy icons, set cursor, set icon theme to Adwaita, and add ~/Github to the sidebar
- `install_apps.sh` — Install system, Flatpak, and AUR (Arch) applications, including Chrome and VS Code
- `install_fonts.sh` — Install user fonts from the additions/fonts directory
- `set_aliases.sh` — Write the managed alias block (`# >>> linux-postinstall aliases >>>` … `# <<< linux-postinstall aliases <<<`) to Bash (and Zsh/Fish when present)
- `set_favorite_apps.sh` — Set favorite apps in the GNOME dock
- `set_wallpaper.sh` — Set GNOME wallpaper from additions/wallpaper.jpg
- `terminal_themes.sh` — Terminal stack: select the default shell, install and verify the selected shell when missing (falling back to Bash when it cannot be verified), install Atuin and Starship when missing, configure the selected shell, and change the default shell with `chsh` (non-interactive, via `run_root`)

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
