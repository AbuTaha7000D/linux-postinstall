# `./setup aliases` — Engineering Specification

Status: implemented behavior. Source of truth for the aliases command.
Implementation: `modules/set_aliases.sh`, alias data in `config/aliases/`, shared
helpers in `lib/common.sh`, CLI wiring in `setup`.

This document describes the behavior the current implementation actually has.
Known limitations are recorded in "Idempotency and limitations".

See `docs/terminal.md`, `docs/dev.md`, and `docs/fonts.md` for the other
commands.

---

## 1. Overview

- **Command:** `./setup aliases`
- **Equivalent dry-run invocations (identical):**
  - `./setup --dry-run aliases`
  - `./setup aliases --dry-run`
- **Purpose:** write one managed alias block into each applicable shell rc file.
  The block is the selected shell's alias file from `config/aliases/` followed by
  the matching distro fragment from `config/aliases/distro/`.
- **Standalone:** yes. `./setup aliases` has no dependency on any other command.
- **Part of the full flow:** yes. It is the fourth step of `./setup install`
  (packages → language → fonts → **aliases** → terminal → dev → GNOME group).
- **Privilege:** user-level only. No `sudo`, no package installation, no network.
- **Non-destructive:** content outside the managed block is never rewritten; a
  one-time backup is taken before the first modification of an existing file.

---

## 2. Targets

| Shell | rc file | Targeted when |
| --- | --- | --- |
| Bash | `~/.bashrc` | always |
| Zsh | `~/.zshrc` | the file exists **or** a `zsh` binary is on `PATH` |
| Fish | `~/.config/fish/config.fish` | the file exists **or** a `fish` binary is on `PATH` |

Targets are written in the stable order Bash → Zsh → Fish. A shell whose rc file
does not exist is created (owner-only, `0600`).

---

## 3. Editable Alias Data (`config/aliases/`)

Alias definitions are plain text, not embedded in shell logic. The data lives in
`config/aliases/`:

| File | Role |
| --- | --- |
| `config/aliases/bash` | Bash common aliases + Bash-specific aliases |
| `config/aliases/zsh` | Zsh common aliases + Zsh-specific aliases |
| `config/aliases/fish` | Fish common aliases + Fish-specific aliases |
| `config/aliases/distro/debian` | Debian-family aliases |
| `config/aliases/distro/redhat` | Red Hat-family aliases |
| `config/aliases/distro/arch` | Arch-family aliases |

For a selected shell, the block is exactly:

```text
<contents of config/aliases/<shell>>
<contents of config/aliases/distro/<family>>
```

`<family>` is the token from `distribution()` (`debian`, `redhat`, or `arch`).
When the family is `unknown`, the distro fragment is omitted, the remaining shell
fragment is still written, and a warning is printed to stderr (not fatal).

The common aliases define `ls` (eza), `grep`, `pingo`, `ff`, `efrc`, `ebrc`,
`update-fonts`, and `finstall`; each shell file adds a `refresh` alias that
sources that shell's rc file. The distro fragments define `supdate`, `install`,
and `remove` for the family package manager, and the Red Hat fragment adds
`update-grub`. Editing or adding files under `config/aliases/` changes what the
next `./setup aliases` run writes; no code change is required.

Because the managed block is appended to each startup file, its definitions
take precedence over earlier user-defined aliases with the same names. Those
names are `ls`, `grep`, `pingo`, `ff`, `efrc`, `ebrc`, `update-fonts`,
`finstall`, `refresh`, `supdate`, `install`, `remove`, and (on Red Hat family)
`update-grub`. The one-time startup-file backup preserves the previous content
for recovery.

On Arch-family systems, `supdate` checks for `yay` before starting any update
commands. If it is missing, the alias prints an error and exits; install `yay`
before using `supdate`.

Fish accepts the same `alias name='command'` syntax used by the other fragments,
so the shared data is source-compatible with all three shells. The module itself
contains no alias definitions.

---

## 4. Managed Block

The block is delimited by exact marker lines:

| Marker | Value |
| --- | --- |
| begin | `# >>> linux-postinstall aliases >>>` |
| end | `# <<< linux-postinstall aliases <<<` |

The block is stripped and re-appended on every run, so exactly one managed block
exists per target file. Lines outside the block are preserved in their original
order.

---

## 5. Execution Flow

Fixed order:

1. Source `lib/common.sh`; compute the distro family via `distribution()`.
2. Determine target shells (`bash` always; `zsh`/`fish` when present).
3. **Phase A — read-only validation (before any mutation).**
   - Warn on an unsupported distribution (stderr); continue.
   - Fail if a needed `config/aliases/<shell>` file is missing.
   - For a supported family, fail if `config/aliases/distro/<family>` is missing.
   - Validate every target: refuse symlinks; refuse non-regular files; fail on a
     malformed managed block; preflight writability of the target and its
     destination directory.
   - Syntax-check each composed fragment with the real interpreter when it is
     installed (`bash -n`, `zsh -f -n`, `fish --no-config --no-execute`). A shell
     without an available interpreter is not checked.
4. **Dry-run:** after validation, print the would-run lines and exit `0`; no
   backup is written and no file is modified.
5. **Phase B — one-time backup.** For each existing target that has no
   `.linux-postinstall.bak`, copy the original with `cp -a` (preserving mode,
   ownership, ACLs, extended attributes, and SELinux context). An existing backup
   is never overwritten; new files get no backup.
6. **Phase C — write.** For each target, stage the cleaned content plus the fresh
   block in an exclusive temporary file in the destination directory, then swap
   it in atomically.
7. Print `Aliases set successfully!`.

---

## 6. Decision Tree / Conditions

```text
family = distribution()          → debian | redhat | arch | unknown

targets:
    bash → always
    zsh  → [ -f ~/.zshrc ]   OR command -v zsh
    fish → [ -f ~/.config/fish/config.fish ] OR command -v fish

fragment(shell):
    cat config/aliases/<shell>
    IF family in {debian,redhat,arch}: cat config/aliases/distro/<family>

validate target:
    IF symlink            → fatal (refusing to modify symlinked file)
    IF exists and not file → fatal (not a regular file)
    IF malformed block     → fatal (BEGIN without END, orphan END, nested BEGIN)
    IF destination not writable, or existing file not readable+writable → fatal

validate fragment:
    IF interpreter available and fragment fails syntax check → fatal

dry-run:
    FOR each target: print backup would-run (if file exists) and write would-run
    exit 0 (no mutation)

real:
    backup each existing target once (cp -a), if no .bak exists
    write each target in order: strip block, append fresh block, atomic mv
```

---

## 7. Files and Configuration

| Path | Access | Purpose |
| --- | --- | --- |
| `config/aliases/{bash,zsh,fish}` | read | per-shell alias fragment |
| `config/aliases/distro/{debian,redhat,arch}` | read | distro alias fragment |
| `~/.bashrc` | create/modify | managed block (always targeted) |
| `~/.zshrc` | create/modify | managed block (when zsh present) |
| `~/.config/fish/config.fish` | create dir + create/modify | managed block (when fish present) |
| `<rc>.linux-postinstall.bak` | create once | original content, taken before first modification |
| `/etc/os-release` (or `$OS_RELEASE_FILE`) | read | family detection |
| `<target dir>/.linux-postinstall.XXXXXX` | create/remove | exclusive staging file, swapped in by `mv` |

Notes:

- Existing targets keep their security metadata: the staging file is a `cp -a`
  copy of the target, so mode, ownership, ACLs, extended attributes, and SELinux
  context carry over; a preservation failure aborts before the target is
  replaced.
- Newly created files are owner-only (`0600`) by policy.
- The staging file is created with `mktemp` in the destination directory, so a
  predictable path cannot be pre-created, followed, or clobbered. Staging files
  are removed on exit.
- The module does not use the shared `run`/`run_root` helpers for its writes; it
  branches on `SETUP_DRY_RUN` directly because it needs atomic replacement and
  custom dry-run messages. It performs no privileged operation.

---

## 8. Dry-Run Contract

Both `./setup --dry-run aliases` and `./setup aliases --dry-run` behave
identically. `SETUP_DRY_RUN=1` prints, per target:

```text
would run: back up <file> to <file>.linux-postinstall.bak (if missing)   # only when <file> exists
would run: write linux-postinstall alias block to <file>
```

and exits `0`. Validation still runs, so a symlinked, malformed, unwritable, or
syntax-invalid target can still fail in dry-run before any output.

Dry-run creates no file or directory, takes no backup, uses no network, and
invokes no `sudo`. The success line is not printed.

---

## 9. Idempotency and Limitations

- **Idempotent:** the block is stripped and re-appended, so reruns leave exactly
  one block and are byte-identical when the fragment data is unchanged.
- **One-time backup:** a `.linux-postinstall.bak` is created only when missing
  and is never overwritten; pre-existing backups (even unrelated ones) are left
  untouched.
- **Preserving:** content outside the managed block is never modified.
- **Limitations:**
  - Duplicate blocks already present are consolidated into one; the module does
    not attempt to reconcile conflicting manual edits inside an old block.
  - A malformed marker state is fatal rather than repaired.
  - A failure while writing one target leaves earlier targets already updated;
    there is no rollback.
  - The writability preflight checks the destination directory and an existing
    target; it does not guarantee an atomic `mv` succeeds under all conditions.
  - Syntax validation only runs when the corresponding shell interpreter is
    installed and only checks syntax, not alias semantics.

---

## 10. Failure Behavior

| Situation | Behavior |
| --- | --- |
| Unsupported distribution | Warning on stderr; the shell fragment is still written without distro aliases (not fatal) |
| Missing `config/aliases/<shell>` file | **Fatal** (`exit 1`, stderr) |
| Missing `config/aliases/distro/<family>` file | **Fatal** (`exit 1`, stderr) |
| Target is a symlink | **Fatal**: `Error: refusing to modify symlinked file: <file>` |
| Target exists and is not a regular file | **Fatal**: `Error: not a regular file: <file>` |
| Malformed managed block | **Fatal**: `Error: malformed linux-postinstall alias block in <file>` |
| Target or destination directory not writable | **Fatal**: `Error: not writable: <file>` |
| Composed fragment fails interpreter syntax check | **Fatal**: `Error: generated alias block failed <shell> syntax validation` |
| Backup (`cp -a`) fails | **Fatal**, before any target is modified |
| Write to a target fails | **Fatal**; earlier targets remain updated (no rollback) |

Required failures propagate through `setup` (`run_step`); no success message is
printed after a failure. Because validation happens before any mutation,
validation failures leave every target unchanged.

---

## 11. Security / Privilege Behavior

- No privileged operation: the module contains no `sudo`, no `run_root`, and no
  package-manager invocation. It never authenticates sudo.
- Symlinked targets are rejected during validation, so the module does not
  rewrite a file through a link under normal operation. A narrow TOCTOU race
  remains: if another process replaces an already-validated target with a
  symlink before the write phase, the staging copy can follow it. The exclusive
  `mktemp` staging file limits, but does not eliminate, this window.
- Staging files are created exclusively with `mktemp` in the destination
  directory to prevent path pre-creation or symlink-following attacks.
- Existing file metadata (mode, ownership, ACLs, xattrs, SELinux context) is
  preserved via `cp -a`; new files are owner-only (`0600`).
- No network access and no service, firewall, or authentication configuration
  change.
- The module contains no alias definitions and no distro package-manager text
  (`install`/`supdate`/`remove` come from `config/aliases/`, not from code).

---

## 12. External Dependencies

| Dependency | Used for | Notes |
| --- | --- | --- |
| `bash` | required interpreter for the module | `setup` runs the module as `bash "$script"` |
| `awk` | block detection and stripping | always available |
| `mktemp`, `cp`, `mv`, `rm` | staging, backup, atomic replacement | user-level |
| `bash` / `zsh` / `fish` | optional fragment syntax validation | skipped when the interpreter is absent |
| `config/aliases/` data | block contents | read-only to the module |

There is no network dependency and no `distribution()`-based install path.

---

## 13. Verification

A reviewer should verify, on a sandboxed `HOME` and `PATH`:

**Syntax and CLI**

- `bash -n setup lib/common.sh modules/set_aliases.sh`.
- `./setup help` and `./setup version` succeed.
- Invalid/extra arguments fail nonzero with a usage hint.

**Positive behavior**

- Each target shell with a present rc file receives exactly one managed block.
- The block is `<shell>` fragment followed by the correct `distro/<family>`
  fragment; the Red Hat fragment includes `update-grub` and the others do not.
- Existing content outside the block is preserved; a one-time
  `.linux-postinstall.bak` holds the original.
- Reruns are byte-identical and create no duplicate block or second backup.
- Existing files keep mode/ACL/xattr/SELinux context; new files are `0600`.

**Negative ("must NOT happen")**

- Dry-run writes nothing and prints no success line.
- Symlinked, malformed, unwritable, or syntax-invalid targets fail before any
  mutation and create no backup.
- No raw `sudo` and no distro package-manager text in `modules/set_aliases.sh`.
- No alias definitions embedded in `modules/set_aliases.sh`.

**Sandboxed test group**

The out-of-tree aliases group exercises runtime alias definitions for every shell
and distro fragment, family selection, idempotency and preservation, malformed
blocks, symlink refusal, one-time backups, dry-run, partial-commit failure
without rollback, syntax gating, and metadata preservation. At minimum, run
`bash -n modules/set_aliases.sh` and the focused aliases group.

---

## 14. Review Checklist

```text
[ ] `aliases` is standalone and user-level; no sudo, network, or packages.
[ ] Targets: bash always; zsh/fish when rc file exists or shell is present.
[ ] One managed block per target, delimited by the exact marker lines.
[ ] Block = shell fragment followed by the matching distro fragment.
[ ] Unknown family warns and writes the shell fragment without distro aliases.
[ ] Validation runs before any mutation; failures leave targets unchanged.
[ ] Symlinks, non-regular files, malformed blocks, and unwritable targets fail.
[ ] Fragment syntax is checked with the real interpreter when available.
[ ] One-time backup per existing target; never overwrites an existing backup.
[ ] Reruns are byte-identical with no duplicate block or backup.
[ ] Existing metadata preserved; new files owner-only (0600).
[ ] Dry-run prints would-run lines only and writes nothing.
[ ] No alias definitions embedded in the module; data lives in config/aliases/.
[ ] Required failures propagate; no success line after failure.
[ ] bash -n passes.
```
