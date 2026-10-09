# Agent Instructions

## 1. Project purpose

This is a small personal Linux post-install and rebuild tool. After installing a supported Linux distribution, the user should be able to clone this repository and run one command to install the packages, development tools, selected applications, shell configuration, fonts, wallpaper, and optional GNOME preferences used on their own machines. Signing in to applications and accounts remains manual.

The project targets Fedora, Debian, and Arch distribution families. It is not a universal provisioning framework, a general-purpose dotfiles manager, or an enterprise configuration-management system.

## 2. Architecture rules

Keep the architecture explicit and proportional to the work:

- `setup` owns CLI parsing, the fixed module order, and overall failure handling.
- `lib/` may contain genuinely shared shell functions. Do not create library layers for one-off code.
- `modules/` contains actual setup operations. Modules must have clear required/optional behavior and return meaningful statuses.
- `config/` contains user-editable data where a plain-text list is simpler than embedding the data in shell logic; currently `config/aliases/` holds the per-shell and distro alias fragments.
- `assets/` contains static assets such as fonts, icons, and wallpaper.

This layout is conceptual guidance, not a requirement to create every directory or file. Reuse the existing tree if it is clearer. Do not move files merely to make the tree look architecturally tidy.

Unnecessary abstraction and project bloat are forbidden. Prefer straightforward Bash, explicit family-specific package lists, and a short fixed execution order. Do not build a framework.

## 3. Agent roles and workflow

### Manager

- Owns the architecture and `ROADMAP.md`.
- Does not casually redesign the project during implementation.
- Updates the roadmap when scope or an architectural decision genuinely changes.

### Developer

- Implements one roadmap task at a time.
- Stays within that task's scope and keeps changes minimal.
- Validates the work and reports what was run and what remains unverified.
- Does not silently expand scope or make architecture decisions assigned to the Manager.

### Senior

- Independently reviews Developer work against the task acceptance criteria.
- Checks architecture and simplicity, failure propagation, safety, and idempotency.
- May reject unnecessary complexity or scope expansion.
- Must PASS the task before the next task begins.

Workflow:

```text
Manager
  ↓
Roadmap task
  ↓
Developer implementation
  ↓
Senior review
  ├── FAIL → Developer fixes → Senior re-review
  └── PASS → COMMIT → next task
  ↓
Phase gate
  ↓
next phase
```

## 4. Engineering principles

- Keep the project small and understandable.
- Prefer straightforward Bash over abstractions.
- Do not build frameworks or speculate about future generalization.
- Avoid unnecessary dependencies.
- Required failures must propagate; never report overall success after a required operation failed.
- Clearly distinguish optional skips/failures from required success.
- Make reruns safe and predictable.
- Preserve existing user configuration; do not replace it without a deliberate, documented, recoverable decision.
- Do not silently modify dangerous system configuration.
- Do not perform network operations unrelated to the selected installation task.
- Do not add features outside the roadmap without a Manager decision.
- Do not commit unless the user explicitly requests it.

## 5. Supported distribution model

Support the Fedora, Debian, and Arch families pragmatically and explicitly. Use `/etc/os-release` family information where appropriate, but do not claim universal derivative support. Keep package names and installation commands correct for each family. Unsupported distributions should fail clearly rather than falling through to success.

## 6. Validation expectations

Use the smallest validation that gives useful confidence:

- Run `bash -n` on changed shell scripts.
- Check CLI help, valid commands, and invalid-command status.
- Check that required module and package failures propagate and cannot produce a success message.
- Check representative distro-family detection cases.
- Check rerun-sensitive behavior such as shell configuration, favorites, and bookmarks.
- Check that `--dry-run` runs print would-run commands and mutate nothing (sandbox HOME, PATH tripwires on mutating commands).
- Check that `grep -RniE 'oh-my-pos[h]|poshtheme[s]' .` returns no matches. The brackets match the same literal characters; they are written only so this instruction line does not match its own grep.
- Check language prompting in interactive and non-interactive conditions (10-second English default) and alias rerun idempotency per shell (exactly one managed block).
- Check desktop-environment gating: GNOME steps run only on GNOME.
- Validate support on fresh or disposable systems from each claimed family before claiming it works.

Do not introduce a large testing framework unless the project demonstrably needs one. Do not run package installation, system configuration, or destructive setup actions on the user's live machine as a test.

## 7. Intentional design decisions

The following behaviors are rejected and must not be reintroduced without an explicit architecture decision:

- Sudoers timestamp manipulation.
- Automatic GitHub pull/update from the installer.
- Direct `/etc/resolv.conf` replacement.
- `chattr +i` DNS behavior.
- Destructive `.bashrc` replacement.
- Unconditional initialization of optional shell tools.
- Fixed `/tmp` working directories for installers.
- Unnecessary countdown sleeps.
- Complex desktop-file/favorites discovery where explicit IDs suffice.
- Recursive GNOME extension or browser workflows.
- Theme/archive workflows in the default install.
- Oh My Posh installation or configuration (the prompt tool is Starship, installed only via the official starship.rs installer).
- Starship installation through distro package managers (`dnf`, `apt`, `pacman`, `yay`), COPR, or GitHub release binaries.
- Large abstraction layers, package-provider frameworks, module registries, dependency graphs, state databases, rollback engines, and generic configuration engines.

`ROADMAP.md` is the implementation plan. It distinguishes the current repository from planned work; do not treat a planned task as completed until its acceptance criteria and review gate have been met.

## 8. Approved restoration plan — binding rules (2026-10-07)

The binding rules from the 2026-10-07 approved plan are the bullets below; the full plan text, its validation criteria, and deferred work remain in git history (the pre-T01 `ROADMAP.md`), and the current task-by-task implementation record is `ROADMAP.md`. These are the binding implementation rules:

- **Layout:** shared helpers live in `lib/common.sh`; setup operations live in `modules/`; the `scripts/` directory is retired. `setup` keeps CLI parsing, the fixed step order, and failure handling.
- **CLI:** commands are `install`, `terminal`, `aliases`, `packages`, `language`, `fonts`, `dev`, `gnome`, `shortcuts`, `favorites`, `extensions`, `help`, `version`; options are `--dry-run` (global, any position), `-h`/`--help`, and `-v`/`--version`. No arguments and `install` share one code path. Old command names and extra arguments fail nonzero with a usage hint.
- **Install order:** packages → language → fonts → aliases → terminal → dev, then the GNOME group (wallpaper, gnome_themes, icons_and_cursors, favorites, shortcuts, extensions) only when the detected desktop is GNOME; otherwise print a skip line. Detection uses `XDG_CURRENT_DESKTOP` with `DESKTOP_SESSION` fallback.
- **Starship:** installed only by the terminal layer with the official installer exactly as `curl -sS https://starship.rs/install.sh | sh -s -- -y`. Never via dnf, apt, pacman, yay, COPR, or GitHub release binaries. `--dry-run` prints that exact line when Starship is missing and never executes it. The terminal module selects the default shell (Bash/Zsh/Fish, 5-second prompt), installs the selected shell when missing, and appends guarded init lines for the selected shell only: bash `eval "$(starship init bash)"`, zsh `eval "$(starship init zsh)"`, fish `starship init fish | source`.
- **Terminal:** the terminal command owns shell selection, shell/Atuin/Starship installation, selected-shell configuration, and `chsh` to the selected shell (via `run_root`, non-interactive, targeting the current user). After a Zsh/Fish package install the module verifies the shell with `command -v`; if it cannot be verified (package failure or a "successful" install that left the shell missing), it warns, falls back to Bash before any configuration or `chsh`, and configures Bash instead. Dry-run never verifies and never falls back on simulated results. Oh My Posh is completely removed; never reintroduce it or any reference to its theme repository.
- **Sudo:** all privileged operations go through `run_root` in `lib/common.sh`, which authenticates lazily via `ensure_sudo`: a `sudo -n -v` probe (credential check plus timestamp refresh) and only when that fails a single interactive `sudo -v`. `setup` exports a marker file only after a successful interactive `sudo -v`, and an EXIT trap runs `sudo -k` only when that marker exists, so a credential timestamp that predates the run is never cleared; cleanup runs on success and failure. Dry-run never invokes or authenticates sudo. Raw `sudo` calls in modules are forbidden (`set_aliases.sh` sudo strings are alias text, not commands).
- **Language:** the 10-second interactive prompt with English default is restored; non-TTY runs default to English; unknown distributions fail nonzero on stderr.
- **Aliases:** one managed block per shell rc file (`# >>> linux-postinstall aliases >>>` … `# <<< linux-postinstall aliases <<<`), definitions live in `config/aliases/` (per-shell and distro alias fragments), installed by `modules/set_aliases.sh`; nothing outside the block rewritten. The remote-execution `terminal-theme` alias stays removed.
- **dev:** self-contained development environment module, part of the default install, with no dependency on `./setup packages`; its VS Code install (and its Flathub pattern, which mirrors `modules/install_apps.sh`) is intentional duplicated work and allowed. Fixed stage order: system-package binary-presence matrix (including the OpenSSH client and server) → VS Code (official vendor builds, AUR on Arch) → DBeaver (Flatpak) → mise with Python 3.13 → JupyterLab (pipx) → Codex (npm user-prefix) → OpenCode (official installer, `--no-modify-path`) → Debian `fdfind` symlink plus the managed dev rc block (`# >>> linux-postinstall dev >>>`) and completion guidance. Every install stage is installed → skip, missing → install, with fatal real-mode post-verification. The SSH server is installed but never enabled or started and no sshd configuration is changed; manual activation is documented in README, never printed or executed by the module. Privileged operations use only `ensure_sudo`/`run_root` (no raw sudo in the module, no `sudo -S`); `--dry-run` prints would-run lines only.
- **Dry-run and hygiene:** mutations go through `run`/`run_root` or an explicit module-level dry-run branch; no countdown sleeps, no recursive self-re-invocation, prompts are TTY-guarded (see §7).
- **Fonts:** stay in the fonts module; never move into installer logic.
- **Scope:** no commits unless explicitly requested; no `list` command; no framework machinery; the existing multi-distro package architecture stays intact.
