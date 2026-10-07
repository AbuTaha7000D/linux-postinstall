# Implementation Roadmap

## Status and scope

This document is the persistent implementation roadmap and future-work record. At the time this roadmap was written, the repository contained a `setup` launcher and task scripts under `scripts/`, and did not yet match the proposed `lib/`, `modules/`, and `config/` organization. Phases 1 and 2 passed their review gates, and a pre-Phase-3 cleanup pass then removed direct DNS modification and other risky leftover behavior, fixed locale failure handling and step ordering, simplified the family package lists, and made vendor and architecture checks lazy; that pass was reviewed and its gate passed. The approved restoration plan below is the current work package. Completed work is recorded through status updates and review gates rather than per-task markers.

The target is a small personal rebuild tool for Fedora-, Debian-, and Arch-family systems. The roadmap does not authorize a framework, universal distro support, or unrelated features.

## Approved restoration plan — 2026-10-07

The user approved a complete plan to restore the intended CLI and behavior, with a Starship-based terminal stack. This section is the authoritative record of that plan. It is organized into requirements, implementation decisions, validation criteria, deferred work, and constraints, and it does not add requirements beyond what was approved. Where this section conflicts with older task text (for example the P3-T02 mention of Oh My Posh), the approved decision here wins and the task text is aligned with it.

### Requirements

**CLI redesign and command hierarchy.**

- Commands: `install`, `terminal`, `aliases`, `packages`, `language`, `fonts`, `dev`, `gnome`, `shortcuts`, `favorites`, `extensions`, `help`, `version`.
- Options: `--dry-run` (global, accepted in any position), `-h`/`--help`, `-v`/`--version`.
- No arguments and `install` run the identical full setup through a single code path.
- `help` prints structured usage with commands and options sections. Invalid commands, old command names (`all`, `install_apps`, and the other retired group names), module arguments after `install`, `list`, and unknown options fail nonzero with a usage hint on stderr.
- `--dry-run` performs no file changes, package installs, sudo invocations, or shell-configuration changes; it prints the commands that would run, including the exact Starship installer line.
- The existing refusal to run as root and the fail-fast step runner (named failing step, nonzero propagation, no success message after a required failure) are retained.

**lib/ vs modules/ architecture.**

- `scripts/` is migrated to `modules/`; shared helpers move to `lib/common.sh`.
- `lib/common.sh` provides the dry-run-aware `run`/`run_root` helpers, distro-family detection with the existing `OS_RELEASE_FILE` seam, and desktop-environment detection.
- `setup` keeps CLI parsing, the fixed module order, and overall failure handling.
- The existing multi-distro package architecture (explicit family arrays, Flatpak/Flathub, yay/AUR only on Arch, vendor Chrome/VS Code with lazy architecture checks) stays intact. System package installation stays in the packages layer; Starship is installed by the terminal layer; modules do not duplicate the family package lists.

**Install flow and GNOME/non-GNOME behavior.**

- Normal steps, always: packages → language → fonts → aliases → terminal → dev.
- GNOME steps, only when the detected desktop is GNOME: wallpaper → gnome_themes → icons_and_cursors → favorites → shortcuts → extensions. Non-GNOME desktops print one clear skip line; the normal steps still run.
- Detection uses `XDG_CURRENT_DESKTOP` (colon-separated, case-insensitive) with `DESKTOP_SESSION` fallback, and the detected environment is printed.
- Explicit `./setup gnome` runs the GNOME group on any desktop; individual modules keep their own guards.

**Terminal behavior.**

- The terminal command owns the full terminal stack: shell selection, ensuring the selected shell, Atuin, and Starship are installed, configuring Atuin and Starship for the selected shell, and making it the default shell via `chsh`.
- `chsh` targets the user-selected shell (Bash, Zsh, or Fish), replacing the previous unconditional `chsh` → bash.
- Starship and Atuin initialization are appended with an exact-line guard to the selected shell's rc file only (`~/.bashrc`, `~/.zshrc`, or `~/.config/fish/config.fish`); nothing else in user shell configuration is touched.
- The terminal module owns the Starship installation logic (official installer only); the packages layer contains none.

**Starship installation (official installer only).**

- The terminal layer installs Starship using the official non-interactive installer, exactly: `curl -sS https://starship.rs/install.sh | sh -s -- -y`.
- The same command works across Fedora, Debian, and Arch families; no distro-specific method replaces it.
- Starship must not appear in any distro-specific package array and must never be installed via `dnf`, `apt`, `pacman`, `yay`, COPR, or GitHub release binaries.
- In dry-run, read-only presence checks run and the exact installer line is printed only when Starship is missing; it is never executed. Real runs skip installation when `starship` is already present (idempotent) and fail nonzero if installation fails or `starship` is still missing after the installer.
- `curl` is already in all three package arrays, so the prerequisite comes from the package step itself.

**Complete Oh My Posh removal.**

- All Oh My Posh installation and configuration logic, theme-repository references, rc-file lines, documentation mentions, and comments are removed.
- `grep -RniE 'oh-my-pos[h]|poshtheme[s]' .` must return no matches (the brackets only keep this line from matching its own grep); no dead code or stale documentation referring to the tool may remain.
- Starship and Oh My Posh are never both installed or configured.

**Language, aliases, fonts, dev.**

- Language restores the interactive prompt with the approved text: the language menu with `1) English` / `2) Arabic`, `Default: English`, and `You have 10 seconds to choose.`, a 10-second input timeout, English default on timeout, empty, or invalid input, and English default for non-TTY input. Unknown distributions keep failing nonzero with a stderr message; the locale-file backup and prerequisite guards are kept.
- Aliases are installed as one managed block per shell rc file (bash always; zsh and fish when present) delimited by `# >>> linux-postinstall aliases >>>` and `# <<< linux-postinstall aliases <<<`, stripped and re-appended on rerun so the block appears exactly once and content outside it is never modified. Definitions are embedded in the module (migrated from `additions/shell_conf`), with correct quoting for bash, zsh, and fish and distro-family-specific aliases baked in.
- Font installation stays in the existing fonts module; Starship's Nerd Font requirement is satisfied by that module, never by installer logic.
- `dev` exists as a placeholder module (prints that the development environment is not yet defined, exit 0) and is part of the default install flow now, so its future content joins the flow automatically. It also runs standalone via `./setup dev`.

**Dry-run, idempotency, and module hygiene.**

- Every mutating command runs through `run`/`run_root`, or behind an explicit module-level dry-run branch where a pipeline or redirect cannot be wrapped; probes and reads stay direct.
- Countdown `3…2…1` and `sleep 1` blocks are removed from all modules (AGENTS.md §7).
- The recursive `bash "$0"` re-open loop in `gnome_extensions` is removed; it becomes a single pass, with manual URLs printed on non-TTY input and one bounded prompt on a TTY.
- All `read -p` and `select` prompts are TTY-guarded so unattended runs skip cleanly instead of failing under `set -e`.
- Reruns must remain safe: no duplicate rc lines, no duplicated favorites, shortcuts, or sidebar bookmarks, and no repeated download damage.

**Documentation.**

- README usage is updated to the new commands, and stale `./setup.sh` / `chmod +x setup.sh` references are fixed. Stale documentation of already-removed behavior (the sudoers timestamp section) is dropped.
- The module README moves with `modules/` and is updated (Starship instead of Oh My Posh, managed-block aliases, `dev`, `bash modules/…` examples).
- `additions/shell_conf` keeps its alias content as a legacy reference with its Oh My Posh section removed; it is no longer applied to the user's rc files.

### Implementation decisions (approved)

- **Starship channel:** the official starship.rs installer for every supported family. Verified from the installer source: `-y` skips prompts, and the installer self-elevates with `sudo` only when `/usr/local/bin` is not writable, so the exact pipeline works both for a normal user and as root.
- **Rejected Starship channels:** distro package arrays (no official Fedora package exists anyway), COPR (a persistent third-party repository plus an extra dependency), and GitHub release binaries.
- **Placement:** the installer step lives in the terminal layer together with shell selection, Atuin, and `chsh`; the packages layer no longer installs Starship.
- **`dev` scoping:** placeholder now, wired into the default install; its stack is deliberately undefined (“do not invent the stack yet”).
- **Names:** command names come from the approved CLI; existing script file names are kept inside `modules/` (`install_apps.sh` remains the `packages` layer and `terminal_themes.sh` implements the terminal stack).
- **CLI extras:** `-v`/`--version` is kept (the original CLI had it); `list` is dropped; old group commands and `install <group>` arguments are removed.
- **GNOME order:** the existing relative order is kept; the spec's example listing was treated as illustrative.
- **Alias source of truth:** definitions are embedded in the aliases module (robust, no parsing); `additions/shell_conf` becomes legacy reference data. The remote-execution `terminal-theme` alias is not migrated (P3-T02).
- **Terminal guards:** real runs install Starship when missing (official installer) and fail nonzero with a clear message if the installer leaves it missing; dry-run performs only read-only presence checks and prints would-run lines.
- **`chsh` and Atuin:** retained; `chsh` targets the selected shell instead of always bash.
- **Bookmarks rerun:** the `~/Github` sidebar line gets an existence guard so reruns do not duplicate it.
- **Roadmap alignment:** the P3-T02 Oh My Posh reference is updated to Starship as part of recording this plan (authorized by the same instruction that directed updating this file).

### Validation criteria

All validation is sandboxed: fake `HOME`, PATH tripwire commands, `OS_RELEASE_FILE` substitutions, and pseudoterminals where interaction is required. No real package installation, sudo, locale writes, `chsh`, gsettings, or network mutation runs on the live machine.

1. `bash -n` passes for `setup`, `lib/common.sh`, and every `modules/*.sh`.
2. `help`, `-h`, and `--help` exit 0 with commands and options sections; `version` and `-v` exit 0; invalid commands (`bogus`, `list`, `all`, `install_apps`, the empty string) exit nonzero with a usage hint on stderr.
3. Dry-run matrix: every command with `--dry-run` in both positions exits 0, prints would-run lines including the exact `curl -sS https://starship.rs/install.sh | sh -s -- -y` line from the terminal layer, triggers no mutating tripwire commands (`sudo`, `dnf`, `apt-get`, `pacman`, `yay`, `wget`, `curl`, `chsh`, `locale-gen`, `localectl`, `gsettings`, install-mode `flatpak`), and leaves the sandbox HOME untouched.
4. `./setup --dry-run` output is identical to `./setup install --dry-run`.
5. Desktop scenarios: `XDG_CURRENT_DESKTOP=GNOME` includes all seven GNOME steps; Hyprland, KDE, and empty desktop values run normal steps only plus the skip line; the detected environment is printed.
6. Language scenarios: piped input → English; pseudoterminal with `2` → Arabic; pseudoterminal with no input → English after about 10 seconds; invalid input → English; unreadable or foreign `OS_RELEASE_FILE` → nonzero with stderr.
7. Package matrix: Fedora, Debian, and Arch `OS_RELEASE_FILE` substitutions produce the correct family commands; `yay` and `pacman` never appear off-Arch; Starship is absent from all three arrays and packages output contains no Starship line.
8. Aliases: two runs against a fake HOME leave exactly one marker pair and preserve pre-existing user content; zsh and fish stubs on PATH receive their own blocks; dry-run writes nothing.
9. Terminal: selects a shell, installs the selected shell/Atuin/Starship when missing, appends only the selected shell's exact init strings, and changes the default shell only when needed; no Oh My Posh state exists.
10. `grep -RniE 'oh-my-pos[h]|poshtheme[s]' .` returns no matches; a supplementary case-insensitive `Oh My Posh` scan finds nothing outside git history.
11. Failure propagation: a stubbed required module failure exits nonzero, names the failed step, and prints no success message; `dev` exits 0 with its placeholder message in both modes.
12. `git status` shows only intended paths (`setup`, `lib/`, `modules/`, `README.md`, `additions/shell_conf`, plus the authorized `AGENTS.md` and `ROADMAP.md` recording).
13. Diff review confirms no unrelated functionality changed.

### Deferred work and known-unverified items

- The actual `dev` stack (toolchains, containers, databases, IDEs) — intentionally undefined until specified.
- Fresh or disposable per-family validation (P5-T03) — still required before strengthening support claims.
- Fish rc quoting is validated only if fish is present on the host.
- No live package installs, real locale/`chsh`/gsettings changes, or real GNOME session are exercised by this work's validation.
- `config/` directory creation remains conditional guidance in AGENTS.md §2, not part of this plan.

### Constraints and out-of-scope

- Do not commit unless explicitly requested (none was).
- Do not install Starship through distro package managers, COPR, or GitHub release binaries; never leave dual Oh My Posh/Starship state.
- Do not add a `list` command, dev stack content, or any feature outside this plan.
- Do not build frameworks, registries, state databases, or package-provider abstractions (AGENTS.md §7).
- Do not move font installation into installer logic; do not duplicate Starship installation logic across layers.
- Do not overwrite user shell configuration outside the project's managed blocks.
- Keep the existing multi-distro package architecture intact.
- Keep AGENTS.md as the persistent engineering instructions and ROADMAP.md as this roadmap and future-work record; updating both with this plan is the authorized exception to any earlier read-only treatment.

## Phase 1 — Safe Entry Point and Failure Contract

**Goal:** Make CLI invocation predictable and failures truthful.

**Why:** Later module work needs a reliable launcher that does not make hidden changes before the user selects an operation.

### P1-T01 — Replace launcher preflight side effects

- **Description:** Parse the command before performing privileged, network, or system-changing operations. Remove sudoers modification and automatic GitHub `git ls-remote`/`git pull`. Support `./setup`, `./setup help`, `./setup install`, and `./setup install <group>...`. No arguments and `install` both run the full setup. Invalid commands must fail nonzero.
- **Acceptance criteria:** Help works without sudo or network and performs no changes. No command silently pulls code or edits sudoers. No arguments and `install` both run the documented full setup. Invalid commands exit nonzero with a usage hint.
- **Senior review focus:** Confirm there are no side effects before argument validation, no hidden network activity, and no sudoers mutation.
- **Dependencies:** None.

### P1-T02 — Define launcher failure propagation

- **Description:** Required module failures must propagate; required failure stops installation. Overall success is printed only after all required operations succeed. Optional skips and failures are distinguishable.
- **Acceptance criteria:** A failing required module produces nonzero status, identifies the failed step, prevents later dependent required work, and never prints full success. Optional skips are identified as skips.
- **Senior review focus:** Inspect pipelines, conditionals, `||`, subshells, command substitutions, and child-script return codes for masked failures.
- **Dependencies:** P1-T01.

**Phase gate:** No pre-command side effects; a required module failure cannot yield overall success.

## Phase 2 — Distro and Package Installation

**Goal:** Make the required package path explicit and reliable for the three supported families.

**Why:** Package installation is central to the fresh-machine goal, and one shared package list cannot represent three package managers reliably.

### P2-T01 — Simplify distro-family detection

- **Description:** Detect Fedora, Debian, or Arch family using `/etc/os-release` data. Return a clear unsupported result otherwise.
- **Acceptance criteria:** Representative Fedora, Debian/Ubuntu/Mint, and Arch/CachyOS identifiers resolve as intended. Unsupported or unreadable identification fails clearly. Detection does not claim support for every derivative.
- **Senior review focus:** Check `ID`/`ID_LIKE` handling and ensure unsupported values cannot proceed as a supported family.
- **Dependencies:** P1-T02.

### P2-T02 — Separate and validate family package lists

- **Description:** Replace the shared cross-family package list with appropriate package names and install commands for each family. Keep lists minimal and personal.
- **Acceptance criteria:** Each retained package name is checked for its target family. Package-manager failure returns nonzero and cannot be hidden by per-package logging. Already-installed packages are harmless.
- **Senior review focus:** Check list accuracy, package-manager invocation, and truthful status reporting.
- **Dependencies:** P2-T01.

### P2-T03 — Make Flatpak installation explicit and safe

- **Description:** Make Flatpak and Flathub prerequisites explicit, keep the selected app list editable, and install it repeatably.
- **Acceptance criteria:** Missing Flatpak or Flathub is clearly handled according to whether Flatpaks are required or optional. Failed required app installs are visible and produce nonzero status. Reruns do not damage or duplicate installation state.
- **Senior review focus:** Check remote setup/scope, privilege use, and error propagation.
- **Dependencies:** P2-T02.

### P2-T04 — Decide vendor-download and AUR scope

- **Description:** Decide which current VS Code, Chrome, and AUR installation paths provide enough value to retain. Remove unused paths. Retained paths must be explicit and architecture-aware.
- **Acceptance criteria:** No retained installer relies on a fixed `/tmp` directory. Unsupported architecture and download/install failures are reported clearly. AUR helper bootstrapping is intentional and not hidden in a required path without review.
- **Senior review focus:** Check source trust, architecture assumptions, cleanup, interruption/rerun behavior, and whether the feature is worth its maintenance cost.
- **Dependencies:** P2-T02, P2-T03.

**Phase gate:** Family detection is reliable; required package failures propagate; Flatpak behavior is explicit and rerunnable; vendor/AUR behavior is an intentional decision.

## Phase 3 — Shell and User Configuration

**Goal:** Configure the user's shell and personal assets without destroying user data or breaking startup.

**Why:** The current shell configuration replaces `.bashrc` and initializes tools whether or not they installed successfully.

### P3-T01 — Replace destructive shell configuration

- **Description:** Preserve existing `.bashrc` content. Install a separate project-owned file with one guarded source line, or use another equally simple non-destructive approach.
- **Acceptance criteria:** Existing user content survives. Repeated runs do not duplicate source lines or overwrite the only backup with generated content. Behavior is documented.
- **Senior review focus:** Check fresh, existing-custom, and rerun cases.
- **Dependencies:** P1-T02.

### P3-T02 — Make optional shell tools safe

- **Description:** Make Atuin installation/configuration and Starship initialization failures explicit. Optional initialization must not break shell startup if a tool or config is absent. Remove the remote-execution alias.
- **Acceptance criteria:** Interactive shell startup works with either tool absent. Repeated runs do not duplicate init commands. Failed required downloads/installs return nonzero. Supported shell assumptions are explicit.
- **Senior review focus:** Check installation ordering, `SHELL` assumptions, and startup behavior after partial failure.
- **Dependencies:** P3-T01, P2-T02.

### P3-T03 — Make fonts and wallpaper predictable

- **Description:** Retain useful font and wallpaper setup with project-relative paths, clear prerequisite checks, and safe reruns.
- **Acceptance criteria:** Missing files or required commands are reported; project assets can be copied regardless of the caller's working directory; repeated runs do not duplicate or alter unrelated user files. GNOME-only setting skips cleanly outside GNOME.
- **Senior review focus:** Check paths, copy destinations, command failures, and GNOME detection.
- **Dependencies:** P1-T02.

**Phase gate:** Existing user configuration is preserved; shell startup tolerates missing optional tools; rerunning asset setup is safe.

## Phase 4 — Optional GNOME Preferences

**Goal:** Keep valuable GNOME preferences optional, simple, and rerunnable.

**Why:** GNOME is a reasonable personal target but should not block the core setup on other desktops.

### P4-T01 — Consolidate and simplify GNOME preferences

- **Description:** Retain only useful shortcuts, favorites, wallpaper, icon, cursor, or theme settings. Group them behind an optional GNOME command. Use explicit desktop IDs instead of fuzzy discovery.
- **Acceptance criteria:** GNOME work detects the session and skips clearly elsewhere. Invalid app IDs are reported. Repeated runs do not duplicate favorites/bookmarks. Shortcut paths are valid, or the shortcut feature is removed. Whole-list replacement behavior is documented.
- **Senior review focus:** Check GNOME schema paths, session detection, existing user values, and rerun behavior.
- **Dependencies:** P1-T02, P3-T03.

### P4-T02 — Remove risky/manual workflows from default install

- **Description:** Remove direct DNS file mutation and immutable flags. Remove recursive extension browsing and keep manual theme/archive workflows out of default install. Retain a named optional helper only if it has clear personal value.
- **Acceptance criteria:** No code changes `/etc/resolv.conf` or applies `chattr +i`. Default install does not wait for manual downloads/confirmations or recursively launch itself. Any retained optional workflow is bounded and documented.
- **Senior review focus:** Search for remaining DNS mutation, recursive invocation, archive deletion, or manual prompts in the required path.
- **Dependencies:** P1-T01, P4-T01.

**Phase gate:** GNOME work is optional; non-GNOME systems skip cleanly; DNS mutation and recursive/manual workflows are absent from default install; reruns are safe.

## Phase 5 — Validation, Documentation, and Support Claim

**Goal:** Validate the behavior and document the real fresh-install workflow.

**Why:** Support claims must match observed behavior, and the user should be able to rebuild without reverse-engineering scripts.

### P5-T01 — Add minimal high-value validation

- **Description:** Add proportionate checks for shell syntax, CLI behavior, failure propagation, distro-family detection, and rerun-sensitive configuration. Use command stubs where useful; do not create a test framework.
- **Acceptance criteria:** Checks run without root or network, never invoke real package installation, and fail when their target behavior regresses. No unnecessary test infrastructure is added.
- **Senior review focus:** Check behavior coverage, test isolation, and whether tests could change the host.
- **Dependencies:** P2-T01 through P4-T02.

### P5-T02 — Align README and CLI help

- **Description:** Document prerequisites, supported distro families, the fresh-install command, optional GNOME behavior, network requirements, editable configuration, rerun behavior, and known limitations. Remove stale documentation if redundant.
- **Acceptance criteria:** Every documented command exists; a user can clone and run without guessing; deleted features and unsupported claims are absent.
- **Senior review focus:** Cross-check documentation against actual CLI and behavior.
- **Dependencies:** P5-T01.

### P5-T03 — Validate on fresh or disposable systems

- **Description:** Run the required path on fresh/disposable Fedora, Debian-family, and Arch-family systems and adjust only demonstrated problems.
- **Acceptance criteria:** Each claimed family completes the required path, or documentation explicitly narrows the support claim. Evidence comes from clean/disposable environments, not the user's daily machine.
- **Senior review focus:** Check that validation was genuinely fresh and that failures were not hidden.
- **Dependencies:** P5-T01, P5-T02.

**Phase gate:** Checks pass; docs match implementation; every claimed distro family has actual validation or a clearly stated limitation.

## Task and phase review workflow

Implement one task at a time. Senior reviews each task against its acceptance criteria and may return it for correction. A PASS is required before starting the next task. At each phase gate, Senior reviews the combined phase changes before work proceeds to the next phase. If an implementation proves a planned item unnecessary, simplify it and have the Manager update this roadmap rather than adding infrastructure to preserve the plan literally.

## Dependency order

```text
P1-T01 → P1-T02
             ↓
P2-T01 → P2-T02 → P2-T03 → P2-T04
             ↓
P3-T01 → P3-T02
P3-T03 ───────────────┐
                      ↓
             P4-T01 → P4-T02
                      ↓
             P5-T01 → P5-T02 → P5-T03
```

P3-T03 depends only on P1-T02 and may proceed once that foundation is accepted; P4-T01 waits for both P3-T03 and the launcher contract. Keep task order mostly linear so each change has a clear review boundary.

## Explicitly out of scope

Do not add plugin architecture, dependency injection, module registries, state databases, rollback systems, package-provider abstractions, universal distro support, generic configuration engines, or enterprise provisioning features. Do not treat this roadmap as permission to expand the project beyond the personal rebuild goal.
