# `./setup dev` — Engineering Specification

Status: approved contract. Source of truth for the dev command.
Implementation: `modules/dev.sh`, shared helpers in `lib/common.sh`, CLI wiring
in `setup`.

This document describes the **approved intended behavior**. Where the current
implementation differs, the mismatch is called out in "Known implementation
notes and mismatches".

See `docs/terminal.md` for the terminal contract; `dev` depends on neither the
terminal command nor the aliases command.

---

## 1. Overview

- **Command:** `./setup dev`
- **Equivalent dry-run invocations (identical):**
  - `./setup --dry-run dev`
  - `./setup dev --dry-run`
- **Purpose:** set up a complete development environment on a fresh machine
  with one command: system development packages, VS Code, DBeaver, mise with
  Python 3.13, JupyterLab, Codex, OpenCode, and the managed dev shell block.
- **Standalone:** yes. `./setup dev` does **not** require `./setup packages` to
  run first; it installs everything it needs itself. Some work duplicates
  `modules/install_apps.sh` on purpose (VS Code, and the Flathub remote/install
  pattern), and that duplication is allowed.
- **Part of the full flow:** yes. It is the sixth step of `./setup install`
  (packages → language → fonts → aliases → terminal → **dev** → GNOME group).
- **Relationship with other commands:**
  - `packages` (`modules/install_apps.sh`) also installs VS Code/Chrome and
    Flatpak apps; dev deliberately duplicates only VS Code and the Flathub
    pattern, and leaves `install_apps.sh` untouched.
  - `terminal` (`modules/terminal_themes.sh`) installs shells/Atuin/Starship and
    writes exact init lines. dev writes its own managed PATH/mise block; the two
    coexist and never duplicate each other.
  - `aliases` writes the alias block. dev's block uses different markers.
  - dev is the only command that installs the OpenSSH server, but it never
    enables or starts it (see §11).

---

## 2. Scope

### Owned by this command

1. System development package matrix (binary-presence based) for the detected
   family, including the OpenSSH **client and server**.
2. VS Code: official vendor `.rpm`/`.deb` on Fedora/Debian, AUR
   `visual-studio-code-bin` on Arch with automatic `yay` bootstrap.
3. DBeaver Community via Flatpak/Flathub.
4. mise (official installer) + Python 3.13 via `mise use -g python@3.13`.
5. JupyterLab via pipx, pinned to the mise-managed Python, plus `ipykernel`.
6. Codex via npm into the user prefix (`~/.local`), with a managed `~/.npmrc`.
7. OpenCode CLI via the official installer (`--no-modify-path`).
8. Debian-only `fdfind` → `fd` symlink in `~/.local/bin`.
9. Managed dev shell block (PATH + mise activation) in the shell rc files.
10. Completion guidance (reload guidance + README pointer).

### Explicitly outside scope

- PostgreSQL **server** installation, initialization, or startup (only the psql
  client is installed).
- Enabling, starting, or configuring `sshd`; SSH keys, passwords, and
  authentication configuration; firewall changes.
- Docker/Podman/Kubernetes/cloud CLIs, C#/.NET, `yq`, language version managers
  other than mise, PostgreSQL server, and any feature not listed in §1.
- Installing Starship or Atuin (owned by `terminal`).
- The aliases block (owned by `aliases`).
- GNOME configuration, fonts, packages, language.
- Large frameworks, module registries, dependency graphs, state databases,
  rollback engines, or generic configuration engines.

### Source of truth in the repository

- `setup` — CLI parsing, `--dry-run` handling, dispatch (`dev` maps to
  `modules/dev.sh`), failure propagation, sudo cleanup.
- `modules/dev.sh` — the entire behavior described here.
- `lib/common.sh` — `distribution()`, `run()`, `run_root()`, `ensure_sudo()`.
- `modules/install_apps.sh` — read-only reference for the intentional
  duplication (VS Code, Flathub pattern).

Related commands that must **not** be modified to implement dev behavior:
`modules/install_apps.sh`, `modules/terminal_themes.sh`,
`modules/set_aliases.sh`, `setup`, `lib/common.sh`.

---

## 3. Execution Flow

Fixed stage order:

1. **Source + detect.** Source `lib/common.sh`; compute `dtype` via
   `distribution()`.
2. **D01 — system packages.** Build the missing-package list from the
   binary-presence matrix, install the set in one transaction, then re-verify
   every missing binary.
3. **D02 — VS Code.** Skip if `code` present; otherwise vendor install on
   Fedora/Debian (x86_64 only) or `yay`/AUR install on Arch, then verify `code`.
4. **D03 — DBeaver.** Skip if `flatpak info io.dbeaver.DBeaverCommunity`
   succeeds; otherwise ensure the Flathub remote and install, then verify.
5. **D04 — mise + Python 3.13.** Install mise via the official installer when
   missing; then ensure Python 3.13 is configured via `mise use -g python@3.13`
   and verify `python --version` reports 3.13 and `mise which python` resolves.
6. **D05 — JupyterLab.** Skip if `~/.local/bin/jupyter` exists; otherwise
   `pipx install --python "$(~/.local/bin/mise which python)" jupyterlab` and
   `pipx inject jupyterlab ipykernel`, then verify the binary.
7. **D06 — Codex.** Ensure exactly one managed `prefix=$HOME/.local` line in
   `~/.npmrc`; skip if `~/.local/bin/codex` exists; otherwise
   `npm install -g --prefix "$HOME/.local" @openai/codex`, then verify.
8. **D07 — OpenCode.** Skip if `~/.local/bin/opencode` exists; otherwise run
   the official installer with `--no-modify-path` under pipefail, then verify.
9. **D08 — fd symlink + dev rc block + completion.** Debian-only `fd` symlink
   (guarded); strip-and-reappend the managed dev block to `~/.bashrc` (always),
   `~/.zshrc` and fish config (when present or their shells exist); print
   completion guidance.
10. Return `0` on success; any required failure exits nonzero and `setup`
    propagates it.

---

## 4. Decision Tree / Conditions

```text
system packages (D01):
    FOR each matrix entry: IF `command -v <bin>` fails → add family package
    Debian: always append python3-venv
    IF no package missing → report "already installed"
    ELSE install once:
        redhat: dnf makecache; dnf install -y <pkgs>
        debian: apt-get update; apt-get install -y <pkgs>
        arch:   pacman -S --needed --noconfirm <pkgs>
      THEN (real mode) re-check every previously-missing binary → fatal if any absent
    Unsupported distro → fatal

VS Code (D02):
    IF `command -v code` → skip
    ELSE (install path):
        redhat: download linux-rpm-x64 → dnf install -y <rpm>   (x86_64 required)
        debian: download linux-deb-x64 → apt-get install -y <deb> (x86_64 required)
        arch:   IF yay missing → pacman base-devel + git clone AUR + makepkg -si; verify yay
                yay -S --needed --noconfirm visual-studio-code-bin   (not architecture-gated)
      verify `code` (real mode) → fatal if absent

DBeaver (D03):
    IF `flatpak info io.dbeaver.DBeaverCommunity` → skip
    ELSE IF flatpak missing (real mode) → fatal
    IF flathub remote absent → flatpak remote-add --if-not-exists
    flatpak install -y flathub io.dbeaver.DBeaverCommunity
    verify flatpak info (real mode) → fatal if absent

mise (D04):
    IF `command -v mise` OR `-x ~/.local/bin/mise` → skip install
    ELSE sh -c "curl -fsSL https://mise.jdx.dev/install.sh | sh"; verify; fatal if absent
    IF python is 3.13 AND `mise which python` resolves → skip
    ELSE mise use -g python@3.13; verify; fatal if failed

JupyterLab (D05):
    IF -x ~/.local/bin/jupyter → skip
    ELSE IF pipx missing (real mode) → fatal
    pipx install --python "<mise python>" jupyterlab; pipx inject jupyterlab ipykernel
    verify -x ~/.local/bin/jupyter; fatal if absent

Codex (D06):
    ensure ~/.npmrc has exactly one `prefix=$HOME/.local` line (strip others, append)
    IF -x ~/.local/bin/codex → skip install
    ELSE IF npm missing (real mode) → fatal
    npm install -g --prefix "$HOME/.local" @openai/codex; verify; fatal if absent

OpenCode (D07):
    IF -x ~/.local/bin/opencode → skip
    ELSE (set -o pipefail; XDG_BIN_DIR="$HOME/.local/bin" curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path)
    verify; fatal if absent

fd symlink (D08):
    IF dtype == debian AND `command -v fdfind` AND NOT -e ~/.local/bin/fd
        → ln -s "$(command -v fdfind)" ~/.local/bin/fd

dev rc block (D08), real mode:
    FOR ~/.bashrc (always), ~/.zshrc (if exists or zsh present), fish config (if exists or fish present):
        strip existing dev block; append exactly one fresh block
    dry-run: print target lines only

completion:
    print reload guidance and README pointer (never privileged-command text)
```

---

## 5. Implementation Details

```text
setup
  └── run_step modules/dev.sh dev
        └── source lib/common.sh
              ├── distribution()  → redhat | debian | arch | unknown
              ├── run()           → print in dry-run, else execute
              ├── run_root()      → print sudo line in dry-run, else ensure_sudo + sudo
              └── ensure_sudo()   → lazy `sudo -n -v` probe, then one `sudo -v`
```

Key helpers inside `modules/dev.sh`:

- `add_missing <binary> <package>` — append `<package>` when `<bin>` is absent;
  collapse duplicate packages (Arch lists `openssh` for both `ssh` and `sshd`).
- `require_vendor_arch` — fail unless `uname -m` is `x86_64`, invoked only on a
  path that downloads a vendor VS Code package.
- `cleanup_vendor_tmp` / `cleanup_yay_tmp` — EXIT-trap cleanup of `mktemp -d`
  download/build directories (never a fixed `/tmp` path).
- `emit_dev_block <shell>` / `apply_dev_block <rc_file> <shell>` — managed dev
  block (strip-and-reappend).
- `flatpak` probes: `flatpak info <id>` and `flatpak remote-list`.

Managed dev block:

| Marker | Value |
| --- | --- |
| begin | `# >>> linux-postinstall dev >>>` |
| end | `# <<< linux-postinstall dev <<<` |

Block body by shell:

- Bash:
  `export PATH="$HOME/.local/bin:$PATH"`
  `eval "$(~/.local/bin/mise activate bash)"`
- Zsh:
  `export PATH="$HOME/.local/bin:$PATH"`
  `eval "$(~/.local/bin/mise activate zsh)"`
- Fish:
  `fish_add_path "$HOME/.local/bin"`
  `~/.local/bin/mise activate fish | source`

Paths and environment:

- `~/.local/bin` — user-level install root (mise, jupyter, codex, opencode, fd).
- `~/.mise/shims` and `~/.local/bin` are prepended to `PATH` during the run.
- `~/.npmrc` — managed npm user prefix.
- `SETUP_SUDO_MARKER` — exported by `setup` for sudo cleanup.

---

## 6. Distro Behavior

Family detection via `distribution()` from `/etc/os-release` (`ID`, then
`ID_LIKE`): `redhat`, `debian`, `arch`, or `unknown` (fatal).

### D01 binary-presence matrix (binary → package)

| Binary | Fedora | Debian/Ubuntu/Mint | Arch |
| --- | --- | --- | --- |
| `ssh` | `openssh-clients` | `openssh-client` | `openssh` |
| `sshd` | `openssh-server` | `openssh-server` | `openssh` |
| `git` | `git` | `git` | `git` |
| `gcc` | `gcc` | `gcc` | `gcc` |
| `g++` | `gcc-c++` | `g++` | `gcc` |
| `clang` | `clang` | `clang` | `clang` |
| `make` | `make` | `make` | `make` |
| `cmake` | `cmake` | `cmake` | `cmake` |
| `gdb` | `gdb` | `gdb` | `gdb` |
| `python3` | `python3` | `python3` | `python` |
| `pip3` | `python3-pip` | `python3-pip` | `python-pip` |
| `pipx` | `pipx` | `pipx` | `python-pipx` |
| `node` | `nodejs` | `nodejs` | `nodejs` |
| `npm` | `npm` | `npm` | `npm` |
| `go` | `golang` | `golang-go` | `go` |
| `vim` | `vim` | `vim` | `vim` |
| `nvim` | `neovim` | `neovim` | `neovim` |
| `fzf` | `fzf` | `fzf` | `fzf` |
| `rg` | `ripgrep` | `ripgrep` | `ripgrep` |
| `fd` (Debian probe: `fdfind`) | `fd-find` | `fd-find` | `fd` |
| `jq` | `jq` | `jq` | `jq` |
| `tmux` | `tmux` | `tmux` | `tmux` |
| `sqlite3` | `sqlite` | `sqlite3` | `sqlite` |
| `psql` | `postgresql` | `postgresql-client` | `postgresql` |
| `curl` | `curl` | `curl` | `curl` |
| `wget` | `wget` | `wget` | `wget` |
| `flatpak` | `flatpak` | `flatpak` | `flatpak` |

Debian exception: `python3-venv` has no dedicated binary probe and is **always**
appended (apt is idempotent, so an extra update+install is harmless).

Debian exception: the `fd` row probes the **binary** `fdfind` (Debian's package
does not provide an `fd` binary) and installs the **package** `fd-find`. Fedora's
package is also `fd-find` but provides the `fd` binary, so Fedora probes `fd`.

### D01 install command per family

| Family | Command |
| --- | --- |
| redhat | `dnf makecache`, then `dnf install -y <pkgs>` |
| debian | `apt-get update`, then `apt-get install -y <pkgs>` |
| arch | `pacman -S --needed --noconfirm <pkgs>` (never `-Syu`) |

### D02 VS Code per family

| Family | Source | Install |
| --- | --- | --- |
| redhat | `https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64` | `dnf install -y <rpm>` |
| debian | `...os=linux-deb-x64` | `apt-get install -y <deb>` |
| arch | AUR `visual-studio-code-bin` | bootstrap `yay`, then `yay -S --needed --noconfirm visual-studio-code-bin` |

Vendor packages are x86_64-only; `require_vendor_arch` fails otherwise on the
download path.

### Arch `yay` bootstrap (D02)

Only when `yay` is missing:

1. `run_root pacman -S --needed --noconfirm base-devel`
2. `run git clone --depth 1 https://aur.archlinux.org/yay.git <tmp>/yay`
3. `(cd <tmp>/yay && run makepkg -si --noconfirm)` — **non-root**
4. Verify `command -v yay`; fatal on failure.

Never `-Syu`. This automatic bootstrap is intentionally different from
`install_apps.sh`, which requires `yay` to exist and fails with instructions.

### D04–D07 (family-independent)

mise, JupyterLab via pipx, Codex via npm user-prefix, and OpenCode via the
official installer behave the same across families.

### D08 Debian `fd`

Debian ships the find-tool binary as `fdfind`; dev creates
`~/.local/bin/fd → $(command -v fdfind)` on Debian only. Fedora/Arch provide
`fd` from their packages.

---

## 7. Files and Configuration

| Path | Access | Purpose |
| --- | --- | --- |
| `/etc/os-release` (or `$OS_RELEASE_FILE`) | read | family detection |
| `~/.npmrc` | create/modify | exactly one managed `prefix=$HOME/.local` line; other lines preserved; existing `prefix=` lines removed |
| `~/.local/bin/` | create/read | user-level install root |
| `~/.local/bin/fd` | create (Debian) | symlink to `fdfind` |
| `~/.local/bin/mise`, `jupyter`, `codex`, `opencode` | read/created by installers | presence probes / install targets |
| `~/.mise/` | created by mise | Python toolchain |
| `~/.bashrc` | strip+append block | dev block (always) |
| `~/.zshrc` | strip+append block | dev block (if file exists or zsh present) |
| `~/.config/fish/config.fish` | create dir + strip+append block | dev block (if file exists or fish present) |
| `<mktemp -d>` | create/remove | vendor download and yay build; removed on EXIT |
| `$SETUP_SUDO_MARKER` | touch/remove (via `setup`) | sudo cleanup marker |

Notes:

- The dev block is delimited by `# >>> linux-postinstall dev >>>` …
  `# <<< linux-postinstall dev <<<` and is stripped and re-appended each run; no
  duplicate blocks.
- Content outside the managed dev block is preserved.
- dev does **not** touch `~/.bashrc`/`~/.zshrc` content outside its block, does
  not touch the aliases block or terminal init lines, and does not modify
  `/etc/ssh/sshd_config`, `/etc/shells`, firewall rules, or services.
- Temporary directories are always under `mktemp -d` (never a fixed `/tmp`
  path) and are cleaned up via an EXIT trap.

---

## 8. Dry-Run Contract

Both `./setup --dry-run dev` and `./setup dev --dry-run` behave identically.
`SETUP_DRY_RUN=1` must guarantee:

**Allowed (read-only / reporting):**

- Reading `/etc/os-release`.
- Presence checks (`command -v`, `-x` path tests).
- Read-only `flatpak info` / `flatpak remote-list` probes (these may create
  Flatpak cache directories as a side effect of the real `flatpak` binary; that
  is environmental, not a script mutation — see notes).
- Printing would-run lines for every intended mutation: package installs
  (`would run: sudo …`), vendor VS Code install, yay bootstrap, DBeaver install,
  mise/Python/JupyterLab/Codex/OpenCode installs, the fd symlink, and the dev rc
  targets (`would run: write linux-postinstall dev block to <file>`).

**Forbidden:**

- Package installation or index refresh (`dnf`/`apt-get`/`pacman`/`yay`).
- Network access (no vendor download, AUR clone, mise/OpenCode installers).
- File writes or directory creation (`~/.npmrc`, `~/.local`, `~/.bashrc`,
  `~/.zshrc`, fish config, fd symlink).
- `sudo` invocation or credential authentication (`run_root` and `ensure_sudo`
  only print/return early).
- Service or firewall changes (never performed in any mode).

Dry-run must be testable with a sandboxed `HOME` and PATH tripwires: assert zero
files created, zero installers run, zero sudo, and only would-run output.

---

## 9. Idempotency

| Stage | Pre-check |
| --- | --- |
| D01 | binary-presence matrix; no missing → report and skip install |
| D02 | `command -v code` → skip |
| D03 | `flatpak info <id>` → skip |
| D04 | `command -v mise`/`-x ~/.local/bin/mise`; Python 3.13 + `mise which python` → skip |
| D05 | `-x ~/.local/bin/jupyter` → skip |
| D06 | `~/.npmrc` exactly-one managed prefix line; `-x ~/.local/bin/codex` → skip |
| D07 | `-x ~/.local/bin/opencode` → skip |
| D08 fd | `[ ! -e ~/.local/bin/fd ]` guard |
| D08 block | strip-and-reappend → exactly one block per rc file |

Repeated execution is safe: no reinstall, no duplicate managed block, no
duplicate `prefix=` line, and the fd symlink is not recreated. The managed
`.npmrc` rewrite is idempotent because existing `prefix=` lines are removed and
exactly one managed line is appended.

---

## 10. Failure Behavior

| Situation | Behavior |
| --- | --- |
| Unsupported distribution | **Fatal** (`exit 1`, stderr), before any install |
| D01 index refresh or install fails | **Fatal** |
| D01 post-verify: any previously-missing binary still absent | **Fatal** |
| VS Code download/install fails | **Fatal** |
| Vendor arch not x86_64 on the download path | **Fatal** |
| yay `base-devel` install, clone, or `makepkg` fails; yay absent after build | **Fatal** |
| VS Code absent after install | **Fatal** |
| flatpak command missing (real mode, DBeaver needed) | **Fatal** |
| Flathub remote add or DBeaver install fails; absent after install | **Fatal** |
| mise install/verify, or Python 3.13 setup/verify fails | **Fatal** |
| pipx install/inject fails, or Jupyter binary absent | **Fatal** |
| npm install fails, or Codex binary absent | **Fatal** |
| OpenCode installer fails (including curl failure via pipefail), or binary absent | **Fatal** |
| fd symlink creation fails (Debian) | **Fatal** |

There is no warning-only path in dev: every install stage is required.
**Post-verification is fatal for every install stage in real mode.** Dry-run
never post-verifies and never reports success for a simulated install. A
required failure exits nonzero with an stderr message and `setup`'s `run_step`
names the failed step; `setup` never prints the success message after a failure.
`setup`'s EXIT trap clears sudo credentials only when this run created them.

---

## 11. Security / Privilege Behavior

- All privileged operations go through `run_root` in `lib/common.sh`. The module
  contains **no** raw `sudo` command and **no** `sudo -S`.
- `run_root` authenticates lazily via `ensure_sudo`: a `sudo -n -v` probe (also
  refreshing a still-valid timestamp), and only when that fails a single
  interactive `sudo -v`. No retry loop; a cancelled prompt cannot hang.
- `setup` exports `SETUP_SUDO_MARKER` and touches it only after a successful
  interactive `sudo -v`; its EXIT trap runs `sudo -k` only when the marker
  exists, so a timestamp that predates the run is never cleared. Cleanup runs on
  success and failure. Dry-run never invokes or authenticates sudo.
- User-level operations (mise, pipx, npm user-prefix, OpenCode installer, fd
  symlink, rc blocks) run **without** root.
- **SSH:** the OpenSSH **client and server** packages are installed.
  - `sshd` must **not** be enabled or started.
  - `sshd_config` must **not** be modified.
  - Firewall rules must **not** be modified.
  - SSH keys, passwords, and authentication configuration must **not** be
    modified.
  - Manual activation is documented only in `README.md` and is never printed or
    executed by `modules/dev.sh` (the module must contain no
    privileged-command text).
- **PostgreSQL:** only the psql client is installed. The PostgreSQL **server**
  must **not** be initialized or started; no `initdb`, `pg_ctl`,
  `pg_ctlcluster`, data-directory creation, or service operation is performed.
- No service is enabled/started and no firewall rule is changed in any mode.
- Never store, echo, or log credentials.

---

## 12. External Dependencies

| Dependency | Used for | Notes |
| --- | --- | --- |
| `dnf` / `apt-get` / `pacman` | D01 system packages, VS Code vendor installs, yay `base-devel` | privileged via `run_root` |
| `yay` (AUR) | Arch VS Code | auto-bootstrapped via `base-devel` + `git` + `makepkg` |
| `code.visualstudio.com` | VS Code `.rpm`/`.deb` download | x86_64 only; `wget` |
| Flathub (`https://flathub.org/repo/flathub.flatpakrepo`) | DBeaver remote | via `flatpak remote-add` |
| `https://mise.jdx.dev/install.sh` | mise install | official installer, `curl \| sh` |
| `pipx` | JupyterLab | uses the mise Python |
| `npm` | Codex | user prefix `~/.local` |
| `https://opencode.ai/install` | OpenCode | official installer, `--no-modify-path` |
| `git` | yay AUR clone | via `run` |
| `curl`, `wget` | downloads | via `run` |
| Network | all downloads/installers | only when the target is missing and not dry-run |

No distro package, COPR, or GitHub release binary is used for mise, Codex,
OpenCode, or Starship. DBeaver is Flatpak only.

---

## 13. Verification

A Senior reviewer should verify, on a sandboxed `HOME` and PATH:

**Syntax and CLI**

- `bash -n setup lib/common.sh modules/dev.sh`.
- `./setup help` and `./setup version` succeed.
- Invalid/extra arguments fail nonzero with a usage hint.

**Positive behavior**

- Each stage skips when its artifact is present and installs when missing.
- D01 installs exactly the missing family packages in one transaction and
  re-verifies every previously-missing binary.
- VS Code vendor install on Fedora/Debian; yay bootstrap + AUR install on Arch.
- DBeaver installs via Flatpak/Flathub and is verified with `flatpak info`.
- mise/Python 3.13, JupyterLab (+ipykernel), Codex (`~/.npmrc` managed prefix),
  and OpenCode install and verify.
- Debian creates the `fd` symlink; Fedora/Arch do not.
- Exactly one dev block per rc file, with the documented content and markers.
- `setup install` runs dev as the sixth step and stops on a dev failure.

**Negative ("must NOT happen")**

- Dry-run: no package install, no network, no file/directory creation, no sudo
  authentication, no service changes.
- `sshd` is not enabled or started; no `sshd_config`, firewall, or
  authentication change.
- PostgreSQL server is not initialized or started (`initdb`, `pg_ctl`,
  `pg_ctlcluster` never run).
- No raw `sudo` in `modules/dev.sh`; no `sudo -S` anywhere in code.
- No `systemctl`/`systemctl enable|start` text in `modules/dev.sh`.
- No removed-prompt-tool references: `grep -RniE 'oh-my-pos[h]|poshtheme[s]' .`
  returns no matches.
- File checks: `grep -nE 'sudo|systemctl' modules/dev.sh` is empty; no `-Syu`
  except a comment; `modules/install_apps.sh` is unchanged.

---

## 14. Test Matrix

| Scenario | Expected result |
| --- | --- |
| Fresh environment (Fedora) | D01 installs all missing packages; VS Code `.rpm`; DBeaver Flatpak; mise/Python/JupyterLab/Codex/OpenCode; dev block; exit 0 |
| Fresh environment (Debian) | Same, plus `.deb` VS Code, `postgresql-client`, `python3-venv`, and `fdfind`→`fd` symlink |
| Fresh environment (Arch) | Same, with `pacman -S --needed --noconfirm`, `yay` bootstrap, AUR VS Code, `openssh` deduped |
| Partially installed | Only missing stages run; present stages report "already installed" |
| Fully installed (idempotent) | All stages skip; one dev block per rc; no reinstall; exit 0 |
| Second run | No duplicate block, no duplicate `prefix=` line, no recreated fd symlink |
| Dry-run `--dry-run dev` | Would-run lines only; zero mutations; no sudo/network |
| Dry-run `dev --dry-run` | Byte-identical to the other order |
| Unsupported distro | Fatal, nonzero, before any install |
| D01 install failure / partial install | Fatal after re-verify |
| VS Code install failure | Fatal |
| Non-x86_64 with VS Code missing | Fatal (vendor arch check) |
| yay bootstrap failure | Fatal |
| DBeaver/Flatpak failure | Fatal |
| mise / Python 3.13 failure | Fatal |
| JupyterLab / Codex / OpenCode failure | Fatal |
| SSH client+server | Installed; `sshd` not enabled/started; no config change |
| PostgreSQL | psql client only; no server initialization/startup |
| sudo boundaries | Privileged ops via `run_root` only; user-level installs unprivileged |
| Failure propagation | `setup` stops and names the failed step; no success message |

---

## 15. Review Checklist

```text
[ ] dev is standalone and does not depend on ./setup packages.
[ ] Fixed stage order is D01→D02→D03→D04→D05→D06→D07→D08.
[ ] The full package matrix is family-correct (Fedora/Debian/Arch names).
[ ] Arch uses pacman -S --needed --noconfirm and never -Syu.
[ ] yay is bootstrapped non-root (base-devel, git clone, makepkg) and verified.
[ ] VS Code uses official vendor builds / AUR; code presence gates install.
[ ] DBeaver uses Flatpak/Flathub and is verified with flatpak info.
[ ] mise uses the official installer; Python is 3.13 via mise.
[ ] JupyterLab uses pipx pinned to the mise Python + ipykernel.
[ ] Codex uses a managed npm user prefix (~/.npmrc exactly one prefix= line).
[ ] OpenCode uses the official installer with --no-modify-path.
[ ] Debian creates the fdfind→fd symlink; Fedora/Arch do not.
[ ] The dev rc block uses the documented markers and appears exactly once.
[ ] Every install stage post-verifies fatally in real mode.
[ ] Dry-run performs no install, network, file write, or sudo auth.
[ ] Repeated execution is idempotent (no duplicates).
[ ] Required failures propagate; setup names the failed step.
[ ] Privileged ops use run_root/ensure_sudo only; no raw sudo, no sudo -S.
[ ] sshd is installed but never enabled/started; no sshd_config/firewall/auth changes.
[ ] PostgreSQL server is never initialized or started.
[ ] No removed-prompt-tool references exist anywhere.
[ ] bash -n passes; alias/duplication boundaries stay intact.
```

---

## Known implementation notes and mismatches

- **No contract/implementation mismatches found** for the stages above.
- **Arch `postgresql`:** Arch has no separate client-only package, so the
  spec-mandated `postgresql` package bundles server binaries. The module installs
  it (for `psql`) but never runs `initdb`, `pg_ctl`, or starts a service, so the
  "no PostgreSQL server initialized/started" contract holds; only unused server
  binaries are present. This is a deliberate spec decision, recorded for
  transparency.
- **Fedora `postgresql`:** on Fedora this is the client package; the server
  package `postgresql-server` is never requested.
- **Debian `python3-venv`:** always appended, so a Debian rerun performs
  `apt-get update` + install even when everything else is present. This is
  explicitly sanctioned by the approved plan (apt is idempotent).
- **D05 dry-run line:** dry-run prints the pipx JupyterLab command with the
  literal `"$(~/.local/bin/mise which python)"` rather than evaluating the
  substitution, so a fresh `HOME` without mise produces no stderr noise. The real
  branch still resolves the mise Python.
- **D03 read-only probes in dry-run:** the real `flatpak` binary may create
  `~/.cache/flatpak` / `~/.local/share/flatpak` skeleton entries when
  `flatpak info`/`remote-list` run in dry-run. This is environmental and mirrors
  the established `install_apps.sh` probe convention; the module itself writes
  nothing.
- **D04 mise failure detection:** the mise installer runs as
  `sh -c "curl … | sh"`; a curl failure can still return success, so a failed or
  empty install is caught by the subsequent presence/version verification,
  which is fatal.
