# `./setup fonts` — Engineering Specification

Status: implemented behavior. Source of truth for the fonts command.
Implementation: `modules/install_fonts.sh`, shared helpers in `lib/common.sh`,
CLI wiring in `setup`.

This document describes the behavior the current implementation actually has.
Known limitations are recorded in "Idempotency and limitations".

See `docs/terminal.md` and `docs/dev.md` for the other commands.

---

## 1. Overview

- **Command:** `./setup fonts`
- **Equivalent dry-run invocations (identical):**
  - `./setup --dry-run fonts`
  - `./setup fonts --dry-run`
- **Purpose:** copy the bundled fonts under `assets/fonts/` into the current
  user's font directory and refresh the font cache.
- **Standalone:** yes. `./setup fonts` has no dependency on any other command.
- **Part of the full flow:** yes. It is the third step of `./setup install`
  (packages → language → **fonts** → aliases → terminal → dev → GNOME group).
- **Privilege:** user-level only. No `sudo`, no package installation, no network.

---

## 2. Source and Destination

| Role | Path |
| --- | --- |
| Source | `<repo>/assets/fonts/` |
| Destination | `${XDG_DATA_HOME:-$HOME/.local/share}/fonts` |

- The destination honors `XDG_DATA_HOME`; when it is unset (or empty) the
  default `~/.local/share/fonts` is used.
- The source is resolved relative to the module location, so the command works
  regardless of the caller's current directory.
- Files are copied **flat** into the destination; no `assets/fonts` level is
  recreated beneath it.
- fontconfig reads the XDG font directory (`$XDG_DATA_HOME/fonts`); the legacy
  `~/.fonts` directory is not used.

---

## 3. Install Sequence

Real mode, in order:

1. Fail if the source directory does not exist.
2. Fail if the source directory is empty.
3. Fail if `fc-cache` is not available.
4. `mkdir -p "<destination>"`.
5. `cp -r "<source>"/* "<destination>"/`.
6. `fc-cache -f`.

Steps 4–6 run through the shared `run` helper. Each has an explicit failure
branch that prints a specific message to stderr and exits nonzero; the success
line is printed only after the cache refresh succeeds.

---

## 4. Dry-Run Behavior

`SETUP_DRY_RUN=1` (either flag position) prints the planned commands and exits 0
without validation or any mutation:

```text
would run: mkdir -p "<destination>"
would run: cp -r "<source>"/* "<destination>"/
would run: fc-cache -f
```

Dry-run creates no directory, copies no files, runs no `fc-cache`, uses no
network, and invokes no `sudo`. The source and `fc-cache` checks are real-mode
only.

---

## 5. Dependencies and Error Handling

| Dependency | Used for |
| --- | --- |
| `bash`, `mkdir`, `cp`, `ls` | copy operations and source check |
| `fc-cache` (fontconfig) | rebuild the user font cache |

There is no distribution detection, package manager, network access, or `sudo`.

| Situation | Behavior |
| --- | --- |
| Source directory missing | **Fatal** (`exit 1`, stderr): `Error: Font directory '<dir>' does not exist.` |
| Source directory empty | **Fatal** (`exit 1`, stderr): `Error: No font files found in '<dir>'.` |
| `fc-cache` not found | **Fatal** (`exit 1`, stderr): `Error: fc-cache (fontconfig) not found. Install fontconfig and re-run.` |
| Directory creation fails | **Fatal**: `Error: Failed to create font directory '<dest>'.` |
| Copy fails | **Fatal**: `Error: Failed to copy fonts from '<dir>' to '<dest>'.` |
| Cache refresh fails | **Fatal**: `Error: Fonts were copied to '<dest>' but the font cache was not refreshed.` |

Required failures propagate through `setup` (`run_step`); no success message is
printed after a failure.

---

## 6. Idempotency and Limitations

- Reruns are safe: `mkdir -p` is idempotent and `cp` overwrites same-named
  files, producing no duplicates and no nested font directory.
- Fonts already in the destination that are unrelated to the source are left in
  place; nothing is deleted.
- Limitations:
  - Same-named files in the destination are overwritten, including user edits.
  - Fonts removed from `assets/fonts/` are **not** removed from the
    destination; the command never deletes.
  - Font files are not validated, and successful registration is not verified
    (`fc-list` is not used); only the `fc-cache` exit status is checked.
  - Copying uses the `*` glob, so dotfiles are skipped and any subdirectory would
    be copied recursively rather than flattened. The bundled tree contains
    neither, so this does not occur in practice.

---

## 7. Test Coverage

An out-of-tree sandboxed test group covers:

- **Dry-run:** would-run lines printed, XDG destination named, no mutation, no
  `fc-cache`, no `sudo`, completion printed.
- **Real mode:** destination created, flat copy (matching file count and
  content, no nested directory), `fc-cache -f` run without `-v`, no `sudo`.
- **Rerun:** exit 0, no duplicates, source files intact, an unrelated
  destination file preserved.
- **Failure paths:** missing `fc-cache`, `fc-cache` failure, missing source, and
  empty source each exit nonzero with the documented stderr and no success line.
- **Syntax:** `bash -n` on the module and the harness.

At minimum, run `bash -n modules/install_fonts.sh` and the focused fonts group.
