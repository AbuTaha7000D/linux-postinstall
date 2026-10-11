# `./setup install` and `./setup`

`./setup install` and `./setup` with no arguments run the same code path: the
full setup, in a fixed order, stopping at the first step that fails. No
arguments and `install` are equivalent.

## Installation order

Six general steps run on every supported desktop:

| # | Step | Module | Purpose |
| --- | --- | --- | --- |
| 1 | `packages` | `modules/install_apps.sh` | Native packages, Flatpak apps, and vendor applications |
| 2 | `language` | `modules/change_language.sh` | Set the system language |
| 3 | `fonts` | `modules/install_fonts.sh` | Install user fonts from `assets/fonts` |
| 4 | `aliases` | `modules/set_aliases.sh` | Write the managed shell alias block |
| 5 | `terminal` | `modules/terminal_themes.sh` | Select the shell, install Atuin/Starship, `chsh` |
| 6 | `dev` | `modules/dev.sh` | Set up the development environment |

When the detected desktop is GNOME, four more steps run after those, in order:

| # | Step | Module |
| --- | --- | --- |
| 7 | `set_wallpaper` | `modules/set_wallpaper.sh` |
| 8 | `set_favorite_apps` | `modules/set_favorite_apps.sh` |
| 9 | `add_custom_shortcut` | `modules/add_custom_shortcut.sh` |
| 10 | `gnome_extensions` | `modules/gnome_extensions.sh` |

On any other desktop the group is skipped with:

```
Skipping GNOME steps (desktop: <de>).
```

Desktop detection uses `XDG_CURRENT_DESKTOP` (colon-separated list) with a
`DESKTOP_SESSION` fallback, via `desktop_environment` in `lib/common.sh`. See
[docs/gnome.md](gnome.md) for the GNOME group.

## Dry run

`--dry-run` may appear in any position and is exported as `SETUP_DRY_RUN=1`
before any step runs. Each step then prints the commands it would run
(`would run: ...`) instead of executing them. A dry run never authenticates
`sudo` and changes nothing.

```bash
./setup --dry-run
./setup --dry-run install
./setup install --dry-run   # equivalent
```

## Failure behavior

Each general step runs as `bash <module>`. If one exits nonzero, `setup` prints
to stderr:

```
Error: Failed at step '<name>' (<module path>) with exit code <N>
```

and stops immediately with that exit code. Later general steps do not run. The
GNOME group is the exception: it attempts all four independent modules and
then returns nonzero if any failed. `Installation complete.` is not printed on
failure. There is no rollback: steps that already ran keep their changes.

## Configuration and assets

| Path | Used by |
| --- | --- |
| `config/packages/<family>.txt` | `packages` |
| `config/flatpak.txt` | `packages` |
| `config/aliases/` | `aliases` |
| `config/starship.toml` | `terminal` |
| `assets/fonts/` | `fonts` |
| `assets/wallpaper/wallpaper.jpg` | `set_wallpaper` |
| `config/favorites.txt` | `set_favorite_apps` |
| `config/shortcuts.txt` | `add_custom_shortcut` |
| `config/gnome-extensions.txt` | `gnome_extensions` |

Except for `config/shortcuts.txt` (three tab-separated fields per line; see
[docs/shortcuts.md](shortcuts.md)), each list file holds one entry per line.
Blank lines and text after `#` are ignored, so the files are safe to annotate. A
missing or unreadable required list is fatal.

## Prerequisites

- Run as a regular user. The script refuses to run as root.
- Privileged operations authenticate lazily through `sudo` (`ensure_sudo` /
  `run_root`) when they first run. Sudo credentials expire according to the
  system's sudo policy. Setup does not run `sudo -k`: sudo timestamps are shared
  state and clearing one could invalidate another active setup process.
- A network connection for package, Flatpak, and extension downloads.
- A supported family (Fedora, Debian, or Arch). An unsupported distribution
  fails.
- The language step prompts once for English/Arabic with a 5-second English
  default (non-interactive runs default to English). The selected locale must
  already be available (`locale -a`) or the step fails without changes.
- The terminal step prompts for the default shell (Bash/Zsh/Fish, 5-second Bash
  default) and changes it with `chsh`; non-interactive runs use Bash.
- The GNOME steps need GNOME plus their tools: `gsettings` for wallpaper,
  favorites, and shortcuts; `gnome-extensions` and `python3` for extensions.

## Idempotency

Not every step is guaranteed idempotent. The `packages`, `favorites`,
`shortcuts`, and `gnome_extensions` steps check existing state and only change
what is missing. The `aliases` step replaces only its own managed block, so
reruns are stable. The `language`, `fonts`, and `set_wallpaper` steps rewrite
their target on each run (the language step backs up the locale file first). The
`dev` and `terminal` steps skip what is already installed and verify what they
install; the dev shell block is rewritten on each run.
