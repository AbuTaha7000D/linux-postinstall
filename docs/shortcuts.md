# `./setup shortcuts`

Adds the GNOME custom keyboard shortcuts listed in `config/shortcuts.txt`.
The command is idempotent: for each entry it checks whether a shortcut with the
same name, command, or keybinding already exists and only adds what is missing.

## Configuration

| File | Purpose |
| --- | --- |
| `config/shortcuts.txt` | Custom keyboard shortcuts added by GNOME, one per line, in order |

Each line holds one shortcut as three tab-separated fields:

```
Name	Keybinding	Command
```

- `Name` — the label shown in GNOME Settings.
- `Keybinding` — the accelerator, e.g. `<Alt>T`.
- `Command` — the shell command run when the shortcut is pressed.

Blank lines and everything from `#` to the end of a line are ignored, so the
file is safe to annotate. Surrounding whitespace around each field is trimmed.

- A **missing or unreadable** file is fatal and prints the file name on stderr.
- A data line that does not have **exactly three non-empty fields** is fatal and
  prints the file name and line number.
- A readable file that contains **only comments or blank lines** prints a skip
  message and changes nothing.

The file is only ever read, never written.

## Behavior

- Shortcuts are added in the order they appear in the file.
- The next free `custom<N>` keybinding path is allocated from the current
  `custom-keybindings` list.
- An entry whose name, command, or keybinding already exists is skipped, so
  rerunning the command does not create duplicates.
- If adding a shortcut fails, the command exits nonzero instead of reporting
  success.

## GNOME only

The command requires GNOME and `gsettings`. On any other desktop (or when
`gsettings` is missing) it prints a skip message and exits successfully.

## Dry run

`./setup --dry-run shortcuts` reads the file and prints a single summary line
naming the configured shortcuts, e.g.:

```
would run: add GNOME custom shortcuts (Resources, Settings, Terminal, Toggle Mic) via gsettings
```

It changes nothing.
