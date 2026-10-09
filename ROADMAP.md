# ROADMAP — `./setup dev` implementation

This roadmap is the **persistent source of truth** for building the self-contained
`./setup dev` command. If work is interrupted, re-read this file, note the
`## Current state` section, inspect the repository, and resume at the first task
whose `Senior review` is not `PASS`.

## Status legend

- **Senior:** `NOT REVIEWED` → `FAIL` (fix, re-review) → `PASS` (done, gated).
- **Commit:** `NOT AUTHORIZED` until the user authorizes a commit. No commit
  happens during this project unless the user explicitly asks for one.
- **Validation result:** recorded exactly as run by Developer and by Senior.

## Current state

- **Commits:** dev implementation `1bd1793`, dev/terminal specs `583855d`;
  T02 fix pending explicit commit authorization.
- **Completed tasks:** T01, D01, D02, D03, D04, D05, D06, D07, D08, D09, D10, T02.
- **In progress:** none.
- **Failed tasks:** none (D07 and D09 each had one FAIL→fix→PASS cycle; T02 passed review first time).
- **Remaining:** none.
- **Next task:** none — T02 PASS; awaiting authorization to commit it plus the
  documentation follow-up.

## Fixed context (from the approved plan)

- `./setup dev` must be **fully self-contained**: fresh supported distro →
  complete development environment, no dependency on `./setup packages`.
- Every dependency: **installed → skip, missing → install**. Idempotency beats
  avoiding duplication. Duplication with `modules/install_apps.sh` is allowed
  and intentional. **Do not modify `modules/install_apps.sh`.**
- **Locked decisions:**
  - mise manages **Python only**; Node.js/Go stay distro packages.
  - Python 3.13 via mise; JupyterLab via pipx; Codex via npm user-prefix;
    OpenCode via official installer (`--no-modify-path`, `XDG_BIN_DIR`);
    DBeaver via Flatpak; VS Code = official Microsoft `.rpm`/`.deb`, Arch =
    `visual-studio-code-bin` via yay with automatic yay bootstrap from AUR;
    Debian `fdfind` → `~/.local/bin/fd` user symlink.
  - C#/.NET deferred; no yq; no Docker/Podman/k8s/cloud CLIs; no PostgreSQL
    server requirement.
  - Arch installs use `pacman -S --needed --noconfirm <missing>` only; **never
    `pacman -Syu`** (no forced full system upgrade).
  - SSH: install OpenSSH **client and server**; **never** enable/start the
    service; **never** touch sshd_config/firewall/auth/keys/passwords; document
    the manual enable command only. `sshd` presence verified via `command -v sshd`.
  - Sudo: only `ensure_sudo()`/`run_root()` from `lib/common.sh`. No second
    mechanism, no `sudo -S`, no stored passwords. User-level tools stay
    user-level (`~/.local/bin`).
  - Failure policy: unsupported distro, index refresh failure, package install
    failure, VS Code download/install/verify failure, Arch yay bootstrap
    failure, Flathub/DBeaver failure, mise/installer failure, python install
    failure, pipx missing, Jupyter/Codex/OpenCode install-or-verify failure →
    all **fatal** (nonzero, step named, no success message). No warning-only
    path for missing dev dependencies.
- **Files that may change:** `modules/dev.sh`, `ROADMAP.md`, `AGENTS.md`,
  `README.md`, `modules/README.md`, sandbox harness under `/tmp/opencode/vt`.
- **Files that must stay unchanged** (only change if a real blocker is found):
  `modules/install_apps.sh`, `setup`, `lib/common.sh`,
  `modules/set_aliases.sh`, `modules/terminal_themes.sh`.
- **No framework, no abstraction layer**, no `lib/packages.sh`. Code must
  mirror existing repo conventions (see `modules/set_aliases.sh`,
  `modules/install_apps.sh`, `lib/common.sh`).
- **Sandbox tests only.** Never run package installs, sudo authentication, or
  network operations against the live machine. All real-mode testing happens in
  sandbox HOMEs with tripwire/fake PATHs under `/tmp/opencode/vt`.

---

## T01 — Rebuild ROADMAP.md (dev-focused)

- **Objective:** Replace the old roadmap with this persistent, task-driven
  roadmap for the `./setup dev` project. Done (created with this file).
- **Scope/files:** `ROADMAP.md`.
- **Implementation requirements:** Records the fixed context above, task-by-task
  plan (D01–D10), per-task ID / objective / scope / requirements / validation /
  senior-review status / commit status, and the current-state block.
- **Validation/tests:** Re-read the file; confirm every task has the seven
  fields and the current-state block identifies the next task.
- **Senior review:** PASS (orchestrator-created; contains the review gates for
  all later tasks).
- **Commit:** NOT AUTHORIZED.

---

## D01 — System development packages + SSH (dev.sh system step)

- **Objective:** Implement the system-package stage of `dev.sh`: per-family
  binary-presence matrix, build a missing-package list, one install transaction
  per family with index refresh, post-install verification with fatal
  propagation, dry-run support, and unsupported-distro handling. Includes SSH
  client+server installation (verified installed, never enabled/started).
- **Scope/files:** `modules/dev.sh` (scaffold: header, `distribution()`,
  dry-run plumbing, system step only — later tasks add their sections);
  `/tmp/opencode/vt/run_dev.sh` (new harness group for the system step);
  `run_abc.sh` (replace the placeholder-assertion in group A with a safe
  dry-run dev smoke check).
- **Implementation requirements:**
  - dev.sh must source `lib/common.sh` the same way `install_apps.sh` does,
    and must fail clearly on unsupported distro.
  - Binary→package matrix (add only when `command -v <binary>` is missing):
    - common families: `ssh`→openssh client, `sshd`→openssh server, `git`,
      `gcc`, `g++`, `clang`, `make`, `cmake`, `gdb`, `python3`, `pip3`,
      `pipx`, `node`, `npm`, `go`, `vim`, `nvim`, `fzf`, `rg`, `fd`/`fdfind`,
      `jq`, `tmux`, `sqlite3`, `psql`, `curl`, `wget`, `flatpak`.
    - Fedora: `openssh-clients`, `openssh-server`, `gcc-c++` (g++),
      `python3-pip` (pip3), `pipx`, `golang`, `fd-find` (fd binary),
      `sqlite`, `postgresql` (psql). `python3`/`nodejs`/`npm`/etc. as needed.
    - Debian/Ubuntu/Mint: `openssh-client`, `openssh-server`, `g++` (g++),
      `python3-pip` (pip3), `python3-venv` (always included on Debian, no
      binary probe; package-manager idempotent), `pipx`, `golang-go`,
      `fd-find` (fdfind binary), `sqlite3`, `postgresql-client` (psql).
    - Arch: `openssh` (covers client+server via one package), `gcc` (includes
      g++), `python-pip` (pip), `python-pipx`, `go`, `fd`, `sqlite`,
      `postgresql` (psql).
  - Build one `missing_packages` list; when non-empty:
    - Fedora: `run_root dnf makecache` then `run_root dnf install -y …`.
    - Debian: `run_root apt-get update` then `run_root apt-get install -y …`.
    - Arch: `run_root pacman -S --needed --noconfirm …` (no `-Syu`).
    - Index refresh happens **only** when the list is non-empty (no network on
      idle reruns).
  - Post-install verification: for every binary that was missing, re-run
    `command -v`; any still missing → fatal error naming the missing tools.
    In dry-run, verification is skipped.
  - Dry-run: print `would run: sudo dnf makecache`/`sudo apt-get update` and
    `would run: sudo dnf|apt-get|pacman install … <missing list>`; if nothing
    missing print an "all required system tools present" message. Never
    executes anything, never authenticates, never refreshes indexes.
  - SSH: install client+server exactly as above. **Never** run
    `systemctl enable/start/restart`, never edit sshd_config. A final module
    message documents the manual enable command per family (text only; this can
    live in D10's message polish, but emitting the note in dev.sh belongs to
    this step's intent — keep it minimal: a simple guidance line is acceptable).
  - No raw `sudo` in dev.sh; only `run_root`. No `sudo -S` anywhere.
  - `bash -n modules/dev.sh` must pass.
- **Validation/tests** (new `/tmp/opencode/vt/run_dev.sh`, group DEV-SYS; test
  must be safe to rerun):
  - Fedora/Debian/Arch `--dry-run dev` via `OS_RELEASE_FILE` + sandbox PATH
    without the dev binaries: exact `would run:` install lines including the
    correct per-family package names and SSH client/server packages; rc 0.
  - Fedora/Debian/Arch dry-run: tripwire log has no HARD/FAIL lines; sandbox
    HOME untouched; both argument orders (`--dry-run dev`, `dev --dry-run`).
  - Real-mode fresh install with a fake package manager that materializes stub
    binaries in a sandbox bin dir on PATH (dir pre-created empty): all systems
    tools verified present afterwards; install ran once.
  - Re-run with all binaries present: rc 0, no install lines, no index refresh.
  - Fake pkg manager failing install → nonzero, `Failed at step 'dev'`, no
    completion message.
  - Post-install verification failure (fake installs nothing): fatal exit.
  - Unsupported distro (osrel/nixos or gentoo): nonzero, "Unknown or
    unsupported distribution".
  - SSH: after a real mode run, `sshd` present; **no** `systemctl`/enable/start
    anywhere in the log or output of dev-only tests.
  - Group A in `run_abc.sh`: dev placeholder assertion replaced with a safe
    deterministic dev dry-run smoke check (sandbox PATH + osrel fedora), rc 0.
- **Validation result:** Developer + Senior ran `bash -n` (all ok);
  `run_dev.sh` DEV-SYS `pass=59 fail=0` (x2, rerun-safe); `run_abc.sh`
  A/B/C/K `pass=43 fail=0`; hygiene greps (prompt-tool phrases, raw `sudo`,
  `sudo -S`, `systemctl`/`sshd_config`) all empty. Install-failure is
  exercised via the index-refresh branch (T4 uses `DEVSOFT_RC` on
  `makecache`); the `dnf install` failure branch is covered by inspection
  (identical `if ! run_root … exit 1` pattern). Non-blocking.
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D02 — VS Code (vendor/AUR) + Arch yay bootstrap

- **Objective:** Add the VS Code stage to dev.sh. `code` present → skip; `code`
  missing → install the official Microsoft build per family (Fedora `.rpm`
  via dnf, Debian `.deb` via apt, Arch AUR `visual-studio-code-bin` via yay),
  verify `code`, failure → fatal. On Arch, bootstrap yay automatically
  (non-interactive) when missing.
- **Scope/files:** `modules/dev.sh` (VS Code section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-VSCODE).
- **Implementation requirements:**
  - Mirror the vendor-install pattern from `install_apps.sh` lines 128–265
    (x86_64 gate via `uname -m`, `mktemp -d` + cleanup trap, `wget` the
    official URL, `run_root`/`run` install). Dry-run prints the same style of
    would-run lines as `install_apps.sh` (adapt for the separate dev flow).
  - Arch yay bootstrap (only when `code` missing **and** `yay` missing):
    - Ensure `base-devel` via `run_root pacman -S --needed --noconfirm base-devel`
      (idempotent; only invoked when a build is actually required).
    - `mktemp -d` (real mode only), `run git clone --depth 1 https://aur.archlinux.org/yay.git …`,
      then `(cd <dir> && run makepkg -si --noconfirm)`; non-root builder (setup
      already rejects EUID 0); internal sudo uses the cached credentials from
      the earlier `ensure_sudo`. Verify `command -v yay`; failure → fatal.
    - Then `run yay -S --needed --noconfirm visual-studio-code-bin`; verify
      `command -v code`; failure → fatal.
  - Dry-run must print the yay-bootstrap would-run lines (clone + makepkg)
    without creating directories or running anything.
- **Validation/tests:** fedora `.rpm` dry/real path; debian `.deb` dry/real
  path; arch dry shows base-devel + clone + makepkg + yay install lines; arch
  real with fake git/curl/makepkg/yay materializing `yay`/`code` stubs in the
  sandbox bin dir; `code` pre-present → skip with no install; vendor download
  failure → fatal; arch without a successful yay build → fatal.
- **Validation result:** Developer + Senior ran `bash -n` (all ok); `run_dev.sh`
  DEV-SYS 59/0 + DEV-VSCODE 56/0 (x3, rerun-safe, self-healing after fakes
  mutated); `run_abc.sh` 43/0; `run_de.sh` 31/0. `run_fgh.sh` 260/4 and
  `run_ijl.sh` 38/1 remain — the expected pre-D10 gaps only (S3/S6 bin-hard
  fixture does not materialize dev tools `pipx fd psql`; group L flags
  ` M ROADMAP.md` + stray `?? TODO.md`). No new failures. Hygiene greps
  (prompt-tool phrases, raw `sudo`, `sudo -S`, `systemctl`/`sshd_config`)
  empty. Ad-hoc Senior checks confirm wget failure and makepkg-without-yay
  failures are fatal with correct messages. Non-blocking: vendor-download
  failure and Arch non-x86_64 gate are covered by inspection/behavior, not by
  a dedicated suite case (`require_vendor_arch` not called on the Arch path).
- **Senior review:** PASS (two minor, non-blocking notes recorded above).
- **Commit:** NOT AUTHORIZED.

---

## D03 — DBeaver via Flatpak/Flathub

- **Objective:** Add the DBeaver stage. Install `io.dbeaver.DBeaverCommunity`
  via the system Flatpak if not present; add the Flathub remote only if
  missing; verify; failure → fatal.
- **Scope/files:** `modules/dev.sh` (DBeaver section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-DBEAVER).
- **Implementation requirements:** mirror `install_apps.sh` flathub-remote +
  per-app install pattern (lines 75–124) for the single DBeaver id, using
  `flatpak info io.dbeaver.DBeaverCommunity` as the idempotency probe and
  post-install verification. Flatpak command is part of the D01 system set;
  if it is still missing, that is fatal. Dry-run prints the would-run
  remote-add + install lines. No service, no permission changes.
- **Validation/tests:** dry-run remote-add+install; real install with remote-add
  before app install; already-installed (no ops); verify-failure → fatal;
  remote already exists → no remote-add.
- **Validation result:** Developer + Senior ran `bash -n` (ok); `run_dev.sh`
  DEV-SYS 59/0, DEV-VSCODE 56/0, DEV-DBEAVER 34/0 (x2, rerun-safe). Suites:
  `run_abc.sh` 43/0, `run_de.sh` 31/0; `run_fgh.sh` 260/4, `run_ijl.sh` 38/1
  unchanged (expected pre-D10). Hygiene greps empty; no sudo/systemctl
  references in dev.sh. Behavior verified live with `--dry-run dev`.
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D04 — mise + Python 3.13

- **Objective:** Add the runtime-manager stage. Install mise (user-level,
  `~/.local/bin`) via the official installer unless already present; install
  and set Python 3.13 through mise; verify both; failure → fatal.
- **Scope/files:** `modules/dev.sh` (mise + python section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-MISE).
- **Implementation requirements:** user-level mise to `~/.local/bin` via the
  official installer (`curl -fsSL https://mise.jdx.dev/install.sh | sh`) unless
  already present (`command -v mise` or `$HOME/.local/bin/mise` exists). In
  dry-run print that exact pipeline; in real mode run it and verify mise is
  available, else fatal. Once mise is present, run `mise use -g python@3.13`
  and verify `python --version` starts with `Python 3.13` and `mise which
  python` returns a non-empty path; dry-run prints that command; idempotent if
  already satisfied; fatal on failure. PATH must include `$HOME/.local/bin`
  and `$HOME/.mise/shims` for real-mode checks/runs. No system package
  installs for mise/Python.
- **Validation/tests:** dry-run prints installer and python use lines; real fresh
  installs mise then sets Python 3.13; mise already present → skip installer;
  Python 3.13 already configured → skip `mise use`; installer failure →
  fatal; `mise use` failure → fatal; bad Python version → fatal.
- **Validation result:** Developer + Senior ran `bash -n` (ok); `run_dev.sh`
  DEV-SYS 59/0, DEV-VSCODE 56/0, DEV-DBEAVER 34/0, DEV-MISE 48/0 (x2,
  rerun-safe, outputs identical). Suites: `run_abc.sh` 43/0, `run_de.sh` 31/0;
  `run_fgh.sh` 260/4, `run_ijl.sh` 38/1 unchanged (expected pre-D10).
  Hygiene: prompt-tool grep empty; no `sudo`/`systemctl`/`sshd_config` in
  dev.sh; no `-Syu` except comment. Code follows the task-specified
  verification (not the older `mise ls`+explicit `$HOME/.local/bin/mise`
  variant).
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D05 — JupyterLab via pipx

- **Objective:** Add the data-tooling stage. Install JupyterLab into an isolated
  pipx venv (system pip never polluted), running under the mise Python, with
  ipykernel injected; verify; failure → fatal.
- **Scope/files:** `modules/dev.sh` (pipx/jupyter section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-JUPYTER).
- **Implementation requirements:**
  - Probe `[ -x "$HOME/.local/bin/jupyter" ]`; when missing:
    `pipx install --python "$(~/.local/bin/mise which python)" jupyterlab`
    then `pipx inject jupyterlab ipykernel`. Real mode only; dry-run prints
    both lines. If `command -v pipx` is missing (system step failed), fatal
    with a clear message.
  - Post-verify `[ -x "$HOME/.local/bin/jupyter" ]`; fatal on failure.
- **Validation/tests:** dry prints both lines; real fresh install+inject; already
  present → skip; pipx missing → fatal; jupyter binary not created → fatal.
- **Validation result:** Developer + Senior ran `bash -n` (ok);
  `run_dev.sh` totals 235 PASS/0 FAIL (DEV-SYS 59/0, DEV-VSCODE 56/0,
  DEV-DBEAVER 34/0, DEV-MISE 48/0, DEV-JUPYTER 38/0), identical over 2 runs.
  Suites: `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh` 260/4 (unchanged),
  `run_ijl.sh` 37/2 (unchanged baseline: includes `ROADMAP.md:263` hygiene
  hit added earlier + pre-existing untracked files). No new failures.
  Hygiene greps clean in changed files; no commits.
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D06 — Codex via npm user-prefix

- **Objective:** Add the AI-tool stage. Install Codex user-level
  (`~/.local/bin/codex`) via `npm install -g --prefix` into `~/.local`, with
  an idempotently-managed `prefix=$HOME/.local` line in `~/.npmrc`; verify;
  failure → fatal.
- **Scope/files:** `modules/dev.sh` (codex section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-CODEX).
- **Implementation requirements:**
  - Probe `[ -x "$HOME/.local/bin/codex" ]`; when present → skip message.
    Always ensure `~/.npmrc` has exactly one `prefix=$HOME/.local` line
    (strip existing `prefix=` lines, append the managed one — non-destructive
    to other lines); when codex missing, run
    `npm install -g --prefix "$HOME/.local" @openai/codex`. Real mode only;
    dry-run prints one would-run line for the `.npmrc` change plus the
    install would-run line.
  - Post-verify `[ -x "$HOME/.local/bin/codex" ]`; fatal on failure.
- **Validation/tests:** dry lines; real with fake npm creating the binary;
  `.npmrc` contains exactly one managed prefix line and preserves unrelated
  lines; already-present → skip; fake npm failure → fatal.
- **Validation result:** Developer + Senior ran `bash -n` (ok); `run_dev.sh`
  297 PASS/0 FAIL (DEV-SYS 59/0, DEV-VSCODE 56/0, DEV-DBEAVER 34/0,
  DEV-MISE 48/0, DEV-JUPYTER 38/0, DEV-CODEX 62/0), x2 identical. Suites:
  `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh` 260/4, `run_ijl.sh` 37/2
  (unchanged pre-existing baselines). Ad-hoc rerun idempotency on junk
  `.npmrc`: unrelated lines preserved, single prefix line after each run. No
  sudo/systemctl; no commits.
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D07 — OpenCode CLI

- **Objective:** Add the OpenCode CLI stage. Install user-level
  (`~/.local/bin/opencode`) via the official installer with `--no-modify-path`
  and `XDG_BIN_DIR`; verify; failure → fatal.
- **Scope/files:** `modules/dev.sh` (opencode section), `/tmp/opencode/vt/run_dev.sh`
  (group DEV-OPENCODE).
- **Implementation requirements:**
  - Probe `[ -x "$HOME/.local/bin/opencode" ]`; when missing, run exactly:
    `XDG_BIN_DIR="$HOME/.local/bin" curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path`.
    Real mode only; dry-run prints that exact line and never executes it.
  - Post-verify `[ -x "$HOME/.local/bin/opencode" ]`; fatal on failure.
- **Validation/tests:** exact dry line; real with fake curl emitting a script
  that creates the binary; already-present → skip; installer produces nothing →
  fatal; curl-side pipeline failure → fatal (pipefail in subshell).
- **Validation result:** Developer + Senior ran `bash -n` (ok); `run_dev.sh`
  332 PASS/0 FAIL (DEV-SYS 59/0, DEV-VSCODE 56/0, DEV-DBEAVER 34/0,
  DEV-MISE 48/0, DEV-JUPYTER 38/0, DEV-CODEX 62/0, DEV-OPENCODE 35/0),
  x2 identical. Suites: `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh`
  260/4, `run_ijl.sh` 38/1 (unchanged baselines). Hygiene greps clean.
- **Senior review:** FAIL (comment token) → fix (comment reworded to
  "unprivileged as the current user") → re-review PASS.
- **Commit:** NOT AUTHORIZED.

---

## D08 — Debian fd symlink + dev rc block

- **Objective:** Add the final dev.sh stages: the Debian-family
  `fdfind` → `~/.local/bin/fd` user symlink, and the managed dev shell-config
  rc block (PATH + mise activation) per present shell. Deterministic and
  idempotent re-runs.
- **Scope/files:** `modules/dev.sh` (fd symlink + rc block section), dev.sh
  final completion message (reload + SSH manual-enable note), `/tmp/opencode/vt/run_dev.sh`
  (groups DEV-FD, DEV-RC).
- **Implementation requirements:**
  - fd symlink (Debian family only): if `command -v fdfind` and
    `[ ! -e "$HOME/.local/bin/fd" ]` → create `~/.local/bin` (real mode) and
    `run ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"`. Dry-run prints
    the would-run line only. Not run on Fedora/Arch.
  - rc block: mirror `set_aliases.sh` structure exactly (BLOCK_BEGIN/END
    delimiters `# >>> linux-postinstall dev >>>` / `# <<< linux-postinstall dev <<<`,
    strip-and-re-append via `run sed -i`, bash always, zsh/fish when present),
    but with dev content:
    - bash/zsh: `export PATH="$HOME/.local/bin:$PATH"` then
      `eval "$(~/.local/bin/mise activate bash)"` (zsh: `… zsh)`.
    - fish: `fish_add_path "$HOME/.local/bin"` then
      `~/.local/bin/mise activate fish | source`.
    - The block must not duplicate the aliases block or terminal lines.
  - Completion message: brief reload guidance (text only, never executes
    anything privileged). The SSH manual-enable commands (Fedora/Arch
    `sudo systemctl enable --now sshd`; Debian `sudo systemctl enable --now
    ssh`) are **documented in README.md by D09, not printed by dev.sh**:
    Manager decision (D08 review) — keeping dev.sh free of any
    sudo/systemctl text lets T7, the D10 source hygiene grep, and the
    README-pointer message coexist without routing text to stderr.
- **Validation/tests:** debian real → symlink created, fd reachable through
  `~/.local/bin`; fedora/arch → no symlink; dry prints symlink line; rc block
  exactly once per rc after two runs, coexists with aliases block, pre-existing
  user lines preserved, dry-run reports targets and writes nothing; bash/zsh/
  fish discovery via presence stubs; completion prints reload guidance and
  README pointer, never systemctl/sudo text (stdout or stderr).
- **Validation result:** Developer + Senior ran `bash -n` (ok); `run_dev.sh`
  424 PASS/0 FAIL (59/56/34/48/38/62/35/35/57), x2 identical. Suites:
  `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh` 260/4, `run_ijl.sh` 38/1
  (unchanged baselines). `grep -nE 'sudo|systemctl' modules/dev.sh` empty;
  prompt-tool hygiene clean; no `-Syu` except comment. Senior note folded in:
  `tail` added to run_dev.sh corebin so the trailing-newline guard is actually
  exercised in-sandbox (rc1.err now clean; counts unchanged).
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## D09 — Documentation

- **Objective:** Update the repo docs to describe the real dev module,
  standalone usage, sudo/dry-run/idempotency contract, SSH install-only policy,
  and the ownership rule (duplication with packages is intentional).
- **Scope/files:** `AGENTS.md`, `README.md`, `modules/README.md`.
- **Implementation requirements:**
  - `AGENTS.md`: replace/update the dev-related binding bullets in the approved
    plan section (self-contained dev; SSH server installed but never
    enabled/started; sudo via `ensure_sudo`/`run_root` only; no `sudo -S`;
    duplication with `install_apps.sh` allowed).
  - `README.md`: `dev` bullet becomes real; add a short "Development
    environment" section (what it installs, standalone `./setup dev`, manual
    SSH enable, reload note) without bloating the file.
  - `modules/README.md`: `dev.sh` bullet becomes real.
  - Do not advertise features that do not exist; no OMP references; preserve
    existing doc style.
- **Validation/tests:** `bash -n`; grep hygiene greps still empty; docs mention
  SSH manual-enable; no claim that dev enables sshd; no leftover
  "placeholder" wording for dev in docs.
- **Validation result:** Developer + Senior ran all suites — `run_dev.sh`
  424/0, `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh` 260/4,
  `run_ijl.sh` 38/1 (group L only: doc modifications, allowlist updated by
  D10); hygiene and `systemctl`-in-code greps empty; `bash -n` ok. First
  Senior review FAILed on two AGENTS claims (DBeaver "duplication" with
  `install_apps.sh` — it has no DBeaver; "every stage" post-verify — rc/fd/
  npmrc are write stages). Fixed to "VS Code install + Flathub-pattern
  mirror" and "every **install** stage"; re-review PASS.
- **Senior review:** PASS (after one FAIL/fix cycle).
- **Commit:** NOT AUTHORIZED.

---

## D10 — Integration: sandbox harness updates + full suite

- **Objective:** Make the existing sandbox suites reflect a real dev module and
  run the complete regression: A/B/C/K, D/E, F/G/H/S, I/J/L plus the new dev
  groups. Adjust harness fixtures so full `./setup install` real-mode tests
  stay deterministic now that dev installs (or skips) real tooling.
- **Scope/files:** `/tmp/opencode/vt/run_fgh.sh` (S3/S6: pre-seed sandbox
  `~/.local/bin` with mise/jupyter/codex/opencode stubs, a `bin-dev` stub dir
  on the stub PATH containing the dev-tool binaries, and a `FAKE_DBEAVER`
  flag so the soft flatpak fake reports DBeaver installed), `/tmp/opencode/vt/run_ijl.sh`
  (group L allowed-changes list updated for the head-of-worktree state:
  modified `AGENTS.md`/`README.md`/`modules/README.md`, untracked
  `modules/dev.sh`), `/tmp/opencode/vt/run_abc.sh` (A-dev dev smoke already
  converted in D01), and any other assertion the changes break. Sandbox files
  only — no repo code changes.
- **Implementation requirements:**
  - Pre-seeding decisions must keep dev fully idempotent-skip inside S3/S6
    (all system tools present, user-level binaries present, DBeaver present),
    so the full install exercises the auth/cleanup path without new installs.
  - Dry-run groups (B, K, S9) must remain green: dev dry-run prints only; no
    files created; no sudo/auth; no network.
  - Group L: allowlist the exact head-of-worktree status (modified docs,
    untracked dev.sh, deleted/recreated ROADMAP as applicable).
- **Validation/tests:** run all suites to completion and record the full pass
  grid: `run_abc.sh` (A/B/C/K), `run_de.sh` (D/E), `run_fgh.sh` (F/G/H/S),
  `run_ijl.sh` (I/J/L), `run_dev.sh` (all DEV groups). Also:
  `for f in modules/dev.sh setup lib/common.sh modules/*.sh; do bash -n "$f"; done`;
  prompt-tool hygiene greps empty (per AGENTS Validation section); `sudo -S`
  empty everywhere; raw `sudo` in module code only as `set_aliases.sh` alias
  text and `lib/common.sh` plumbing (README may quote the documented SSH
  activation commands); `grep -nE 'sudo|systemctl' modules/dev.sh` empty
  (README documents the activation commands, dev.sh must not); both dry-run
  argument orders covered.
- **Validation result:** Developer + Senior, all suites run twice each with
  byte-identical output — `run_abc.sh` 43/0, `run_de.sh` 31/0,
  `run_fgh.sh` 264/0 (S3/S6 fixed by `bin-dev` stub matrix + seeded
  `~/.local/bin` + `FAKE_DBEAVER`, all dev stages skip, 0 network tripwires,
  S3 cold 1×`sudo -v`/1×`sudo -k`+marker removed, S6 warm 0/0),
  `run_ijl.sh` 39/0 (group L exact six-entry allowlist, rejects anything
  else), `run_dev.sh` 424/0 → **801/0 total, zero FAIL**. Pre→post delta
  confined to exactly the 5 expected FAIL→PASS flips; no assertions weakened.
  `bash -n` all repo + harness scripts ok; hygiene greps (`oh-my-pos[h]`,
  `sudo -S` in code, `sudo|systemctl` in dev.sh) empty; both dry-run orders
  byte-identical, 0 files, 0 auth, 0 network. Senior non-blocking notes:
  group L is one-directional (rejects unexpected entries; subset passes),
  harness is unversioned (mtime/assertion-name heuristics used for evidence),
  prose `sudo`/`systemctl` in docs is intentional.
- **Senior review:** PASS.
- **Commit:** NOT AUTHORIZED.

---

## Done — all tasks above PASS; commits NOT AUTHORIZED.

## Final pre-commit review (2026-10-08)

Independent Senior review of the complete dev implementation (T01, D01–D10):
**FAIL** initially on F1 (AGENTS.md claimed a `ROADMAP.md` "Approved
restoration plan" section that the T01 rewrite removed). Fixed in the same
pass: F1 (pointer now cites the binding bullets + git history, verified
`HEAD:ROADMAP.md` holds the plan), F2 (`ROADMAP.md` Done heading), F3
(`dev.sh` dry-run prints the pipx line literally instead of evaluating the
mise substitution on a fresh HOME). Focused Senior re-review: **PASS**.
Full grid rerun twice: run_abc 43/0, run_de 31/0, run_fgh 264/0,
run_ijl 39/0, run_dev 424/0 → **801/0**, zero FAIL. Hygiene/syntax/repo
state clean. Non-blocking observations: harness `S7 took Ns` wall-clock line
and real-`flatpak` dry-run cache skeleton are pre-existing/environmental.
Commit remains NOT AUTHORIZED pending explicit user authorization.

---

## T02 — Atuin official-path detection + Fish init dedupe (2026-10-09)

- **Objective:** Correct the terminal Atuin presence check to the official
  installer's real install location and make Fish Atuin initialization
  idempotent against the installer-written guarded block, without changing the
  AGENTS §8 exact-init-line contract, PATH ownership, `run_root`, Starship, or
  Bash/Zsh exact-line behavior.
- **Scope/files:** `modules/terminal_themes.sh` only, plus this roadmap entry.
- **Root cause:** The official Atuin installer (`https://setup.atuin.sh` →
  `atuin-installer.sh`) installs to `$HOME/.atuin/bin/atuin` and owns PATH via
  `$HOME/.atuin/bin/env`, sourced from the shell rc. The module checked
  `$HOME/.local/bin/atuin`, so a fresh install was present but unverified and
  `setup terminal` exited 1 with a false "Atuin installation failed". For Fish
  the installer writes a guarded block (`if status is-interactive` … `atuin
  init fish | source` … `end`); the exact-line guard did not match it, so
  terminal appended a second Atuin init.
- **Implementation requirements:**
  - `atuin_present()` (and the post-install verification that reuses it) is
    `command -v atuin >/dev/null 2>&1 || [ -x "$HOME/.atuin/bin/atuin" ]`.
  - `ensure_init_line` gains an optional broader-detection substring; the Fish
    Atuin call passes `atuin init fish`, so an installer-written guarded block
    suppresses a second append. The canonical exact line
    (`eval "$(atuin init bash|zsh)"`, `atuin init fish | source`) is unchanged
    and is still what terminal writes when no Atuin init is present.
  - No PATH ownership, no `run_root` change, no Starship/Bash/Zsh change.
- **Validation/tests:** `bash -n setup lib/common.sh modules/*.sh`; full sandbox
  grid twice (A/B/C/K, D/E, F/G/H/S, I/J/L, DEV). New F/G/H/S cases: H24 (fresh
  Bash Atuin install — installer creates `~/.atuin/bin/atuin` + env line,
  process PATH unchanged; assert no false failure, exactly one init,
  byte-identical rerun) and H25 (Fish installer guarded block; assert terminal
  appends no second Atuin init).
- **Validation result:** Full grid run twice (timing-normalized byte-identical):
  `run_abc.sh` 43/0, `run_de.sh` 31/0, `run_fgh.sh` 286/0 (was 264; +22 new
  H24/H25 Atuin cases), `run_ijl.sh` 39/0, `run_dev.sh` 424/0
  (59/56/34/48/38/62/35/35/57) → **823/0 total, zero FAIL**. New cases: H24
  fresh Bash Atuin install (official installer creates `~/.atuin/bin/atuin` +
  `env` line, process PATH unchanged) → rc0 with no false failure, exactly one
  init line, env line preserved, byte-identical rerun; H25 Fish installer
  guarded block → exactly one Atuin init, no raw second line, no installer
  attempted. `bash -n setup lib/common.sh modules/*.sh` ok; hygiene greps empty
  (`oh-my-pos[h]|poshtheme[s]`); harness group L/J allowlists updated to the
  current worktree (docs' allowed spaced prompt-tool mention,
  `modules/terminal_themes.sh` modification).
- **Senior review:** PASS (independent review; no blocking findings).
- **Commit:** `fix: detect Atuin at its official install path and dedupe fish init`
  (this file is committed with that change; hash recorded in git history).