
# Modular Linux Postinstall Scripts

This directory contains the setup modules invoked by the `setup` launcher. Each module performs a single, well-defined task. The project targets Fedora/Nobara, Debian/Ubuntu/Linux Mint, and Arch/CachyOS; it does not claim compatibility with every derivative.
Debian-family support requires Debian 13 (trixie) or newer, Ubuntu 24.04 LTS (noble) or newer, or a Linux Mint release based on a supported Ubuntu version. `fastfetch` is omitted from the shared Debian-family package list because Ubuntu 24.04 does not provide it. On Arch and CachyOS, the packages and dev modules bootstrap the `yay` AUR helper through the shared `ensure_yay` helper when VS Code or Chrome is missing and `yay` is not installed. Chrome and VS Code vendor installers support x86_64 only.

Shared helpers (distribution/family detection, desktop-environment detection, `run`/`run_root` dry-run wrappers, and the `ensure_yay` AUR-helper bootstrap) live in `../lib/common.sh`.


## Available Scripts

- `add_custom_shortcut.sh` — Add the custom GNOME keyboard shortcuts listed in `config/shortcuts.txt` (name, keybinding, command; tab-separated), allocating the next free `custom<N>` path and skipping entries whose name, command, or binding already exist
- `change_language.sh` — Set system language (English/Arabic, 5-second interactive prompt; verifies the selected locale is available via `locale -a` before any change, backs up the locale file, and rewrites only `LANG`/`LC_ALL` through `run_root`)
- `dev.sh` — Development environment: install missing system development packages (binary-presence matrix, OpenSSH client and server included) in a single family-specific transaction with post-verification, then VS Code (official vendor builds on Fedora/Debian, AUR on Arch with the shared `ensure_yay` bootstrap), DBeaver via Flatpak, mise with Python 3.13, JupyterLab via pipx, Codex into the npm user prefix, and the OpenCode CLI via the official installer; finally the Debian `fdfind` → `fd` symlink in `~/.local/bin` and the managed dev block (`# >>> linux-postinstall dev >>>` … `# <<< linux-postinstall dev <<<`) with PATH and mise activation for Bash (and Zsh/Fish when present), ending with reload guidance. Standalone (no `packages` prerequisite) and idempotent; the SSH server is installed but never enabled or started
- `gnome_extensions.sh` — Install and enable the extensions listed in `config/gnome-extensions.txt`, fetching a release compatible with the running GNOME Shell from extensions.gnome.org
- `install_apps.sh` — Install missing native packages (lists under `config/packages/`), Flatpak apps (`config/flatpak.txt`; detection checks the user and system scopes, installation uses the existing system scope), and AUR (Arch) applications, including Chrome and VS Code, bootstrapping `yay` through the shared `ensure_yay` helper when it is missing; native packages are detected with the family package manager, and cross-source duplicates (native Thunderbird/OBS) are skipped. A missing required list file is fatal; comment-only lists are skipped
- `install_fonts.sh` — Install user fonts from the assets/fonts directory
- `set_aliases.sh` — Write the managed alias block (`# >>> linux-postinstall aliases >>>` … `# <<< linux-postinstall aliases <<<`) to Bash (and Zsh/Fish when present)
- `set_favorite_apps.sh` — Set the GNOME dock favorites from `config/favorites.txt`, matching each desktop-file ID exactly against installed desktop entries (XDG application directories, including Flatpak/Snap exports); missing apps are skipped and never added, order is preserved, and the write is skipped when the dock already matches
- `set_wallpaper.sh` — Set GNOME wallpaper from assets/wallpaper/wallpaper.jpg
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
