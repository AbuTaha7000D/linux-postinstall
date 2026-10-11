# `./setup gnome`

Runs the GNOME desktop configuration group: four modules in this fixed order.

| # | Step | Module | Purpose |
| --- | --- | --- | --- |
| 1 | `set_wallpaper` | `modules/set_wallpaper.sh` | Copy `assets/wallpaper/wallpaper.jpg` to `~/Pictures` and set it as the GNOME background |
| 2 | `set_favorite_apps` | `modules/set_favorite_apps.sh` | Set the GNOME dock favorites from `config/favorites.txt` |
| 3 | `add_custom_shortcut` | `modules/add_custom_shortcut.sh` | Add the custom keyboard shortcuts from `config/shortcuts.txt` |
| 4 | `gnome_extensions` | `modules/gnome_extensions.sh` | Install and enable the extensions from `config/gnome-extensions.txt` |

The command runs all four modules as `bash <module>` in the listed order, even
if an earlier module fails. It reports each failed module and exits nonzero if
the group is incomplete. Within shortcuts and extensions, independent entries
are attempted after an individual entry fails. Successful earlier changes are
not rolled back.

## Desktop-environment behavior

`./setup gnome` does not check the desktop environment itself. Each module
checks for GNOME (via `desktop_environment`) and the commands it uses; on any
other desktop it prints a skip message and exits successfully. The extensions
module uses `gnome-extensions` for state checks and does not require `gsettings`.
Running `./setup gnome` outside GNOME therefore prints four skip lines and
reports completion without changing anything.

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

- A GNOME desktop; the wallpaper, favorites, and shortcuts steps use
  `gsettings`.
- The wallpaper step requires `assets/wallpaper/wallpaper.jpg`.
- The extensions step requires `gnome-extensions` and `python3` (fatal when
  missing on GNOME) and `curl` plus network access for each extension that must
  be downloaded.

## Dry run

```bash
./setup --dry-run gnome
```

Each module prints its planned `would run:` lines and changes nothing. Modules
may read configuration and current GNOME state to describe the plan.

## Limitations

- The command does not gate on the desktop; each module decides independently.
- The wallpaper step overwrites `~/Pictures/wallpaper.jpg` on each run.
- A failed setting or configured item does not stop later independent GNOME
  work; the group still exits nonzero and reports incomplete results.
- The extensions step needs a release compatible with the running GNOME Shell
  major version; it fails when none is available for an extension.
