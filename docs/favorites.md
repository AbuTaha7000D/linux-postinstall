# `./setup favorites`

Sets the GNOME Shell dock favorites to the desktop-file IDs listed in
`config/favorites.txt`, in that order. The command is idempotent: it compares
the filtered list with the current dock and skips the write when they already
match.

## Configuration

| File | Purpose |
| --- | --- |
| `config/favorites.txt` | Desktop-file IDs pinned to the GNOME dock, one per line, in order |

The file holds one desktop-file ID per line. Blank lines and everything from
`#` to the end of a line are ignored, so the file is safe to annotate. Entries
may be written with or without the `.desktop` suffix; the suffix is added when
missing.

- A **missing or unreadable** file is fatal and prints the file name on stderr.
- A readable file that contains **only comments or blank lines** prints a skip
  message and changes nothing.
- The file is only ever read, never written.

## Availability

An entry is pinnable only when its desktop file exists by **exact name** in one
of the application directories:

- `$XDG_DATA_HOME/applications` (default `~/.local/share/applications`)
- each `$XDG_DATA_DIRS` entry plus `/applications` (default
  `/usr/local/share:/usr/share`)
- the Flatpak and Snap export locations (`~/.local/share/flatpak/exports/share`,
  `/var/lib/flatpak/exports/share`, `/var/lib/snapd/desktop`), for systems where
  those are not already on `XDG_DATA_DIRS`

Desktop-file availability is the only criterion. There is no package-manager
probing and no fuzzy name matching, because a package name and a desktop-file
ID are not interchangeable (for example, the Flatpak `com.bitwarden.desktop`
exports `com.bitwarden.desktop.desktop`).

## Behavior

- Entries whose desktop file is not installed are **skipped with a warning** and
  are **not** removed from `config/favorites.txt`, so the same file works on
  machines with different applications installed.
- If **no** configured entry is available, the command warns and **leaves the
  dock unchanged**; it never clears the dock.
- Order is preserved and duplicate IDs are collapsed.
- The `gsettings set org.gnome.shell favorite-apps` write is skipped when the
  resulting list already matches the dock.

## GNOME only

The command requires GNOME and `gsettings`. On any other desktop (or when
`gsettings` is missing) it prints a skip message and exits successfully.

## Dry run

`./setup --dry-run favorites` reads the file and desktop entries, prints the
specific `gsettings set` line it would run (including which entries are
skipped), and changes nothing.
