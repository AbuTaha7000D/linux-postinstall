# `./setup language` — Engineering Specification

Status: implemented behavior. Source of truth for the language command.
Implementation: `modules/change_language.sh`, shared helpers in `lib/common.sh`,
CLI wiring in `setup`.

This document describes the behavior the current implementation actually has.
Known limitations are recorded in "Idempotency and limitations".

See `docs/aliases.md`, `docs/terminal.md`, `docs/dev.md`, and `docs/fonts.md`
for the other commands.

---

## 1. Overview

- **Command:** `./setup language`
- **Equivalent dry-run invocations (identical):**
  - `./setup --dry-run language`
  - `./setup language --dry-run`
- **Purpose:** set the system language to English (US) or Arabic.
- **Standalone:** yes. `./setup language` has no dependency on any other command.
- **Part of the full flow:** yes. It is the second step of `./setup install`
  (packages → **language** → fonts → aliases → terminal → dev → GNOME group).
- **Privilege:** privileged. Writes `/etc/locale.conf` (Fedora/Arch) or
  `/etc/default/locale` (Debian/Ubuntu) through `run_root`.

---

## 2. Selection Prompt

- Interactive (TTY) runs print a menu with two choices: `1) English` and
  `2) Arabic`, default English, with **5 seconds** to answer.
- Any input other than `2` (including Enter, invalid text, or a timeout)
  selects English. Input is matched by exact `case`, never evaluated as shell.
- Non-TTY runs (unattended, redirected stdin, CI) skip the prompt entirely and
  select English. The menu is never printed in this mode; interactive selection
  is only reached on a real TTY (`[ -t 0 ]`).

| Condition | Result |
| --- | --- |
| TTY + `2` | Arabic (`ar_EG.UTF-8`) |
| TTY + `1`, Enter, invalid, or 5s timeout | English (`en_US.UTF-8`) |
| Non-TTY (`</dev/null`, pipes) | English, no menu |

---

## 3. Locale File Resolution

| Family | File |
| --- | --- |
| Fedora / RHEL / Arch / CachyOS | `/etc/locale.conf` |
| Debian / Ubuntu | `/etc/default/locale` |

Resolution checks existence in that order. Family detection is by file
presence, matching how each distribution actually stores its system locale.
If neither file exists the command fails nonzero on stderr with
`Warning: Unknown distro.` (no best-effort in-shell update).

Symlinks are resolved first (`readlink -f`) so the backup and write always
target the real file, and the resolved target must be a regular file.

---

## 4. Locale Availability Gate

Before any modification the selected locale must already be installed. The
module runs `locale -a` and looks for the base locale name (e.g. `en_US` or
`ar_EG`, with an optional encoding suffix).

| Family | Where the locale comes from |
| --- | --- |
| Fedora/RHEL | `glibc-langpack-*` package |
| Debian/Ubuntu | `locales` package + `locale-gen` |
| Arch/CachyOS | locale generation from `/etc/locale.gen` |

If the selected locale is not listed, the module prints a clear error on
stderr with a family-appropriate install hint and exits nonzero. No backup is
created and no write is attempted — the system is left exactly as it was.

---

## 5. Apply Sequence (real mode, in order)

1. Verify required tools are present (`locale`, `tee`, `cp`, `readlink`).
2. Resolve the locale file; fail nonzero if unknown or not a regular file.
3. Verify the selected locale is available via `locale -a`; fail nonzero if
   missing (before any modification).
4. `run_root cp -p <file> <file>.bak` — recoverable backup. A backup failure
   is fatal (nothing was written).
5. Rebuild the file content preserving every existing line and replacing only
   `LANG=` (and `LC_ALL=` when present) with the selected locale; append
   `LANG=` if the file has none. Unrelated settings such as `LC_TIME`,
   `LC_MESSAGES`, and `LC_PAPER` overrides are kept verbatim.
6. `run_root tee <file>` writes the new content. A write failure is fatal and
   names the backup location.
7. If `update-locale` exists (Debian/Ubuntu), `run_root update-locale`. A
   failure here is non-fatal: the locale file itself is already correct and
   `update-locale` is only a helper that regenerates it from the file.
8. Source the file into the current shell when readable, then print the
   current locale for confirmation.
9. Print `System language set to English.` / `System language set to Arabic.`

**Privilege note:** only steps 4, 6, and 7 are privileged; all go through
`run_root` (lazy `ensure_sudo`). There are no raw `sudo` calls in the module.

---

## 6. Dry-Run Behavior

`SETUP_DRY_RUN=1` (either flag position) prints one would-run line and exits 0
without a prompt, without verification, and without any mutation:

```text
would run: set system language (English default) and write the system locale
file (with backup)
```

The module returns at that line, before the locale-file resolution or any
wrapped command, so no `would run: sudo ...` lines are emitted. No sudo is
invoked, probed, or authenticated.

---

## 7. Failure Handling

| Situation | Behavior |
| --- | --- |
| Unknown distribution (no locale file) | **Fatal**: `Warning: Unknown distro.` on stderr, exit 1 |
| Resolved locale file is not a regular file | **Fatal** (exit 1, stderr) |
| Selected locale missing from `locale -a` | **Fatal**: error + install hint on stderr, exit 1, no backup, no write |
| Required tool missing | **Fatal** (exit 1, stderr) |
| Backup (`run_root cp`) fails | **Fatal**: error on stderr, exit 1, nothing written |
| Write (`run_root tee`) fails | **Fatal**: error names the backup, exit 1 |
| `update-locale` fails | **Non-fatal warning**: the file is already correct |

Required failures propagate through `setup` (`run_step`), so no success
message is printed after a failure.

---

## 8. Idempotency and Limitations

- Reruns are safe and byte-stable: rewriting the same `LANG`/`LC_ALL` on an
  already-applied file produces identical content, and the backup is
  overwritten (`cp -p`).
- Only `LANG` (and `LC_ALL` when already present) are modified; pre-existing
  per-category `LC_*` overrides are preserved. This is intentional: the module
  does not blindly replace the whole file.
- Limitations:
  - The locale must already be installed; the module never runs
    `locale-gen`/`dnf install` itself. It only documents what to install.
  - Availability is checked by base name (`locale -a`), so an encoding variant
    of the same locale counts as available; the module then writes
    `LANG=ar_EG.UTF-8`/`LANG=en_US.UTF-8` regardless of which variant is
    installed.
  - The running session's environment is changed only for the current shell
    process (sourcing the file); a full desktop/reboot is what locks it in.
  - `update-locale` failure is tolerated (see §7), so a broken Debian helper
    does not undo an otherwise valid write.

---

## 9. Test Coverage

An out-of-tree sandboxed test group covers:

- **Prompt:** TTY Arabic selection, TTY explicit English, TTY invalid input →
  English, TTY 5s timeout → English (waits ≥5s), non-TTY → English with no
  menu, and the `You have 5 seconds to choose.` text.
- **Dry-run:** one would-run line, no menu, no sudo/tripwire log, completion.
- **Unknown distro:** sandboxed module with no locale file → rc1, warning on
  stderr.
- **Availability gate:** fake `locale -a` without the selected locale → rc1,
  error on stderr, no backup, no write (verified against a sandbox file).
- **Apply/preserve (exec-mode sandbox):** backup created, `LANG`/`LC_ALL`
  updated, unrelated `LC_TIME` preserved, sudo `cp` and `tee` logged, success
  message, rerun byte-stable.
- **Failure propagation:** `language` named as the failed step across the S
  group (auth failure, failing `tee`).

At minimum, run `bash -n modules/change_language.sh` and the focused F group +
S group.