# `./setup gnome`

Runs the GNOME desktop configuration group: four modules in this fixed order.

| # | Step | Module | Purpose |
| --- | --- | --- | --- |
| 1 | `set_wallpaper` | `modules/set_wallpaper.sh` | Copy `assets/wallpaper/wallpaper.jpg` to `~/Pictures` and set it as the GNOME background |
| 2 | `set_favorite_apps` | `modules/set_favorite_apps.sh` | Set the GNOME dock favorites from `config/favorites.txt` |
| 3 | `add_custom_shortcut` | `modules/add_custom_shortcut.sh` | Add the custom keyboard shortcuts from `config/shortcuts.txt` |
| 4 | `gnome_extensions` | `modules/gnome_extensions.sh` | Install and enable the extensions from `config/gnome-extensions.txt` |

The command runs the modules as `bash <module>` and stops at the first failure
(see [docs/install.md](install.md) for the failure format).

## Desktop-environment behavior

`./setup gnome` does not check the desktop environment itself. Each of the four
modules independently checks for GNOME (via `desktop_environment`) and
`gsettings`, and on any other desktop prints a skip message and exits
successfully. Running `./setup gnome` outside GNOME therefore prints four skip
lines and reports completion without changing anything.

`./setup install` only reaches this group when the detected desktop is GNOME;
otherwise it prints `Skipping GNOME steps (desktop: <de>).` and does not invoke
these modules.

## Configuration and assets

| Path | Used by |
| --- | --- |
| `assets/wallpaper/wallpaper.jpg` | `set_wallpaper` |
| `config/favorites.txt` | `set_favorite_apps` |
| `config/shortcuts.txt` | `add_custom_shortcut` |
| `config/gnome-extensions.txt` | `gnome_extensions` |

`config/favorites.txt` and `config/gnome-extensions.txt` hold one entry per
line; `config/shortcuts.txt` holds three tab-separated fields per line. Blank
lines and text after `#` are ignored, and a missing or unreadable required list
is fatal. See [docs/favorites.md](favorites.md) and
[docs/shortcuts.md](shortcuts.md) for the favorites and shortcuts file formats.

## Requirements

- GNOME with `gsettings`.
- The wallpaper step requires `assets/wallpaper/wallpaper.jpg`.
- The extensions step requires `gnome-extensions` and `python3` (fatal when
  missing on GNOME) and network access to `extensions.gnome.org`.

## Dry run

```bash
./setup --dry-run gnome
```

Each module prints its planned `would run:` lines and changes nothing.

## Limitations

- The command does not gate on the desktop; each module decides independently.
- The wallpaper step overwrites `~/Pictures/wallpaper.jpg` on each run.
- The extensions step needs a release compatible with the running GNOME Shell
  major version; it fails when none is available for an extension.
