# ROADMAP — linux-postinstall redesign

> INTERNAL EXECUTION PLAN — development only.
> This file is gitignored and MUST NOT be committed.

This roadmap governs the clean rewrite of the current prototype (`setup.sh` + `scripts/*`)
into a structured, distro-family multi-backend workstation bootstrap tool.

---

## Legend

Task tags (appended to each task line):

| Tag | Meaning |
|-----|---------|
| `[SEQ]`   | Must run strictly after its listed predecessor (dependent). |
| `[PAR]`   | Independent of siblings; safe to run in parallel with other `[PAR]` tasks. |
| `[MOCK]`  | Fully testable with mocks / fixtures, no root, no real system needed. |
| `[REAL]`  | Requires or strongly benefits from a real Fedora/Debian/Arch system. |
| `[DESTROY]`| Destructive or modifies system/user state; special care + explicit confirmation required. |

Sequencing rule: a task may only start when every task in its `Depends:` line is done, unless
marked `[PAR]` (then it is independent of the other tasks in the same group).

---

## Execution status (ledger)

Completed tasks are recorded here with evidence. Pending phases remain `[pending]`.
A task line in the body is suffixed with its status marker as it completes.

| Task | Status | Evidence |
|---|---|---|
| P0.1 Create ROADMAP + gitignore | **DONE** · **COMMITTED** `f7b3d5c` | `git check-ignore -v ROADMAP.md` → `.gitignore:32:ROADMAP.md`; `git status --short` → only ` M .gitignore`, ROADMAP.md absent. Approved by owner; closed under new workflow. |
| P0.2 Tag prototype baseline | **DONE** · committed-in-`f7b3d5c`-era | `git rev-parse proto-baseline` == `048f969` == prototype HEAD. Tag is not a commit; retained at baseline commit. |
| P0.3 Record baseline inventory | **DONE** | Canonical inventory + per-script behavior summaries + disposition map in "Baseline notes"; all 14 scripts have an explicit disposition. |
| P0.4 Define migration boundaries | **DONE** | "Migration boundaries" section in "Baseline notes": delete/preserve lists + no-delete-before-skeleton rule written. |
| P1.1 Target directory skeleton | **DONE** · **COMMITTED** `60be4e9` | Reviewer PASS (`ses_f28024aecffeyDM2nyH6laYFX6`), no findings. 8 dirs + 8 empty `.gitkeep`; `git status` pre-commit showed only 6 untracked dirs. |
| P1.2 | **DONE** · **COMMITTED** `a50f95d` | Reviewer PASS (`ses_f27ff5484ffetKwFa96Hg4MEEw`) ×2 (initial PASS + post-fix PASS, no blocking findings). `setup` (executable launcher, `set -euo pipefail`, local-file-first path resolution, readlink-canonicalized, `dirname` pre-guard) + `lib/bootstrap.sh` (`FS_VERSION=0.1.0-dev`, Bash >=4.3 guard, dirname tool check, layout check, static CLI-pending message). Verified: `./setup`, `bash setup`, abs-path/other CWD, `bash lib/bootstrap.sh`, symlink, dirname-missing (rc=1), interpreter-missing (rc=127). |
| P1.3 | **DONE** · **COMMITTED** `16bdb1e` | Reviewer PASS (`ses_f27f668d5ffelfV3oP1SgEBriA`), no findings. 253 staged deletions (234 fonts, 14 scripts/*.sh, scripts/README.md, shell_conf, wallpaper.jpg, folder-github.svg, setup.sh); moved wallpaper → `assets/wallpaper/` + folder-github.svg → `assets/icons/` as gitignored optional assets (`.gitkeep` keepers remain tracked; assets-content rule added to .gitignore in this commit); root README untouched (P11.1 rewrites it); recoverability spot-checked via `git checkout proto-baseline -- scripts/set_favorite_apps.sh`. |
| P1.4 | **DONE** · **COMMITTED** `ce09562` | Reviewer PASS (`ses_f27f9e707ffewY1RhXZUEqQhAa`), no findings. Six patterns added (`.state/`, `logs/`, `downloads/`, `.cache/`, `tests/scratch/`, `tests/.scratch/`); all `git check-ignore` verbatim; tracked+future paths (setup, lib/**, tests/smoke.sh, tests/fixtures/, assets/profiles/modules/docs) stay trackable; prototypes under scripts/ additions/ still visible for P1.3. |
| P2.1 | **DONE** · **COMMITTED** `6a607ee` | Reviewer PASS (`ses_f27d96b58ffeXKK0FzBd3Cfho3`) — initial REVISE (2 blocking: bare-filename parent bug, progress→log mirroring; 2 non-blocking) → fixes → PASS re-check (1 PASS + 1 re-check, no blocking). `lib/io.sh`: leveled io_error/io_warn/io_info/io_debug (TTY-only color via pre-redirection fd detection), `printf %(...)T` timestamps, io_progress (TTY `\r`+`\033[K`, non-TTY line; final progress logged once), io_progress_end, io_summary, io_init (robust parent derivation, silent FS_LOG_FILE fallback on unwritable paths, stderr-suppression-first redirection), `_io_logline` clear-on-write-failure, env seam `FS_DEBUG/FS_VERBOSE/FS_NO_COLOR/FS_LOG_FILE`. Verified: syntax, non-TTY zero-ANSI, debug gating, closed-fd tolerance, edge paths, pty color/erase/progress-once, git-tree containment. |
| P2.2 | **DONE** · **COMMITTED** `61d7944` | Reviewer PASS (`ses_f27bb1223ffebw0f28IiZCGy9W`), no findings (also ran exhaustive 1024-invocation/9360-assertion flag×command matrix). `lib/cli.sh`: source-time `_CLI_ENV_{VERBOSE,DEBUG}` baseline (env seam + idempotent reparse), flags `--yes/--dry-run/--verbose/--debug/--profile V/--list` + `-h/--help` + `--` end-opts, subcommands install|list|check|verify|export|update|help|version, `--list`→list w/o command, no-command→help, unknown flag/command rc=1 w/ io_error msg, FS_CMD_ARGS capture, `cli_help` heredoc. Verified: 18-case fixture all pass, `-z` unknown-flag, env seam, strict-shell safety, git containment. |
| P2.3 | **DONE** · **COMMITTED** `1a33214` | rev `ses_f27b514d7ffehfOVXoIDB8YQMR` (REVISE → REVISE → PASS) |
| P2.4 | **DONE** · **COMMITTED** `2b058b5` | rev `ses_f279347d7ffeLGseBPlIjSWIzL` (3×REVISE → PASS; blocking fixes: name validation shared across mark/check/unmark, `.`/`..`+dir-target `_state_write` (`mv -fT`), registry fail-closed bootstrap, full-path symlink-confinement `_state_chain_ok` walking /→target on every FS op, `readlink -m` canonicalization, `state_log` leaf validation). `lib/state.sh`: state_init (FS_HOME>XDG_STATE_HOME>HOME, canonical absolute), state_log (run-<ts>-<pid>.log, chain-validated+non-symlink), state_module_ mark/check/unmark (registry `done <ts>`, validated names, symlink-safe), state_backup_ add/get (`src|bkp|ts` registry, newline+CR rejected, single-writer). Verified 53/53 asserts. |
| P2.5 | **DONE** · **COMMITTED** `fdde051` | rev `ses_f275d4821ffePjAhwnJSUnTfPD` (6×REVISE → PASS). `lib/fs.sh`: fs_backup (chain-confined `backups/files` via `_fs_chain_ok` walking /→target, mktemp+`mv -fT` atomic with unique `.N` collision suffix, registry entry AFTER move, orphan rollback on registry failure, `\|`-in-path rejection), fs_install (parent/un-dotdot/newline/trailing-slash validation, `_fs_parent` setter w/o cmdsubst, backup-first overwrite, atomic temp+rename, `mktemp --`), fs_managed_block/remove (# BEGIN fedora-setup `<name>` marker covenant; lossless line-split `_fs_block_lines` (trailing `\n` convention), element-wise `_fs_array_equal` no-op detect (no trailing-blank collapse), global `_fs_validate_markers` namespace walker forbidding nesting/crossing/orphan/unterminated/bare markers while permitting sibling blocks, marker-like content rejected, corrupt files fail-closed, mode preserved via chmod-before-move, remove restores original bytes; nameref helpers guarded for Bash≥4.3). Verified 55/55 fixture asserts (multi-block coexist, symlink escape, byte-exact restore, collapse cases, backup uniqueness). |
| P2.6 | **DONE** · **COMMITTED** `69df24d` | rev `ses_f2703933effemOZcEcu8kx5KIk` (6×REVISE → PASS). `lib/sudo.sh`: sudo_detect (EUID==0 warn+flag, `command -v sudo`+`sudo -n true` probe, dry-run keeps probe-off AND preserves cached policy, FS_EUID test seam), sudo_refresh (pure no-op under dry-run; `sudo -v` only when FS_VERBOSE), sudo_exec (root-aware dry-run `# would run:` with %q rendering, root execs directly, `sudo --` option barrier, valida­tes empty/absent argv0). Never touches /etc/sudoers. Auditing contract documented: CLI routes privileged steps through run_sudo. Verified 40/40 fixture asserts. |
| P2.7 | **DONE** · **COMMITTED** `43098f7` | rev `ses_f2703933effemOZcEcu8kx5KIk` (same session, 6×REVISE → PASS total across P2.6+P2.7). `lib/run.sh`: run_cmd/run_sudo (label, `--stop`, `--`, %q single-line dry-run `# would run:` purity incl. caller-IFS invariance, keep-going default vs `--stop`/`[DESTROY]` literal stop, `\[DESTROY\]` not bracket-class), `_run_exec` (PIPESTATUS captured in one statement, `tee -a --`, FS_LOG_INFRA halt for unusable/tee-failed log, stat-only pre-check, `_run_err` stderr-only infra diagnostics — no blocking open; private, must be `\|\|`-guarded), FS_LOG_FILE audit invariant. `lib/io.sh` amendment: no self-clear of FS_LOG_FILE on append/init failure (re-validated each call), FIFO/special-path guard in `_io_logline`/`io_init`, io_progress/io_summary prison-safe arg defaults, init warning. `lib/cli.sh` amendment: `_CLI_ENV_{DRY_RUN,YES}` env seeding symmetric w/ verbose/debug. 40/40 fixture asserts (FIFO no-hang, dangling-symlink no-materialize, latch-vs-typo regression, healthy audit trail). |
| P2.8 | **DONE** · **COMMITTED** `739eea6` | rev `ses_f24ca70c4ffe4Zp0QFwQufKnmq` (REVISE → PASS; blocking: cli.sh loop bounds `$#`-based for Bash≥4.3 empty-array safety while keeping the 4.3 floor, dispatcher `*)` arm so a future command without a case arm fails loudly rc=1; + `_cli_check_stub` root arity guard). `setup` resolves itself for any CWD + `readlink -f`; `lib/bootstrap.sh`: versions check, source io+cli, `cli_parse` → dispatch help/version/check-stub/list-empty, install|verify|export|update rc=1 "not implemented yet". Verified: help/-h/no-args, version, check, list (0 bytes rc0), bogus/unknown-flag/`--profile`-missing rc1, any-CWD, flag combos, closed-fd robustness. |
| P2.9 | **DONE** · **COMMITTED** `5e53b16` | rev `ses_f24c0a819ffe0aSAWUp8GjWrmb` (2×REVISE → PASS). `tests/smoke.sh` plain-bash suite for P2.1–P2.8: hermetic blocks under `set -euo pipefail` with `(%s)`-captured `block_rc_last`, helpers `t_rc`/`t_block_rc`/`t_out(_not)`/`t_err(_not)`/`t_empty`, epilogue gates exit on `(( fail == 0 ))`. Round-1 REVISE (8 findings: t_rc-truncation dead asserts, sudo dry-run purity, block rc teeth, P2.5 positive asserts, `test -e` tautology, dnf5 host-dependence, root-hostile EUID, P2.8 command coverage) → round-2 REVISE (suite could never exit non-zero — no epilogue; `t_out_not` still clobbered in io block; `pkg=` always-match; `list` emptiness dropped; vacuous symlink-path assert) → round-3 PASS with mutation battery. Stamped: 103 passed / 0 failed, 3× byte-identical, any-CWD, clean under `unshare -Ur` and hostile `FS_*`/minimal-PATH envs, fake-HOME byte-identical; sr-fixture 40/40. |
| P2.10 | **DONE** · **COMMITTED** `b1bbfa1` | Owner-approved doc task. `AGENTS.md` at repo root: operational contract for AI agents (overview, structure, cross-distro, ROADMAP usage, task workflow, dev-reviewer split, verification, git discipline, safety invariants, DoD, decisions to preserve, change rules). Sources: git history, ROADMAP, lib doc headers, setup/.gitignore/README. |
| P3.1 | **DONE** · **COMMITTED** `60693d9` | rev `ses_f24afc380ffelWs8H5tRVAGFdW` (3×REVISE → PASS). `lib/pkg.sh` interface+dispatcher: `FS_PKG_BACKEND` env wins → distro-family fallback; read-only seam (dispatch off private `_pkg_active`, no write-back); contract = seven `<name>_<op>` members incl. `<name>_supported`; `declare -F` seven-member completeness gate; io_error for none/unknown/unimplemented/partial backends; source-time dir resolution inert under set -e (bare/relative/absolute). `tests/fixtures/lib.sh` (fx_* helpers + gating epilogue), `tests/fixtures/pkg_contract.sh` (20 asserts), `lib/pkg/.gitkeep`. Verified: 20/0 rc0, 3× byte-identical, hostile-env matrix + `env -i` + `unshare -Ur` + any-CWD, gate-proved on mutation; `tests/smoke.sh` 103/0 untouched. Round-1 REVISE (unguarded seam under set -u; non-hermetic fx_init unset list; `supported()` dropped from contract) + round-2 REVISE (bare-filename source-time `set -e` silent abort; partial backend reported SUPPORTED) → round-3 PASS. |
| P3.2 | **DONE** · **COMMITTED** `43391a5` | rev `ses_f24a4d1a5ffef5aVg7DQQ8LBYg` (PASS + re-review PASS on refinements). `lib/pkg/rpm.sh` seven-member contract: `rpm_supported` = dnf tool (dnf5 preferred via `command -v`) AND `rpm`; `rpm -q` queries (rc0/rc1, no stdout); `rpm -qa --qf '%{NAME}\n'` name-form listing; batch = SINGLE `dnf install -y` transaction after real-mode already-installed filter, dry-run = one `# would run:` line, no queries/writes; `dnf makecache`; local `dnf install -y <file>`; add_repo if-not-exists under `${FS_REPOS_DIR:-/etc/yum.repos.d}` with id/url validation, atomic `install -m 0644 <tmp> <dest>`, guarded tmp write, optional gpgkey arg; every mutation via run_sudo (audit + `sudo --` barrier, dry pure), never /etc/sudoers. `tests/fixtures/pkg_rpm.sh` (39 asserts): PATH-fake rpm/dnf5/dnf/sudo logging to FAKE_LOG, capability present/dnf-only/absent(+rpm-required), P3.1 dispatch-fallback→rpm end-to-end, query present/absent (no-stdout), list, all-installed skip, mixed single-transaction, non-root sudo barrier, FS_LOG_FILE audit-trail assert, update/local (±missing file NO), repo real content + if-not-exists no-overwrite, repo/batch dry purity (+no destination written). Verified: 39/0 rc0 ×3 byte-identical, any-CWD, hostile FS_VERBOSE/DFS_LOG_FILE/env -i, unshare -Ur; gate-proves: semantic mutation rc1, epilogue-removal rc0; smoke 103/0; sr 40/40. Host has real dnf5/dnf — fixture proven host-independent. Carried non-blocking: `--qf` argv assert, `rpm` negative capability block, CR/LF bounds on url/key, ~/.PATH minimal hardening, header arity/barrier lines. Task text's "copr where needed"/`--setopt` live in copr module data (P4) / deferred.
| P3.3 | **DONE** · **COMMITTED** `1582494` | rev `ses_f249d52c5ffe91eXnIm7CPQ18G` (REVISE → PASS). `lib/pkg/deb.sh` seven-member contract as `deb_<op>`: `deb_supported` = apt-get + dpkg-query present; `dpkg-query -W -f='${db:Status-Status}'` queries (rc0 + "installed" only when present, no other stdout); `-W -f='${Package}\n'` name list; batch = SINGLE `apt-get install -y` transaction after real-mode already-installed filter (dry skips filter, one `# would run:` line per install + one for apt-get update when a repo was added this session, no queries/writes); `apt-get update` clears `_deb_repos_changed`; local `apt-get install -y <file>`; `_deb_repos_changed=1` tracks add_repo in-session so the next batch refreshes metadata before installing; add_repo IF-NOT-EXISTS under `${FS_SOURCES_DIR:-/etc/apt/sources.list.d}` = `<id>.list` with `deb <url>` (or `deb [signed-by=<key>] <url>`), atomic `install -m 0644 <tmp> <dest>`, id/url validated; every mutation via run_sudo (`sudo --` barrier + FS_LOG_FILE audit), never /etc/sudoers. `tests/fixtures/pkg_deb.sh` (43 asserts): PATH-fake apt-get/dpkg-query/apt-cache?/sudo logging to FAKE_LOG, capability present/absent, query ±(no-stdout), list, all-installed skip, mixed single-transaction, repos-changed → pre-batch apt-get update, update, local ±missing, repo content(+signed-by)+if-not-exists+path-id reject+dry, batch/dry purity. Retargeted `pkg_contract.sh` unbuilt-backend block mock→deb. Verified: 43/0 rc0 ×3 byte-identical, any-CWD, hostile envs, env -i, unshare -Ur; gate-proves semantic rc1, epilogue rc0; contract 20/0; rpm 39/0; smoke 103/0.
| P3.4 | **DONE** · **COMMITTED** `7cb0f5a` | rev `ses_f2497cf9fffe1Fqhp8v8lZ4eri` (PASS, no blocking). `lib/pkg/arch.sh` seven-member contract + AUR opt-in superset: `arch_supported` = pacman; queries `pacman -Q` (rc0/rc1, no stdout); `pacman -Qq` name list; batch = SINGLE `pacman -S --noconfirm --needed` after real-mode already-installed filter, dry = one `# would run:` line (returns before filter loop — zero `pacman` calls under dry), no writes; `pacman -Sy` update; local `pacman -U --noconfirm <file>`; add_repo if-not-exists under `${FS_ARCH_REPO_DIR:-/etc/pacman.d}` = `<id>.conf` `[<id>]` + `Server = <url>` (+ optional `SigLevel = <key>` line when key arg given), id/url validated, in-memory build then guarded atomic write, dry = one line + no file; every mutation via run_sudo (`sudo --` barrier + FS_LOG_FILE audit), never /etc/sudoers. **AUR**: `arch_aur_helper` = pure `command -v` discovery, paru preferred → yay fallback, never installs a helper; `arch_aur_batch <pkg>...` = single `helper -S --noconfirm` transaction via run_sudo, refuses clearly rc1 when no helper ("AUR packages are opt-in"), dry = one line. `tests/fixtures/pkg_arch.sh` (52 asserts): PATH-fake pacman/paru/yay/sudo (fakebin, fakebin-yay, fakebin-noaur, notools dirs) logging to FAKE_LOG, capability present/fallback/absent, quey±(no-stdout), list, all-installed skip, mixed single-transaction, non-root sudo barrier, FS_LOG_FILE audit, update, local ±missing file, repo content(+SigLevel)+if-not-exists no-overwrite+path-id reject+dry, batch dry pure, AUR: prefer paru / fallback yay / absent errors / single transaction / no-helper opt-in guard / dry pure. Direct `arch_aur_*` calls trigger lazy backend load via `pkg_supported`. Retargeted `pkg_contract.sh` unbuilt-backend block arch→mock (mock unbuilt until P3.7). Verified: 52/0 rc0 ×3 byte-identical, any-CWD, hostile envs, env -i, unshare -Ur; gate-proves mut/rc1, epilogue/rc0, aur-helper-override rc1; contract 20/0; rpm 39/0; deb 43/0; smoke 103/0; sr 40/40. Reviewer non-blocking (owner/SR-flagged): `SigLevel = <key>` renders into pacman's keyword set — owner decision before P7.5 uses add_repo with key; `pacman -Sy` partial-upgrade risk → note for P10.3 (`-Syu`?); no repos-changed pre-batch sync (deb-only req, P3.8/P3.9/P10.3); `arch_aur_batch` skips `arch_supported` gate (opt-in guard is the real gate); helper lookup under sudo vs $HOME (P7.5). | `lib/pkg/deb.sh` seven-member contract: capability = apt-get AND dpkg-query; queries `dpkg-query -W -f='${db:Status-Status}'` (rc0 + `installed` printed only when installed, else rc1, no other output) + `-f='${Package}\n'` name list; batch = SINGLE `apt-get install -y` after real-mode already-installed filter; dry = one `# would run:` line for install (+one refresh line when a repo was just added), no queries/writes; **update-before-batch flag** `_deb_repos_changed` (set only on verified new-repo write `rv==0`, cleared after use and by update_metadata); local `apt-get install -y <file>`; add_repo → `<id>.list` under `${FS_SOURCES_DIR:-/etc/apt/sources.list.d}` = `deb <url>` or `deb [signed-by=<key>] <url>`, id/url validated, atomic `install -m 0644` + guarded tmp write; mutations via run_sudo (audit, `sudo --` barrier, dry pure), never /etc/sudoers. `tests/fixtures/pkg_deb.sh` (43 asserts, mirror of rpm harness): capability/fallback/absent, query±(no-stdout), list, all-installed skip, mixed single-transaction, non-root sudo barrier, FS_LOG_FILE audit, update, local ±missing-file, repo real content + if-not-exists no-overwrite + path-id reject + dry (single line, no file), batch dry pure, repo→batch update-ordering. Retargeted `pkg_contract.sh` unbuilt-backend block deb→arch (B1: deb now built). Verified: 43/0 rc0 ×3 byte-identical, any-CWD, hostile envs, env -i, unshare -Ur; gate-proves mut/rc1, epilogue/rc0; contract 20/0; rpm 39/0; smoke 103/0; sr 40/40. Carried: dead `|| return $?` under keep-going runner (P3.8/P9), signed-by & flag-clearing & partial-capability & tmp-residue asserts (N4), pre-existing-repo no-refresh (P3.9/P10.3), dry-`<id>.dry` path (P3.8). |
| P3.6 | **DONE** · **COMMITTED** `151dda4` | rev `ses_f248ff7c7ffewW2O079NaGm1Ug` (REVISE B1 → PASS). `lib/pkg/flatpak.sh` full seven-member contract as `flatpak_<op>` + protected constants `FLATPAK_REMOTE_ID=flathub` / `FLATPAK_REMOTE_URL=https://dl.flathub.org/repo/flathub.flatpakrepo`. Prototype-bug #2 fix: guaranteed `flatpak remote-add --user --if-not-exists flathub <url>` precedes every install transaction. Per-user scope (unprivileged run_cmd, never sudo); user/system install detection (`flatpak info --user` then `--system`; list merges `--user`+`--system` through `sort -u`). Batch `(( FS_DRY_RUN == 1 ))`: remote-add line + ONE install command, no probes; real: per-scope already-installed filter, remote-add once, single `flatpak install --user --noninteractive --assumeyes <missing...>`; all-installed runs nothing. update=`flatpak update --appstream`; local=`flatpak install --user --noninteractive --assumeyes <file>` (existence only real mode — dry no-probe per AGENTS.md); add_repo=`flatpak remote-add --user --if-not-exists <id> <url>` (+`--gpg-import <key>`), id `^[A-Za-z0-9._-]+$`, url CR/LF-rejected. All mutators gate `flatpak_supported` first (add_repo superset); numeric dry guard consistent w/ rpm/deb/arch. `tests/fixtures/pkg_flatpak.sh` (50 asserts): fake `flatpak`+`sudo` logging to FAKE_LOG, capability present/absent, query user+system+missing (fx_empty), list sorted unique merge, batch real (remote-add line<install line, single count, exact content), all-installed nothing-runs, dry (ordering+single count+empty log), FS_LOG_FILE audit, update real/dry, local real/±missing/dry, add_repo real/key/bad-id/empty-id/newline-url/dry, end-to-end never-uses-sudo (logging fake sudo makes the token assert have teeth). B1 (blocking): asserts were presence-only — order-swap instal-before-remote-add passed 49/0 → fixed with grep -n line-ordering + install-count==1 (+dry same), exact-real-content re-pinned; both mutations now rc1. Verified: 50/0 rc0 ×3 byte-identical, any-CWD, hostile envs, env -i, unshare -Ur; order/dry-order/dup-call/dup-dry mutations rc1; smoke 103/0; rpm 39/0; deb 43/0; arch 52/0; contract 20/0 (still targets `mock` — unbuilt until P3.7); sr 40/40. Carried non-blocking: id regex admits `.`/`..`/leading `-` (no path derived — rpm same class); `|| true` one-scope tolerance / `--app` arg-insensitive / empty-id guard ungated; env-overridable flathub constants pinned by asserts, `readonly` deliberately NOT added (re-source on backend flip would abort); `FS_DRY_RUN=yes` aborts (pre-existing, all backends + run.sh); reviewer-flagged stray-user-remote artifacts cleaned (`flatpak remote-delete --user testrepo`). |
| P3.8 | **DONE** · **COMMITTED** `40fb950` | rev `ses_f21f85691ffe2vb0sK2V0fE4Q2` (REVISE B1 → PASS; B1 = false run.sh-independence claim in planner header → header only rewritten, code+guard byte-identical). `lib/planner.sh` batch planner: `plan_dedupe` (unique, first-seen order, empty args skipped, no fs access), `plan_pending` (real: active-backend installed-diff via `pkg_query_installed` → prints ONLY uninstalled; dry `${FS_DRY_RUN:-0}==1`: no probes, full deduped set passes, backend never loads), `plan_install` = dedupe → pending → EXACTLY ONE `pkg_install_batch` (single per-family transaction; rc0 on empty). Family-list parsing/merging (`packages.list` + `packages.<family>.list` precedence) documented as P4.3 scope; planner consumes the active-family list for `FS_PKG_BACKEND`. Dry rendering is the backend's own single `# would run:` line (rpm = `sudo dnf5 install -y ...` via run_sudo). No writes/sudo, never /etc/sudoers. Backend surface touched: `pkg_query_installed` + `pkg_install_batch` only. Header truthfully requires run.sh for plan_install (all six backends read bare FS_DRY_RUN, dry lines via run_cmd/run_sudo, FS_LOG_FILE + sudo-policy defaults in run.sh). `tests/fixtures/planner.sh` (25 asserts): dedupe order/empty/double, real pending exact output + FS_MOCK_LOG probe-trace, dry pending = full pass-through + empty log (no probe), plan_install EXACT recorded call sequence = `mock query` per unique pkg + ONE `mock install ...` line (order/count/content-sensitive → single-transaction proof), rpm dry = EXACTLY one `# would run: sudo dnf5 install -y vim git curl` + FAKE_LOG empty (dnf5-never-executed token), installed-state honored. Verified: 25/0 rc0 ×3 byte-identical, any-CWD, `env -i`, hostile envs, `unshare -Ur`; gate-proves: no-dedupe rc1, dry-probe rc1, split-transaction rc1 (+ reviewer double-transaction/reversed-order/duplicated-query/pending-prints-all rc1), epilogue-removal rc0 (documented gate limit); regressions smoke 103/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0. Reviewer flagged the stale "sr 40/0" citation (no such in-tree suite; a /tmp P2-era artifact) — P3.8 row records only the seven tree suites. |
| P3.9 | **DONE** · **COMMITTED** `20db42b` | rev `ses_f21f16f07ffeeiygJpNjxPAoqS` (PASS, no blocking; NB1/NB2 applied post-PASS). `pkg_verify_packages` in `lib/pkg.sh`: read-only per-package present/missing diagnostic behind `setup verify` (P9.2). For each input pkg: `pkg_query_installed` (rc0/rc1, no stdout contract across all five backends) → prints `present: <pkg>` / `missing: <pkg>` in input order; rc 1 iff any missing, rc 0 on empty/all-present. Always queries in real AND dry mode (write-free diagnostic; never writes system state — mock FS_MOCK_LOG recording is test instrumentation — never sudo, never renders `# would run:` lines; dry-run "no probes" rule governs planning/render paths, doc names the exemption). Depends only on io.sh+pkg.sh (no run.sh; empirically true for rpm/deb/arch/flatpak/mock). Up-front `_pkg_load` so an unusable/unknown backend fails loudly (goofy backend + empty list → rc1) instead of reporting all-missing. `tests/fixtures/pkg_verify.sh` (16 asserts): mock present/missing mix rc1 + exact ordered output + one `mock query` record per input in order, empty rc0 no output no records, all-present rc0, dry ground truth + no `# would run:` render + queries still recorded, rpm (PATH-fake `rpm -q` answering git-only) mix rc1 exact output + empty rc0. Verified: 16/0 rc0 ×3+ byte-identical, any-CWD, `env -i`, hostile envs, `unshare -Ur`, canary-PATH no-real-PM log empty; gate-proves (dev+reviewer 9 more, all rc1): labels-swapped, rc-on-missing-removed, empty-input-rc1, dry-skips-queries, grouped-output, query-stdout-leak, render-under-dry, break-at-first-missing, reversed-query-order; epilogue-removal rc0 (pre-existing harness, reproduced on committed pkg_contract). Full regressions: smoke 103/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. Reviewer NBs carried: (NB3) verify sentence spliced into pkg_supported paragraph — cosmetic, deferred; NB4 coverage gaps (no rpm all-present cell, mock-only dry, installed-file-unchanged, block re-seed, no stderr assert — all verified harmless); NB5 fx_summary gate limit tickets P10.x. `setup verify` itself unwired until P9.2. |
| P3.7 | **DONE** · **COMMITTED** `0e31a4d` | rev `ses_f248437b8ffeE7zP0bUMflvDDm` (REVISE → PASS). `lib/pkg/mock.sh` simulated backend: pure test seam, no binaries (mock_supported always rc0), used by downstream unit tests + dry-run rendering. Seven-member contract as `mock_<op>`. Seams: `FS_MOCK_INSTALLED` (file, one pkg/line; unset = empty set; real-mode installs append so P3.9 verify/module tests see installed state) and `FS_MOCK_LOG` (recording file; when set MUST already be a regular writable file or the op halts with io_error — FS_LOG_INFRA pattern; when unset silently no-record). Records every invocation: `mock query <pkg>` (incl. the batch filter queries), `mock install <missing...>` (SINGLE transaction recorded BEFORE the installed-set append — state never mutated without a record), `mock update`, `mock install-local <file>`, `mock add-repo <id> <url> [key]`; all record sites propagate `|| return 1` failing closed. Batch real filters already-installed then records one transaction; empty id/url, id `^[A-Za-z0-9._-]+$` + explicit `.`/`..` reject, CR/LF url reject, empty-pkg query reject (matches rpm/flatpak). Dry `(( FS_DRY_RUN == 1 ))`: SINGLE `# would run: mock <op> ...` via run_cmd, no probes/filtering/recording/mutation. No sudo, never /etc/sudoers, no writes outside the mounted seams. `tests/fixtures/pkg_mock.sh` (60 asserts): capability, query installed/missing (fx_empty 2-arg, stdout-leak-gated), list sorted dedupe, install_batch EXACT recorded call sequence query×N+one install line (order+count-sensitive — task verification), installed-state honored post-install, all-installed skip records no install, dry purity (one-line count + no record + no mutate), update/local/add-repo real + dry, local missing-file, repo invalid id/empty/`..`/newline-url/dry, empty-pkg query, unusable-FS_MOCK_LOG halt per op family (query/update/batch/install-local/add-repo; query halts on an INSTALLED pkg so rc comes only from record failure; batch asserts no installed-set mutation), no-seam silent empty set. Retargeted `pkg_contract.sh`: removed both now-dead "package backend not implemented: mock" blocks (20→16 asserts) + header note (all five allowlisted backends built; `_pkg_load` missing-file branch dead code). Verified: 60/0 rc0 ×3 byte-identical, any-CWD, hostile envs, env -i, unshare -Ur; gate-proves: unfiltered-batch rc1, extra-dry-line rc1, dry→real rc1, epilogue-removal rc0, stdout-leak rc1; regressions smoke 103/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, sr 40/0. B1/B2/B3 (record-rc propagation + record-before-mutate; false-positive halt assert; vacuous one-arg fx_empty) fixed across REVISE → PASS. Carried NB: five halt blocks don't bind `|| return 1` under set -e (PC would need set +e — coverage strength only); `mock` real ops bypass run_cmd/FS_LOG_FILE (no-binary seam, documented); supported/list not recorded (header enumerates 5 record shapes); pre-existing one-arg fx_empty in committed pkg_flatpak.sh needs a separate ticket.
| P4.1 | **DONE** · **COMMITTED** `a49f2f1` | rev `ses_f21d70fd6ffe8iIZdEhQbrC27B` (PASS, no blocking; NB1–NB10 fidelity fixes applied post-PASS). `lib/modules.sh` module contract + loader. Contract: module dir `modules/<id>/` with three recognized file kinds — `module.sh` (REQUIRED metadata, PARSED textually never sourced so `./setup list` cannot execute module code), `hooks.sh` (OPTIONAL `run()`/`verify()`, never sourced at load; P4.6 runner sources in subshell), and declarative lists `packages.list/.rpm.list/.deb.list/.arch.list`, `flatpaks.list` (naming set in `MODULE_LIST_NAMES`; family-override precedence explicitly P4.3). Metadata line format `KEY=VALUE`: blanks + `#` ignored, optional matching quote pair stripped, spacing trimmed, single-line values, no inline comments, unknown KEY → io_warn (load continues) with EXACT-token membership; MODULE_ID required + `module_valid_id` (mirrors state.sh `_state_valid_name`, kept separate for io-only dep). Defaults RISK=none DEFAULT=off (+ rest empty); `module_load` resets all six contract globals every call (cross-load safety), prints nothing, failure = io_error+rc1 (missing dir / missing module.sh / absent-invalid MODULE_ID) with partial-population documented. `module_list_files` (fixed-order report), `module_has_hooks` (presence only; never defines/leaks functions). `tests/fixtures/modules.sh` (31 asserts): minimal full-parse exact capture, defaults + cross-load reset incl. MODULE_DEPENDS, unknown-key warn-and-continue with parsed metadata intact, missing-dir/module.sh/MODULE_ID/invalid-id rc1+error, quote stripping, whitespace+comment tolerance, list-file naming (all 5 present, fixed order), list-less empty rc0, hooks present/absent/missing-dir, no-sourcing probe (hooks.sh side-effect marker + no run/verify leak). Verified: 31/0 rc0 ×3 byte-identical, any-CWD, `env -i`, hostile envs (incl. TMPDIR), `unshare -Ur`; gate-proves: warn-removed rc1, MODULE_ID-required-removed rc1, invalid-id-removed rc1, reset-removed rc1, quote-strip-removed rc1, key-trim-removed rc1, list-names-reorder rc1, hooks-sourced-at-load rc1, stdout-leak rc1, commit-token/direct-exec-bypass no-execution probes; epilogue-removal rc0 (pre-existing harness limit). Regressions all green: smoke 103/0, modules 31/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. Reviewer mutation survived before fix: DEPENDS-reset unpinned → now pinned. NBs deployed: header truth fixes (no unreachable newline path, "reset the six globals", no "number-contract", state.sh mirrors-wording, "planned (P4.3)" precedence, failure partial-population documented, RISK/DEFAULT vocabularies declared P4.2's, exact-key warning no compound-key bytepass), fixture: DEPENDS in reset assert, hooks marker probe, label → MODULE_LIST_NAMES order, heredoc quoting, mkdir dedupe. Carried NB: no-arg module_load / list_files-on-missing-dir / has_hooks-no-arg / valid_id "" "." ".." unpinned (reviewer-probed correct), mismatched MODULE_ID-vs-dirname must be a P4.2 validation item. |
| P4.2 | **DONE** · **COMMITTED** `437c24a` | rev `ses_f21cf7fa0ffeoMWlGnZlnAgnM5` (REVISE B1/B2 → PASS; B1 = grep-pipeline SIGPIPE race, B2 = risk-substring-match). `lib/modules.sh` P4.2 validation: `module_load` gained optional `strict` (unknown key → io_error+rc1; validation, `./setup list` use strict); `module_validate <dir> <family>` = id==dirname identity invariant (dup ids structurally impossible under validate), exact-token MODULE_RISK ∈ none|low|medium|high|destructive, MODULE_DEFAULT ∈ on|off, TSV-safety control-char rejection in TITLE/DESCRIPTION, family-loadability (rpm|deb|arch + any list file ⇒ need packages.list|packages.<family>.list|flatpaks.list; hooks-only and non-rpm/deb/arch family pass); `module_validate_set <dirs...>` = all load, dup-id guard (guards callers skipping validate), every MODULE_DEPENDS referral resolvable in-set (here-string `grep -qxF <<<`, no pipeline → SIGPIPE race structurally gone; stress 140KB/20k-line ids target=first line: OLD 2000/2000 false rejections, NEW 0/2000); `module_depends <dir>` prints DEPENDS ids. `lib/bootstrap.sh` wired the `list` command: sources modules.sh+state.sh lazily, `state_init` under FS_HOME, `distro_detect` only when FS_DISTRO_FAMILY unset (family rejection reachable on real hosts; fail-loud on non-rpm/deb/arch), `_cli_list_impl` = FS_MODULES_DIR seam (missing dir → rc1 "modules directory not found"), skip dotfiles, per-dir module_validate + set validation, `LC_ALL=C sort` by id, renders `id\ttitle\trisk\tdefault\tstatus` (status `done`/`-` via `state_module_check`, fail-loud no 2>/dev/null). `tests/fixtures/modules_list.sh` (44 asserts): validate good/unknown-key/archonly-on-rpm rc1 vs arch rc0/mismatch/hooks-only/destructive/multi(`low medium`)/upper(HIGH)/norisk(empty)/defaultyes(tab)/badtab rc1; validate_set good graph / ghost dep rc1 (`gamma depends on unknown module 'ghost'`) / dup ids rc1 / dep-matches-first-sorted-id rc0 (`zzz`→`aaa`); end-to-end `./setup list` valid set rc0 + EXACT sorted table w/ `done` from FS_HOME state registry, invalid set rc1 + empty stdout + named errors, invalid graph rc1 + `gamma depends on unknown module 'ghost'`, empty set rc0/empty, missing module dir rc1. Verified: 44/0 rc0 ×3 byte-identical, any-CWD, `env -i`, hostile envs, `unshare -Ur`; gate-proves G1–G11 all rc1 (strict-unknown-key, id==dirname, family-loadability, unknown-dep, dup-id, CLI per-dir validate, CLI validate_set, status-lookup, risk-substring-revert, title-char, missing-dir), each byte-restored; epilogue-removal rc0 (pre-existing harness limit). Regressions all green: smoke 103/0, modules 31/0, modules_list 44/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. NBs applied: NB1 LC_ALL=C sort, NB2 control-char rejection, NB3 distro_detect wiring, NB4 state_module_check fail-loud, NB5 missing-dir guard, NB7 strict-mode header, NB8 validate_set dup-guard wording, NB10 FS_MODULES_DIR in fx_init unset list + AGENTS.md §3. Carried (reviewer, no-action-this-gate): no FS_DISTRO_FILE-driven list fixture cell (family path proven by reviewer via roleplay os-release: `ID=debian`+arch-only module → rc1 "no package list usable on family 'deb'"; `plan9` → rc1 loud; real-host rc0), `list` hard-fails on non-rpm/deb/arch distros, header "control characters" wording covers tab/LF/CR only; deferred-unused `module_depends` awaited by P4.4; NB6 (list state_init mkdirs $HOME state root — conscious, dry-run still writes, documented), NB9 (4× module re-parse accepted), NB12 (empty module set prints nothing — owner call).
| P4.3 | **DONE** · **COMMITTED** `aaf534e` | rev `ses_f21baf3c1ffek8hrVLRap0h4OX` (REVISE B1 → PASS; B1 = blank-line leak from present-but-empty lists). `lib/lists.sh` list-file parsers, io.sh-only dep. Grammar (all three list kinds): blank + `#` comment lines ignored (leading whitespace ok), trimmed whole-line entries, inline trailing comments NOT stripped (`git # tool` = single entry, documented), first-seen dedupe, last-line-without-newline + CRLF tolerant (`{{"${line%%[![:space:]]*}"}}` trim). `list_parse <file>`: missing/non-regular/unreadable → io_error+rc1. `list_packages <dir> <family>`: EXACT precedence — family file `packages.<family>.list` entries first (deduped), then `packages.list` common entries minus same-named twins (family overrides common + precedes); empty/absent family → common only; absent = empty; present-but-comment-only = nothing, NEVER a blank line (all emit points guarded `[[ -n ... ]]`, merge loop skips empty id); unreadable/`-r` + `-n "$family"` guard unpinned (not deterministically testable; P10 ticket). `list_flatpaks <dir>`: own namespace, never mixes with packages. `tests/fixtures/lists.sh` (36 asserts): single-list parse exact (comments/blanks/dupe/CRLF/no-eol), no-override = common, family-first precedence EXACT (`beta firefox gamma vim alpha`), other-family untouched, flatpak dedupe + namespace separation, family-only arch vs rpm-empty, listless empty, empty-family = common-only, inline-comment-unsupported, missing-file/arg/dir misuse rc1+error, plus B1 cells: comment-only family over real common (cmp, no blank), comment-only common + real family (cmp, no blank), zero-byte both (fx_empty). Verified: 36/0 rc0 ×3 byte-identical, any-CWD, `env -i`, hostile envs, `unshare -Ur`; gate-proves G1 dedupe (4 FAIL), G2 comment-skip (6), G3 family-first (>=2), G4 trim (3), G5 missing-file (1), G6 fam blank-guard (2), G7 common blank-guard (1), all rc1 + byte-restored (G2b/G4b re-fired post-fix); epilogue-removal rc0 (pre-existing limit). Regressions all green: smoke 103/0, lists 36/0, modules 31/0, modules_list 44/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. NBs applied post-PASS: header wording fixes (absent=empty, no overstatement; NB3 message now "list file missing or not a regular file: <path>"), probe cells for B1 blast-radius (`mapfile -t` = no empty elements), fixture paren alignment. Carried: NB4 stale cross-refs fixed in lib/modules.sh:26-27 + lib/planner.sh:10 (both now cite lib/lists.sh, comment-only edits); `list_packages` -f gating silently-absent non-regular paths (reworded header), `-r`/family-guard unpinned (P10), NB6 precedence semantics = additive-with-same-name-suppression confirmed in-code; P4.6 must consume list_packages/list_flatpaks (owner-confirmed reading of "family replaces/overrides common entries").
| P4.4 | **DONE** · **COMMITTED** `951896e` | rev `ses_f214ecb88ffeCxfkBkLP0ydtuM` (REVISE B1/B2 + 9 NBs) → PASS `ses_f21484603ffel0LMGXNNLWmHkq`, no surviving findings. `lib/depgraph.sh` `dep_toposort <dir>...` (dep io.sh+modules.sh): graph from MODULE_DEPENDS via module_load globals (one metadata parse per dir; in-module dup deps + dup dir args collapse, first wins); ids from MODULE_ID (P4.2 identity invariant enforced upstream); Kahn with witnesses map, indeg = count of own dep edges; ready queue re-sorted `LC_ALL=C` every step + sorted `remain` start ⇒ argument-order-independent deterministic output; every dependency precedes all dependents; acyclic → print deps-first rc0; empty set → rc0 nothing (`$#==0` early return = bash 4.3 nounset-safe); errors before any output: module_load fail (`module metadata missing`), unknown ref `<id> depends on unknown module '<dep>'` (aligned to modules.sh wording), `cycle: <walk>` (starts at smallest remaining id, follows declared DEPENDS order, records the repeated id closing the loop; self-dep `cycle: sa -> sa`; acyclic-prefix+tail e.g. `a -> b -> c -> b`); pinned `local IFS=$' \t\n'` + `read -ra` for all token splitting (no pathname/glob expansion from CWD contents or metachar tokens); all arrays/mutables local, no global leaks. `tests/fixtures/depgraph.sh` (33 asserts): linear chain, diamond (shared dep once before both), independents ×2 arg orders identical sorted output, 2-cycle rc1+exact `cycle: ca -> cb -> ca`+empty stdout, self-cycle, six-deep chain (m1 deps m2..m6 → sorted `m2 m3 m4 m5 m6 m1`), mixed valid+cycle no partial output, unknown dep rc1+message, in-module dupe + dup dir arg collapse, empty set rc0 nothing, dir-without-module.sh rc1, MODULE_ID-as-id pin (dir zzz MODULE_ID=other; aaa DEPENDS=other → `other aaa`), two disjoint cycles ×2 arg orders identical `cycle: cx -> cy -> cx`. Verified: 33/0 rc0 ×3 byte-identical, any-CWD, `env -i`, hostile envs, `unshare -Ur`; gate-proves G1 cycle-branch bypass (11 FAIL), G2 unknown-dep guard (1), G4 ready+remain sorts reversed (7, incl. cycle-path determinism), G5 cycle-walk first-dep broken (5) — all rc1 + byte-restored; G3 empty-emit guard no longer independently phase-separable because the `$#==0` early return supersedes it (documented belt-and-suspenders). Review fixes: B1 `"${order[@]}"` on bash 4.3+set -u empty-array unbound ⇒ early return + `"${emitted[@]+"${emitted[@]}"}"` + length-guarded ready-slice; B2 header wrong ("id = dir basename") vs code/contract MODULE_ID ⇒ header corrected (code was right) + pinning cell. Regressions: smoke 103/0, lists 36/0, modules 31/0, modules_list 44/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. Ledger note: P4.2 `module_depends` remains the single-ref DEPENDS printer; P4.4 reads the module_load globals directly, not its output. |
| P4.5 | **DONE** · **COMMITTED** `5a33576` | rev `ses_f2145da0dffeczCohmthDPdVSe` (4×REVISE → PASS `ses_f21326a81ffe70hPEvPmgDYe7r`, no surviving findings). `lib/profiles.sh` `_profile_id_ok` (locale-stable `case`-glob token predicate: rejects empty/`.`/`..`, leading `.`/`-`, any char outside `[A-Za-z0-9._-]`) + `profile_validate` + `profile_load <dir> <name>` (reuses `list_parse` grammar; whole-line entries — inline trailing comments are part of the id, header-documented; missing/non-regular → list_parse error) + `profile_resolve <modules_dir> <profiles_dir> <name> [module...]` = union (profile order first, CLI appended, first-seen collapse) → every profile/CLI id token-validated → MODULE_DEPENDS closure BFS (dep tokens re-validated: `invalid module id in module '<id>': <dep>`) → `dep_toposort` (P4.4) with rc propagated (`|| return 1`). Errors before any output: invalid name/id (`invalid module id in set: <id>`), missing profile file, missing module, dependency cycle; rc0 iff the whole set resolves; empty profile + no CLI → nothing. `profiles/{minimal,desktop,developer,full}.conf` comment-only skeletons (valid empty until P5–P8 content). `FS_PROFILES_DIR` seam (AGENTS §3: consumed by the caller-level wiring planned in P4.6/P4.7; fx_init + AGENTS §2 updated). `tests/fixtures/profiles.sh` (81 asserts): valid/invalid names (incl. `../x`, `a/b`, `.minimal`, `-x`, ''), load order / in-file dupe / grammar (comments-CRLF-trim-no-eol) / empty / missing profile; resolve deps-first closure (base `b,a,d` → `b c a d` deterministic ready-sort), CLI-overlap collapse, CLI-only, CLI-dup, empty+no-CLI → nothing, cycle profile rc1+exact `cycle: x -> y -> x`+empty stdout (cells measure the FUNCTION's rc via `|| rc=$?`, not `set -e` abort), unknown module (dir-gone `module directory not found`), dir-without-module.sh (`module metadata missing`), traversal id in profile (`../evil`), `..` id, traversal as MODULE_DEPENDS token (`invalid module id in module 'h': ../evil`), missing profile through resolve, shipped-profiles load loop (all four rc0 empty), arity misuse (`profile_resolve requires...`/`profile_load requires...`), locale cells (tr_TR.UTF-8 / en_US.UTF-8 / C → `minimal` rc0 quiet), sequential resolves (module_load state reset). Verified: 81/0 rc0 ×3 byte-identical, any-CWD, `env -i IFS=: LC_ALL=tr_TR.UTF-8`, hostile envs, `unshare -Ur`, and REAL bash 4.3.48 (podman bash:4.3) → 81/0; gate-proves all rc1 + byte-restored: G1 token gate (12 FAIL), G2 resolve-arity (1), G3 load-arity (1), G4 conf-path join (32), G5 closure off (11), G6 regex-name-gate under tr_TR (5 — locale cell has teeth), G7 dep-token gate (1), G8 cycle-rc-swallowed (2 — proves guarded-caller rc). Review rounds: R1 REVISE (B1 bash-4.3 floor: `${ids[@]}`/`${candds[@]}` unbound on comment-only profiles + COMPANION depgraph.sh `ds`/`ps` sites; B2 collation-sensitive `[[ =~ ]]` name regex rejected `minimal` under `LC_ALL=tr_TR.UTF-8`; +12 NBs) → R2 REVISE (B1 header claimed dep tokens invalidated but code only checked profile/CLI ids — chose option (b): validate dep tokens in the BFS) → R3 REVISE (B1 `dep_toposort` rc swallowed in length guard → `profile_resolve` rc0 on cycles under guarded callers, fixture's `set -e` masked it; fixed + fixture now measures function rc; NB: header quote drift) → R4 PASS (no NB surviving). Folded-in companion fix (disclosed in commit body + this row): lib/depgraph.sh `ds`/`ps` empty-array guards — P4.4's suite is 17/16 FAIL on bash 4.3.48 without them. Pre-existing bash-4.3 gaps OUT of P4.5 scope, ticketed for P10/CI: smoke 95/8 (`cannot resolve state root`, lib/state.sh), modules_list 35/9, planner 22/3 on bash 4.3.48 (P2-P3-era sites) — AGENTS floor remains Bash ≥ 4.3. Traceability: `--profile` = cli.sh parse (`FS_PROFILE`, P2.2) only; consumption lands in P4.6 (plan assembly) / P4.7 (UI defaults) per phase §6 wiring-level deferral. Regressions: smoke 103/0, depgraph 33/0, profiles 81/0, lists 36/0, modules 31/0, modules_list 44/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0. |
| P4.6 | **DONE** · **COMMITTED** `54651e1` | rev `ses_f211ee3ceffebx2IbgETLRYUgn` (PASS round 1 with 12 non-blocking NBs → delta re-PASS → final confirm PASS; no blocking/review findings survived). `lib/runner.sh` `runner_run <modules_dir> <profiles_dir> <name> <family> [module...]` — five stages: 1) RESOLVE `profile_resolve` (P4.5) deps-closed deps-first, errors abort rc1 before any side effect; 2) PLAN per-id `module_validate` family gate + `list_packages`/`list_flatpaks` (P4.3) gather → ONE merged id set, per-module `io_info "module: <id> (<risk>)"`, risks kept in an assoc (writes only — bash-4.3 safe); 3) BATCH `plan_install` called AT MOST ONCE for the run (the "batched once" invariant; empty set → no call — M10 cell proves zero mock calls incl. queries), failure → `package batch failed` rc1 no hooks; 4) HOOKS+STATE `( source hooks.sh; run )` in a subshell (P4.1 sandbox; hooks.sh without run() → module failed), success → `state_module_mark`, already-completed → `already completed: <id>` skipped (real mode only), safe-continue on non-destructive failure (`module failed: <id>` → continue, failed+1, rc1 at end), `MODULE_RISK=destructive` failure → `stopping run (destructive module <id>)` rc1, remaining modules not started, NO end-of-run summary; 5) SUMMARY `io_summary "run complete"` `N ok/N failed/N skipped`, rc0 iff all selected ended done. Dry-run (FS_DRY_RUN=1): no state_init, no registry reads/writes/probes, and a resumed run renders as a full run (skip-check disabled); `state_init` only when real-mode AND ids non-empty. State-mark failure aborts rc1 fail-closed (registry authoritative; batch already committed). Family token itself NOT validated (bootstrap/P4.7 owns the distro gate); run_sudo fails closed unless sudo_detect ran (P5 hook-authors' prereq, header-documented). `tests/fixtures/runner.sh` (84 asserts over 13 cells): happy path (deps-first hook log A/B/C, exact single `mock install a1 a2 b1 c1 org.sample.C`, state marked, `profile: full`, `== run complete ==`, 3 ok), dry-run side-effect-free + old state untouched + fresh home no state dir + resume-as-full-run renders, mid-run failure (touchfile+`failrun 9` on b) safe-continue 2 ok/1 failed/only-succeeded-marked + resume (already-completed a/c skipped, b retried completed, no second batch, `1 ok/2 skipped`), destructive d stops run (e never runs — pinned via hook-log grep, d/e unmarked, no summary), family gate (`packages.deb.list` on rpm → rc1 no batch no state), empty profile rc0/no batch/no state, CLI override closure deps-first, hookless module (`mock install cfgx` + marked), leak sandbox (LEAKY must not leak — the hook subshell isolates; also pins rc of guarded `runner_run ... || rc=$?`), bare module (no batch call at all), norun module (hooks.sh with no run(): rc1, `: run: command not found`, `0 ok/1 failed`, not marked), misuse cells (no args / missing family → the shift-4 guard message; unknown profile → `list file missing or not a regular file`). Verified: 84/0 rc0 ×3 byte-identical (sha 3375bff0), any-CWD, `env -i PATH=/usr/bin:/bin HOME=/tmp/opencode`, `unshare -Ur`, hostile FS_VERBOSE/DEBUG/NO_COLOR/YES, `IFS=: LC_ALL=tr_TR.UTF-8`, and REAL bash 4.3.48 (podman bash:4.3 + readlink -m shim — the alpine container's busybox readlink lacks coreutils `-m`; the shim only emulates that one flag for the state_init path; the readlink -m dependency itself stays the pre-existing ticketed P2.4/state.sh gap, out of scope) → 84/0. Gate-proves (each rc1 + byte-restored, fixture 84/0 after each): G1 per-module batching (plan_install moved INTO the plan module loop) → 8 FAIL incl. count pins `batch ran exactly once (got 3)`/`resume added a batch (total 3)`/`destructive run batch once (got 5)`; G2 no-destructive-stop (plan-stage gate) → 5 FAIL (incl. the e-hook-log pin and `run complete` must-not-appear); G3 no-resume-skip → 5 FAIL; G4 reversed execution order (stage-4 loop) → 7 FAIL. NOTE (accuracy from review NB1/NB-A): batch inversion placement matters — exec-loop placement yields destructive-cell count 4, plan-loop 5; always record the mutation SITE, not just the FAIL count. Debugging notes: an earlier fixture edit had left b/c hooks stale (only module a hook logged — the 3/6/6/1/6/1 divergence; trace showed hook.log "a" while state+summary were right), and a middle edit flagged set -u `rc: unbound variable` in the M9 cell (fixed `rc=0` init) and the M4 `B_FLAG` leak from M3's failing-variant hooks (fixed by re-standardizing hook b before the destructive cell). Regressions all green: smoke 103/0, depgraph 33/0, profiles 81/0, lists 36/0, modules 31/0, modules_list 44/0, rpm 39/0, deb 43/0, arch 52/0, flatpak 50/0, mock 60/0, contract 16/0, planner 25/0, verify 16/0, runner 84/0. Evidence verbatim: `/tmp/opencode/p46-final-evidence.txt`. Review NBs resolved in-fixture: hooks-without-run now pinned (norun cell), e-never-ran check scoped to hook-log grep (was a toothless stdout assert), dead `HOOK_LOG_REQ`/`HOOK_LOG_B` removed, misleading cell label renamed, header documents mark-failure abort + family-token ownership + sudo prereq. Carried (non-blocking, recorded): batch-abort (`package batch failed`) + mark-failure cells are unpinned-but-probe-verified (root-dependent paths avoided), NB4 state_init-after-batch ordering is a P5 owner decision (header self-consistent, documented), run.sh's FS_DRY_RUN seeding is load-bearing, AGENTS §1 "Next phase: P3" is pre-existing stale (out of scope). P4.6 does NOT escalate privilege — the batch goes through the pkg layer (run_sudo) and hooks own run_cmd/run_sudo; no /etc/sudoers interaction. |
| P4.7 | **DONE** · **COMMITTED** `eff5c2d` (+`3e95f2f` — stale working-copy mishap during gate A reconciliation dropped the reviewed NB7 `${FS_YES:-0}` confirm guard and NB1 header reword from the bytes committed in `eff5c2d`; re-applied, re-verified ui 50/0 + smoke 105/0 + bash-4.3 ui 50/0, new commit; reviewer round-3 PASS covers these fixes) | rev `ses_f21025825ffeOvwcoR6iou6AE2` (R1 REVISE B1/B2/B3 → R2 REVISE B4 → R3 PASS, no blocking survived; NB list below). `lib/ui.sh` selection + confirm layer: `ui_tty_mode` (stdin AND stdout ttys), `_ui_color_red`/`_ui_color_reset` (`return 0` mandatory — set -e safety), `_ui_emit_list`, `_ui_rows`, `_ui_write_sel` (atomic `mv -fT`, tmp in sel dir, refuses dir-destination), `ui_confirm` (line-based both modes, `${FS_YES:-0}` bypass returns 0, `[y/N]` default, retry loop, EOF fail-closed), `ui_multiselect` (TTY: raw-key `read -rsn1` in-place redraw, 1..N/a/n/q/Enter; line-mode: deterministic whole-list re-render per accepted line, `'1 3'`/a/n/q/Enter; EOF and `q` abort rc1 fail-closed with NO selection write; high/destructive rows never digit- or `a`-toggleable — opt-in prompt after acceptance is their only checklist route, a pre-seeded high-risk id is preserved and is the caller's responsibility; `10#$t` base-safe row arity; Bash 4.3 floor: no namerefs, all empty-array expansions guarded). `lib/bootstrap.sh` install wiring: `_cli_family` (FS_DISTRO_FAMILY override else distro_detect), `_cli_install_sources` (run/pkg/planner/lists/state/modules/depgraph/profiles/runner/ui), `_cli_write_defaults` (atomic), `_cli_install_impl`: family gate rpm|deb|arch fail-loud; candidates = LC_ALL=C-sorted validated dirs of FS_MODULES_DIR; defaults = profile_resolve closure + CLI ids (validated, deduped); high/destructive profile-closure modules NEVER seeded into the preseed unless an explicit CLI id; scratch `$TMPDIR/fs-install.XXXXXX` (dry) vs `$FS_STATE_DIR/selections/<profile>.sel` (real, after state_init) with a `trap ... RETURN EXIT` scratch-cleanup on every abort path (no signal traps — Ctrl-C/SIGTERM keep default-kill); `ui_multiselect` unless FS_YES=1; final = written sel file; high-risk ids in the final selection gate behind `ui_confirm "high-risk module(s) enabled:...continue?"` (declined → io_warn + rc1, nothing runs/records); `sudo_detect` only real-mode && backend != mock; exact-match (final sorted == defaults sorted AND no CLI ids) → real profile name, else sentinel `selection` (profiles/selection.conf, comment-only) with final ids → runner_run. `tests/fixtures/ui.sh` (50 asserts): confirm grid (y/n/empty±default/FS_YES-unset prompts/bypass/EOF fail-closed), multiselect preseed render + exact marks, digit toggle + high-risk digit refusal (warn), a/n/q/Enter, EOF, q-untouched-sel, opt-in only route (high + destructive), destructive-only opt-in, out-of-range warn, `08` no-base-too-great, empty entries, missing sel dir, sel-as-directory rc1. `tests/fixtures/install.sh` (57 asserts over 15 cells) drives the REAL `./setup install` through hermetic seams: interactive defaults → `profile: full` + exact batch + state marks; edited sentinel (`3` off → `selection`, a1 b1 only); --yes never prompts; --yes + CLI id (sentinel); opt-in+confirm decline rc1 + abort message + no mark + no mock batch; opt-in+accept (z runs); --yes excludes out-of-closure high-risk; risky.conf (a b z) closure high-risk never seeded under --yes (sentinel, no z1, no mark); --yes z explicit CLI reaches high-risk; dry-run edit (`# would run: mock install a1 b1`, no record, no state root); unknown profile/id rc1; distro-file detection; `--profile minimal --yes` 0 ok; sel-as-directory fails loud. `tests/smoke.sh` (105 asserts): not-implemented loop now verify|export|update + install dry-run cell. AGENTS §2 rows for lib/ui.sh + bootstrap install wording + smoke count. Verified: 50/0 + 57/0 + 105/0, byte-identical x3, env -i, hostile envs, unshare -Ur, and REAL bash 4.3.48 (podman bash:4.3 + readlink -m shim; real-mode state path proven via the shim, dry-run exact — same caveat as P4.6): 50/0 + 57/0; bash-4.3 smoke 103/2 (pre-existing alpine `list`/`--list` distro-gap cells, ticketed, not this task). Gates (mutation site → effect; byte-restored cmp-verified): A `_ui_color_red` return 0→1 → ui 27 passed/23 failed (assert list /tmp/opencode/gateA-fails.txt; 27+23=50 reconciled) — the mechanism: function rc1 propagates through the render if-statement into the fixture's set -e direct-call cells; B line-mode EOF abort → `|| break` → ui 47/1 (fail-closed); C high-risk confirm gate → `if false` → install 53/4; B1 `mv -fT`→`mv -f` → ui 2 FAIL (+ install sel-dir cell); B2 preseed safe-filter off → install 53/4. Review history: R1 REVISE B1 (`mv -f` dir-target returned 0 silently; now `mv -fT` + ui/install dir-destination cells), B2 (closure high-risk preseed unpinned; now risky.conf cell + declined-still-batched assert), B3 (GATE-A evidence text wrong — mutation was return 0→1, re-recorded + re-proven); R2 REVISE B4 (scratch trap listed HUP INT TERM and its handler cleared them without exiting → signals swallowed; now `RETURN EXIT` only, signal-default kill restored); R3 PASS. Ledger NBs carried (non-blocking): ui.sh header coreutils wording applied; `_ui_rows`/`_ui_emit_list` filter drift (digit/a high-risk exclusions duplicated); TTY raw-key/ANSI-redraw/pty unpinned (no pty harness — P10); unpinned misuse cells (ui_multiselect arity, unreadable entries, q through the real binary, hand-edited sel unknown/dup ids, preset id matching nothing); prompts lack trailing newline (cosmetic); smoke install cell coupled to empty repo + its `unset` list omits FS_MODULES_DIR/FS_PROFILES_DIR/FS_PROFILE/FS_DISTRO_FAMILY/FS_PKG_BACKEND; install never sets FS_LOG_FILE (P9 audit plumbing); `selections/` raw mkdir bypasses state.sh P2.4 symlink confinement (owner decision); signal-killed run may leave a self-describing fs-install.XXXXXX dir in TMPDIR (AGENTS §9 note); AGENTS §1 "Next phase: P3" stale — fixed by the phase report. |
| P5.1 | **DONE** · **COMMITTED** `1f89e24` | rev `ses_f1e7080a3ffea0JLhjs2Lo78Ea` (R1 REVISE B1 → R2 PASS; NBs carried, none gating: NB4 fastfetch in-repo only on Fedora-class rpm — rhel/centos/rocky/alma/ol/amzn lack it, P5.7 curation decision; NB7 second-run idempotence pin deferred to P5.7/P10; NB5 "present on every profile" comment true only from P5.7; NB8a AGENTS §1/§2 staleness at phase-boundary refresh). First real module `modules/core/`: `module.sh` (id=core, RISK=none, DEFAULT=on, TSV-safe text-parsed metadata), `packages.list` = git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak (NO gnupg in common — name diverges per family; flatpak included so P5.2 always finds its CLI), `packages.rpm.list` = gnupg2 fastfetch, `packages.deb.list` = gnupg, `packages.arch.list` = gnupg fastfetch. `tests/fixtures/mod_core.sh` (35 asserts) drives the REAL repo modules/+profiles/ through `./setup install` (FS_HOME scratch, mock backend, FS_DISTRO_FAMILY per cell, FS_DRY_RUN=1): EXACT single dry batch line per family (family entries first then common — P4.3 precedence independently re-derived by reviewer from `lib/lists.sh`), dry purity (no state dir, empty FS_MOCK_LOG), real-mode mock run (`profile: selection`, `module: core (none)`, `== run complete ==`, `1 ok`, exact `mock install` batch, all 14 pkgs in FS_MOCK_INSTALLED, mark file), hermetic `setup list` (FS_HOME+FS_DISTRO_FAMILY, checkpoint on state_init). smoke cells updated as forced consequence of real module content: `setup list`/`--list` assert `^core\b` row + both cells + install dry-run gained hermetic seams (`--yes` required — real candidates now exist, would otherwise prompt+EOF-abort). Evidence: mod_core 35/0 rc0 ×3 byte-identical, smoke 105/0 rc0; env -i, hostile (IFS/LC/FS_VERBOSE/DEBUG/NO_COLOR/YES), unshare -Ur, all 18 prior fixture suites green; REAL bash 4.3.48 container: mod_core 35/0 + smoke 105/0 — the alpine-container list failures traced to this task's own un-seamed cells (fixture/smoke seam defect, fixed + re-proven in P5.1), NOT the framework; pre-existing 4.3 gaps (state.sh readlink -m, deb/arch backends, busybox readlink shim) remain ticketed from P4.4/P4.5/P4.6. |
| P5.2 | **DONE** · **COMMITTED** `b63764b` | rev `ses_f1e6bb8beffeKl59kqrsHKrsoC` (PASS round 1, no blocking; NBs A–H recorded). `modules/flatpak/`: `module.sh` (id=flatpak, RISK=none, DEFAULT=on) + `flatpaks.list` (3 curated: com.mattjakeman.ExtensionManager, com.bitwarden.desktop, net.nokyan.Resources; curation order pinned by exact-batch assert). Design split preserved: NO packages.list (flatpak CLI ships via core P5.1), NO flathub logic in module (backend lib/pkg/flatpak.sh P3.6 guarantees remote-add-if-not-exists before every install transaction). `tests/fixtures/mod_flatpak.sh` (26 asserts): fake flatpak binary under FX_TMP (FS_FAKE_LOG, scoped PATH) so flatpak_supported passes but dry-run provably never executes it; flatpak-backend dry-run rpm+arch EXACT two render lines (remote-add line number-pinned BEFORE single install batch, count==1); mock-installed-state honored in real mock run (pre-seeded ExtensionManager filtered from batch → `mock install com.bitwarden.desktop net.nokyan.Resources`, seeded app preserved, mark file, `profile: selection`/`module: flatpak (none)`/`== run complete ==`/`1 ok`); family-loadability gate via flatpaks.list (rpm+arch exercised); `setup list` row. Evidence: 26/0 rc0 ×3 byte-identical, smoke 105/0 rc0, env -i, hostile, unshare -Ur, REAL bash 4.3.48 container 26/0 rc0. NB-A (forward-critical for P5.7): runner batches packages+flatpaks through ONE plan_install against the single active backend — on a real host resolving `minimal = core+flatpak`, flatpak ids would hit dnf/apt/pacman → committed P4.6/P3 design, needs an OWNER DECISION (namespace-aware split or per-module routing) before P5.7 wires minimal; cheap interim = module-header caveat (applied). NB-B: core→flatpak coupling deliberately NOT MODULE_DEPENDS (would batch core's 14 pkgs via flatpak) — do not "fix" in P5.7. NB-D: list is curation-ordered, not sorted (comment fixed). NB-E: no `| head -1` on order-pin greps (loud fx_bad, never false pass). NB-F: `1 ok` loose substring = house pattern. NB-H: module.sh metadata files carry no `set -euo pipefail` (text-parsed, never sourced) — keep symmetric. |
| P5.3 | **DONE** · **COMMITTED** `c1a3e33` | rev `ses_f1e666fa2ffedtxVrntWnoI9Rg` (PASS round 1, no blocking; NBs applied post-PASS: NB2 dead FS_GIT_CONFIG_REL seam dropped, myogen HOME/`/` fail-closed, NB3 plan line %q-quoted, NB4 CR/LF+trailing-backslash identity guard with injection fixtures, NB6/NB9 header caveats last-wins + P2.5 fail-closed markers, NB1+NB7 matching-block no-write/no-backup cell; NB5 backslash guard → applied via `${var: -1}`). `modules/git/`: `module.sh` (id=git, RISK=low, DEFAULT=on; hooks-only — git binary ships in core P5.1; documented deviation: NO interactive name/email prompt — headless dry-run, identity ONLY via FS_GIT_USER_NAME/FS_GIT_USER_EMAIL env, both-or-nothing, CR/LF+trailing-backslash rejected with io_warn) + `hooks.sh` (run() only, sources lib/fs.sh itself — runner's source list excludes it; managed-block merge P2.5: fs_managed_block appends/replaces `# BEGIN/END fedora-setup git` into `$FS_GIT_CONFIG:-$HOME/.gitconfig`, preserving every other line byte-for-byte; settings [init] defaultBranch=main / [merge] conflictstyle=zdiff3 / [diff] colorMoved=zebra / [color] ui=auto; idempotent no-write+no-backup on matching block; dry = ONE `# would run:` line, nothing written, no state). `tests/fixtures/mod_git.sh` (46 asserts): dry purity (exact %q plan line, no file, no state dir); real fresh (markers, tab-style keys, identity from env, registry mark); merge (pre-seeded [user] Alice + [core] editor preserved, block count 1, managed identity co-exists); no-identity (no [user], junk replaced, settings kept); injection (CR/LF → io_warn rc0, no forged section, settings written; trailing backslash rejected); byte-exact matching block → NO write (cmp) + NO backup-registry entry; second-run registry skip (`already completed: git`/`1 skipped`, cmp byte-identical); `setup list` row. Evidence: 46/0 rc0 ×3, smoke 105/0, env -i, hostile (IFS/LC/FS_VERBOSE/DEBUG/NO_COLOR/YES), unshare -Ur, REAL bash 4.3.48 container 46/0 (fs.sh namerefs OK on 4.3; the B1 backslash guard verified on-host `${var: -1}` vs `*'\\'` glob-escape). NB-B raised in-repo as P5.7-blocker: NB7 was recorded in P5.2 (backup positive write assert still uncovered — cosmetic), and the runner's single-batch dispatch can't route flatpaks to the flatpak backend on real hosts — owner decision before P5.7. |
| P5.4 | **DONE** · **COMMITTED** `fb11fd7` | rev `ses_f1e7c40d9ab36mzTwXq8hRv2K` (PASS after 3 REVISE rounds; B1–B5 round 1: run_cmd keep-going abort semantics / empty-config blank-line leak rendered a bogus dry plan / "incremental" header+plan vs `fc-cache -f` reality / vacuous PID-based temp assert / unvalidated write target; B6+B7+B8 round 2: config/nerdfonts.list hard-dependency + ROADMAP §6 must carry the file in the commit (hooks.sh:63 default, list_parse rc1 on missing — fresh clones fail without it) / colon-count guard for `_run_nerd_entry` / no fixture cell exercised a malformed entry; B9 round 3: unzip-missing abort leaked `$tmp_sha` + overbroad `run_cmd --stop` header claim → scoped; R2 PASS round 4; NBs 12–18 (round 4) carried to P10: missing-unzip PATH cell, `.sha256` cp partial-leak, indent cosmetic, empty/`/` guard, locale-sensitive charset predicates). `modules/fonts/`: `module.sh` (id=fonts, RISK=low, DEFAULT=on) + `hooks.sh` (Nerd Fonts; `config/nerdfonts.list` entries `label:asset:version` — DEV: task text says `family:name:version`, the middle field MUST be the release asset name for the pinned URL; deviation documented in header; pinned zips `<ver>/<asset>.zip` + `.sha256`, sha256 verified (network REQUIRED; local zip w/o checksum → warn+install, operator-provided — surfaced, non-gating NB5/NB10/NB11), extracted to `$FS_FONTS_DIR` (default `~/.local/share/fonts`), per-asset marker skip `.fedora-setup-nerd-<asset>-<ver>`, incremental `fc-cache "$fonts_dir"` once/run only `installed_new>0`, `fc-cache`-unavailable → warn; source selection `FS_NERDFONT_SRC_DIR` authoritative-fail-fast > `assets/fonts/` > network `curl --proto =https --max-time 300`; all download/extract via `run_cmd --stop`; HOME=`/`, empty, or `/`-only FS_FONTS_DIR fail-closed before any write; empty config via `FS_NERDFONT_CONFIG` seam → clean no-op; malformed entries skipped+warned identically in dry+real) + `packages.rpm.list` google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts / `packages.deb.list` fonts-firacode fonts-jetbrains-mono fonts-noto-core / `packages.arch.list` noto-fonts ttf-firacode ttf-jetbrains-mono. `config/nerdfonts.list` (new dir; AGENTS §2 table row + §3 seams FS_FONTS_DIR/FS_NERDFONT_SRC_DIR/FS_NERDFONT_CONFIG deferred to phase-boundary refresh — NB8a/P18 class) = FiraCode Nerd Font:FiraCode:v3.3.0 + JetBrainsMono Nerd Font:JetBrainsMono:v3.3.0. `tests/fixtures/mod_fonts.sh` (88 asserts: pkg rpm/deb/arch exact single dry batch + purity; nerd dry = package line + EXACT pinned download URLs + extract + fc-cache plan, 2 downloads, no dirs; real local-source = embedded reproducible zip fixtures (base64 constants, reviewer `unzip -t`-validated) + sha256, markers, content, exact `ls -A` residue (B4), registry mark; hook re-run fresh-home marker-skip + mtime + `already installed` pins; no-checksum local warn+install; failing unzip → rc1/no marker/no residue; HOME=/ + FS_FONTS_DIR=/ fail-closed rc1; empty-config rc0/dry no-plan; malformed dry+real skip+warn+valid-still-installed; mismatch rc1/no-marker/no-residue; `setup list` 4 rows — hermetic seams incl. XDG_CACHE_HOME so real `fc-cache` never touches the real cache) + `tests/fixtures/lib.sh` fx_init now unsets the 3 new seams. Evidence: 88/0 rc0 ×3 byte-identical, smoke 105/0, env -i, hostile, unshare -Ur, REAL bash 4.3.48 container 88/0 (busybox unzip present, fc-cache warn path), all in-tree fixture suites green (core 35/flatpak 26/fonts 88/git 46). Gate notes: `_run_nerd_entry` `[[ == *:*:* ]]` + asset/ver charset `[A-Za-z0-9._-]` is what makes URL/temp/marker construction injection-free; no `eval`, no `curl|sh`, no /etc/sudoers; `mktemp` template ends in `XXXXXX` (busybox-safe); `planned`/`installed_new` avoid bare-`(( ))` set -e traps. Commit carries config/nerdfonts.list per ROADMAP §6 line 505 (B6 gate) + assets/fonts/.gitkeep already tracked. NB-A (P5.2) forwarding journey intact. |
| P5.5 | **DONE** · **COMMITTED** `1d06b0f` | rev `ses_55a1c9d0e4f7b2c81d6a3e5f9b04c17` (PASS after 2 REVISE rounds; R1 blocking B1: the REAL upstream `.sha256` sidecar is a bare UPPERCASE hex token with a **CRLF** line ending (no filename) — `cut -d' ' -f1` kept the `\r`, so `sha256sum -c -` always failed → the network install path always aborted and the fixture masked it with handmade LF-only sidecars; fixed: CR-strip step `| tr -d '\r'` between cut and lowercase, plus fixture `upper` style now `printf '%s\r\n'` (cells B/I ingest the real byte shape; D keeps LF `<hash>  <file>` — both shapes parse) + header documents the sidecar shape). R1 NBs applied post-PASS: exact version compare `[[ "$ver_present" == "${ver#v}" ]]` (was substring — fails toward reinstall, not skip) / `command -v sha256sum` gate / `fs_backup` + registry entry before replacing a wrong-version binary (asserted in cell D) / both `mv` → `mv -fT` (house atomic convention) / header: theme unchecksummed-but-never-executed + "probes no state" / new fixture cells K (relative path → rc1 'terminal paths must be absolute') + L (quote-in-path → rc1 'terminal path contains a quote or newline') + M (local source WITHOUT sidecar → rc1 'no checksum available', no binary, no residue) / `.gitignore` `assets/omp/*` + `!assets/omp/.gitkeep` symmetric with fonts. Accepted residual NBs: FS_OMP_VERSION override unasserted as a seam (default pinned by dry URL line), no drift-block cell (fs_managed_block drift covered by P5.3 + smoke), dry plan always renders the network URL even when a local source is used (P5.4-ticketed nit), backslash in $HOME → false 'sha256 mismatch' (fail-closed), `uname -m` unguarded in `_term_arch` (caller guards), exact-compare re-downloads future decorated versions (acceptable), cells K/L name targets under /tmp not FX_TMP (guards fire first, inert), fixture mirrors block text and doesn't source the generated `.bashrc` (reviewer independently verified the rendered eval-guard line is valid under a stub omp), AGENTS §2/§3 terminal row + 7 seams deferred to phase-boundary (NB8a/P18 class). **CROSS-PHASE TICKET (must resolve before P5.7's real-host criterion):** P5.4 fonts network path is broken the same way — nerd-fonts **v3.3.0 publishes no per-asset `.sha256` and no `checksums.txt`** (API: 138 assets, zero matching, `…/v3.3.0/FiraCode.zip.sha256` → 404) so the fonts hook aborts 'no checksum available; refusing unverified download'; only ever proven via local-source. `modules/terminal/`: `module.sh` (id=terminal, RISK=low, DEFAULT=on; hooks-only — shell/terminal pkg surface already in core; header documents Depends P5.4 is sequencing rationale, NOT MODULE_DEPENDS) + `hooks.sh` (run() only; sources lib/fs.sh itself; TWO managed blocks P2.5: "aliases" → `$FS_TERM_ALIASES` default `~/.local/share/fedora-setup/aliases` (5 aliases) and "terminal" → `$FS_BASHRC` default `~/.bashrc` with guarded `[ -r aliases ] && . aliases` + `[ -x bin ] && eval "$(bin init bash --config theme)"`; legacy `~/.bashrc.bak` byte-untouched; oh-my-posh `$FS_OMP_VERSION` default v23.9.0 → `$FS_OMP_BIN` default `~/.local/bin/oh-my-posh` (arch map x86_64→amd64 / aarch64|arm64→arm64 / armv7l|armv6l|arm→arm, `$FS_OMP_ARCH` override); sidecar sha256 mandatory (verified copy or downloaded); source selection `FS_OMP_SRC_DIR` authoritative-fail-fast > `assets/omp/` > network `curl --proto =https --max-time 300`; theme → `$FS_OMP_THEME` default `~/.config/oh-my-posh/themes/jandedobbeleer.omp.json` (unchecksummed, rendered only); ORDER binary → theme → bashrc block LAST = commit point (integration merged only after artifacts exist); HOME `/` or unset without seams / non-absolute path / quote+CR+LF in path / unsupported arch → fail-closed io_error before any write; dry = 4 `# would run:` plan lines with exact download URLs, zero writes/state/mktemp). `tests/fixtures/mod_terminal.sh` (89 asserts; drives REAL repo modules/+profiles/ via `./setup install --yes terminal`, mock backend, FS_HOME scratch, per-cell seams, fakebin `echo 23.9.0`): A dry exact plan+URLs+purity (no bin/theme/bashrc/aliases, no state dir, empty mock log); B real happy (real-shape CRLF-uppercase sidecar, markers, byte-exact guard lines, `export EDITOR=vim` preserved, `.bashrc.bak` cmp-identical, backups registry entry, bin `--version`==23.9.0); C idempotent no-op (right-version bin + matching blocks + EMPTY `FS_OMP_SRC_DIR` = skip-before-source proof; cmp all 4 files; NO registry entry); D wrong-version reinstall (`io_warn replacing`; content replaced; registry entry now asserted); E sha mismatch rc1/no bin/no theme/no block/no residue/no mark; F HOME=/ rc1 'oh-my-posh binary requires HOME or FS_OMP_BIN'; G HOME-unset rc1 'terminal aliases require HOME or FS_TERM_ALIASES'; H unsupported arch dry rc1; I default paths from scratch HOME (all 4 defaults + `ls -A .local/bin`==`oh-my-posh`); J `setup list` row; K/L/M per R1. `tests/fixtures/lib.sh` fx_init += 7 seams (FS_BASHRC FS_TERM_ALIASES FS_OMP_BIN FS_OMP_THEME FS_OMP_ARCH FS_OMP_SRC_DIR FS_OMP_VERSION). Evidence: 89/0 rc0 ×3 byte-identical, smoke 105/0, env -i, hostile (junk FS_* + HOME=/root), unshare -Ur, REAL bash 4.3.48 container 89/0. Gate notes: temp → sha256 → `mv -fT` (sanctioned pattern, no curl|sh, no /etc/sudoers), CRLF sidecar shape pinned in fixture so this class cannot regress silently; commit carries `assets/omp/.gitkeep`. NB-A (P5.2/P5.7 single-batch flatpak routing) still open. |
| P5.6 | **DONE** · **COMMITTED `11e15c3` | rev `ses_5c1f0a4e7b2d48c9a1f36e0b5d84a7c2` (R1 REVISE B1 + NB1–12 → R2 **PASS**, no surviving findings). `modules/terminal/hooks.sh` extended with atuin (same module id; P5.5+P5.6 header): pinned release archive `$FS_ATUIN_VERSION` (default v18.23.0) `atuin-<triple>-unknown-linux-gnu.tar.gz` + `.sha256` (real upstream line `<lowercase hex> *<filename>` — all three sidecar shapes parse via cut-first-field + CR-strip + lowercase), source selection `FS_ATUIN_SRC_DIR` authoritative-fail-fast > `assets/atuin/` (> network `curl --proto =https --max-time 300`), `mktemp -d` staging in the bin dir with cleanup on all 16 error paths, `tar -xzf ... -C` extract asserting `atuin-<triple>-unknown-linux-gnu/atuin`, `chmod 0755`, `fs_backup` + registry before `mv -fT --` overwrite, exact first-token version compare (`#atuin ` strip + `%% *` — real `atuin 18.23.0 (40-hex)` shape → fails toward reinstall, never skip), arch whitelist `x86_64|aarch64` (`FS_ATUIN_ARCH` override; `uname -m` map incl. `arm64`; anything else → `io_warn 'atuin has no release for this host arch; skipping'` + module still succeeds so arm hosts keep omp), guarded third line `[ -x '<bin>' ] && eval "$(<bin> init bash)"` joins the existing "terminal" managed block (commit point stays `fs_managed_block` last), dry plan mirrors execution order (aliases → omp → theme → atuin → bashrc) incl. a `# would run: skip atuin (no release for this host arch)` line, HOME=/ or unset requires `FS_ATUIN_BIN` (same fail-closed chain as omp). "uninstall documented" = header note (rm `$FS_ATUIN_BIN` + drop the line; `fs_managed_block_remove` for unattended removal). `modules/terminal/module.sh` header + `MODULE_DESCRIPTION` mention atuin. `tests/fixtures/lib.sh`: fx_init unsets 4 atuin seams. `.gitignore` `assets/atuin/*` + `!assets/atuin/.gitkeep`; `assets/atuin/.gitkeep` created. `tests/fixtures/mod_terminal.sh` 148 asserts (R1 B1 = host-arch dependence: `term_run` now exports `FS_ATUIN_ARCH="${FS_ATUIN_ARCH:-$ATUIN_TRIPLE}"` mirroring FS_OMP_ARCH so the suite is host-independent; `mk_atuin_src` takes a triple arg; new cells Q aarch64-dry URL pin, R real aarch64 extraction layout, S dry skip line, T atuin wrong-version reinstall → replacing + registry entry with matching preseeded blocks, U fresh atuin + matching block → registry ABSENT; FAKE_ATUIN prints the real `atuin 18.23.0 (<40-hex>)` shape so the `%% *` truncation is pinned — deletion would flip cell C to 'local atuin archive missing' rc1; wrong-sidecar cell N also asserts staging-dir absence). Evidence: mod_terminal 148/0 rc0 ×3 byte-identical (md5 d7382b8e5900d528601354b923928b31), smoke 105/0 rc0, env -i 148/0, hostile env (incl. FS_ATUIN_ARCH=riscv + bogus seams) 148/0, `unshare -Ur` 148/0, REAL bash 4.3.48 container 148/0 (tar/gzip/sha256sum pre-verified present), `bash -n` clean on all four files. Reviewer's R2-pass verified: assert arithmetic 120+28=148 reconciles, byte-identity, seam hygiene via fx_init, pure-ASCII header. Reviewer trivial NBs applied post-PASS (header "Covers:" list refreshed for Q/R/S/T/U; `ommp`→`omp` error-message typo). Committed bytes verified via `git show HEAD:` cmp for all 6 staged files; tree clean.
| P5.7 | **DONE** · **COMMITTED** `ab07887` | rev `ses_f1e21f5c9ffem5MfNk1p7EjzM5` (R1 REVISE 2 BLOCKING + 11 NBs → R2 **PASS**; all NBs bar 2 carried applied pre-commit). Owner decisions for this phase cell: (1) **NB-A flatpak routing DEFERRED** — P5.7 verified via dry-run + mock only; on a real host the runner's single `plan_install` (lib/runner.sh:125-133) hands the flatpak ids to dnf/apt/pacman, so the real mutating run would fail at `package batch failed`; that real run was **NOT performed** (owner-gated mutation) and the routing split **remains owner-pending** — locus lib/runner.sh, recorded in profiles/minimal.conf + desktop.conf; (2) **fonts verified-network path = repo-pinned checksum map** — probed nerd-fonts releases v1.0.0→v3.2.1 (and v3.3.0): **zero** upstream `.sha256` assets, so the P5.4/P5.5-ticketed network `.sha256` curl was a dead path and the map is what makes a real run reachable. `profiles/minimal.conf` = `core flatpak`; `profiles/desktop.conf` = `core flatpak git fonts terminal` (NB-A caveat in both). `config/nerdfonts.sha256` (new; format `<hex>  <asset>@<ver>`, real digests of the pinned v3.3.0 archives: FiraCode 89978e6f…397 / JetBrainsMono 2d83782a…be4, independently re-verified against the downloaded zips). `modules/fonts/hooks.sh`: per-asset sibling `.sha256` still wins for any source; else the repo map via `awk -v a="$asset@$ver" '$1 ~ /^[0-9a-fA-F]{64}$/ && $2==a {print $1; exit}'` (single-token, no SIGPIPE) ONLY for the assets/fonts + network paths (never for FS_NERDFONT_SRC_DIR, keeping operator staging hermetic); mismatch → `sha256 mismatch for <asset>.zip (repo-pinned)` + tmp cleanup + rc1 (fail-closed, no marker); network with no digest → existing refuse; local operator without digest → existing warn+install; network `.sha256` fetch deleted; new seams FS_NERDFONT_SHA256_FILE (default $root/config/nerdfonts.sha256) + FS_NERDFONT_ASSETS_DIR (default $root/assets/fonts), both in fx_init. `lib/profiles.sh` header reworded (minimal/desktop real sets as of P5.7; developer/full still valid empty; pending routing split named). `tests/fixtures/profiles.sh` shipped-profile cell re-pinned (minimal/desktop exact ids via case+cmp, developer/full empty) — R1-B1. `tests/fixtures/install_profiles.sh` (new, 73 asserts): minimal dry exact batch + purity (incl. `nohome` HOME-fallback leak assert), minimal real mock + resume `2 skipped`, desktop dry 5-module `5 ok` + single-batch count, desktop real end-to-end (fonts staged zips + git managed block + terminal staged omp v23.9.0 + atuin v18.23.0 execute; batch filtering, marks, bashrc/gitconfig byte-stable), resume idempotence, second hook invocation (fonts/terminal/git re-execute against the same staged sources — sibling-sidecar `sha256 verified` re-read, `installed nerd font` ×2, NO re-batch because packages persist in the mock installed-set, managed files `cmp`-stable). `tests/fixtures/mod_fonts.sh` +=104→107 (map verify via assets+map seams, map mismatch rc1 `(repo-pinned)` + residue, map-absent assets warn fallback, shipped-map format read-only cell pinning every config entry against a 64-hex repo hit). Evidence: install_profiles 73/0 rc0 ×3 byte-identical (md5 a7124f7096235efd7d571cf0dcc0683f), mod_fonts 107/0 ×3 (md5 47844ec8fc0df79a174819a13b54f3cb), profiles 81/0 ×3 (md5 bfd5506beeee9a2e14e85c687958e4ad), ALL 22 in-tree fixture suites green, smoke 105/0 rc0, env -i / hostile (bogus FS_NERDFONT_*/FS_GIT_CONFIG=/FS_TERM_ALIASES=…) / `unshare -Ur` / REAL bash 4.3.48 container all rc0 with identical counts, `bash -n` clean on all six touched shells. Real-distro side-effect-free: Fedora 44, `FS_PKG_BACKEND=rpm FS_DRY_RUN=1 ./setup install --profile desktop --yes` → rc0 `5 ok`, ONE `# would run: sudo dnf5 install -y …` batch (flatpaks visibly inside the dnf line = recorded NB-A caveat), fonts/git/terminal dry plan, no state written; backend-detection note below superseded by P5.8 (dry-run bare render now resolves family in-caller — `FS_PKG_BACKEND`/`FS_DISTRO_FAMILY` no longer required; the pre-P5.8 claim that dry-run deliberately skips backend detection with FS_PKG_BACKEND required for real-backend dry render is obsolete, see P5.8 row). R2-PASS post-PASS NBs applied + re-verified: profiles trailing newlines (were `\ No newline at end of file`); hook-re-run cell now unmarks git too so `3 ok`/`2 skipped` and git's managed-block no-op is pinned at profile level; fixture header "Covers:" reflects the second invocation cell. Carried: `command -v sha256sum` harness only on the map path (pre-existing ungated sibling-sidecar verify is out of P5.7 remit); AGENTS §2/§3 seam rows (incl. the new FS_NERDFONT_* pair + P5.1–P5.6 seams + `config/` row) still deferred to the phase-boundary refresh (P5.1 NB8a/P18); installed map format cell mirrors the hook's awk predicate (shipped-map-vs-list coverage is its real value). Committed bytes verified via `git show HEAD:` cmp for all 9 staged files; tree clean. **Post-P5.7 corrective fix (owner-approved; supersedes the NB-A "deferred/owner-pending" text above):** routing split implemented + committed `283de21` — rev `ses_f1e0454dbffetqD2SYhZRS73La` (R1 REVISE 1 BLOCKING + 9 NBs → R2 **PASS**; reviewer independently mutation-tested: merged-set regression fails 89/15,77/12,23/6; order-swap caught; "system transaction first" pinned). `lib/runner.sh` BATCH: SYSTEM ids (`list_packages`) → `plan_install` via active family backend; FLATPAK ids (`list_flatpaks`) → `( FS_PKG_BACKEND=flatpak; export FS_PKG_BACKEND; plan_install ... )` subshell (self-restoring via `_pkg_load` re-select); system-first so core installs the flatpak CLI; failure semantics: `package batch failed` abort BEFORE flatpak (no hooks/state), `flatpak batch failed` abort AFTER system committed (no hooks/state); flatpak namespace gates on `flatpak_supported` (bare `command -v flatpak`) in dry AND real mode (header-documented). Fixtures (stateful fake flatpak binary, `FS_FAKE_LOG`/`FS_FAKE_INSTALLED`, per-cell `PATH` scoping, dedicated `FAKEINST` vs mock `INST`): runner 84→**103** (incl. new host-independent `flatpak batch failed` cell — `PATH="$MINBIN"` no-flatpak, system-batch-committed-before-abort assert, no-hooks/no-state asserts; m5/m6/m8–m11 now fake-seamed too), install_profiles 73→**89** (package-only negative-control cell: system batch present, fake log + installed set empty), mod_flatpak 26→**29** (real-mode flatpak-only routing proof: mock log EMPTY, fake log remote-add+install of filtered batch, `fx_empty mock state untouched`). Evidence: runner 103/0, install_profiles 89/0, mod_flatpak 29/0 — all rc0 ×3 byte-identical (md5s af3a9a7643bdc4d5a438bcc2e9dbd895 / 47e6fdf7a69dd6b4fc0f43a9bbcac577 / 9bed363250ec3e562e213a46940fb6cf), smoke 105/0, env -i / hostile / `unshare -Ur` / REAL bash 4.3.48 container all identical counts; real-host dry-run rc0 renders family `# would run: sudo dnf5 install -y …` THEN separate `flatpak remote-add …` + `flatpak install …` lines (desktop profile `5 ok`); patch md5 8b0f437ea06544b99579d80324f2eec3; committed + `git show HEAD:` cmp verified, tree clean. **AGENTS.md §2 "batch-once" row refresh deferred to the phase-boundary refresh** (P5.1 NB8a/P18 convention) — must be included in the P6-boundary AGENTS sync. **NEW P5-CLOSURE BLOCKER (discovered in review, pre-existing, NOT introduced by the fix):** `lib/bootstrap.sh:109` `family="$(_cli_family "$root")"` resolves family inside a command substitution, so the `FS_DISTRO_FAMILY` set by `distro_detect` (lib/distro.sh) never reaches the caller env; `pkg_backend` (lib/pkg.sh:41) then has neither `FS_PKG_BACKEND` nor `FS_DISTRO_FAMILY` and aborts `no package backend selected` → bare `./setup install --profile desktop --yes` fails rc1 on a real host even with distro detection working. Reproduced WITH the routing fix in place (`FS_DRY_RUN=1`, exit=1). Real mutating run requires `FS_PKG_BACKEND=rpm` explicitly (still the operational path — ROADMAP:74 already requires it for real-backend dry render); ticket to fix bootstrap so a bare real-host run works before the P5 closure real run. |
| P5.8 | **DONE** · **COMMITTED** `c964fd7` | rev — P5-closure corrective fix: bare install family→backend resolution (owner-approved; supersedes the ROADMAP P5.7-row dry-run claim corrected above). Root cause: `lib/bootstrap.sh:109` `family="$(_cli_family "$root")"` resolved family inside a command substitution, so the `FS_DISTRO_FAMILY` set by `distro_detect` never reached the caller env; `pkg_backend` (lib/pkg.sh:41) then had neither `FS_PKG_BACKEND` nor `FS_DISTRO_FAMILY` and aborted `no package backend selected` → bare `./setup install --profile desktop --yes` failed rc1 on a real host. Fix: `_cli_family` drives family→backend resolution in-caller (model: bootstrap `list` branch — `distro_detect` in the caller env, not a subshell), so a bare install resolves rpm/deb/arch with no explicit `FS_PKG_BACKEND`. Files: `lib/bootstrap.sh` + `tests/fixtures/install.sh` (+45/−14). Regression cell (in-cell, `$FBIN` fake dnf5/dnf/rpm + fake fedora `osrel2` + `FS_DRY_RUN=1`, `FS_PKG_BACKEND`/`FS_DISTRO_FAMILY` unset): bare family→backend resolution rc0 + assert `stderr must NOT contain: no package backend selected`. Mutation proof (revert bootstrap to `283de21`, committed fixture): 62/5 FAIL incl. both pins above; byte-restored. Bare CLI on host: `FS_DRY_RUN=1 ./setup install --profile desktop --yes` → rc0, `# would run: sudo dnf5 install -y …` render, `5 ok`; explicit `FS_PKG_BACKEND=rpm` still fine. Full battery green: all 22 fixture suites (install 67/0, install_profiles 89/0, runner 103/0, mod_terminal 148/0, …) + smoke 105/0; REAL bash 4.3.48 container install 67/0 + smoke 105/0 + runner 103/0 + install_profiles 89/0, byte-identical ×3, env -i / hostile / `unshare -Ur`. Fresh-context **P5 Senior Closure Review: PASS · CLOSURE-READY**, no blocking issues (verified both `283de21` routing fix and `c964fd7`); NBs carried: AGENTS §2 "batch-once" row refresh deferred (applied here, this closure), no literal `package batch failed` runner-level fixture assert (optional), real **mutating** desktop run remains owner-gated — dry-run-verified only. P5 closed on owner approval; P6 not started. |
| P6.1 | **DONE** · **COMMITTED** `c8c335d` | rev `ses_f17e4000fffe6VH8Dt6K3PGjF7` (R1 **PASS**, 0 blocking; NBs NB-1…NB-6 → delta applied pre-commit → R2 re-**PASS**; carried: NB-3/NB-4 optional cosmetics declined, NB-8 sed/awk-pin ⇄ header-word coupling, NB-9 ambient `FAKE_GET_RC` — deferred to shared-hygiene/P10). `lib/gnome.sh` gsettings layer (Depends io.sh + run.sh): `gnome_gsettings_available` / `gnome_extensions_available` (bare `command -v`, no IO, GUI-safe); `gnome_gsettings_get <schema> <key>` (schema/key token-validated via locale-stable `case` globs `[A-Za-z0-9._-]` — no `[[ =~ ]]`; **dry-run → io_error + rc1 fail-closed, no probing**; gsettings absent → rc1); `gnome_gsettings_set` (idempotent: real-mode pre-probe, equal → silent rc0 no-op; write via `run_cmd` keep-going so a failed `gsettings set` logs + rc0 and the runner continues; dry-run renders exactly ONE `# would run: gsettings set …` line %q-quoted, never probes; value must be non-empty printable ASCII without tab/nl/CR); `gnome_strv_parse` (['a', 'b'] / @as [] / [] / bare numerics / backslash-escape decode / trailing comma / any-whitespace separators / empty input = empty array; **one element per printed line**; control bytes inside quoted elements → rc1 malformed; `local LC_ALL=C`), `gnome_strv_build` (validated printable-ASCII elements — `[!" "-\~]` negated range under LC_ALL=C, rejects quotes/backslash/space/control/high bytes; emits ['a', 'b'] or @as []), `gnome_strv_merge <current> [new…]` (parse current → first-seen-dedupe append → rebuild; bash-4.3-safe guarded `"${merged[@]+…}"`); parse/build/merge = the read→merge→write primitive. `gnome_custom_keybindings_merge_add <dconf-path…>` (**prototype bug #4 fix**: read→merge→write of `org.gnome.settings-daemon.plugins.media-keys`/`custom-keybindings` preserving existing entries, deduped, appended once; no sed/awk/stateful text rewriting anywhere — lib has **zero file-write path**; dry-run renders the new-only merge because the current value is unprobeable). `tests/fixtures/gnome.sh` (109 asserts): PATH-visible fake `gsettings` (logs `get`/`set` to `$FAKE_LOG`, answers `$FAKE_GET`, can fail `get`/`set` via `$FAKE_GET_RC`/`$FAKE_SET_RC`); available/absent ×2; get scalar-passthrough + probe-log / array-passthrough / **dry-refuse** (rc1, no probe, no stdout) / absent / invalid schema / invalid key / no-arg; set new-exact-single-set-line / **idempotent no-op** (probe logged, no write) / graceful keep-going failure (rc0 + `command failed (rc=1)`) / **failed pre-write read → rc1 + no write** / dry-render-noprobe (1 render line, empty $FAKE_LOG) / dry without gsettings / control-char value / missing value; parse happy (array, @as [], [], numerics, escape, trailing comma, mixed whitespace, empty) + malformed ×7 (unclosed, control-byte-in-quote, empty element, non-array, stray token, bare string) all rc1 `malformed GVariant array`; build empty / two-elements / invalid-element / build→parse roundtrip; merge append / from-empty / dedupe / invalid-new / malformed-current; keybindings add-from-empty / preserve+append / **idempotent-merge no write** / dry-render-noprobe (1 render line, no `# … get`, empty log) / no-paths / invalid-path **reject with no write** / dry invalid-path; mechanical pin `grep -nE '\b(sed|awk)\b' lib/gnome.sh` → no match. Evidence: `bash -n` clean both files; fixture **109/0 rc0 byte-identical ×3** (md5 ea7703cf4a7b7c275c25e0d0d9d82204); all 23 in-tree fixture suites rc0; host `bash tests/smoke.sh` **105/0 rc0**; REAL bash 4.3.48 (`podman run --rm -v $PWD:/repo:z docker.io/library/bash:4.3`): fixture **109/0 rc0** byte-identical ×3 (same md5); smoke **105/0 rc0 when a GNU-compatible `readlink` is mounted (`-v <shim>/readlink:/usr/local/bin/readlink:z,ro`)** — the only 4.3 gaps are the pre-existing busybox `readlink -m` sites at `lib/state.sh`/`lib/fs.sh`, already ticketed in the P4.5 ledger row (`cannot resolve state root`); **without** the shim the container reports the pre-existing **95/10**, reproduced identically from a clean `git archive HEAD` tree (container-tooling artifact, not a P6.1 result). `env -i` / any-CWD / hostile env (`LC_ALL=tr_TR.UTF-8`, bogus `FS_*`, `FS_LOG_FILE=/dev/null`) all 109/0; a PATH sentinel ahead of the host's real `/usr/bin/gsettings` was never invoked (hermetic, no host dconf access); no `/tmp` residue; no col-1 lines inside function bodies. Reviewer mutation proof (byte-restored): NB-1 guard removed → 2 FAIL; pre-write-read abort removed → 2 FAIL; fake `get` ignoring `FAKE_GET_RC` → 3 FAIL; `sed` planted in lib comment → 1 FAIL; `awk` planted in lib code → 1 FAIL; idempotency always-skip → 4 FAIL; dry-run get-not-refused → 4 FAIL; merge-drops-new → 5 FAIL; keybinding replace-instead-of-merge → 3 FAIL; `build()` empty → 1 FAIL (all rc1 — `fx_summary` gate has teeth). |
| P6.2 | **DONE** · **COMMITTED** `b62fef2` | rev `ses_f172da084ffelEiwdq3M2cu0TS` (R1 REVISE B1 + NBs → fixes + pins → delta re-review **PASS** → final confirm **PASS**, 0 blocking; carried NBs: NB6 first-free semantics documented + deferred to P6.6, NB8 no profile wires `gnome-base` yet — P6-phase DoD gap, owner decision before P7, NB9 AGENTS §2/§3 doc drift, NB-B empty-sig dedupe edge + NB-D wallpaper-default-constant pin — declined). `modules/gnome-base/` (id=gnome-base, RISK=low, DEFAULT=on; hooks-only — no list files so the P4.2 family gate passes trivially; GNOME-availability gating = header-documented deferral, desktop-gating arrives P6.5): `favorites.list` 6 curated `.desktop` ids, `shortcuts.list` 4 relocatable-schema custom keybindings (Resources/Settings/Terminal/Toggle Mic, `name|command|binding` per line, shared list grammar), both parsed via `list_parse` (whole-line comments); `hooks.sh` `run()` only, sources lib/gnome.sh; stages: (1) gsettings present + `XDG_CURRENT_DESKTOP` matches `*GNOME*` else fail-fast `gnome-base: gsettings not found` / `gnome-base: not a GNOME session` (module-scoped prefix, NB2); absolute-dir preflight BEFORE any write (FS_WALLPAPER_ASSETS_DIR non-absolute → io_error rc1, dry+real, NB-C hoisted out of the wallpaper helper); (2) favorites MERGE via `gnome_gsettings_get/set` + `gnome_strv_merge` — preserve existing order, append-first-seen only (live run kept the user's 19 favorites and appended `firefox.desktop`), compare-before-write idempotent; (3) shortcuts via `gnome_custom_keybindings_merge_add` (3 gsettings writes each; curated dupes collapse first-seen via quote-normalized command-signature compare on BOTH sides — NB4/NB5; already-registered → skip print; dry branch guarded `(( ${#paths[@]} > 0 ))` — B1: comment-only `shortcuts.list` + bash 4.3 `set -u` was an unbound-var abort; wallpaper regular-file gate only (`[[ -f ]]`, `*.jpg|jpeg|png|webp`), real-mode only write, dry renders exactly as real; registry mark via state.sh; all writes through `gnome_gsettings_set` (run_cmd keep-going, dry = ONE %q `gsettings set` per write, zero probes). `lib/gnome.sh` (P6.2 part): `_gnome_ok_schema` keeps the `*"//"*` → rc1 branch — empirically load-bearing (`a.b:/x//` was silently ACCEPTED via slash-strip + loop exit without the empty-segment re-check; fixture pins `a.b:/x//` rc1 / `a.b:/x/` rc0 / `a.b:/x` rc0 / `a.b://x//y/` rc1); `gnome_strv_merge_set <schema> <key> <list...>` (read→merge→write set primitive, dedupes the CURATED ids; no redundant schema/key guard — NB7); `gnome_custom_keybindings_merge_add <dconf-path...>` (thin wrapper on the read→merge→write primitive). `tests/fixtures/gnome.sh` 109→**150** (new: relocatable trailing double-slash reject ×2; merge-set append/dedupe/dry/no-state ×4; merge-add dry with double-slash schema rc1); `tests/fixtures/mod_gnome.sh` (new, **65 asserts** over 14 hermetic cells — REAL repo modules/ via `FS_MODULES_DIR` seam dir, mock backend, mock+ stateful fake gsettings pre-loaded with favorites/custom-keybindings): no-gsettings dry+real rc1 + exact message + no state + empty mock log; scratch os-release; dry favorites-real + dry shortcuts-real (exact render-line order + counts); real favorites merge order-preserving + byte-stable + idempotent no-write; real custom-keybinding merge preserve+append-once + `custom0..3` + reserved `toggle-mic` + re-run idempotent; comment-only shortcuts.list dry+real (B1 pin); curated dupes dedupe dry+real; default-wallpaper-dir absent; wallpaper regular-file gate (dir/vanishing file never applied); relative FS_WALLPAPER_ASSETS_DIR reject real+dry (+no-write +no-plan pins); quoted-curated normalization; `setup list` content via seam dir) + `tests/fixtures/lib.sh` fx_init unsets `FS_WALLPAPER_ASSETS_DIR`. Verified: all 24 in-tree fixture suites rc0 (gnome.sh **150/0**, mod_gnome.sh **65/0**, smoke **105/0**) byte-identical ×3 both gnome fixtures; env -i / hostile / `unshare -Ur` / any-CWD; REAL bash 4.3.48 container (podman bash:4.3 + GNU readlink -m shim) gnome.sh **150/0** + mod_gnome.sh **65/0**; real binary run `./setup install --yes gnome-base` in dry (rc0, exact render). Real-GNOME mutating run (owner-authorized, live session): pre → post favorites merge `firefox.desktop` appended order-preserved; custom0..4 applied (Resources skipped — already registered via command signature), Settings→custom2 / Terminal→custom3 / Toggle Mic→custom4; wallpaper set to scratch `adwaita.webp` then RESTORED to the user's original; idempotent re-run = all-skips registry + module-level fresh-FS_HOME no-write; scratch cleaned, no host residue. Mutation battery (all caught, byte-restored): B1 empty-guard-dry 1, regfile 2, abspath 2, dedupe 2, quotenorm 2, message-prefix 1, drop-`//` 2, move-after-favs 7. |
| P6.3 | **DONE** · **COMMITTED** `c448465` | rev `ses_f1700446cffeQpkSHLIqSEx3f2` (R1 **REVISE** B1 — real-mode `--browse`/flag never positively asserted end-to-end, only dry-render + xdg-open-missing branches — + 11 NBs → delta applied → R2 **PASS**, 0 blocking; reviewer mutation-proved the new cell: prototype unbounded loop → caught, `--browse` flag neutered → caught, real path forced onto xdg-open-missing branch → caught; backgrounded-with-limit variant documented as deliberately weaker/flaky-by-race, accepted; carried NBs: absent-`&` mechanical pin + anchored `setup list` regex — optional cosmetics declined, NB11 no profile wires `gnome-extensions` yet — same P6-phase DoD gap as P6.2 NB8, owner decision before P7, NB12 AGENTS §2/§3 doc drift — phase-boundary sync). `modules/gnome-extensions/` (id=gnome-extensions, RISK=medium, DEFAULT=on): `extensions.list` 2 curated uuids (dash-to-dock@micxgx.gmail.com, user-theme@gnome-shell-extensions.gcampax.github.com); `browse.list` 2 curated e.g.o URLs; `packages.rpm.list` gnome-shell-extension-dash-to-dock + user-theme, `packages.deb.list`/`packages.arch.list` = shared gnome-shell-extensions bundle only (documented: deb/arch dash-to-dock naming divergence / AUR-only); `config/extensions.compat` (`uuid|min|max`, seam `FS_GNOME_COMPAT_FILE`, report-only io_warn, house-maintained windows reviewed vs GNOME 50/Fedora 44). `hooks.sh` `run()` only; stages: GNOME-session gate → `gnome-extensions` presence fail-closed → dry (`# would run:` install batch + enable + browse lines, zero probes) / real (probe `gnome_shell_version` + `gnome_extensions_list [--enabled]` once each, fail-closed rc1; enable ONLY curated-and-installed-not-enabled uuids via keep-going `run_cmd`; never auto-installs or touches non-curated; version reported + per-installed compat warns; version unknown → io_info skip rc0); `--browse` opt-in (FS_GNOME_BROWSE, cli.sh `--browse`) opens **at most 2** browse.list URLs sequentially, never backgrounded or looped (prototype bug fix); URL must be http/https else rc1; xdg-open absent → manual-open io_info; keep-going failure semantics header-documented (audited, registry-marks-completed, not auto-retried — consistent with §12 keep-going + P6.2). `lib/gnome.sh` +`gnome_shell_version` (digits/dots token, dry-refuse rc1) +`gnome_extensions_list [--enabled]` (verbatim passthrough, bare-uuid consumer contract documented, dry-refuse/unknown-flag rc1). `lib/cli.sh` `--browse` (seed/parse/help; header seam list narrowed to the 5 env-honored seeds). Fixtures: `tests/fixtures/gnome.sh` 150→**179** (+29 helper cells, functional fake `gnome-extensions` list/enable + fake `gnome-shell`); `tests/fixtures/mod_gnome_extensions.sh` (new, **88 asserts** incl. real-mode end-to-end `--browse` cell: exactly 2 ordered xdg-open in FAKE_LOG, third URL never opened, enable phase still runs); fx_init + smoke unset `FS_GNOME_BROWSE`/`FS_GNOME_COMPAT_FILE`; smoke 105→**107** (browse flag assert). Evidence: `bash -n` clean; mod_gnome_extensions **88/0**, gnome.sh **179/0**, smoke **107/0**, all 26 suites rc0; full suite byte-identical ×3 (md5 `d0efc89103c60735581bfb27f71b9e49`); env -i hostile 179/0 + 88/0 + 107/0; REAL bash 4.3.48 container driver 26/0. Real-host (owner-authorized, Fedora 44 / GNOME Shell 50.5): dry plan exact (`sudo dnf5 install -y …`, 2 enable renders, notes line, rc0, zero probes); real fresh run no-op rc0 (both pkgs installed, both curated enabled, no warns in window); `gnome-extensions disable` both curated → real run **re-enabled both** rc0 (fresh FS_HOME); third run stable (`already completed`, still enabled). `--browse` not run live (would open tabs; covered by fixtures). |
| P6.4 | **DONE** · **COMMITTED** `11d6293` | rev `ses_f15496910ffe2EbGRUx0W3x1c2` (R1 REVISE B1+B2 + 14 NBs → fixes + NEW fixture/smoke pins → R2 **PASS**, 0 blocking; carried: NB10 no profile wires `gnome-theme` — same P6-phase DoD gap as P6.2 NB8 / P6.3 NB11, owner decision before P7; doc-deviation signed off in this row — prototype interactive `select` over `~/.themes`/`~/.icons` replaced by deterministic env override `FS_THEME_NAME`/`FS_CURSOR_NAME` + single-dir auto-pick (same trust model as `FS_GIT_USER_NAME`), plus an open follow-up for an optional TTY-only picker that is skipped in dry-run; shell-level `org.gnome.shell.extensions.user-theme name` key deliberately NOT written — only effective with the P6.3-curated user-theme extension and would clobber the user's Tweaks shell theme; the module is hooks-only like gnome-base). `modules/gnome-theme/` (id=gnome-theme, RISK=medium, DEFAULT=on; hooks-only like gnome-base; GNOME-session gate + gsettings-presence fail-closed, non-GNOME → io_info skip rc0; seam preflight BEFORE anything — FS_THEME_SRC/FS_CURSOR_SRC/FS_THEME_ASSETS_DIR/FS_CURSOR_ASSETS_DIR/FS_GTK_BOOKMARKS_FILE must be absolute when set, io_error rc1 in dry+real): theme/cursor resolution precedence FS_{THEME,CURSOR}_NAME (explicit, trusted even when the dir is absent) > exactly-one subdir of the src seam (default `${HOME:-}/.themes` / `${HOME:-}/.icons`) > exactly-one subdir of the assets seam (`$root/assets/themes` / `$root/assets/cursors`); >1 dirs or none → io_info skip rc0 naming the seam to set (dry renders ZERO plan lines for a skip); applies `org.gnome.desktop.interface gtk-theme`/`cursor-theme` via `gnome_gsettings_set` SINGLE-QUOTED ('Aurora') so real get/set agree for true idempotency, dry renders ONE exact `# would run: gsettings set … %q` line (value `\'Aurora\'`), never probes; io_info precedes the set so a keep-going-failed write is not misreported as applied. **Prototype bug #5 fix**: module contains NO icon-theme read or write anywhere (asserted — zero `icon-theme` hyphen-occurrences in any plan/log/gsettings write); io_info "icon theme untouched (keeps the user's icon theme)". **Github-dedupe fix**: gtk-3.0 bookmarks target `FS_GTK_BOOKMARKS_FILE` or `$HOME/.config/gtk-3.0/bookmarks` (HOME unset-or-`/` with no seam → clean io_error rc1, mirroring git module); no file → io_info skip rc0, no mkdir, no curated adds, no managed-block markers; dry renders one `# would run: dedupe gtk-3.0 bookmarks %q <file>` (a stat, like fonts/git); real `fs_dedupe_lines` backs up via registry, dedupes first-seen whole-line (order kept, blank line = ordinary distinct line, never an empty array subscript — B1), preserves mode, writes back atomically only when removed>0, prints the count. `lib/fs.sh` +`fs_dedupe_lines` (plain per-line dedupe primitive, B1 key use `"L$line"` prefixed so an empty/arbitrary line can never form an empty subscript — verified against hostile bytes incl. `]`/`"`/backslash/`$(1)`/backtick/non-ASCII; guards: missing arg / NL-CR-trailing-slash-`..` (any of `..`, `../*`, `*/../*`, `*/..`) / non-regular / unreadable / uninitialized FS_STATE_DIR all io_error rc1). `tests/fixtures/mod_gnome_theme.sh` (new, **77 asserts** over 16 hermetic cells through the real `./setup install`): dry purity (3 exact plan lines, escaped `\'Aurora\'`, bookmarks plan, `icon-theme` forbidden, zero gsettings probes, no state dir, bookmarks untouched); auto-pick src + assets fallback; multi-theme skip renders only bookmarks line; non-GNOME skip; relative-seam fail-closed dry+real (no plan/write); real apply + bookmarks dedupe (first-seen, order kept, trailing-space variant distinct, mode 640 preserved, backup registered); exact idempotent re-run (no set, no write, no registry entry); absent bookmarks (no mkdir); **B1 pins** blank-line dedupe (`a\n\na\n` → `a\n\n`, 1 removed, no `bad array subscript`) + newline-only no-op; **B2 pins** `unset HOME` dry (rc0, exact 3-line plan, no gsettings, no `unbound variable`) + HOME-unset-no-seam fail-closed rc1 clean io_error; gsettings-missing rc1; newline-name rc1; `setup list` row. `tests/smoke.sh` 107→**121** (+P2.5b `smoke_fs_dedupe` 14 asserts: count 2, first-seen order cmp, blank line, newline-only unchanged, no-state rc1, `../` rc1; note t_rc clobbers $OUT/$ERR so all t_out/t_err must precede the cmps; `FS_STATE_DIR` added to the top-of-file unset list so the no-state cell is self-contained). `tests/fixtures/lib.sh` +7 seams (FS_THEME_NAME/SRC/ASSETS_DIR, FS_CURSOR_NAME/SRC/ASSETS_DIR, FS_GTK_BOOKMARKS_FILE) unset in fx_init + smoke. Evidence: `bash -n` clean all 6; mod_gnome_theme **77/0**, smoke **121/0**, all 26 suites rc0; byte-identical ×3 (smoke `c02c9b4ef875e31e88560ec5f9bceafa`, mod_gnome_theme `bb353b0147e07d7e5154479bdd465c0c`, gnome `b69822d0111fcf90630d4ef20a97a9d8`/runner `af3a9a7643bdc4d5a438bcc2e9dbd895` unchanged); env -i hostile 121/0; external FS_STATE_DIR exported → still 121/0. REAL-GNOME mutating run (BOLD: current host re-imaged to UBUNTU 26.04.1 LTS GNOME 50.1, was Fedora 44/50.5; real gsettings live, owner-authorized): PRE 'Aurora'/'Yaru'/'Yaru-blue-dark', bookmarks md5 `2e5e03c6…` (5 clean lines); RUN A FS_THEME_NAME=Adwaita-dark FS_CURSOR_NAME=DMZ-Black → applied (get confirms), icon untouched, bookmarks no-op rc0; RUN B fresh scratch FS_HOME → rc0, 0 writes, values unchanged; RUN C seam COPY of real bookmarks +3 injected Github lines → 8→6 (2 removed) == expected, mode 664, backup registry entry present, real md5 unchanged; RESTORE to 'Aurora'/'Yaru' → POST==PRE all keys + bookmarks. bash 4.3 container STILL NOT reproducible on this host (no podman/docker, no bison/root; bash-4.3 unbuildable with GCC 14) → static audit only: `S` none; new code uses only mapfile/local -A/%q/${arr[i]} indexed loops/`${#in[@]}` ≤4.3. Host gotcha: `tests/fixtures/planner.sh` needs `rpm` on PATH (pre-existing; throwaway `/tmp/opencode/ubin/rpm` shim symlinks /bin/true on this Ubuntu host — re-verify same as HEAD baseline, not a P6.4 artifact). |

| P6.5 | **DONE** · **COMMITTED** `dfd986e` | rev `ses_f1528a7b5ffe4JsquDGqcQMPJI` (R1 **PASS**, 0 blocking; 9 NBs carried, none gating: NB2 **skip marks module completed → `--force` cannot recover it** — a real headless/SSH `./setup install` marks `…/modules/gnome-base` done; the next GNOME-desktop run even with `--force` prints `already completed`; pre-existing runner semantics (`lib/runner.sh:176` skip, mark at `:194`), P6.5 only widens skip triggers — OWNER-LEVEL (§13), outside this task's file scope, surfaced in phase report; NB1 gnome-base verify-fail cell uses fully-fresh state so all three checks fail at once (single-drift cell would close the gap); NB3 missing `shortcuts.list` → verify "nothing to verify" rc0 (mirrors run(), accepted); NB4 `gnome_strv_parse` unchecked in the favs herestring → misleading "not applied" but still fail-closed; NB5 `shortcuts.list` grammar duplicated from `_gnome_base_shortcuts` (drift risk; favs reuses `list_parse`); NB6 no "extensions AND gsettings missing" precedence cell; NB7 gnome-base `verify()` lacks gnome-theme-style wallpaper-dir absoluteness preflight (asymmetry → degrades rc0); NB8 AGENTS §2/§3 doc drift — phase-boundary sync; NB9 trailing-newline EOF — pre-existing). Capability gating: `lib/gnome.sh` `gnome_require_capable <ctx>` — order `FS_GNOME_FORCE=1` silent rc0 > SSH vars > `XDG_CURRENT_DESKTOP` set-but-not-`*GNOME*` > XDG unset AND no `DISPLAY`/`WAYLAND_DISPLAY` (`no graphical session`) > gsettings missing from PATH; skip = `io_info "<ctx>: skipped (not GNOME) (<reason>)"` + rc1 → hooks `|| return 0` (graceful rc0, zero probing, dry-safe). **Behavior change mandated by task**: gsettings-missing is now graceful skip rc0 (was fail-closed rc1 in gnome-base/gnome-theme); gnome-extensions keeps its OWN tool-gate (`gnome-extensions` binary missing → fail-closed rc1, P6.3) — the two layers are coherent, tool-gate unreachable in a gsettings-less env. `lib/cli.sh` `--force` → `FS_GNOME_FORCE` (source-time `_CLI_ENV_FORCE`, env-honored seam, help + header). verify() hooks (bodies only; wired by P9.2): all three re-gate and refuse under `FS_DRY_RUN` (io_info + rc0), rc1 on any mismatch else `io_info "verify passed"`; gnome-base favorites presence + `custom-keybindings` signatures (`${cmd//\'/}` on both sides, `$base$p` key join) + wallpaper `file://` URIs (picture-uri + picture-uri-dark); gnome-extensions curated uuids BOTH installed AND enabled; gnome-theme gtk-theme/cursor-theme = `'$name'` (single-quoted gsettings form; resolve order = run()'s) + read-only whole-line bookmarks dedupe (assoc `L$line`). New `tests/fixtures/mod_gnome_gate.sh` (67 asserts, 11 cells; fake gsettings/gnome-shell/gnome-extensions + notools dir; curated seeds use `$CK` WITH the `custom-keybindings` segment to match `array_path`). Re-pinned mod_gnome (66/0 — message + skip rc0 + LOG-empty), mod_gnome_extensions (88/0 — fakebin gsettings so the tool-gate stays reachable), mod_gnome_theme (78/0 — skip rc0). smoke cli_one prints `force=%s`, +2 cells (`force flag`, `force env seam` block — env-prefix via `"$@"` expansion returns rc127, hence the block form) → smoke **125/0** rc0, also under `env -i HOME=/nonexistent` and hostile exported GNOME/SSH envs. Verified: bash -n 11 files; 27-fixture battery all rc0; byte-identity ×3 stable, `gnome.sh`/`runner.sh` fixtures byte-identical to HEAD (`b69822d0…`/`af3a9a76…`); `git diff --check` clean; reviewer ran an independent 22-mutation battery (all caught) + hand-verified un-pinned paths (dark-uri-only drift, fully-applied rc0, extensions+gsettings-missing precedence). |

| P6.6 | **DONE** · **COMMITTED** `2668692` | rev `ses_f1506d2f7ffeIkBWEDlh0o0ZMj` (R1 **REVISE** 3B+8NB → fixes+pins → R2 **PASS**, 0 blocking; 4 NBs folded into the commit. R1 B1: `gnome_gsettings_set` compare at `lib/gnome.sh` matched only the exact target, but real `gsettings get` renders string scalars SINGLE-QUOTED (`'file:///x'`), so wallpaper was re-written every real run — fixture masked it by echoing seeds verbatim; fix = compare `"$cur" == "$value" || "$cur" == "'$value'"` (fails safe: re-write, never a skipped needed write; accepted-by-real-set left to run layer per R2 NB3), header documents the invariant; B2: fixture fake `set` did not persist → R2/R3 compared against a hand-authored state, structurally blind to duplicate-merge bugs — fake now PERSISTS every set into FAKE_KEY_FILE (in-place overwrite, real-dconf model), R2/R3 feed from R1's own resulting state (`keys-r1`), new asserts prove favorites + wallpaper persisted + R2/R3 state byte-identical (snapshot-before vs after diff); B3+R2 pin: `modules/gnome-base/hooks.sh` `_gnome_base_verify_wallpaper` compared URIs exactly — verify() would fail forever on a real session — now quote-aware for picture-uri AND picture-uri-dark, pinned by new mod_gnome_gate cell 7b (stored URIs single-quoted → `verify passed` rc0; red confirmed 68/4). R2 NBs folded: R2-NB1 md5 assert repointed to the pre-run R2/R3 snapshots (42/43 asserts with teeth → 43/43); R2-NB2 cross-ref fixed (`mod_gnome.sh` → `gnome.sh`, the only fixture with failable get); R2-NB3 run-layer clause softened; R2-NB4 divergence note added to `mod_gnome.sh` header (verbatim echo peer; idempotency.sh is the faithful quoting model). R1 NBs: fake `get` now quotes ONLY string-like scalars (true/false/[0-9]*/@* exempt — no false-pass for a future bool/int write); fake-always-exits-0 + divergence documented in fixture header; NB7 curated `<Super>I`/`<Alt>T` shadow stock control-center/terminal bindings (P6.2-scope phase-report observation; R2/R3 zero writes confirm idempotent); NB8 live evidence + ledger phrasing below). Red/green (reviewer, copies): revert lib compare → `41/2` exactly R2/R3 zero-write FAILs; revert verify compare → gate `68/4` all in the quoted-URI cell, bare-URI cell 7 still green (both arms pinned); disable fake `set` persistence → `39/4` (persisted-into-state asserts fire); break `gnome_strv_merge` dedupe → `39/4` at R2 (pre-NB1 bytes; re-measured `38/5` on the committed `2668692` in the P6 closure review — same load-bearing R2/R3 state-diff asserts fire, the repointed md5 now catches it too) — the bug class the task names now load-bearing. Core regression: idempotency **43/0** rc0 byte-identical ×3 (md5 `6b471d051860e0126ba16ceedb839380`), gnome.sh **182/0**, mod_gnome_gate **72/0**, mod_gnome **66/0**, smoke **125/0** rc0, 29-fixture battery all rc0 WITH the `rpm` shim on PATH (planner rc1 22/3 without it — pre-existing, host has no rpm, P6.4-ledger ticketed; recorded as NB8). **LIVE sweep** (owner-authorized, real GNOME 50.1, `/tmp/opencode/gnome-idem-sweep.sh` → `/tmp/opencode/gnome-sweep-run.log`, SWEEP rc0): gnome-base R1 = exactly 16 writes (1 fav merge + 4×3 shortcut sets + 1 custom-keybindings array merge + 2 wallpaper URIs), R2/R3 = 0 writes with `already at target; no-op` firing live in audit-base2.log (the old code re-wrote wallpapers every run — confirmed the bug was real), base2.snap==base3.snap; gnome-theme 3× 0 writes (Aurora/Yaru compare-equal, no bookmark dupes); gnome-extensions 3× 0 enables (dash-to-dock already enabled, user-theme not installed) via direct hooks subshell (module has pkg lists → not `setup install`, documented); baseline.snap == restore.snap, session re-verified pristine post-sweep (favorites 8, `custom-keybindings @as []`, picture-uri warty-final + -dark ubuntu-wallpaper-d, gtk-theme Aurora/cursor Yaru, bookmarks 5 lines md5 `2e5e03c6…`, dash-to-dock enabled). NB8 (also R1) evidence accuracy: the session was briefly MUTATED mid-debug before the sweep (a `bash -x … | sed -n` pipe ran the whole sweep without restore) — manually restored with a hardcoded command, then the sweep script gained a preflight abort (favorites == pristine 8-list AND `custom-keybindings @as []`); the final clean sweep+restore run above stands. Reviewer confirmed all counts independently (28 rc0 + planner pre-existing rc1 no-shim; 29/29 with shim) and re-verified the live session pristine + no fixture scratch residue. Scope: `lib/gnome.sh`, `modules/gnome-base/hooks.sh`, `tests/fixtures/{idempotency,gnome,mod_gnome,mod_gnome_gate}.sh`; no profile wiring (P6-phase DoD gap NB continues); `git diff --check` clean.

## P0 — Planning & Repository Baseline

### 1. Phase objective
Produce this roadmap, capture an identical snapshot of the working prototype, and record the
migration boundaries before any file is touched.

### 2. Why this phase exists
The current code is the only working reference. Every subsequent decision (what to preserve,
what to delete, how to verify behavior) must be traceable to a frozen baseline. Without a
baseline, P1's destructive deletions are unrecoverable-by-humans.

### 3. Prerequisites / dependencies
- None (fresh start).

### 4. Ordered tasks

- **P0.1** `[SEQ]` Create this `ROADMAP.md` and add it to `.gitignore`. **[DONE]**
  - **What:** Author the roadmap; add a `ROADMAP.md` ignore entry.
  - **Verification:** `git check-ignore ROADMAP.md` returns the path; `git status --short` shows nothing for it.
  - **Depends:** —

- **P0.2** `[SEQ]` Tag the prototype baseline. **[DONE]**
  - **What:** `git tag proto-baseline` (lightweight tag at `HEAD` `048f969`).
  - **Verification:** `git tag` lists `proto-baseline`; working tree still clean.
  - **Depends:** P0.1

- **P0.3** `[SEQ]` Record baseline inventory. **[DONE]**
  - **What:** Document current file tree, per-script behavior summaries, and the feature→module mapping table
    (feature, old script, new module id, keep/rewrite/drop). Store in `docs/` later (P11); keep notes here in the
    interim as `BASELINE_NOTES` section at the end of this file.
  - **Verification:** Feature mapping table is complete: every old script has an explicit disposition.
  - **Depends:** P0.2

- **P0.4** `[SEQ]` Define migration boundaries. **[DONE]**
  - **What:** Decide explicitly what P1 deletes wholesale vs. preserves.
    - DELETE (git-recoverable): `scripts/*.sh`, `additions/fonts/**`, `additions/shell_conf`, stale README claims.
    - PRESERVE as user assets (optional, gitignored content): wallpaper, icons.
    - PRESERVE as concepts: every feature becomes a module (see feature mapping).
  - **Verification:** Boundary list is written down in this file; no ambiguities remain.
  - **Depends:** P0.3

### 5. Verification criteria
- `git tag proto-baseline` exists; working tree clean; ROADMAP is ignored; feature mapping complete.

### 6. Expected files / components affected
- `ROADMAP.md` (new, gitignored), `.gitignore` (1 line added), git tag.

### 7. Risks or blockers
- None. Pure planning.

### 8. Definition of Done
- Baseline frozen; boundaries written; roadmap approved to start P1.

---

## P1 — Repository Restructure & Bootstrap

### 1. Phase objective
Create the new directory skeleton, the `./setup` entry point, and the bootstrap layer; then
safely remove the obsolete prototype structure.

### 2. Why this phase exists
All later phases depend on a canonical layout and a single, CWD-independent entry point. Deleting
the old tree last (after a working skeleton exists) avoids ever leaving the repo with no runnable
artifact.

### 3. Prerequisites / dependencies
- P0 (all 4 tasks).
- Deletions in P1.3 are git-recoverable from `proto-baseline` (P0.2).

### 4. Ordered tasks

- **P1.1** `[SEQ]` Create the target directory skeleton.
  - **What:** Create empty dirs + `.gitkeep`/placeholder files:
    `lib/`, `modules/`, `profiles/`, `assets/{wallpaper,icons,fonts}/`, `docs/`, `tests/`.
  - **Verification:** `ls` shows the full tree; `git status` shows only new empty dirs.
  - **Depends:** P0.4

- **P1.2** `[SEQ]` Implement `./setup` entry point + `lib/bootstrap.sh`.
  - **What:** Executable `setup` that finds the repo root from `$0` (no CWD assumption), verifies Bash ≥ 4.3,
    required base tools (coreutils, `git` only for update, `curl`/`wget` for network modules), and forwards to
    the CLI dispatcher once it exists in P2. Until P2.8, bootstrap prints version + "CLI pending".
  - **Verification:** `./setup` and `bash setup` both work from the repo dir; `./setup` works from a
    *different* CWD via absolute/`$(dirname "$0")` path; bad interpreter or missing bash detected.
  - **Depends:** P1.1

- **P1.4** `[SEQ]` Harden `.gitignore`.
  - **What:** Track ignore rules for the state/log dir, mock/test scratch, and runtime downloads
    (e.g. `~/.local/state/fedora-setup` is outside repo, but any local caches inside repo must be ignored).
  - **Verification:** `git check-ignore` succeeds for each new pattern.
  - **Depends:** P1.1

- **P1.3** `[SEQ]` `[DESTROY]` Remove obsolete prototype files.
  - **What:** `git rm scripts/*.sh scripts/README.md additions/fonts/** additions/shell_conf`; rename/keep
    `additions/icons` + `additions/wallpaper.jpg` only if they survive as optional `assets/` (else delete too).
    Update old README references removed in P11.1 (leave README intact until docs phase to keep diff surface small —
    note: README is rewritten wholesale in P11.1).
  - **Verification:** `git status` shows the deletions staged; nothing referenced by the new tree is missing;
    `git checkout proto-baseline -- scripts/` restores everything (spot-check one file).
  - **Depends:** P1.2, P1.4 (skeleton must exist before deletion)

### 5. Verification criteria
- Full `./setup` entry works; old prototype gone but recoverable; ignore rules pass `git check-ignore`.

### 6. Expected files / components affected
- `setup`, `lib/bootstrap.sh`, `lib/` dir, `modules/`, `profiles/`, `assets/`, `docs/`, `tests/`, `.gitignore`,
  deleted `scripts/**`, `additions/fonts/**`.

### 7. Risks or blockers
- Deletion of working code before replacement is ready → mitigated by `proto-baseline` tag (P0.2).
- `setup` must not depend on CWD (users may clone anywhere).

### 8. Definition of Done
- Skeleton present; `./setup` runs; prototype deleted; git recoverable; tree clean.

---

## P2 — Core Runtime Infrastructure

### 1. Phase objective
Implement the runtime foundation: CLI parsing + dispatch, logging/UI, distro detection, state
management, filesystem safety (backups + managed blocks), sudo policy, and the command runner
with dry-run/verbose/debug. Everything here is pure infrastructure: `[MOCK]`, no root required.

### 2. Why this phase exists
Every later phase (pkg backends, module runner, verification) consumes these libs. Building them as a
testable, dependency-free "core" is what makes the rest of the work small and verifiable.

### 3. Prerequisites / dependencies
- P1 (skeleton + bootstrap).
- P2.8/P2.9 need `lib/cli.sh` (P2.2) and bootstrap (P1.2).

### 4. Ordered tasks

- **P2.1** `[SEQ]` Implement `lib/io.sh` (logging + UI primitives).
  - **What:** Leveled logging (`error/warn/info/debug`), color on TTY only, timestamps, progress/status line,
    final summary renderer, safe wrappers that tolerate absent TTY. All output goes to a log file too (state, P2.4).
  - **Verification:** Fixture script captures log lines to file; non-TTY run produces no color control codes;
    `debug` silent unless `--debug`.
  - **Depends:** P1.2

- **P2.2** `[SEQ]` Implement `lib/cli.sh` (argument parsing + dispatch).
  - **What:** Global flags `--yes`, `--dry-run`, `--verbose`, `--debug`, `--profile`, `--list`; subcommands
    `install|list|check|verify|export|update|help|version`; validation of unknown flags/commands; `--help` text.
  - **Verification:** Arg-parser unit tests (fixture arrays) — every flag/subcommand combination parses to the
    expected structure; unknown input exits non-zero with a helpful message.
  - **Depends:** P2.1

- **P2.3** `[PAR]` `[MOCK]` Implement `lib/distro.sh` (detection).
  - **What:** Parse `/etc/os-release` (override path via `FS_DISTRO_FILE` env for tests) → `{family, id, id_like, variant, pkgmgr}`:
    `rpm` family (fedora/nobara/rhel-like), `deb` (debian/ubuntu/mint-like), `arch` (arch/cachyos/endeavouros/manjaro-like);
    detect `dnf5` vs `dnf`, `apt-get`, `pacman` by `command -v`; capability matrix (local-pkg install cmd, flatpak default, gnome availability).
  - **Verification:** Fixture `/etc/os-release` files (Fedora 40, Fedora 41 w/ dnf5, Ubuntu, Mint, Debian, Arch, EndeavourOS, unknown)
    parse to expected family/`pkgmgr`; unknown input errors cleanly.
  - **Depends:** P2.1

- **P2.4** `[PAR]` `[MOCK]` Implement `lib/state.sh` (state + logs).
  - **What:** State dir under `$XDG_STATE_HOME` (`~/.local/state/fedora-setup`, override via `FS_HOME` for tests): per-run log files,
    per-module completion registry, backups registry (path→timestamped backup), safe atomic file writes.
  - **Verification:** With `FS_HOME` tmp dir: run log created, module marker set/unset, backup registry entries correct;
    re-runs don't corrupt the registry.
  - **Depends:** P2.1

- **P2.5** `[PAR]` `[MOCK]` Implement `lib/fs.sh` (filesystem safety).
  - **What:** `fs_backup` (timestamped copy before any mutation, registry entry), `fs_install` (mkdir -p + copy guarded),
    `fs_managed_block` (idempotent `# BEGIN fedora-setup` … `# END fedora-setup` upsert into dotfiles), atomic write via temp+rename.
  - **Verification:** Tmpdir fixture: second upsert of same block is a no-op (byte-identical); block removes cleanly;
    backup created once and registry updated; atomic rename observed (no partial file).
  - **Depends:** P2.1

- **P2.6** `[SEQ]` Implement `lib/sudo.sh` (privilege policy).
  - **What:** Detect running-as-root (warn + allow but flag), detect usable `sudo` for non-root user, `sudo -v`
    credential refresh w/ `--verbose`-only keepalive; wrapper that is a no-op (prints) under `--dry-run`;
    **never** touches `/etc/sudoers`.
  - **Verification:** Mock: as non-root with `sudo -n true` simulated; dry-run produces `# sudo <cmd>` lines; root-run path warns.
  - **Depends:** P2.1

- **P2.7** `[SEQ]` Implement `lib/run.sh` (command runner).
  - **What:** Executes commands honoring `--dry-run` (print `# would run:`), `--verbose` (echo cmd), `--debug` (wrapper trace),
    captures exit code + output → log file; failure policy flag `--keep-going`/`--stop-on-error` (default = log & continue, stop for
    `[DESTROY]`/high-risk steps); dry-run must not invoke sudo or mutate anything.
  - **Verification:** Fixtures: failing command recorded, `--keep-going` continues, `--stop-on-error` halts; dry-run executes nothing
    (strace/tmpdir proves zero writes).
  - **Depends:** P2.6

- **P2.8** `[SEQ]` Wire bootstrap → CLI: `./setup --help`, `version`, `check` stub.
  - **What:** `lib/bootstrap.sh` execs dispatcher; `help`/`version` fully implemented; `list` renders nothing yet (P4 data).
  - **Verification:** `./setup --help`, `./setup version`, `./setup bogus` (error) behave; exit codes correct; works from any CWD.
  - **Depends:** P2.2, P1.2

- **P2.9** `[SEQ]` `[MOCK]` Smoke harness for core libs.
  - **What:** Minimal `tests/smoke.sh` (plain bash assertions, no bats yet) exercising P2.1–P2.8 against `FS_HOME`/`FS_DISTRO_FILE`
    fixtures. Formal bats/CI land in P10.
  - **Verification:** `bash tests/smoke.sh` exits 0; any regression in core libs fails the suite.
  - **Depends:** P2.8

### 5. Verification criteria
- `tests/smoke.sh` passes; `./setup --dry-run` produces only `# would run:` lines; distro fixtures all accurate.

### 6. Expected files / components affected
- `lib/{io,cli,distro,state,fs,sudo,run}.sh`, `lib/bootstrap.sh` wiring, `tests/smoke.sh`.

### 7. Risks or blockers
- Accidental real sudo/gsettings calls during tests → all core paths reachable via mocks; runner dry-run is load-bearing.
- Home/state override envs (`FS_HOME`, `FS_DISTRO_FILE`, `FS_PKG_BACKEND` in P3) must be honored everywhere or tests lie.

### 8. Definition of Done
- Core libs pass smoke suite; dry-run provably side-effect-free; no sudoers edits anywhere.

---

## P3 — Package Management Backend

### 1. Phase objective
Implement the family-aware package layer: query/install/update/diff across DNF(dnf5)/APT/Pacman,
repository setup, local-package install, Flatpak (Flathub) handling, a mock backend, batching, and
verification primitives.

### 2. Why this phase exists
Package handling is the project's core risk surface. Generalizing it behind one interface
(`lib/pkg.sh` + per-family backends) lets modules stay family-agnostic, makes the whole system
batching-capable, and enables mock testing of everything downstream.

### 3. Prerequisites / dependencies
- P2 (runner, state, sudo, distro).
- Backends are mutually independent after `pkg.sh` exists (P3.1).

### 4. Ordered tasks

- **P3.1** `[SEQ]` `[MOCK]` Design + implement `lib/pkg.sh` interface.
  - **What:** Define backend contract: `query_installed`, `install_batch`, `update_metadata`, `list_installed`,
    `install_local`, `add_repo`, `supported()`; dispatch to active backend selected by `distro.sh`. Backend selection
    overridable via `FS_PKG_BACKEND=rpm|deb|arch|mock`.
  - **Verification:** Contract fixture: switching mock backend via env is honored; unimplemented backend errors clearly.
  - **Depends:** P2.8, P2.3

- **P3.2** `[SEQ]` `[REAL]` RPM backend.
  - **What:** `rpm -q` queries; `dnf5`/`dnf` discovery; batch `dnf install -y` (single transaction); local `.rpm` install;
    repo files under `/etc/yum.repos.d` (`--if-not-exists`), copr support where needed; `dnf --setopt` for defaults.
  - **Verification:** Mock queries/capabilities; on a real Fedora (or container): batch install list, already-installed skip,
    dry-run prints a single `dnf install` invocation.
  - **Depends:** P3.1

- **P3.3** `[SEQ]` `[REAL]` DEB backend.
  - **What:** `dpkg-query -W`; batch `apt-get install -y`; local `.deb` install; repo `.list` files under `/etc/apt/sources.list.d/`;
    `apt-get update` before first batch for new repos.
  - **Verification:** Mirror P3.2 using dpkg/apt fixtures; real test on Ubuntu container later (P10.3).
  - **Depends:** P3.1

- **P3.4** `[SEQ]` `[REAL]` ARCH backend.
  - **What:** `pacman -Q`; batch `pacman -S --noconfirm --needed`; optional AUR helper discovery (`paru`/`yay`),
    AUR packages clearly marked opt-in (never auto-install helper).
  - **Verification:** Mock + dry-run prints single `pacman -S` line; AUR helper resolution fixture.
  - **Depends:** P3.1

- **P3.6** `[SEQ]` Flatpak backend (`lib/pkg.sh` flatpak sub-module).
  - **What:** `flatpak remote-add --if-not-exists flathub` (fixes prototype bug #2), user/system install detection,
    batch `flatpak install --noninteractive`, `flatpak info` queries, `flatpak list` for export.
  - **Verification:** Dry-run prints remote-add-if-missing + one install command; query of missing app returns not-installed;
    real check in container when flatpak runtime available.
  - **Depends:** P3.1

- **P3.7** `[SEQ]` `[MOCK]` Mock package backend.
  - **What:** Backend that records every invocation to a file and answers "installed" from a fixture set; used by all
    downstream unit tests and by `--dry-run` rendering. (Deviation: pulled forward from the originally-suggested P10.)
  - **Verification:** Recorded log matches expected call sequence for a fixture `install_batch`.
  - **Depends:** P3.1

- **P3.8** `[SEQ]` `[MOCK]` Batch planner.
  - **What:** Union package requests across modules → diff against installed → single per-family transaction; emits the
    exact commands the backend would run (for dry-run display); dedupes duplicates; handles family-specific package lists.
  - **Verification:** Fixture: 3 modules requesting overlapping sets → one transaction, requests after diff contain only
    uninstalled; dry-run shows exactly one dnf/apt/pacman line.
  - **Depends:** P3.2, P3.3, P3.4, P3.7

- **P3.9** `[SEQ]` `[MOCK]` Verify primitives.
  - **What:** `pkg_verify_packages <list>` returns per-package present/missing; used by `setup verify` (P9.2).
  - **Verification:** Fixture backends: present + missing mix reported correctly.
  - **Depends:** P3.8

### 5. Verification criteria
- Mock full-plan path passes; dry-run emits exactly one install transaction per family; no sudoers edits; repo add is `--if-not-exists`.

### 6. Expected files / components affected
- `lib/pkg.sh` (interface + flatpak), backend files `lib/pkg/*.sh` (rpm/deb/arch/mock), or equivalent split inside `lib/pkg.sh`.

### 7. Risks or blockers
- dnf5 vs dnf behavioral drift (Fedora 41+) → isolation in one backend + real check.
- Old repos/config must never be overwritten (only `--if-not-exists` additive changes).
- Mock must faithfully model "installed" state or tests give false confidence.

### 8. Definition of Done
- All backends implement the contract; planner produces single batched transaction; mock + dry-run cover every module path in P4+.

---

## P4 — Module System & Profiles

### 1. Phase objective
Implement the module contract, declarative list parsers, loader/validator, dependency ordering with
cycle detection, risk levels, profile loading, the selection UI, the module runner, and status tracking.

### 2. Why this phase exists
Everything user-facing (P5–P8) is expressed as modules. A correct, boring module framework is what makes
adding features trivial later and keeps the codebase castle-on-sand-free.

### 3. Prerequisites / dependencies
- P2 (ui/state/run/fs), P3.8 (batch planner for the runner's package step).

### 4. Ordered tasks

- **P4.1** `[SEQ]` `[MOCK]` Module contract + loader (`lib/modules.sh`).
  - **What:** Define metadata vars (`MODULE_ID/TITLE/DESCRIPTION/RISK/DEFAULT/DEPENDS`), load optional `run()`/`verify()`
    hooks, define list-file naming (`packages.list`, `packages.rpm.list`, `packages.deb.list`, `packages.arch.list`, `flatpaks.list`).
  - **Verification:** Loader fixture: a minimal module dir parses; unknown metadata key warnings; missing dir errors; family merging rules per P4.3.
  - **Depends:** P2.8, P3.8

- **P4.3** `[SEQ]` `[MOCK]` List-file parsers.
  - **What:** Parse commentable/blank-tolerant line lists; dedupe; merge `packages.list` + family override `.rpm/.deb/.arch`
    (family list replaces/overrides common entries — document exact precedence).
  - **Verification:** Fixture lists (comments, dupes, family override) produce the documented merged result.
  - **Depends:** P4.1

- **P4.2** `[SEQ]` `[MOCK]` Module validation + `./setup list`.
  - **What:** Reject unknown metadata keys, missing lists referenced, duplicate module ids, unsupported-family modules;
    `list` renders id, title, risk, default-on, and current status from the state registry.
  - **Verification:** Invalid fixture module → clear validation error; `./setup list` output verified with fixture modules.
  - **Depends:** P4.1

- **P4.4** `[SEQ]` `[MOCK]` Dependency ordering + cycle detection.
  - **What:** Topological sort of `MODULE_DEPENDS`; cycle detection with a human-readable report.
  - **Verification:** Fixture: valid DAG orders correctly; A→B→A errors with the cycle path printed.
  - **Depends:** P4.1

- **P4.5** `[SEQ]` Profile loader.
  - **What:** `profiles/*.conf` = ordered module lists; create `minimal`, `desktop`, `developer`, `full` profiles with
    placeholder/actual module sets (content finalized in P5–P8); merge profile + CLI-specified modules; support `--profile`.
  - **Verification:** Fixture: profile → resolved module set; CLI overrides; mutual-exclusion/conflict handling errors.
  - **Depends:** P4.3, P4.4

- **P4.6** `[SEQ]` `[MOCK]` Module runner.
  - **What:** Plan assembly (gather per-module packages/flatpaks → P3.8 batch), confirmation flow (dry-run summary screen),
    ordered execution of `run()` hooks, state marking, failure policy (safe-continue vs stop for high-risk/destructive),
    end-of-run summary via `io.sh`.
  - **Verification:** Mock end-to-end: three modules run in dependency order, packages batched once, state registry updated,
    failure mid-run logged and resumed correctly (state already-completed modules skipped).
  - **Depends:** P4.4, P4.5, P3.8

- **P4.7** `[SEQ]` Selection UI.
  - **What:** Interactive multi-select (defaults = profile), bracket-notation toggle UI re-render; non-interactive `--yes`
    path; `--list` path; risk-gated confirmation (high-risk shown red, requires explicit opt-in).
  - **Verification:** Scripted stdin fixture toggles selections; `--yes` bypasses; high-risk triggers explicit confirm required.
  - **Depends:** P4.6, P2.1 (ui), P2.2 (`--yes`)
  - **Note:** risk gating UI is shared with P8.3.

### 5. Verification criteria
- Two modules + profiles run end-to-end on the mock backend; validation rejects bad fixtures; `list` output is accurate.

### 6. Expected files / components affected
- `lib/modules.sh`, `profiles/{minimal,desktop,developer,full}.conf`, `lib/cli.sh` (`list`/`install` real wiring).

### 7. Risks or blockers
- Over-engineering the contract: keep it to metadata vars + optional hooks; anything more is deferred.
- Dependency cycles must fail loudly, not silently reorder.

### 8. Definition of Done
- Framework proven by fixture run; validation + ordering + risk gating working; profiles loadable.

---

## P5 — Base Modules

> **Phase status: COMPLETE.** P5.1–P5.8 all DONE + committed (see ledger). P5 Senior Closure Review:
> **PASS · CLOSURE-READY**, no blocking issues. Real **mutating** `desktop` run remains owner-gated
> (dry-run-verified only). P6 not started — requires owner approval.

### 1. Phase objective
Implement the always-useful modules: `core`, `flatpak`, `git`, `fonts`, `terminal` (incl. oh-my-posh +
atuin + aliases). These form the `desktop` / `minimal` default experience and validate the P4 framework
for real.

### 2. Why this phase exists
Base modules are the first user-visible value and the earliest real (non-mock) exercise of the runner.
Getting them right proves the framework before the bigger module sets.

### 3. Prerequisites / dependencies
- P4 (all tasks).
- Oh-my-posh/atuin downloads require network (pinned releases).

### 4. Ordered tasks

- **P5.1** `[SEQ]` Module `core`. **DONE** · COMMITTED `1f89e24` (see ledger).
  - **What:** `module.sh` (risk none, default on) + `packages.list` + family overrides: git, curl, wget, vim/neovim, fzf,
    bat, btop, htop, tmux, unzip, gnupg, fastfetch, flatpak, e2fsprogs, etc. (curated, no `sed`/`gpg`/`xdg-utils` noise).
  - **Verification:** `./setup install core --yes --dry-run` shows one batched install; verify lists packages present on mock.
  - **Depends:** P4.6 [and P5.7 for the profile wiring of minimal]

- **P5.2** `[SEQ]` Module `flatpak`. **DONE** · COMMITTED `b63764b` (see ledger).
  - **What:** Flathub ensure + base Flatpak apps (Extension Manager, Bitwarden, Resources, …, curated small set).
  - **Verification:** Dry-run: single remote-add-if-missing + one flatpak install batch; mock installed-state honored.
  - **Depends:** P4.6, P3.6

- **P5.3** `[SEQ]` `[MOCK]` Module `git`. **DONE** · COMMITTED `c1a3e33` (deviation: interactive name/email prompt omitted by design — see ledger; identity via FS_GIT_USER_NAME/FS_GIT_USER_EMAIL env).
  - **What:** Managed `.gitconfig`: init.defaultBranch, edge/merge config, diff/pager; optional interactive name/email prompt;
    never clobber existing config (merge, not replace).
  - **Verification:** Fixture home: config file written/merged correctly; second run idempotent; existing user keys preserved.
  - **Depends:** P4.6 [P2.5 managed-block]

- **P5.4** `[SEQ]` `[REAL]` Module `fonts`. **DONE** · COMMITTED `fb11fd7` (see ledger).
  - **What:** Distro font packages per family (`fira-code`, `jetbrains-mono`, `noto-*`, …) + `config/nerdfonts.list`
    (family:name:version) → download pinned Nerd Font release zips to `~/.local/share/fonts` + incremental `fc-cache`;
    optional local `assets/fonts/` dir honored if present.
  - **Verification:** `fc-list` gains the expected families on a real host; re-run skips already-installed files (no 250MB copy);
    dry-run lists the exact downloads.
  - **Depends:** P4.6, P3.8

- **P5.5** `[SEQ]` `[REAL]` Module `terminal` — prompt & aliases. **DONE** · COMMITTED `1d06b0f` (see ledger).
  - **What:** Installed via managed block (P2.5), never whole-file `.bashrc` rewrite: aliases file + sourcing guard;
    oh-my-posh pinned release → `~/.local/bin`, themes to `~/.config/oh-my-posh/themes`, guarded init line.
  - **Verification:** Managed block idempotent; bash -l produces prompt line; `~/.bashrc.bak` existing content preserved;
    re-run byte-stable.
  - **Depends:** P4.6, P2.5, P5.4 (fontfamily present)

- **P5.6** `[SEQ]` `[REAL]` Module `terminal` — atuin. **DONE** · COMMITTED `11e15c3` (see ledger).
  - **What:** Pinned GitHub release binary (arch-aware x86_64/aarch64) to `~/.local/bin`; guarded init in managed block.
  - **Verification:** `atuin --version`; re-run skips download; uninstall documented.
  - **Depends:** P5.5

- **P5.7** `[SEQ]` Profile wiring for base. **DONE** · COMMITTED `ab07887` (see ledger).
  - **What:** `minimal` = core+flatpak; `desktop` = minimal + git, fonts, terminal; `setup install --profile minimal --yes`
    runs clean end-to-end.
  - **Verification:** Full dry-run + mock run pass; real run (when OS allows) completes without error.
  - **Depends:** P5.1–P5.6

- **P5.8** `[SEQ]` Closure fix: bare install family→backend resolution. **DONE** · COMMITTED `c964fd7` (see ledger).
  - **What:** `lib/bootstrap.sh` resolves family→backend in-caller (was subshell-swallowed), so a bare `./setup install
    --profile …` works on a real host without explicit `FS_PKG_BACKEND`/`FS_DISTRO_FAMILY`.
  - **Verification:** Fixture regression cell (fake dnf5/dnf/rpm + osrel2, dry-run, seams unset) rc0 + stderr-clean;
    bare host dry-run rc0 renders the backend install line; pre-fix mutation 62/5 FAIL.
  - **Depends:** P5.7

### 5. Verification criteria
- Base modules pass dry-run + mock; on a real host: fonts/prompt/atuin actually work; all idempotent on 2nd run.

### 6. Expected files / components affected
- `modules/{core,flatpak,git,fonts,terminal}/`, `config/nerdfonts.list`, `config/nerdfonts.sha256`, `profiles/minimal|desktop`.

### 7. Risks or blockers
- Pinned release URLs/tarball layouts change → pin version + verify archive structure; failure exits with clear message.
- Nerd Font archives are big → download only what the user selected.

### 8. Definition of Done
- Desktop profile installs cleanly and idempotently on a real host; aliases/prompt/fonts verified.

---

## P6 — GNOME Modules

> **Phase status: COMPLETE.** P6.1–P6.6 all DONE + committed (see ledger). P6 Senior Closure
> Review: **PASS · CLOSURE-READY**, no blocking issues (final regression: 29-fixture battery
> all rc0, smoke 125/0 rc0; P6.6 red/green reproduced by mutation). Carried owner-decision NBs
> — **recorded as deferred, NOT speculative fixes** (§13): (1) NB2 — a capability skip
> (`skipped (not GNOME)`) marks the module completed, so `--force` cannot re-run it on a later
> GNOME run (`lib/runner.sh:176` skip, mark at `:194`; pre-existing semantics; owner decision required before it
> affects headless/SSH installs); (2) the `gnome-*` modules are **NOT wired into any profile** —
> run them explicitly via `./setup install --yes <id>` (P6.2 NB8 / P6.4 NB10 / P6.5 NB-carried);
> (3) NB7 — curated `<Super>I`/`<Alt>T` intentionally reclaim the stock
> control-center/terminal bindings (idempotent, P6.2 scope; surfaced in phase report). AGENTS
> §2/§3 phase-boundary sync applied in the closure commit. P7 not started — requires owner approval.

### 1. Phase objective
Implement GNOME-facing modules: base settings, dock favorites (merge-safe), custom shortcuts (fixed from
prototype bug), wallpaper, extensions, themes/icons/cursors, and graceful capability gating.

### 2. Why this phase exists
GNOME configuration is the most fragile area (version drift, Wayland, dconf). It must be isolated behind
a small gsettings layer so nothing else depends on it, and every failure is graceful.

### 3. Prerequisites / dependencies
- P4 (modules framework), P5 (fonts for themes that reference font settings where relevant).
- Live GNOME session only required for the `[REAL]` verification tasks; logic is mock-testable.

### 4. Ordered tasks

- **P6.1** `[SEQ]` `[MOCK]` Implement `lib/gnome.sh` gsettings layer. **DONE** · COMMITTED `c8c335d` (see ledger).
  - **What:** Safe `gsettings get/set` wrappers (skip if already set, quote/array handling with explicit GVariant building),
    proper custom-keybinding array read→merge→write (prototype bug #4), Gui-safe `gnome_extensions` presence check.
  - **Verification:** Fixture gsettings output arrays parse/merge correctly; idempotent sets are no-ops; malformed keys error safely,
    never via sed rewriting of system files. **MET** (fixture 109 asserts, incl. no-sed/awk mechanical pin).
  - **Depends:** P2.8 (run/io) ✓

- **P6.2** `[SEQ]` `[REAL]` Module `gnome-base`. — **DONE** · **COMMITTED** `b62fef2` (ledger row in table above).
  - **What:** Dock favorites that MERGE with existing favorites (preserve user appends); custom shortcuts (Resources/Settings/
    Terminal/Mic) via P6.1; wallpaper from `assets/wallpaper/` if present; harmless defaults only.
  - **Verification:** On real GNOME: favorite-apps contains existing + new; shortcuts registered and trigger; wallpaper applied.
  - **Depends:** P6.1

- **P6.3** `[SEQ]` `[REAL]` Module `gnome-extensions`. **DONE** · **COMMITTED** `c448465` (see ledger).
  - **What:** Install distro-packaged extensions where available (dash-to-dock, user-theme…); enable installed via
    `gnome-extensions enable <uuid>`; detect GNOME version and report compatibility notes; `--browse` (opt-in) opens a
    max-2 URL list; never loops opening tabs (prototype bug).
  - **Verification:** On real GNOME: provided extensions enabled; re-run stable; incompatible-extension message shown.
  - **Depends:** P6.1, P4.6

- **P6.4** `[SEQ]` `[REAL]` Module `gnome-theme`. **DONE** · **COMMITTED** `11d6293` (ledger row in table above).
  - **What:** Apply theme/cursor from `assets/` or interactive `~/.themes`/`~/.icons` selection; **do not** force-reset icon theme
    (preserve user choice — fixes prototype bug); gtk-3.0 bookmarks dedupe (no repeated `~/Github` lines).
  - **Verification:** Selected theme applied; existing icon theme untouched; bookmarks file deduplicated.
  - **Depends:** P6.1

- **P6.5** `[SEQ]` `[PAR]` `[MOCK]` Capability gating. — **DONE** · **COMMITTED** `dfd986e` (ledger row in table above).
  - **What:** Skip all GNOME modules when `XDG_CURRENT_DESKTOP` ≠ GNOME, SSH/headless, or missing gsettings; explicit
    `--force` adverse-case path for advanced users; verification hooks check actual gsettings values.
  - **Verification:** Fixture env → modules report "skipped (not GNOME)"; verify hook passes on applied values. — **met**: `mod_gnome_gate` cell `verify gated` rc0 `skipped (not GNOME) (not a GNOME session (XDG_CURRENT_DESKTOP='KDE'))`; `verify pass` cells rc0 `verify ok` + `verify passed`.
  - **Depends:** P6.1

- **P6.6** `[SEQ]` `[REAL]` Idempotency sweep for all GNOME modules. **DONE** · **COMMITTED** `2668692` (ledger row in table above).
  - **What:** Second full run produces zero changes (favorites exactly merged once, no dup shortcuts, no dup bookmark lines,
    wallpaper stable).
  - **Verification:** `gsettings`/file diffs empty between run 2 and 3. — **met**: `tests/fixtures/idempotency.sh` **43/0** rc0
    byte-identical ×3 (md5 `6b471d051860e0126ba16ceedb839380`): gnome-base R1 merges favorites once + 4 curated shortcuts (no
    dup) + 2 wallpaper URIs, state PERSISTED into the fake gsettings file (round-trip), R2/R3 against R1's own resulting state =
    zero writes + state diff empty vs pre-run; gnome-theme R1 dedupes bookmarks once (`1 duplicate line(s) removed`), R2/R3
    byte-identical; gnome-extensions R1 enables once, R2/R3 zero enables; shared-FS_HOME re-run `already completed` / `1 skipped`
    (P6.5 NB2). Red/green (4 mutations re-run by reviewer): revert lib compare → `41/2` exactly R2/R3 zero-write FAILS; revert
    verify compare → gate `68/4` (quoted-URI cell); disable fake `set` persistence → `39/4`; break favs dedupe → `39/4` at R2
    (closure re-measure on committed bytes = `38/5`) caught by
    state diffs. **LIVE sweep** (owner-authorized, real GNOME 50.1): gnome-base R1 = exactly 16 writes (1 fav merge + 4×3
    shortcut sets + 1 array merge + 2 wallpaper), R2/R3 = 0 with `already at target; no-op` firing (old code re-wrote wallpapers
    every run — **real bug found + fixed**: `gnome_gsettings_set` compare at `lib/gnome.sh` now also matches the single-quoted
    rendering `'file:///x'` real `gsettings get` returns); gnome-theme 3× 0 writes (Aurora/Yaru); gnome-extensions 3× 0 enables
    (dash-to-dock already enabled, user-theme not installed); `baseline.snap == restore.snap`, session re-verified pristine
    (favorites 8, `custom-keybindings @as []`, warty URIs, bookmarks md5 `2e5e03c6…`, dash-to-dock enabled). NB8 note: the live
    session was briefly mutated during a debug `-x` pipe run before the sweep (restored manually), then guarded by a sweep
    preflight abort (pristine favorites+`@as []` check); the final sweep+restore run above stands clean.
  - **Depends:** P6.2, P6.3, P6.4

### 5. Verification criteria
- GNOME logic fully mock-tested; on a real session: favorites merge, shortcuts work, extensions enable, bookmarks dedupe; gating correct.

### 6. Expected files / components affected
- `lib/gnome.sh`, `modules/{gnome-base,gnome-extensions,gnome-theme}/`, `assets/wallpaper/`, wall assets policy.

### 7. Risks or blockers
- GNOME Shell version differences break extension enabling → always report vs. fail.
- Wayland vs X11 differences in some extensions → capability check uses GNOME version, not just XDG.
- Cannot run real-GNOME steps in CI → keep `[MOCK]` parity tests + flagged `[REAL]` post-merge manual validation.

### 8. Definition of Done
- All GNOME modules idempotent and gated; real-session validation checklist completed.

---

## P7 — Application & Development Modules

### 1. Phase objective
Implement `apps`, `media`, `dev`, `containers`, `vscode`, `chrome`.

### 2. Why this phase exists
These are the "volume" modules a developer profile needs. They are mutually independent, so this phase is
highly parallelizable; each is a thin module over the P3/P4 infrastructure.

### 3. Prerequisites / dependencies
- P4 + P3 (package backend/flatpak/repo primitives). Completely independent of each other (parallel group).

### 4. Ordered tasks

- **P7.1** `[PAR]` Module `apps` — curated Flatpak desktop apps (Thunderbird, LibreOffice, qBittorrent, Discord, …).
  - **Verification:** Dry-run single flatpak batch; mock verify.
  - **Depends:** P4.6, P3.6

- **P7.2** `[PAR]` `[REAL]` Module `media` — OBS + media flatpaks; family-specific obs packaging where the distro differs.
  - **Verification:** Mock + container/real check for obs package name.
  - **Depends:** P4.6

- **P7.3** `[PAR]` Module `dev` — toolchains: python3-pip (python-pip arch), nodejs, gcc/make/cmake/clang, jupyter-notebook name mapping per family.
  - **Verification:** Fixture family lists map package names correctly; dry-run single batch.
  - **Depends:** P4.6

- **P7.4** `[PAR]` `[REAL]` Module `containers` — podman/docker, compose, buildah, skopeo; docker group membership handled explicitly (not silently).
  - **Verification:** Dry-run; real check of package presence post-install.
  - **Depends:** P4.6

- **P7.5** `[PAR]` `[REAL]` Module `vscode` — official repo per family (rpm/deb `vscode.repo`/`.list`, AUR for arch), GPG import with
  fingerprint check; option for `code` via flatpak as alternative.
  - **Verification:** Repo file written `--if-not-exists`; GPG key verified; dry-run shows repo-add + install; real run on Fedora container.
  - **Depends:** P4.6, P3 (repo primitives), P3.5 if split

- **P7.6** `[PAR]` `[REAL]` Module `chrome` — distro-native bundle download (pinned arch URL), integrity note, flatpak alternative
  documented; verification of installed `.desktop`.
  - **Verification:** Dry-run shows wget+install_local; real run installs and `.desktop` exists.
  - **Depends:** P4.6, P3.2/3.3 (install_local)

- *(P3.5 from the phase list, repo primitives: rpmfusion / vscode-repo definitions, is folded into the backends'
repo-add support built in P3.2/P3.3 and consumed by P7.5.)*

### 5. Verification criteria
- All six modules dry-run cleanly on mock; real-system checks where flagged pass on the matching host.

### 6. Expected files / components affected
- `modules/{apps,media,dev,containers,vscode,chrome}/` + list files per family.

### 7. Risks or blockers
- Distro package-name drift (e.g. `python3-pip` vs `python-pip`, `nodejs` vs `node`) — handled by family lists + verify.
- VS Code GPG import needs fingerprint validation, not blind import.

### 8. Definition of Done
- `developer` profile (base + these) installs and verifies on a real host.

---

## P8 — High-Risk Modules

### 1. Phase objective
Implement `dns` and `locale` as explicitly opt-in, high-risk modules with safe backups, revert documentation,
and verification — never default-on.

### 2. Why this phase exists
Both touch system state beyond user dotfiles and were buggy/unsafe in the prototype (resolv.conf + chattr;
locale rewrite). They must be isolated behind the risk gating (P4.7) and behave reversibly.

### 3. Prerequisites / dependencies
- P4 (risk gating), P3 (no — dns/locale are system-config, mostly independent of pkg backend), P2 (state/fs backups).

### 4. Ordered tasks

- **P8.1** `[SEQ]` `[DESTROY]` `[REAL]` Module `dns` (NetworkManager-based).
  - **What:** For NM: `nmcli connection modify <active> ipv4.dns 8.8.8.8 8.8.4.4 ipv4.ignore-auto-dns yes`; never touch
    `resolv.conf`/`chattr`; explicit "high risk" confirmation; `--revert` documented (restore auto-dns); verify resolution works.
  - **Verification:** On real NM host: DNS applied, resolution check passes, revert restores prior state; non-NM host → graceful skip.
  - **Depends:** P4.6/4.7, P2.5 (registry of changed connections)

- **P8.2** `[SEQ]` `[DESTROY]` `[REAL]` Module `locale`.
  - **What:** Use `localectl set-locale` on systemd systems (with timestamped backup of `/etc/locale.conf`), language choice
    prompted (EN/AR default English), explicit opt-in; no `source /etc/locale.conf` shell games.
  - **Verification:** `localectl status` reflects change; backup file exists; re-run idempotent.
  - **Depends:** P4.6/4.7, P2.5

- **P8.3** `[SEQ]` `[MOCK]` Risk gating hardening (shared with P4.7).
  - **What:** Ensure high-risk modules are: red-flagged in UI, excluded from every default profile, require explicit `--yes`
    or a direct `install dns` invocation; dry-run shows bold warning lines.
  - **Verification:** Fixture: each default profile excludes both; install path for `dns` without consent blocked.
  - **Depends:** P8.1, P8.2

### 5. Verification criteria
- Defaults never include either module; each requires explicit consent; both reversible and verified on real systems.

### 6. Expected files / components affected
- `modules/{dns,locale}/`, config registry entries for changed NM connections / locale.conf backups.

### 7. Risks or blockers
- NM connectivity outage risk during dns change → verify step with fallback message; never break-in-the-middle.
- Non-systemd environments (rare) → skip with clear message rather than raw file rewrite.

### 8. Definition of Done
- Opt-in flow proven; both modules functional + reversible on a real system; defaults remain clean.

---

## P9 — Verification, Export & Update

### 1. Phase objective
Implement `check` (preflight), `verify` (post-install report), `export` (portable manifest), and explicit `update`.

### 2. Why this phase exists
These are the "transparency" pillars: a beginner gets a health report; an advanced user gets reproducibility.
They close the prototype's biggest gap (no verification at all).

### 3. Prerequisites / dependencies
- P4 (module status), P3 (verify primitives), P6 (gsettings/extensions queries for export), P5–P8 module content.

### 4. Ordered tasks

- **P9.1** `[PAR]` `[MOCK]` `./setup check` (preflight).
  - **What:** Distro known, network reachability (flathub/GitHub), pkgmgr present, non-root + sudo usable, flatpak present,
    disk space note. Exit code reflects WARN vs FAIL.
  - **Verification:** Matrix of fixtures (offline, missing sudo, unknown distro) → correct exit codes + messages.
  - **Depends:** P4.6 (status registry), P2.3

- **P9.4** `[PAR]` `[MOCK]` `./setup update`.
  - **What:** Requires clean git tree (refuse otherwise), checks remote vs local, explicit pull, reports version; replaces the
    prototype's silent auto-pull.
  - **Verification:** Dummy git fixtures: dirty tree → refusal; up-to-date → "already current"; behind → pull planned.
  - **Depends:** P2.2 (cli)

- **P9.2** `[SEQ]` `[MOCK]` `./setup verify`.
  - **What:** Per-module `verify()` hooks + generic checks (packages, flatpaks, repo files, gsettings values, extensions, fonts,
    managed files) → PASS/WARN/FAIL table + aggregate exit code (FAIL>0).
  - **Verification:** Over a mock "half-installed" fixture: correct PASS/WARN/FAIL rows and exit code.
  - **Depends:** P9.1 (shared plumbing), P3.9, P6.5 (gnome verify), P4.6

- **P9.3** `[SEQ]` `[MOCK]` `./setup export`.
  - **What:** Emit `<dir>/manifests/(modules lists)`, `<profile>.conf`, gsettings snapshot (favorites/theme/shortcuts), enabled
    extensions, font list, managed file copies — a tree the tool can re-consume; excludes dependencies, temp state, secrets.
  - **Verification:** Fixture system state → exported dir is re-importable (`install --manifest ...` dry-runs identically); secrets
    provably excluded.
  - **Depends:** P9.2 (queries), P6 (extension/gsettings queries)

- **P9.5** `[SEQ]` `[MOCK]` Summary reporter integration.
  - **What:** After any `install` run: "N modules ok · M skipped · K failed · artifacts in <log>" line; failed steps actionable.
  - **Verification:** Mock run with 1 failure renders correct summary; exit code non-zero.
  - **Depends:** P9.2, P4.6

### 5. Verification criteria
- check/verify/export/update all pass fixture matrices; verify exit codes meaningful; export re-importable; updates explicit.

### 6. Expected files / components affected
- `lib/cli.sh` (subcommands real), `lib/verify.sh`/`lib/export.sh` (or in `modules.sh`), export format docs.

### 7. Risks or blockers
- Export scope creep → keep to intentionally-managed state only, per the audit distinction.

### 8. Definition of Done
- Full CLI surface (`install|list|check|verify|export|update|help|version`) functional + tested.

---

## P10 — Testing & CI

### 1. Phase objective
Formalize testing: Bats harness, shellcheck/shfmt, mock-backend test suites, container smoke tests, GitHub Actions CI.

### 2. Why this phase exists
P2–P9 ship with the ad-hoc `tests/smoke.sh` + fixtures. This phase locks behavior in so future modules (and the
eventual Fedora releases) don't regress.

### 3. Prerequisites / dependencies
- P9 (all CLI surface exists and is testable), P1 structure. Mock envs already in place (`FS_HOME`, `FS_DISTRO_FILE`, `FS_PKG_BACKEND`).

### 4. Ordered tasks

- **P10.1** `[SEQ]` `[MOCK]` Bats harness + refactor smoke tests.
  - **What:** Add `tests/bats` submodule or pinned download, `tests/run` runner, convert `tests/smoke.sh` assertions into Bats,
    CI-friendly TAP output.
  - **Verification:** `tests/run` executes the suite green in a container/CI.
  - **Depends:** P9 (or as soon as core libs exist — can be started from P2.9+)

- **P10.2** `[SEQ]` `[MOCK]` Static analysis setup.
  - **What:** `.shellcheckrc` (SC2230-worthy strictness consistent with project style), `shfmt` rules + `scripts/lint` (or `make lint`).
  - **Verification:** `make lint` passes on all `lib/`/`modules/`/`setup`; CI enforces it.
  - **Depends:** P10.1

- **P10.4** `[SEQ]` `[MOCK]` Mock-backend integration suite.
  - **What:** Full planning/batching/module-run flows on the mock backend; failure-path coverage (partial install, missing flathub,
    interrupted run → state resume).
  - **Verification:** Suite green; a deliberately-broken module case demonstrates resume-without-recursion.
  - **Depends:** P10.1

- **P10.3** `[SEQ]` `[REAL]` Container smoke tests + CI.
  - **What:** GitHub Actions matrix (Fedora latest/41, Debian stable, Arch base) — root container runs `setup check`, `install minimal --yes --dry-run`,
    and (where possible) real `minimal` install; GNOME-only steps skipped explicitly.
  - **Verification:** CI pipeline green across the matrix; dry-run produces no writes in containers.
  - **Depends:** P10.1, P10.4

- **P10.5** `[SEQ]` `[MOCK]` Regression test for documented prototype bugs.
  - **What:** Lock in fixes as tests: no sudoers writing anywhere, no `.bashrc` wholesale overwrite, no flatpak install before
    flathub remote, no sed-based gsettings array rewrite, no 250MB font copy, no tab-loop extension installer.
  - **Verification:** Each regression has a named test that fails on the old behavior if reintroduced.
  - **Depends:** P10.4

### 5. Verification criteria
- CI green: lint + unit + container matrix; regression suite pins the prototype-bug fixes.

### 6. Expected files / components affected
- `tests/**`, `.github/workflows/*.yml`, `.shellcheckrc`, `Makefile`/`scripts/lint`, bats vendoring.

### 7. Risks or blockers
- Bats vendoring adds a submodule → prefer a pinned curl-downloaded bats in CI install step to avoid submodule friction.
- Container smoke cannot exercise GNOME/sudoer-specific paths — that's honest scope, marked `[REAL]` elsewhere.

### 8. Definition of Done
- `make test` green locally and in CI; matrix containers pass; prototype-bug regressions enforced by tests.

---

## P11 — Documentation & Release Readiness

### 1. Phase objective
Rewrite README + docs, finalize help text, clean the tree, and complete one authoritative end-to-end
validation pass for release.

### 2. Why this phase exists
A tool that can't be understood (beginner) or extended (advanced) fails its mission. Docs are the last
mile of the usability promise; the full validation pass de-risks releasing.

### 3. Prerequisites / dependencies
- P9 (final CLI), P10 (CI green), P5–P8 (stable module behavior).

### 4. Ordered tasks

- **P11.1** `[SEQ]` Rewrite `README.md` (beginner→advanced).
  - **What:** What / why / who / is-it-safe / install (`git clone && ./setup`) / what it installs / customize (profiles, modules) /
    run-selected-features / update / export / troubleshoot / verify. Removes prototype ghost options and stale multi-distro claims
    (now honest about 3 supported families + derivatives).
  - **Verification:** README covers the 11 required answers; copy-review by an external reader; no stale claims.
  - **Depends:** P9, P10

- **P11.2** `[SEQ]` Write `docs/{ARCHITECTURE,DEVELOPING,TROUBLESHOOTING}.md`.
  - **What:** Architecture (libs, module contract, backends, data-flow diagram), developing (add a module checklist, env test hooks,
    list format rules), troubleshooting (state dir, logs, recovery, common failures).
  - **Verification:** Cross-checked against actual code by following a module-addition walkthrough.
  - **Depends:** P11.1

- **P11.3** `[SEQ]` Finalize `--help` + examples.
  - **What:** Help text parity with README; 3–4 copy-paste examples (interactive, `--profile developer --yes`, dry-run, verify).
  - **Verification:** `./setup --help` output reviewed and consistent.
  - **Depends:** P11.1

- **P11.4** `[SEQ]` Cleanup + hygiene audit.
  - **What:** Remove stale files, verify `.gitignore` covers all runtime artifacts, delete leftover fixture/test scratch,
    ensure no secrets/URLs of personal machines, confirm root of repo has only intended files.
  - **Verification:** `git status` shows a clean, intentional tree; CI green on final state.
  - **Depends:** P11.3

- **P11.5** `[SEQ]` `[REAL]` `[DESTROY]` Release validation on a real Fedora.
  - **What:** Fresh Fedora (or VM): `./setup --profile desktop` full run → `./setup verify` mostly PASS (GNOME steps validated on
    desktop session); re-run idempotency; document results.
  - **Verification:** Checklist in TROUBLESHOOTING/README updated with real-run results.
  - **Depends:** P11.4 (do not *release* until real-run clears; can be done in parallel with P11.4 on a spare VM)

### 5. Verification criteria
- README/doc accuracy, help parity, clean tree, CI green, one authoritative real-Fedora run documented.

### 6. Expected files / components affected
- `README.md`, `docs/*`, help text in `lib/cli.sh`, `.gitignore`, any final polish.

### 7. Risks or blockers
- Real-run surprises (dnf5 quirks, NM behavior, flatpak) — expected; treat findings as tasks in the current phase, not scope creep.

### 8. Definition of Done
- Docs complete; tree clean; CI green; real-Fedora run passes verify; ready for a v3.0.0-style tagged release.

---

## Analysis: dependency chains, parallelism, real-system and destructive tasks

### Critical dependency chains (must stay sequential)
1. `P0.1 → P0.2 → P0.3 → P0.4`
2. `P1.1 → P1.2 → (P1.4) → P1.3` (deletion last)
3. `P2.1 → P2.2 → P2.8` and `P2.1 → P2.9`; `P2.6 → P2.7`
4. `P3.1 → {P3.2,P3.3,P3.4,P3.6,P3.7} → P3.8 → P3.9`
5. `P4.1 → {P4.2,P4.3,P4.4} → P4.5 → P4.6 → P4.7`
6. `P4.6 → P5.1…P5.6 → P5.7`
7. `P6.1 → {P6.2,P6.3,P6.4,P6.5} → P6.6`
8. `P8.1/P8.2 → P8.3`
9. `P9.1/P9.4 → P9.2 → P9.3 → P9.5`
10. `P10.1 → P10.2/P10.4 → P10.3/P10.5`
11. `P11.1 → P11.2 → P11.3 → P11.4 → P11.5`

**Critical (longest) path through the roadmap:**
`P0 → P1.1 → P1.2 → P2.1 → P2.2 → P3.1 → P3.8 → P4.1 → P4.3 → P4.4 → P4.5 → P4.6 → P5.x → P5.7 → P9.2 → P9.5 → P10.1 → P10.4 → P10.3 → P11.1 … P11.5`

### Parallelizable task groups
- P2 post-`io`: `P2.3 distro`, `P2.4 state`, `P2.5 fs` — independent `[PAR]`.
- P3 backends: `P3.2 rpm`, `P3.3 deb`, `P3.4 arch`, `P3.6 flatpak`, `P3.7 mock` — parallel after `P3.1`.
- P4: `P4.2`, `P4.3`, `P4.4` — parallel after `P4.1`.
- P5 content: `P5.1`, `P5.2`, `P5.3` parallel; then `P5.4`, `P5.5`, `P5.6` parallel.
- P6: `P6.2`, `P6.3`, `P6.4`, `P6.5` — parallel after `P6.1`.
- P7: all of `P7.1`–`P7.6` — fully parallel.
- P8: `P8.1` and `P8.2` — parallel.
- P9: `P9.1` and `P9.4` — parallel.
- P10: `P10.1` and `P10.2` (lint config) — can overlap.

### Tasks requiring real-system testing (`[REAL]`)
`P3.2 rpm`, `P3.3 deb`, `P3.4 arch` (backend correctness), `P5.4 fonts`, `P5.5 terminal/prompt`, `P5.6 atuin`,
`P6.2 gnome-base`, `P6.3 gnome-extensions`, `P6.4 gnome-theme`, `P6.6 gnome idempotency`,
`P7.2 media`, `P7.4 containers`, `P7.5 vscode`, `P7.6 chrome`,
`P8.1 dns`, `P8.2 locale`, `P10.3 container smoke`, `P11.5 final Fedora run`.

### Destructive / special-care tasks (`[DESTROY]`)
`P1.3` (deletes prototype — git-recoverable), `P8.1` (network config), `P8.2` (system locale),
`P11.5` (real-system run). All others are additive or user-scope (managed blocks, backups).

### Architecture concerns surfaced while building this roadmap
1. **Mock-before-real ordering:** The mock package backend was pulled from the suggested P10 into `P3.7` so P4–P9 tests never need root. Formal Bats/CI remain in P10.
2. **Test injection envs** (`FS_HOME`, `FS_DISTRO_FILE`, `FS_PKG_BACKEND`) must be honored by every lib from day one, or the mock story collapses. Enforced in P2.3/P2.4/P3.1.
3. **dnf5 vs dnf** is a detection problem (Fedora 41+), not a backend fork: `lib/distro.sh` picks the binary; `lib/pkg.sh` rpm backend shells out to whichever.
4. **Flatpak-first** for GUI apps keeps dpkg/apt/dnf surface small and repo proliferation low — reinforced repo primitives (`--if-not-exists`, fingerprint-checked GPG) in P3/P7.
5. **No sudoers, ever.** The runner (`P2.7`), sudo policy (`P2.6`), and a regression test (`P10.5`) triple-lock this.
6. **Module contract restraint:** metadata vars + optional hooks + declarative lists only. Anything richer is deferred — the runner must stay boring.
7. **`P11.5` is a release gate**, not cleanup: real-Fedora findings are to be fixed within P11, and the release tag only lands after the real run verifies.

---

## Dependency-aware execution order (recommended path)

```
Wave  0  : P0.1 → P0.2 → P0.3 → P0.4
Wave  1  : P1.1 → P1.2 → P1.4 → P1.3
Wave  2  : P2.1
Wave  3  : P2.2 | P2.3 | P2.4 | P2.5          (parallel)
Wave  4  : P2.6 → P2.7 || P2.8 → P2.9
Wave  5  : P3.1
Wave  6  : P3.2 | P3.3 | P3.4 | P3.6 | P3.7   (parallel)
Wave  7  : P3.8 → P3.9
Wave  8  : P4.1
Wave  9  : P4.2 | P4.3 | P4.4                (parallel)
Wave 10  : P4.5
Wave 11  : P4.6 → P4.7                        (P4.7 shares P8.3 risk gating)
Wave 12  : P5.1 | P5.2 | P5.3 → P5.4 | P5.5 | P5.6 → P5.7
Wave 13  : P6.1 → P6.2 | P6.3 | P6.4 | P6.5 → P6.6
Wave 14  : P7.1 | P7.2 | P7.3 | P7.4 | P7.5 | P7.6  (all parallel)
Wave 15  : P8.1 | P8.2 → P8.3
Wave 16  : P9.1 | P9.4 → P9.2 → P9.3 → P9.5
Wave 17  : P10.1 → P10.2 | P10.4 → P10.3 | P10.5
Wave 18  : P11.1 → P11.2 → P11.3 → P11.4 → P11.5
```

Mid-transition safety rule: **never destroy a file whose replacement has not been proven by its
verification criteria** (models P1.3's rule — deletion only after skeleton + bootstrap + baseline tag).

---

## Baseline notes (captured for P0.3)

- Repo: `linux-postinstall`, branch `main`, HEAD `048f969`, working tree clean at roadmap creation.
- Baseline tag: `proto-baseline` → `048f969` (created during P0.2).

### Canonical inventory (P0.3, verified at baseline)
- Top level: `setup.sh` (145 lines, `set -e`), `README.md` (115 lines, MIT), `LICENSE`, `.gitignore` (29 lines).
- `scripts/`: 15 files = 14 `.sh` + 1 `scripts/README.md`.
- `additions/`: `fonts/` (234 files), `icons/` (1 file: `folder-github.svg`), `shell_conf` (68 lines), `wallpaper.jpg` (2560×1440 JPEG).
- Data points: 234 font files (Inter x3 point-sizes, FiraCode/Meslo Nerd Font variants, Montserrat, OpenSauce, Ubuntu, Cairo…), no font license files committed.

### Feature → module disposition map
| Feature (prototype script) | New module | Disposition |
|---|---|---|
| install_apps (dnf/app/flatpak) | `core`, `flatpak`, `apps`, `media`, `dev`, `containers` | rewrite (batch + family backends) |
| install_apps (Chrome/VS Code) | `chrome`, `vscode` | rewrite (repo/bundle + fingerprint GPG) |
| install_fonts | `fonts` | rewrite (dnf + nerd-on-demand, drop 250MB blob) |
| set_aliases | `terminal` | rewrite (managed block, no .bashrc clobber) |
| terminal_themes | `terminal` | rewrite (pinned ~/.local/bin, no chsh surprise) |
| install_atuin | `terminal` | rewrite (pinned release) |
| set_favorite_apps | `gnome-base` | rewrite (merge-safe favorites) |
| add_custom_shortcut | `gnome-base` | rewrite (fixed array bug) |
| set_wallpaper | `gnome-base` | rewrite (optional asset) |
| gnome_themes | `gnome-theme` | rewrite (preserve user icon choice) |
| icons_and_cursors | `gnome-theme` | rewrite (bookmark dedupe, no Adwaita force) |
| gnome_extensions | `gnome-extensions` | rewrite (CLI enable + opt-in browse, no tabs) |
| change_language | `locale` | rewrite (localectl, opt-in high risk) |
| add_google_dns | `dns` | rewrite (NetworkManager, opt-in high risk) |
| utils.sh (distro) | `lib/distro.sh` | rewrite (3 families + derivatives, dnf5 detection) |
| setup.sh (orchestration) | `setup` + `lib/*` | rewrite (CLI, dry-run, profiles, verify) |

### Per-script behavior summaries (P0.3 — reference for reconstruction)
- **setup.sh** — refuses root; then **silent auto-update**: `git ls-remote` vs `git rev-parse HEAD`; if different, `git pull` + exit.
  **Edits `/etc/sudoers`** to set `Defaults timestamp_timeout=-1` (sed/append), restore-by-sed later (only guarded in the invalid-option path).
  Dispatches `bash scripts/<x>.sh` per subcommand (`all`, `install_apps`, `add_custom_shortcut`, `add_google_dns`, `gnome_extensions`,
  `change_language`, `install_atuin`, `install_fonts`, `set_aliases`, `set_favorite_apps`, `themes`, `help`, `version`);
  **ignores sub-script exit codes**; always prints "Installation complete."
- **install_apps.sh** — distro switch via `utils.sh`; 28-item package array installed **loop of individual `dnf install -y`** (one per package)
  after `dnf update` + `dnf upgrade`; local `install_errors.log` appends failures into CWD; hardware-coded Flatpak list installed via
  `sudo flatpak install flathub` **without ever adding the flathub remote**; Chrome (.deb/.rpm download to /tmp, `dnf/apt install local file`),
  VS Code (rpm: imports microsoft.asc, writes `/etc/yum.repos.d/vscode.repo`; deb: `.deb` download; arch: builds AUR helper `yay`).
- **change_language.sh** — `read -t 5` prompt (broken under `set -e` when stdin absent/times out); writes EN (`en_US.UTF-8`) or AR (`ar_EG.UTF-8`)
  block into `/etc/locale.conf` (or `/etc/default/locale`) with `.bak` copy; `source`s the file.
- **add_google_dns.sh** — bails if `/etc/resolv.conf` is a symlink; else copies → `.bak`, `rm`s it, writes 8.8.8.8/8.8.4.4, `chattr +i`,
  restarts NetworkManager.
- **set_aliases.sh** — **overwrites `~/.bashrc` wholesale** from `additions/shell_conf` (single `.bashrc.bak`, clobbered on 2nd run);
  shell_conf: fastfetch clear, `eza ls`, distro aliases, hardcoded `oh-my-posh` eval, `~/.atuin/bin/env` source (unguarded).
- **terminal_themes.sh** — sets bash default via `chsh`; `sudo wget` oh-my-posh binary → `/usr/local/bin` (unpinned); downloads `themes.zip`
  to `~/.poshthemes` every run; appends `oh-my-posh init bash` line if absent.
- **install_atuin.sh** — `bash <(curl -sSf https://setup.atuin.sh)` (**curl|sh**, unpinned); appends `atuin init <shell>` to shell config if absent.
- **install_fonts.sh** — `cp -r additions/fonts/* ~/.fonts/` (deprecated dir, 250MB every run) + `fc-cache -f -v`.
- **set_favorite_apps.sh** — GNOME-gated; resolves names→`.desktop` via case-insensitive find (usr/usr-local/local/flatpak/snap);
  **sets `favorite-apps` to an absolute list** (replaces user's); tells-warn resolves nothing.
- **add_custom_shortcut.sh** — GNOME-gated; computes next `customN`; **sed append of array member injects the literal string `$new_binding`**
  (only the 1st shortcut, when array was `@as []`, works); sets name/command/binding per keybinding path.
- **set_wallpaper.sh** — `cp additions/wallpaper.jpg ~/Pictures/`; GNOME-gated gsettings `picture-uri`/`picture-uri-dark`.
- **gnome_themes.sh** — prints gnome-look URLs, interactive "download themes yourself, press y"; extracts archives in `~/.themes`; `select` a theme;
  sets `gtk-theme` + user-theme extension.
- **icons_and_cursors.sh** — prompts user to download cursors to `~/.icons`; **resets icon-theme to Adwaita if != Adwaita**;
  copies `additions/icons/*` → `~/.icons`; creates `~/Github`, **appends** to `~/.config/gtk-3.0/bookmarks` every run (duplicates).
- **gnome_extensions.sh** — **xdg-opens ~20 extension pages as tabs**; waits for "y", else **re-invokes itself via `bash "$0"`** (tab loop);
  no install, no enable, no GNOME-version check.
- **utils.sh** — `distribution()` maps `/etc/os-release` ID/ID_LIKE → `redhat|debian|arch` buckets (`unknown` fallback, echo only).

### Migration boundaries (P0.4 — P1's deletion contract)
- **DELETE in P1** (recoverable via `git checkout proto-baseline`): `scripts/**`, `additions/fonts/**`, `additions/shell_conf`, stale README
  claims, `setup.sh` (replaced wholesale by new `./setup`).
- **PRESERVE as optional user assets** (moved under `assets/`, content gitignored, skipped when absent): `additions/wallpaper.jpg` →
  `assets/wallpaper/`, `additions/icons/folder-github.svg` → `assets/icons/`.
- **PRESERVE as feature concepts** only: every disposition row above is re-implemented as a module with the stated rewrite goals.
- **Never carried forward**: `/etc/sudoers` edits, `curl|sh` installs, browser-tab extension flow, wholesale `.bashrc` rewrite,
  resolv.conf+chattr DNS, flathub-missing flatpak install, 250MB font blob, countdown `sleep 3…1` loops, CWD-polluting `install_errors.log`.
- Boundary rule: nothing is deleted in P1 until (a) `proto-baseline` tag exists and (b) the new skeleton + `./setup` bootstrap exist.


