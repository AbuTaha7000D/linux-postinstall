# `./setup terminal` — Engineering Specification

Status: approved contract. Source of truth for the terminal command.
Implementation: `modules/terminal_themes.sh`, shared helpers in `lib/common.sh`,
CLI wiring in `setup`.

This document describes the **approved intended behavior**. Where the current
implementation differs, the mismatch is called out explicitly in the section
"Known implementation notes and mismatches".

See `docs/dev.md` for the development-environment contract.

---

## 1. Overview

- **Command:** `./setup terminal`
- **Equivalent dry-run invocations (identical):**
  - `./setup --dry-run terminal`
  - `./setup terminal --dry-run`
- **Purpose:** own the terminal stack for the current user: select and configure
  the default shell, install the selected shell when it is missing (with a
  documented fallback to Bash), install Atuin and Starship when missing, add the
  guarded init lines for the selected shell only, and set that shell as the
  login shell with `chsh`.
- **Standalone:** yes. `./setup terminal` runs the terminal stack on its own and
  has no dependency on any other command.
- **Part of the full flow:** yes. It is the fifth step of `./setup install`
  (and no-argument `./setup`): packages → language → fonts → aliases →
  **terminal** → dev → GNOME group.
- **Relationship with other commands:**
  - `aliases` writes a separate managed block to shell rc files. Terminal only
    appends exact init lines and never touches the aliases block.
  - `dev` writes its own managed block (PATH + mise) to shell rc files and, on
    Debian, symlinks `fdfind`. Terminal does not manage either.
  - Terminal is the **only** command allowed to install Starship, and it must
    use the official installer (see §12). It is also the only command that runs
    `chsh`.

---

## 2. Scope

### Owned by this command

1. Interactive (TTY) shell selection, Bash/Zsh/Fish, 5-second default.
2. Installing the selected shell package when it is missing.
3. Verifying the selected shell with `command -v`; falling back to Bash when the
   install cannot be verified.
4. Installing Atuin (official installer) when missing.
5. Installing Starship (official installer) when missing.
6. Appending the Atuin and Starship init lines to the selected shell's rc file
   with exact-line guards.
7. Setting the login shell via `chsh -s <path> <user>` under `run_root`.
8. Reporting what it did and failing fast on required failures.

### Explicitly outside scope

- Alias management (owned by `modules/set_aliases.sh`).
- The dev PATH/mise managed block and the Debian `fd` symlink
  (owned by `modules/dev.sh`).
- GNOME configuration, packages, language, fonts.
- Modifying anything outside the selected shell's rc file for init lines.
- Replacing, truncating, or reordering existing rc-file content.
- Installing any prompt tool other than Starship. The previously used line
  prompt tool (Oh My Posh) is removed and must never be reintroduced.
- Installing Starship via `dnf`, `apt`, `pacman`, `yay`, COPR, or GitHub release
  binaries.

### Source of truth in the repository

- `setup` — CLI parsing, `--dry-run` handling, dispatch (`terminal` maps to
  `modules/terminal_themes.sh`), failure propagation, sudo cleanup.
- `modules/terminal_themes.sh` — the entire behavior described here.
- `lib/common.sh` — `distribution()`, `run()`, `run_root()`, `ensure_sudo()`.

Related commands that must **not** be modified to implement terminal behavior:
`modules/set_aliases.sh`, `modules/dev.sh`, `modules/install_apps.sh`.

---

## 3. Execution Flow

1. Source `lib/common.sh`; compute `DRY` from `SETUP_DRY_RUN`.
2. **Shell selection.** If stdin is a TTY, print the menu and `read -t 5`; map
   `2` → zsh, `3` → fish, anything else/timeout → bash. If stdin is not a TTY,
   select Bash without prompting.
3. Map the selection to shell name/binary/rc file/init lines
   (`apply_shell_selection`).
4. **Shell installation.**
   - Bash selected → nothing to install.
   - Otherwise, if `command -v <shell>` succeeds → already installed.
   - Otherwise, in dry-run, print the would-run install lines and continue.
   - Otherwise install the shell package for the detected family, then verify
     with `command -v`. On failure or unverified install, warn, fall back to
     Bash, re-run selection mapping, and verify Bash exists (fatal if not).
5. **Atuin installation.** Skip if present (`command -v atuin` or
   `~/.atuin/bin/atuin`, the official installer's location); dry-run prints the
   official-installer line; otherwise run the official installer and re-verify
   (fatal on failure).
6. **Starship installation.** Skip if present (`command -v starship`); dry-run
   prints the exact official-installer line; otherwise pre-cache credentials
   with `ensure_sudo`, run the official installer unprivileged (it self-elevates
   internally), and re-verify (fatal on failure).
7. **Init lines.** Ensure the fish config directory exists (fish only, real
   mode). Append the Atuin init line and the Starship init line to the selected
   shell's rc file, each guarded by an exact-line check.
8. **Login shell.** Read the current login shell from `getent passwd <user>`
   (fallback `$SHELL`). If it already matches the selected shell, report and
   stop. Otherwise resolve the shell path and run
   `chsh -s <path> <user>` via `run_root` (fatal on failure).
9. Return `0` on success. Any fatal failure exits nonzero with a message on
   stderr; `setup` propagates it.

---

## 4. Decision Tree / Conditions

```text
select shell:
    stdin is a TTY → prompt (5s): 2=zsh, 3=fish, else bash
    stdin is not a TTY → bash (no prompt, no delay)

install selected shell:
    IF shell == bash → skip install
    ELSE IF `command -v <shell>` → already installed, skip
    ELSE IF dry-run → print would-run install lines, no verify
    ELSE
        run family package install
        IF install failed OR `command -v <shell>` still fails
            → warn, fall back to bash, re-map selection
            → IF bash still missing → fatal
        ELSE → shell confirmed

atuin:
    IF `command -v atuin` OR `-x ~/.atuin/bin/atuin` → skip
    ELSE IF dry-run → print official-installer line
    ELSE run installer; IF fails OR still absent → fatal

starship:
    IF `command -v starship` → skip
    ELSE IF dry-run → print exact `curl -sS https://starship.rs/install.sh | sh -s -- -y`
    ELSE ensure_sudo; run installer; IF fails OR still absent → fatal

init lines (for the selected shell rc file):
    FOR each of atuin_init, starship_init:
        IF exact line already present → report, no change
        ELSE IF dry-run → print "would run: add '<line>' to <file>"
        ELSE append the line

login shell:
    login = getent passwd <user> (fallback $SHELL); compare basename to shell bin
    IF already the default → report, done
    ELSE IF dry-run → print would-run chsh line
    ELSE run_root chsh -s <resolved path> <user>; IF fails → fatal
```

---

## 5. Implementation Details

```text
setup
  └── run_step modules/terminal_themes.sh terminal_themes
        └── source lib/common.sh
              ├── distribution()   → redhat | debian | arch | unknown
              ├── run()            → print in dry-run, else execute
              ├── run_root()       → print sudo line in dry-run, else ensure_sudo + sudo
              └── ensure_sudo()    → lazy `sudo -n -v` probe, then one `sudo -v`
```

Key functions inside `modules/terminal_themes.sh`:

- `apply_shell_selection` — maps `shell_key` → `shell_name`, `shell_bin`,
  `rc_file`, `atuin_init`, `starship_init`. Called once after selection and
  again after a Bash fallback.
- `install_shell_package <pkg>` — family-specific privileged install; returns
  nonzero (with a warning) on failure and on unsupported distributions.
- `atuin_present` / `starship_present` — presence predicates
  (`command -v`, plus `~/.atuin/bin/atuin` for Atuin).
- `ensure_init_line <file> <line> <label>` — exact-line guard, then append.

Constants and environment:

- `STARSHIP_INSTALL_CMD='curl -sS https://starship.rs/install.sh | sh -s -- -y'`
  — the only permitted Starship install path.
- `DRY` mirrors `${SETUP_DRY_RUN:-0}`.
- `SETUP_SUDO_MARKER` (exported by `setup`) lets `setup` clear only the sudo
  timestamp this run created.

Managed init lines by shell:

| Shell | rc file | Atuin line | Starship line |
| --- | --- | --- | --- |
| Bash | `~/.bashrc` | `eval "$(atuin init bash)"` | `eval "$(starship init bash)"` |
| Zsh | `~/.zshrc` | `eval "$(atuin init zsh)"` | `eval "$(starship init zsh)"` |
| Fish | `~/.config/fish/config.fish` | `atuin init fish \| source` | `starship init fish \| source` |

Verification checks: `command -v` for the selected shell, Atuin, and Starship;
`getent passwd <user>` for the current login shell.

---

## 6. Distro Behavior

Family is detected by `distribution()` from `/etc/os-release` (`ID`, then
`ID_LIKE`), mapping to `redhat`, `debian`, `arch`, or `unknown`.

| Family | Shell package install | Notes |
| --- | --- | --- |
| Fedora (`redhat`) | `run_root dnf install -y <pkg>` | `zsh` / `fish` package names |
| Debian/Ubuntu/Mint (`debian`) | `run_root apt-get update` then `run_root apt-get install -y <pkg>` | index refresh precedes install |
| Arch/CachyOS (`arch`) | `run_root pacman -S --noconfirm <pkg>` | no `-Syu`; `--needed` not required here |
| Unknown | warning, return nonzero | shell install is not attempted; a non-Bash selection falls back to Bash |

Atuin and Starship use official installers on **all** families and are not
installed from distro packages. `chsh` is distro-independent.

---

## 7. Files and Configuration

| Path | Access | Purpose |
| --- | --- | --- |
| `~/.bashrc` | append | Atuin/Starship init when Bash is selected |
| `~/.zshrc` | append | Atuin/Starship init when Zsh is selected |
| `~/.config/fish/config.fish` | create dir + append | Atuin/Starship init when Fish is selected |
| `/etc/os-release` (or `$OS_RELEASE_FILE`) | read | family detection |
| `/etc/passwd` via `getent passwd` | read | current login shell |
| `$SETUP_SUDO_MARKER` | touch/remove (via `setup`) | sudo cleanup marker |

Notes:

- Init lines are appended one line at a time and only when the exact line is not
  already present; for Fish, an existing installer-written `atuin init fish`
  block also suppresses the Atuin append. No managed block markers are used by
  this command.
- Existing rc content outside the two appended init lines is never rewritten.
- Terminal does **not** touch `/etc/shells`, `sshd_config`, firewall rules, or
  any service.
- Fish's `~/.config/fish` directory is created in real mode before appending.

---

## 8. Dry-Run Contract

Both `./setup --dry-run terminal` and `./setup terminal --dry-run` behave
identically (`--dry-run` is global and position-independent). `SETUP_DRY_RUN=1`
must guarantee:

**Allowed (read-only / reporting):**

- Detecting the distribution.
- Prompting for shell selection when stdin is a TTY (the prompt is not a
  mutation).
- Printing intended actions: shell install lines, the Atuin installer line, the
  exact Starship installer line, `would run: add '<line>' to <file>`, and the
  `chsh` sudo line.
- Read-only probes: `command -v` (shells, Atuin, Starship), `-x` path tests
  (Atuin at `~/.atuin/bin/atuin`), `getent passwd` (current login shell), and
  `id -un` (target username).

**Forbidden:**

- Any package installation or package-index refresh.
- Network access (no Atuin/Starship installer execution).
- File writes or directory creation (`~/.zshrc`, `~/.config/fish`, etc.).
- `chsh` execution.
- Any `sudo` invocation or credential authentication (`run_root` prints only;
  Starship's `ensure_sudo` returns immediately in dry-run).
- Any service/firewall change.

The whole terminal module must be testable with a sandboxed `HOME` and PATH
tripwires on mutating commands, asserting that dry-run creates zero files, runs
zero installers, authenticates no sudo, and prints only would-run lines.

---

## 9. Idempotency

- **Shell selection:** a TTY selection is a per-run choice; the *effect* is
  idempotent because `chsh` is skipped when the login shell already matches.
- **Shell install:** `command -v` gate means a second run does not reinstall.
- **Atuin/Starship:** presence predicates gate installation; second and
  subsequent runs report "already installed".
- **Init lines:** exact-line guards mean reruns add nothing and do not
  duplicate. For Fish, Atuin detection also recognizes the installer's guarded
  `atuin init fish` block, so terminal does not append a second Atuin init.
- **Login shell:** `getent` comparison means reruns report "already the default
  shell" and skip `chsh`.
- Repeating the command (and every step inside it) is safe: no duplicate rc
  lines, no redundant installs, no repeated shell change. The aliases and dev
  blocks are independent and unaffected.

---

## 10. Failure Behavior

| Situation | Behavior |
| --- | --- |
| Selected shell package install fails, or install "succeeds" but the shell is still missing (real mode) | Warning; fall back to Bash before any configuration/`chsh`; configure Bash instead. Dry-run never verifies and never falls back on simulated results. |
| Bash missing after fallback | **Fatal** (`exit 1`, stderr). |
| Unsupported distribution during shell install | `install_shell_package` warns and returns nonzero; non-Bash selection then falls back to Bash. |
| Atuin installer fails, or Atuin absent after install | **Fatal** (`exit 1`, stderr). |
| Starship installer fails, or Starship absent after install | **Fatal** (`exit 1`, stderr). |
| `ensure_sudo` fails before Starship | **Fatal** (`exit 1`, stderr). |
| `chsh` fails | **Fatal** (`exit 1`, stderr). |
| Non-TTY input | Not a failure: Bash is selected, no prompt, no delay. |

Required failures stop the terminal command and propagate through `setup`
(`run_step` exits nonzero naming the failed step). No success message is printed
after a required failure. `setup`'s EXIT trap clears sudo credentials only when
this run created them, on both success and failure.

---

## 11. Security / Privilege Behavior

- Privileged operations go through `run_root` only. The module contains no raw
  `sudo` command and no `sudo -S`.
- `run_root` authenticates lazily via `ensure_sudo`: a non-interactive
  `sudo -n -v` probe (which also refreshes a still-valid timestamp), and only
  when that fails a single interactive `sudo -v`. There is no retry loop, so a
  cancelled prompt cannot hang the run.
- Operations that require root: installing the shell package (dnf/apt/pacman)
  and `chsh`. Both use `run_root`.
- `chsh` is invoked as `chsh -s <path> <user>` (root plus explicit username) so
  it is non-interactive.
- The Starship official installer performs its own privilege elevation (its
  internal `sudo`) to write `/usr/local/bin`. Terminal runs the installer
  unprivileged and calls `ensure_sudo` first only to pre-cache credentials, so
  that prompt does not occur mid-pipeline; `run_root` is not used for the
  installer.
- Atuin is installed user-level by its official installer and does not require
  sudo. The installer places the binary at `~/.atuin/bin` and owns PATH via
  `~/.atuin/bin/env`, sourced from the selected shell's rc; terminal itself does
  not modify PATH.
- `setup` refuses to run as root (`EUID 0`).
- No service is enabled or started, no firewall rule is changed, and no
  authentication configuration is modified by this command.
- Never store, echo, or log credentials.

---

## 12. External Dependencies

| Dependency | Used for | Notes |
| --- | --- | --- |
| `dnf` / `apt-get` / `pacman` | install Zsh/Fish when missing | privileged, via `run_root` |
| Atuin official installer (`https://setup.atuin.sh`) | install Atuin | user-level to `~/.atuin/bin`; owns PATH via `~/.atuin/bin/env`; network |
| Starship official installer (`https://starship.rs/install.sh`) | install Starship | exact command `curl -sS https://starship.rs/install.sh \| sh -s -- -y`; network |
| Network | Atuin/Starship installers | only when the tool is missing and not dry-run |
| `command -v` | presence detection | shells, Atuin, Starship |
| `getent`, `id` | login-shell detection / target user | read-only |
| `chsh` | change login shell | privileged, via `run_root` |

Starship must never be installed through a distro package manager, COPR, or a
GitHub release binary. No other prompt tool is installed.

---

## 13. Verification

A Senior reviewer should verify, on a sandboxed `HOME` and PATH:

**Syntax and CLI**

- `bash -n setup lib/common.sh modules/terminal_themes.sh`.
- `./setup help` and `./setup version` succeed.
- Invalid/extra arguments fail nonzero with a usage hint.

**Positive behavior (real mode, sandboxed)**

- Shell install path: with the selected shell missing and a fake package
  manager, the module runs the family install command via `run_root` and
  verifies with `command -v`.
- Fallback: when the shell remains missing after install, the module warns,
  falls back to Bash, and configures Bash.
- Atuin/Starship skip when present; install (and re-verify) when missing.
- Init lines are appended exactly once and only the selected shell's rc file is
  modified (plus fish dir creation).
- `chsh -s <path> <user>` runs via `run_root` only when the login shell differs.

**Negative ("must NOT happen")**

- Dry-run: no installers run, no files created, no directory created, no
  `chsh`, no `sudo`/`ensure_sudo` authentication, no network.
- Reruns: exactly one Atuin line and one Starship line (Fish included, despite
  the installer's guarded block); no second `chsh`.
- No references to the removed line prompt tool (Oh My Posh) or its theme
  repository anywhere:
  `grep -RniE 'oh-my-pos[h]|poshtheme[s]' .` returns no matches.
- No raw `sudo` command in `modules/terminal_themes.sh`.

---

## 14. Test Matrix

| Scenario | Expected result |
| --- | --- |
| Fresh Fedora, Bash selected | Bash skipped as installed; Atuin/Starship installed if missing; init lines appended to `~/.bashrc`; no `chsh` |
| Fresh Debian, Zsh selected, zsh missing | `apt-get update` + `apt-get install -y zsh`; `~/.zshrc` init lines; `chsh` to zsh |
| Fresh Arch, Fish selected, fish missing | `pacman -S --noconfirm fish`; fish config dir created; fish init lines; `chsh` to fish |
| Everything installed, selected shell already default | All stages report "already"; no `chsh`; exit 0 |
| Second run (same selection) | No duplicate init lines; no reinstall; no second `chsh` |
| Dry-run (`--dry-run terminal` and `terminal --dry-run`) | Identical output; would-run lines only; zero mutations; no sudo |
| Missing shell, family install fails | Warning; fall back to Bash; configure Bash; exit 0 |
| Missing shell, install unverifiable and Bash also missing | Fatal, nonzero |
| Unsupported distro, Bash selected | Bash path unaffected; no install attempted |
| Unsupported distro, Zsh selected | Warning; fall back to Bash |
| Atuin installer failure | Fatal, nonzero |
| Starship installer failure | Fatal, nonzero |
| `chsh` failure | Fatal, nonzero |
| Non-TTY stdin | Bash selected without prompt; command completes |

---

## 15. Review Checklist

```text
[ ] Shell selection menu appears only for TTY stdin; non-TTY defaults to Bash.
[ ] Missing selected shell is installed via the correct family command.
[ ] Unverifiable shell install falls back to Bash before any config/chsh.
[ ] Dry-run never verifies and never falls back on simulated results.
[ ] Atuin and Starship use official installers only; never distro packages.
[ ] Starship command is exactly `curl -sS https://starship.rs/install.sh | sh -s -- -y`.
[ ] Init lines use exact-line guards and only touch the selected shell rc file.
[ ] `chsh` runs only when needed and via `run_root` with an explicit username.
[ ] All privileged operations use run_root/ensure_sudo; no raw sudo, no sudo -S.
[ ] Dry-run performs zero mutations, zero network, zero sudo.
[ ] Repeated execution creates no duplicate init lines and no second chsh.
[ ] Required failures (Atuin/Starship/chsh/bash fallback) exit nonzero.
[ ] No service, firewall, or authentication configuration is modified.
[ ] No removed-prompt-tool references exist anywhere in the repo.
[ ] bash -n passes and CLI invalid-argument handling is correct.
```

---

## Known implementation notes and mismatches

- **No mismatches found** between the approved contract above and the current
  `modules/terminal_themes.sh` as reviewed for this specification.
- Informational: the Atuin presence predicate matches the official installer's
  real location (`~/.atuin/bin/atuin`) and its PATH-owning `env` file; Fish
  init-idempotency also recognizes the installer's guarded `atuin init fish`
  block.
- Informational: the Debian branch runs `apt-get update` on each shell install;
  this is idempotent and matches the rest of the project's apt convention.
- Informational: fish config-directory creation happens only in real mode and
  only when Fish is the selected shell, before the init lines are appended.
