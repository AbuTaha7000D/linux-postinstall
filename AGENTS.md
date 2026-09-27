# AGENTS.md — linux-postinstall

Operational guide for AI coding agents working in this repository. Read this fully before
changing anything. `ROADMAP.md` is the internal execution plan; this file is the workflow contract.

## 1. Project overview and current goal

A clean rewrite of an old shell prototype (`setup.sh` + `scripts/*` and `additions/*`, all deleted
in `16bdb1e`) into a **structured, multi-distro workstation bootstrap tool**. Each system setup step
is a "module"; modules are grouped into profiles; everything runs through the core libs in `lib/`.

- **Process stance:** this is a gated rewrite. Each task must pass fresh-context Senior Review,
  be committed, and only then may the next task start. A phase ends with a report and explicit
  owner approval before the next phase begins.
- **Current state:** P0–P2 are **DONE** and committed (`f7b3d5c`…`5e53b16`):
  P2.1 io, P2.2 cli, P2.3 distro, P2.4 state, P2.5 fs, P2.6 sudo, P2.7 run, P2.8 bootstrap/CLI,
  P2.9 `tests/smoke.sh` (103 asserts). **Next phase: P3 — Package Management Backend
  (`FS_PKG_BACKEND`; dnf5/apt/pacman + flatpak + mock).** Do not start P3 without owner approval.
- Version: `FS_VERSION="0.1.0-dev"` (see `lib/bootstrap.sh`).

## 2. Repository structure

| Path | Responsibility |
|---|---|
| `setup` | Executable launcher. Resolves its own path from `$0` (no CWD assumption), `set -euo pipefail`, `readlink -f` canonicalization, then `exec`s `lib/bootstrap.sh "$@"`. |
| `lib/bootstrap.sh` | Entry: Bash≥4.3 check, tool/layout checks, sources `io.sh` + `cli.sh`, parses args, dispatches: `help`/`version`/`check`/`list`/`install` rc0 (install = P4.7 real wiring); `verify`/`export`/`update` rc1 "not implemented yet"; unknown → rc1. |
| `lib/io.sh` | Leveled logging (error/warn/info/debug), TTY-only color, timestamps, progress/summary, audit-log init. `io_*` never abort the caller under `set -e`/`set -u`. |
| `lib/cli.sh` | Flags `--yes/--dry-run/--verbose/--debug/--profile V/--list`, `-h/--help`, `--` end-of-options; commands `install|list|check|verify|export|update|help|version`; unknown → rc1. |
| `lib/distro.sh` | Reads `/etc/os-release` (or `FS_DISTRO_FILE`, or 1st arg — read-only input). Capability matrix: family/id/pkgmgr/localpkg/flatpak-default/gnome. Test seam `FS_DISTRO_PKGMGR_OVERRIDE`. |
| `lib/state.sh` | State root `$FS_HOME` (test) > `$XDG_STATE_HOME` > `$HOME`, joined with `/fedora-setup`. Run logs, module registry, backup registry. Symlink/confinement-guarded. |
| `lib/fs.sh` | `fs_backup`, `fs_install`, `fs_managed_block`/`fs_managed_block_remove`. Atomic temp+rename; managed-block marker covenant (see §12). |
| `lib/sudo.sh` | `sudo_detect`, `sudo_refresh`, `sudo_exec`. Never touches `/etc/sudoers`. Dry-run keeps probe OFF and executes nothing. |
| `lib/run.sh` | `run_cmd`/`run_sudo` with label, `--stop`, `[DESTROY]` forced stop, dry-run `# would run:` lines, `FS_LOG_FILE` audit trail + `FS_LOG_INFRA` halt. |
| `lib/runner.sh` | P4.6: `runner_run <modules_dir> <profiles_dir> <name> <family> [module...]` — resolve/plan/batch-once/hooks+state/summary stages; deps-first execution, destructive-stop policy, dry-run state-free, hook subshell sandbox. |
| `lib/ui.sh` | P4.7: `ui_multiselect`/`ui_confirm` selection + confirm layer (no external TUI tool — no ncurses; Bash + coreutils execs only). TTY raw-key re-render vs deterministic line-mode; high-risk rows never digit/`a`-toggleable (opt-in prompt is their only checklist route); EOF/`q` abort rc1 fail-closed; atomic sel-file write via `mv -fT`; `ui_confirm` returns 0 under `--yes`; color helpers must keep `return 0` (set -e safety). |
| `tests/smoke.sh` | Plain-bash smoke suite for P2.1–P2.8 + `setup install` dry-run (P4.7); 105 asserts (P10 adds bats/CI later). |
| `assets/`, `docs/`, `modules/` | Skeletons (tracked `.gitkeep` only). Content arrives in later phases. |
| `profiles/` | P4.5: loadable skeleton profiles `{minimal,desktop,developer,full}.conf` (comment-only, valid empty until P5–P8 content); consumed via `lib/profiles.sh`. |
| `ROADMAP.md` | Internal execution plan. **Gitignored — never commit** (§10). |
| `README.md` | **Stale:** documents the deleted prototype (`setup.sh` etc.). Rewritten only in P11.1 — do not keep it in sync per task. |

Each `lib/*.sh` doc-comment header is authoritative for that library's invariants; keep headers in
sync with code.

## 3. Supported platforms / cross-distro architecture

- Families (from `lib/distro.sh`): **rpm** (fedora/nobara/rhel-like), **deb** (debian/ubuntu/mint-like),
  **arch** (arch/cachyos/endeavouros/manjaro-like). Package backends live behind `FS_PKG_BACKEND`
  (P3): `rpm|deb|arch|flatpak|mock`.
- **`dnf5` vs `dnf` is a detection problem in `lib/distro.sh` (picks the binary), NOT a backend fork**
  (Fedora 41+).
- **Flatpak-first** for GUI apps to keep apt/dnf surface small; `flatpak remote-add --if-not-exists
  flathub` must precede any flatpak install.
- Test-injection env seams must be honored by every lib: `FS_HOME`, `FS_DISTRO_FILE`,
  `FS_PKG_BACKEND`. Extra seams already shipped: `FS_EUID` (root-path testing), `FS_DISTRO_PKGMGR_OVERRIDE`,
  `FS_MODULES_DIR` (module-dir override for `./setup list`), `FS_PROFILES_DIR` (profiles-dir source for
  profile resolution; consumed by the caller-level wiring planned in P4.6/P4.7, bootstrap default = repo `profiles/`). `FS_DISTRO_FAMILY` may be pointed at directly
  to skip distro detection for a `list` run.

## 4. Development status and how ROADMAP.md is used

- Phases P0…P11, each with §1 objective, §4 ordered tasks, §5 verification criteria, §8 Definition
  of Done. Task tags: `[SEQ]` after a listed predecessor (must stay ordered), `[PAR]` parallel-safe,
  `[MOCK]` mock-testable without root, `[REAL]` needs a real distro, `[DESTROY]` destructive /
  requires explicit confirmation.
- Top-of-file "Execution status (ledger)" table records every completed task with its commit and
  reviewer session id (`ses_…`). Task lines get a status marker as they complete.
- "Dependency-aware execution order (recommended path)" lists waves; dependencies drive order —
  a task may start only when every item in its `Depends:` line is done.
- The reviewer session id recorded in the ledger is the handle to resume that same review
  (fixes → re-review in the same session).

## 5. Task execution workflow (mandatory)

1. Implement **only the current task** from ROADMAP. Do not touch other tasks, files, or concerns.
2. Verify the implementation against the task's Verification bullet and its fixture scope.
3. Report evidence: exact commands + outputs (pass counts, rc values); no claims without a run.
4. Submit the task to the fresh-context Senior Reviewer with the diff + evidence.
5. Senior Reviewer is **read-only**: it must not modify files and must not run implementation
   changes; it returns `PASS` or `REVISE` with blocking/non-blocking findings.
6. On `REVISE`: fix only the relevant task, re-verify, and request review again (resume the same
   review session; repeat until PASS).
7. A task **reaches PASS only after a Senior Reviewer PASS** — self-verification alone is insufficient.
8. After PASS, commit the task (**scoped to the task only**, §8), then continue automatically to the
   next task in the same phase.
9. **Stop at the end of the phase:** deliver the phase report and wait for **explicit user approval**
   before starting the next phase.

## 6. Developer vs Senior Reviewer responsibilities

| | Developer (implementing agent) | Senior Reviewer (fresh context) |
|---|---|---|
| Edits files | Yes — current task only | **Never** |
| Runs implementation changes | Yes | **Never** (may run read-only checks, e.g. `bash -n`, existing tests, inspecting diffs) |
| Reads code/ROADMAP/history | Yes | Yes — fully, for freshness |
| Delivers | Implementation + evidence | `PASS` / `REVISE` + findings (file:line, why blocking, required fix) |

Keep the reviewer truly fresh: do not prime its verdict. Resolve REVISE rounds against the *same*
session so findings trace back.

## 7. Verification and evidence expectations

- `bash -n <file>` before running anything.
- Core regression: `bash tests/smoke.sh` must print `summary: N passed, 0 failed` and exit 0.
  Note: FAIL lines go to stderr, so `bash tests/smoke.sh | tail -1` can mask a failure — check the
  exit status.
- Fixtures over real systems: run against `FS_HOME`/`FS_DISTRO_FILE` dummy paths and the `mock`
  backend; never let tests touch `/etc`, `$HOME` of the real user, or real privileges (dry-run is
  load-bearing). After any lib change, also confirm the suite is byte-identical across 2–3 runs.
- Record evidence verbatim in the ledger row after PASS (commands, counts, rc, reviewer verdict + session id).

## 8. Git / commit rules

- Keep changes **scoped to the current task**. `git status`/`git diff` before staging; stage only
  intended files.
- Commit only **after** Reviewer PASS for the task; message style from history:
  `Add <summary> (P<N>.<M>)` (e.g. `Add smoke harness for core libs (P2.9)`, `Wire CLI dispatcher into bootstrap (P2.8)`).
- Never commit secrets, `ROADMAP.md`, runtime state (`*.log`, `.state/`, downloads), or test scratch.
- Do not amend a reviewed commit, force-push, or create empty commits. If a commit fails/hooks
  reject it, fix and make a new commit.
- A task is not "done" until its ledger row records commit + reviewer PASS.

## 9. Safety rules and project invariants

- **Never read or write `/etc/sudoers`** under any circumstance (triple-locked: `run.sh`, `sudo.sh`,
  plus planned regression test P10.5).
- **No `curl | sh`** installs; no download-and-pipe patterns.
- **No wholesale `.bashrc` rewrite.** Dotfile edits use managed blocks only:
  `# BEGIN fedora-setup <name>` … `# END fedora-setup <name>` (marker covenant, `lib/fs.sh`).
- **Dry-run is side-effect-free:** only `# would run: <rendered command>` lines
  (%q quoting, `sudo --` barrier in REAL exec only); no probing, no writes, no sudo invocation.
- Never start a destructive/mutating step without a backup/registry entry first; all writes are
  atomic temp+rename; interrupted runs leave at most `*.XXXXXX` temp files.
- Mid-transition rule: **never destroy a file whose replacement hasn't been proven** by its
  verification criteria.
- State lives off-repo (state root outside the repo; `FS_HOME` is a test override only).
- Environment floor: **Bash ≥ 4.3** everywhere (use `$#`-based loop bounds, guard namerefs — see P2.5/P2.8).

## 10. Handling ROADMAP.md

- Internal execution plan, marked "development only". It is gitignored (`.gitignore` line) and
  **must never be committed**.
- It is the reference for task scope, dependencies, verification, and DoD — do not duplicate it here.
- Task status is updated during the workflow (ledger rows, task-line markers) as tasks pass review
  and are committed; a DONE ledger row is only written after Reviewer PASS + commit.

## 11. Definition of Done

**Task DoD:** implementation matches the task's Verification bullet; `bash tests/smoke.sh` green
(if libs touched); evidence reported; **Senior Reviewer PASS**; task committed; ledger row updated.

**Phase DoD:** all phase tasks DONE + committed; phase §5 Verification criteria met; phase report
delivered; **stop and wait for explicit owner approval** before the next phase.

## 12. Established architectural decisions to preserve

- Libre sourcing graph: any lib needing errors must source `lib/io.sh` first (io_error etc.).
  `sudo.sh` policy globals are cached by `sudo_detect`; `run.sh` fails closed when policy is absent.
- Audit trail: `FS_LOG_FILE` must be a regular writable file (no `/dev/null`, no FIFOs) or the run
  halts via `FS_LOG_INFRA`. `sudo_exec` does **not** tee to the log — privileged steps must go
  through `run_sudo` for auditability.
- `FS_DRY_RUN` / `FS_VERBOSE` / `FS_DEBUG` / `FS_YES` are honored by every lib (env seams);
  `cli.sh` seeds `_CLI_ENV_{DRY_RUN,YES,VERBOSE,DEBUG}` symmetrically at source time.
- `lib/distro.sh` limits itself to detection + capability matrix; package action logic lives in P3.
- No-command → `help` (rc0); unknown flag/command → rc1 with a message; dispatcher is
  fail-loud (`*)` arm) so a future command without a case arm fails loudly.
- Module contract is deliberately restrained: metadata vars + optional hooks + declarative lists;
  the runner stays boring.
- All code: `#!/usr/bin/env bash` + `set -euo pipefail`; **no comments inside function bodies**
  (file-level doc comments only); `set -e` rule of thumb: io_* wrappers must not abort callers.

## 13. Changing an established decision

- First inspect the existing evidence: `git log`, ROADMAP ledger rows + task text, each lib's doc
  header, and review-session findings. Decisions above were hard-won through review — treat them as
  deliberate, not accidental.
- Do **not** silently redefine architecture (naming, APIs, seams, invariants, marker format,
  module contract, error semantics).
- To change one: gather evidence from history/execution, propose the change explicitly, and get
  owner approval before implementing. Reviewed-and-committed decisions change only with new evidence.

## 14. Other repository instructions

- Keep this file and `ROADMAP.md` consistent; if a rule here contradicts something in ROADMAP,
  ROADMAP's task text wins for task scope.
- Do not treat the old README's `setup.sh` / `additions/` instructions as current — that tree was
  deleted in P1.3 (recoverable in git history via tag `proto-baseline`).
- When a change touches a lib, re-run the full smoke suite and re-check the lib doc header still
  matches behavior.
- Do not create documentation files unless the task explicitly requires them.