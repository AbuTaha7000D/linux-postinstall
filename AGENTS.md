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
- **Current state:** P0–P6 are **DONE** and committed: P2.1 io … P2.9 `tests/smoke.sh` become
  `103` asserts under P4.7 (now `105`), P3 backend beans live behind `FS_PKG_BACKEND`
  (`lib/pkg.sh` P3.1; plan/verify/planner/lists/sources in P3.2–P3.5, `tests/fixtures/pkg_*`),
  P4.1 hooks/sandbox … P4.7 selection UI + real `./setup install` wiring (`lib/ui.sh`,
  `lib/runner.sh`, `tests/fixtures/{ui,runner,install}.sh`, profiles/selection.conf).
  P5.1–P5.6 base modules (`core`/`flatpak`/`git`/`fonts`/`terminal`), P5.7 profile wiring +
  package namespace routing (`minimal`/`desktop`; system→family backend, flatpaks→flatpak
  backend, system first), P5.8 bare install family→backend resolution fix (`c964fd7`).
  P6.1 `lib/gnome.sh` gsettings layer, P6.2–P6.4 GNOME modules
  (`gnome-base`/`gnome-extensions`/`gnome-theme`), P6.5 capability gating + verify hooks
  (`--force`; gsettings-missing = graceful skip rc0), P6.6 idempotency sweep
  (`tests/fixtures/idempotency.sh`; real bug fixed — `gnome_gsettings_set` compare-before-write
  now also matches the single-quoted rendering real `gsettings get` returns for string scalars,
  and the `gnome-base` verify wallpaper compare does the same). The `gnome-*` modules are
  **NOT wired into any profile** (open owner decision from the P6 closure; run them explicitly
  via `./setup install --yes <id>`).
  P7.1–P7.4 are **DONE and committed** (the `apps`, `media`, `dev` and
  `containers` modules). `setup update` IS implemented as of P9.4 (`lib/update.sh`, Senior
  Review pending) — it REPORTS by default and moves the tree only under `update --pull`.
  `setup verify` IS implemented as of P9.2 (`lib/verify.sh`),
  and `lib/depgraph.sh` is the P4.4 dependency-graph
  stage, not P7 work.
  P7.5 (`vscode`) is **DONE and committed** (code `b5e50ce`, ledger `a9418a7`; final review
  `ses_f130947f7ffeq9QWe37lcpbPSj` = PASS): it added the pre-batch `prerepo` stage, the
  `MODULE_FLATPAK_ALT_ID`+`MODULE_FLATPAK_ALT_SEAM` alternative pair, and the first module that
  pins a third-party repository key at run time. Deliberate owner decisions: **no native Arch/AUR
  path** (`vscode` on Arch warns and is a no-op; use `FS_VSCODE_FLATPAK=1`), and the Microsoft
  key is **fetched, never vendored**, so a first install needs network.
  **Known verification gap (P7.5):** the task's `[REAL]` Fedora-container run is **DEFERRED** —
  at the time it was recorded this host had no `podman`/`docker` and `unshare -Ur` failed
  (`write failed /proc/self/uid_map`). HOST STATE CHANGES: re-measured 2026-09-30, `podman` 5.8.7
  IS installed and `unshare -Ur` succeeds, so the container route is no longer blocked by the
  host; the gap is now a scope decision, not a capability one. Everything else is covered by
  `tests/fixtures/mod_vscode.sh` and the runner fixture against `FS_PKG_BACKEND=mock`/`rpm`; the
  live vendor endpoints (key, `repodata/repomd.xml.asc` signature, rpm/deb metadata, Flathub app
  id) were verified directly and the pin is committed in `config/vscode-gpg.fingerprint`. Do not
  claim a real Fedora run happened. The full fixture battery needs no rpm shim: the real `rpm`
  6.0.2 on `PATH` is sufficient for `tests/fixtures/planner.sh`'s rpm-family cells (the earlier
  `/tmp/opencode/ubin` shim no longer exists).
  P7.6 (`chrome`) is implemented and Senior Review has **PASSED** — round 1 returned **REVISE**
  with one blocking finding (a failed install was reported as success and the module latched as
  done — §12, postcondition rule) plus 14 non-blocking findings; all were fixed and round 2 in the
  same session (`ses_f12bcfd27ffew3DPMWqL6vUD8O`) returned **PASS**, 0 blocking. It is a
  **hooks-only** module whose native path resolves an architecture-pinned `(URL, SHA-256)` pair
  from the vendor's own repo index at run time, verifies the digest, then installs the bundle with
  the existing `pkg_install_local` seam. It reuses the P7.5 alternative pair
  (`FS_CHROME_FLATPAK=1`), ships **no** list file, and warns + no-ops on Arch.
  **Known verification gap (P7.6) — NOT met, do not claim it:** the `[REAL]` half of the
  criterion (a real mutating package install plus an installed `.desktop`) is **DEFERRED** because
  at the time it was recorded this host had no `podman`/`docker` and `unshare -Ur` failed with
  `write failed /proc/self/uid_map: Operation not permitted`, and a real install is out of bounds
  under §9. HOST STATE CHANGES: re-measured 2026-09-30, `podman` 5.8.7 is installed and
  `unshare -Ur` succeeds; the deferral is now a scope decision, not a host capability. The real *network* path **was** exercised end to end read-only (live index resolved →
  142,114,088-byte bundle downloaded → digest matched → `pkg_install_local` reached with nothing
  installed), and `tests/fixtures/mod_chrome.sh` (236 asserts) covers everything else hermetically.
  See §12 for the trust-boundary wording — the digest is **not** signature verification.
  **Next: close P7.6 (task + ledger commit), then report at the P7 phase boundary.** P8 needs
  owner approval, and the P7 report is blocked on the same `[REAL]` host gap.
  **P7 phase boundary was passed and P8 is now CLOSED** (the line above is retained only as
  history; the authoritative state is below). P8.1 (`dns`, code `7544c38`), P8.2 (`locale`, code
  `2cdb053`) and P8.3 (risk gating, code `05ed1b5`) are all **DONE and committed**. **P8.1–P8.3
  each shipped WITHOUT a Senior Reviewer PASS** under explicit owner instruction (P8.3's approval
  is recorded in the P8.4 phase report); P8 therefore has the same process gap P7.5/P7.6 and P8.1
  already carry, and unlike P0–P7. Do not treat the P8 ledger rows as reviewed.
  P8.1/P8.2 are hooks-only `destructive` modules wired into NO profile (`MODULE_DEFAULT=off`),
  run only by explicit id (`./setup install --yes dns`). P8.3 hardened that surface and found
  **two real defects**: the `[high-risk]` red flag had **never rendered** (`lib/ui.sh` gated color
  on `-z "$FS_NO_COLOR"` while `lib/io.sh` normalizes it to the string `"0"` — every color gate
  must compare numerically), and a single `MODULE_DEPENDS` edge could install a destructive module
  with no consent at all (`lib/runner.sh` now refuses rc1 on any high/destructive module in the
  resolved-but-not-curated set). A third change — refusing high-risk selections whenever stdin is
  not a TTY — was written, measured, and **rejected**; see §12.
  **Known verification gap (P8) — NOT met, do not claim it:** the mutating half of the P8.1/P8.2
  `[REAL]` criteria (DNS applied + revert restoring prior state; `localectl status` reflecting a
  change with a backup file) was **deliberately not performed** — both are destructive system-wide
  changes and both were owner-approved as out of scope. Reversibility and idempotency are proven
  hermetically instead (`mod_dns.sh` 150 asserts, `mod_locale.sh` 120, against the real
  `fs_backup`/`state_note`/`runner` code paths with stateful fakes), and the real `nmcli`/NM stack
  and `localectl`/`/etc/locale.conf` were exercised **read-only**. P8 §8 "functional + reversible
  on a real system" is therefore **not satisfied**; see the P8.4 phase report. The live host is at
  defaults after P8 (`/etc/locale.conf` md5 `164aba1ef1298affaa58761647f2ceba`, NM `Home` with
  empty `ipv4.dns` and `ipv4.ignore-auto-dns:no`).
  **P9.1 (`check`) is DONE and committed** (code `21f919a`, ledger `87a8e08`). **P9.2
  (`verify`, `lib/verify.sh`) is DONE and committed** (code `902b528`; Senior Review
  `ses_f1078edc3ffeNv3zb1H8sweZQ6` = PASS after three rounds: 3 blocking → 1 blocking → 0).
  P9.2 is read-only: it installs nothing, marks nothing, backs nothing up and never
  sudoes. The three `verify()` hooks added in this round close the ROADMAP's "fonts"
  and "managed files" categories, which no shipped module covered.
  **Known verification gap (P9.2) — NOT met, do not claim it:** the `[REAL]`/live-host
  half is **DEFERRED**. At the time it was recorded this host had no `podman`/`docker` and
  `unshare -Ur` failed (`write failed /proc/self/uid_map: Operation not permitted`), so no
  containerized Bash-4.3 floor run and no real-distro audit were performed — the floor is a
  static audit only. HOST STATE CHANGES: re-measured 2026-09-30, `podman` 5.8.7 is installed and
  `unshare -Ur` succeeds; the deferral is now a scope decision, not a host capability. Everything else is covered hermetically by `tests/fixtures/verify.sh`
  against the real `pkg`/flatpak seams, and a live-host READ-ONLY smoke was run
  (it did surface real drift) — but that is supplemental, not the criterion. A
  second, sharper limit: a fully green fixture proves the audit and its oracle
  agree, NOT that the audit agrees with the system — which is exactly how four
  false-PASS defects survived a 215-assert suite. The oracle is now derived from
  the hooks' own body-builders, and the comparison relation is the writer's
  (see §12) — the two fixes are independent and both were needed.
  **P9.3 (`export`, `lib/export.sh`) is DONE and committed** (code `69ae219`; Senior Review
  `ses_f0eb1e4beffespAPKxmBn5HCwJ` = **PASS**, 0 blocking, after four rounds: 5 blocking → 1 → 1 →
  0). It writes a re-importable, allowlist-by-construction snapshot and `install --manifest <dir>`
  replays it through the ordinary runner, so the plan is the exported one rather than the live
  one. The first three review rounds each found a defect of the SAME shape — *the artifact looked
  right while a different artifact governed behaviour* — and all three are now rules in §12: a
  malformed `--manifest` aborted **silently** at rc1 (the profile lookup ran before tree validation);
  a module ABSENT from `manifests/` silently fell back to its **live** list (three states are now
  explicit, and a symlinked list is refused); and, twice, the `export.meta` completion marker was
  written in the wrong ORDER — first of all (a failed export left a tree a re-import accepted),
  then after the manifest loop (a refresh failing on module 2 left the OLD marker beside NEW
  manifests, so a re-import replayed the previous profile over the new ids and **nothing reported
  an error anywhere**). The marker is now dropped after the outdir preflight and before the first
  writing stage, and re-added last, so the window in which a partial tree is still recognizable is
  empty. It is deliberately NOT dropped during argument/profile validation, which writes nothing.
  `_export_block` **shares `lib/fs.sh`'s own `_fs_validate_markers`/`_fs_locate`/`_fs_locate_ok`**
  instead of carrying a private parser, because `fs_managed_block` owns the meaning of "the
  managed block" — a private parser concatenated the bodies of a DUPLICATED block into one the
  writer refuses to manage. After the shared validator passes, `_fs_locate_ok` can only fail on
  that duplicate case, so a separate "unterminated" check is **unreachable**; it was found that way
  (a mutation removing it produced 0 FAILs) and deleted, because a guard that never fires reads as
  protection while providing none. Absence (no marker) and truncation (marker with no END) are kept
  distinct. `FS_MANIFEST`/`FS_PROFILE_SET` are **not** env seams: set only by their flags, reset
  unconditionally by `cli_parse`, so an inherited environment value can never redirect a run into
  an untrusted tree. Format: `docs/export-format.md`.
  **Known verification gap (P9.3) — NOT met, do not claim it:** the `[REAL]`/live-host half is
  **DEFERRED** (at the time it was recorded: no `podman`/`docker` here; `unshare -Ur` failed with
  `write failed /proc/self/uid_map: Operation not permitted`). HOST STATE CHANGES: re-measured
  2026-09-30, `podman` 5.8.7 is installed and `unshare -Ur` succeeds; the deferral is now a
  scope decision, not a host capability. The tree was exercised hermetically against the
  mock backend and read-only on this host, but **nothing proves an export matches a real system's
  installed state**, and a byte-identical re-export is a determinism result, not a correctness one.
  **P9.4 (`update`, `lib/update.sh`) is IMPLEMENTED; Senior Review round 1 PASSED and rounds 2
  and 3 returned REVISE** (review `ses_f0e3e7018ffe4jCCzJ8PPkjGY6`; no ledger row yet, nothing
  committed). Each review round found **one blocking finding, and every one was a real,
  measured data-loss defect in the pre-merge collision guard** — the guard that exists precisely
  because of them:
  - **R2.** git refuses to fast-forward over an untracked-but-NOT-ignored file, but silently
    REPLACES an untracked-and-**ignored** one, and `status --porcelain` reports nothing for it
    — so the cleanliness gate was blind to exactly the case `.gitignore` creates (this repo
    ignores `downloads/`, `assets/*`, `.state/`). `--ff-only` does not help (the fast-forward is
    legitimate) and the HEAD==upstream postcondition is satisfied (HEAD did move), so the tool
    reported `updated to <sha>`, rc 0, with the user's file destroyed.
  - **R3.** Two of that guard's three predicates failed OPEN, both reproduced end to end
    through `./setup update --pull` at rc 0: `[[ -e ]]` is **false for a dangling symlink**
    (a symlink into an unmounted drive — exactly what lives under `assets/wallpaper/`), and
    `ls-files --error-unmatch -- "$path"` treats the path as a **glob pathspec**, so an
    incoming `pkg1?2.deb` is answered by a tracked `pkg1x2.deb` and the guard concludes there
    is nothing to lose.
  The shipped rule is: refuse when the fast-forward would ADD a path that **exists on disk (a
  `-e` OR a `-L`) and is untracked**, the untracked test asked with `--literal-pathspecs`. It is
  deliberately NOT expressed with `status --ignored` (it would refuse on this repo's own
  artifacts forever) nor `check-ignore` on incoming paths (it would refuse an incoming file at
  an ignored path when nothing local is in the way) — both rejections were re-measured by the
  reviewer, not assumed. See §12.
  141 asserts in `tests/fixtures/update.sh` against REAL git repositories (one bare origin,
  seeded, then cloned per cell), 8 new smoke cells (169 total, was 161), 42 suites green, and
  the full battery byte-identical across 3 runs of `bash tests/smoke.sh` followed by every
  `tests/fixtures/*.sh` in sorted order, with the run timestamp and the fixture temp-dir name
  normalized — `sha256` of the concatenation, first 16 hex chars, `01ee89c36cdc769f`. That hash
  is only comparable like-for-like: it changes whenever any assert count changes, and a reviewer
  aggregating the battery differently will get a different digest for identical content (the
  reviewer's own aggregation of the same tree yields `6da7ab6d8cf2eaaa` for identical content).
  `--diff-filter` carries `C` as well as `AMR`; the copy case is covered by inspection only, since
  the copy constructible under `diff.renames=copies` classifies as an add. One limit is left
  standing and documented in the header: an upstream path containing a literal newline is not
  inspected, because the incoming list is read through `$(...)`, which cannot carry NUL. **22 mutations, all 22 caught**, each applied to a throwaway copy of the
  repo and each `cmp`-checked non-vacuous first: 16 from the implementer's set, then the
  reviewer's independent sets, which found mutations the implementer's had missed — the
  `git`-recording shim (a dry run must invoke git **zero** times, and a report *does* fetch),
  the direct-call bogus-`FS_PULL` cell (the pull gate must fail **closed**), and both R3 holes
  (`-L` removed → 6 FAILs; `--literal-pathspecs` removed → 5). Losing the tracked-file test is
  the **false-refusal** direction and is now caught by four *state* oracles rather than by the
  liar cell's message (5 FAILs).
  **Known verification gap (P9.4) — NOT met, do not claim it:** the task is tagged `[MOCK]`,
  and that is what was delivered: no cell fast-forwards the user's actual checkout, and no
  `[REAL]` criterion was attempted. A fast-forward was exercised end to end against real git
  objects in throwaway clones, which is a mechanics result, not a result about someone's working
  tree. Note the R2/R3 defects were found by **reviewer measurement of git's own behaviour in a
  scratch repository, against scenarios the suite did not cover at all** — no mutation exposed
  them, because the cells did not exist. That is the argument for auditing a destructive guard's
  coverage directly, not for mutation cells specifically, and it is a reminder that the "no data
  loss" claim is only as good as the ignore rules a future change introduces.
  **P9.5 (`summary`, `lib/summary.sh`) is IMPLEMENTED; Senior Review rounds 1 and 2 returned
  REVISE (round 1 `ses_f0da80f2bffe3LQHeaOHcclrVh`, round 2
  `ses_f0d77553cffe7rkQNR0qr1vvKL`; the round-3 fixes below are in the tree, uncommitted, and
  awaiting re-review).** The end-of-run summary is a reporter that owns BOTH
  the printed line and the process exit code, and the runner keeps no counter of its own: it
  records each module outcome as it happens (`summary_module_ok/_skip/_fail`) and hands the
  record to `summary_report` + `summary_rc`. Every number printed is `${#SUMMARY_*_IDS[@]}`
  taken at render time from the same three arrays the per-failure rows are printed from, so
  the "N ok · M skipped · K failed" in the line and the rc cannot disagree by construction.
  The rendered line is the ROADMAP's `N modules ok · M skipped · K failed · artifacts in
  <log>`, followed by one `FAIL <id>: hook exited <rc>` row per failed module and — only when
  something failed — `retry: re-run the same command; completed modules are skipped` (a claim
  the fixture proves true against the state registry, not just renders).
  `lib/bootstrap.sh` gained `_fs_open_run_log`, called on the real install path right after
  `state_init`: it opens this run's log via `state_log` + `io_init` and then **checks the
  postcondition**, because `io_init` only warns and always returns 0.
  **Round 1, blocking finding 1 (B1): the guard and the pointer were two tests of one
  property, and they disagreed.** The guard accepted any existing file while the reporter
  named a path; given a pre-existing log this run cannot append to, `io_init` skips its write
  and only warns, the file is still there and still non-empty, so an existence test passed and
  the run refused nothing while the summary named a log holding none of it. Fixed by giving
  `lib/io.sh` ONE predicate, `_io_log_usable` (`-f` AND `-w` AND `-s`), called by both
  `lib/bootstrap.sh` and `lib/summary.sh` — the P9.2 B4 rule applied to a log file. The
  `tests/fixtures/summary.sh` 6c cell pins the predicate on the shapes that hold regardless of
  uid (directory, FIFO, empty file, dangling symlink, absent path, symlink to a real file).
  **Round 1, blocking finding 2 (B2): a root-only cell printed a note and returned 0, so a
  root CI reported full coverage while the `-w` leg of the postcondition was untested.** The
  suite now counts such cells and prints `summary: N passed, M failed, K skipped
  (root-only limitation)`. **Honest limit: this host is uid 1000 with no passwordless sudo,
  so the branch that PRINTS the skip count is itself not exercised here** — only its format is
  pinned. Do not describe the unwritable-log refusal as root-covered.
  Other round-1 findings fixed: the artifacts pointer now uses the shared predicate and reads
  `${FS_DRY_RUN:-0}` safely when sourced alone; three unused record helpers were deleted; the
  "each run opens its own log" cell now runs TWO runs in ONE state root **and in a fresh
  root of its own** (the first version read its "1 before" from a log an earlier cell left
  behind, so a runner that shared one file could not fail it); the anti-counter regex covers
  `((x++))` and `let`; the dry-run + exported-`FS_LOG_FILE` combination is pinned (a dry run
  WITH a usable log DOES name it — the two orderings are easy to conflate); `lib/cli.sh` now
  states the asymmetry (a real install re-points the seam at its own state log); the two abort
  paths that had no cell — the SYSTEM package batch and `state_module_mark` — each got one
  (the batch is failed with `FS_MOCK_LOG` pointing at a directory, which holds as root;
  7d-ii keeps `<state>/modules` a real directory, pre-marks one module so a `skipped`
  record exists at the abort, and puts a DIRECTORY at the second module's mark path so
  `_state_write` is what refuses — an earlier version made `modules` itself a file and
  never reached the call it named); the
  runner-side `hook exited ` patterns are pinned to the exact status with `$`; and all 46
  previously unanchored count assertions are now `^  - `-anchored, so a line reading
  `0 modules ok` cannot satisfy an expectation of `10 modules ok`.
  The failure-row detail is now pinned on BOTH rows with DISTINCT statuses (`7` and `12`) and
  `grep -qx`; the earlier cell checked only the first row, and `agree_rc` never compared row
  text at all, so a reporter rendering a constant status passed 89 green asserts.
  55 assertions across 16 fixture files plus `tests/smoke.sh` were converted from the old
  per-count lines (`- 3 ok` / `- 0 failed` / `- 0 skipped`) to the single combined line — each
  conversion is strictly stronger, since one assertion now pins all three counts on ONE line.
  Totals: smoke 169, 42 fixture suites / 3567 asserts, all green, and
  `tests/fixtures/summary.sh` 105. Byte-identical across 3 runs of the full battery,
  `sha256` first 16 = `7f920400d84c38bd`, after normalizing exactly three things:
  `/tmp/fedora-setup-pkg.<rand>` → `/tmp/FX`, `run-<ts>-<pid>.log` → `run-TS-PID.log`, and
  `[HH:MM:SS]` → `[TS]`. The AGGREGATION is part of the digest, so it is quoted in full
  (see §7). That digest is only comparable like-for-like.
  **Mutations: 25 applied and all 25 caught on uid 1000 in round 1, plus 2 negative controls
  that escape by construction** (a prefix row match instead of the pinned one, and a cell moved after the
  suite's summary block — the second of which is why placement is called out below).
  Every mutation was checked non-vacuous twice over: `cmp` proves the file changed, and a
  **result identical to the baseline is treated as a broken harness, not a finding** — that
  rule caught a mutation runner whose `python3 - args` form read its program from stdin, so
  every "edit" was a silent no-op and an escaped result was the untouched suite re-reported.
  Three mutations escaped during development and each one is why a cell now exists (the
  artifacts `-f` test, the log postcondition, `summary_reset`); see §12.
  **Senior Review round 2 (`ses_f0d77553cffe7rkQNR0qr1vvKL`) returned REVISE with ONE
  blocking finding, and it was the same defect class as the cell it criticised: the new
  `state_module_mark` cell never reached `state_module_mark`.** It put a regular file at
  `<state>/modules`, so `state_init` refused FIRST (`_state_dir_content_ok`) and the run died
  at `lib/bootstrap.sh`'s `state_init || return 1` — the module loop was never entered and the
  reporter held no records, so "the reporter is not reached on this abort path" was asserted by
  a cell that could not have observed it either way. The production code was verified correct
  out of band; the EVIDENCE was the defect, and the evidence is the deliverable. Rebuilt: 7d-ii
  keeps `<state>/modules` a real directory, pre-marks one module so a `skipped` record really
  exists at the abort, and puts a DIRECTORY at the second module's mark path so `_state_write`
  is the thing that refuses — uid-independent, so unlike 7b it also covers a root CI. It now
  asserts the precondition (`already completed: asnap`) as well as the absence of a summary,
  and two mutations prove it is load-bearing: removing the `_state_write` directory guard, and
  making the abort path `summary_report; return 1` (a reporter leaking half a run's records).
  **A cell can be non-vacuous about the CODE and still vacuous about the FUNCTION it names**,
  which is why the honest label matters: cell 7a was renamed in place and its comment now says
  it is a `state_init` cell, because it also fails before `state_log` (it makes `<state>/logs`
  a file, which `state_init` validates). The consequence is stated rather than glossed: **on a
  root CI the `_fs_open_run_log` postcondition has NO coverage**, because 7b is root-skipped and
  7a is not that cell. (Stated more precisely in round 4: the SATISFIED postcondition is
  exercised by every real-install cell, so what is root-uncovered is only the REFUSAL branch.) Also fixed: `mod_vscode.sh` now sources `lib/summary.sh` alongside
  `lib/runner.sh` (nothing calls `runner_run` there yet, and the first cell that does would
  otherwise die at `summary_reset: command not found` under `set -euo pipefail`); the
  root-run format cell no longer hardcodes a suite total that is not this tree's.
  **Mutations: 27 applied and all 27 caught on uid 1000 (16 code mutations + 11
  test-strength mutations), plus 2 negative controls that escape by construction** (a prefix row match instead of the pinned one, and a cell moved after the
  suite's summary block — the second of which is why placement is called out below).
  **Senior Review round 3 (`ses_f0d577073ffedI6Lf3h0Xo5WvZ`) returned REVISE with TWO
  blocking findings, both of them gaps in what the fixture pinned rather than defects in the
  reporter** (the production code was re-verified correct again, out of band). **B-1: the
  `artifacts` clause was unpinned for a CLEAN real install.** Every real install cell in the
  fixture had a failure in it, and the only cell pairing a usable log with rc 0 was a DRY run
  with an exported `FS_LOG_FILE` — so a reporter that cleared `FS_LOG_FILE` when nothing
  failed (a mutation the reviewer wrote) left 596 asserts green across six suites, and the user
  would read `artifacts: none (no run log was opened)` from a run that had opened a real,
  writable, non-empty log: a false statement about the exact relation the `_io_log_usable`
  rule exists for, and a contradiction of the ROADMAP's unconditional line format. Fixed by a
  clean real install cell (`fatgood`, rc 0) that pins the clause AND checks the named path IS
  this run's state-root log and holds the hooks' lines and the summary line.
  **B-2: the first half of 7b was labelled with a function it never reached, and was a
  duplicate of 7a.** It made `<state>/logs` a regular file, which `state_init` refuses before
  `state_log` is called — so `state_log`'s own `log path not usable` branch has NO cell
  anywhere in the repo, and a coverage audit over-counted. The half was **deleted** (7a already
  pins that construction) and the uncovered branch is now **recorded as uncovered**, with the
  reason it is not reachable through `./setup` (a fresh `run-<ts>-<pid>.log` name per run).
  Round-3 non-blocking fixes: the FAIL rows are now asserted **in record order** (matching
  each row independently was order-insensitive, and a reporter printing them reversed stayed
  green); a literal `\u00b7` in one assertion — which bash never expands and which grep warns
  about — was replaced with `"$BULLET"`; the root-run format cell no longer compares a printf
  against its own expansion, and pins the reporting line's FORMAT against the suite's own
  source with bracket-escaped patterns so a pin cannot match its own text (a mutation of that
  line escaped twice before that was fixed — a self-matching pin is a tautology in a trench
  coat); the anti-counter regex is broadened to `(( ++x ))`/`((x += 1))`/`let "x+=1"` and is now
  labelled **best-effort, not a proof** (measured: it catches `((x++))`, `(( ++x ))`,
  `((x += 1))`, `((x = x + 1))`, and `let "x+=1"`, but NOT bare `x+=1` or `x += 1` outside
  `(( ))` -- an unused parallel counter is behaviourally harmless, so this is documentation
  only); and §7 now quotes the exact digest AGGREGATION
  command, not just the normalization, after the reviewer showed the documented digest was not
  re-derivable.
  **Two more coverage limits are now stated instead of implied:** the `-w` **leg** of
  `_io_log_usable` is uncovered on BOTH uids (as root `-w` is always true; as uid 1000 every
  shape 6c pins is decided by `-f`/`-s`, and on the install path the path is freshly minted
  and created writable), and on a root CI the `_fs_open_run_log` postcondition's **refusal**
  branch has no coverage, because 7b is root-skipped and 7a is a `state_init` cell. The
  satisfied branch is covered by every real-install cell.
  **Senior Review round 4 (`ses_f0d1452faffe2W0vQ7eftsE1ct`) returned REVISE with ONE
  blocking finding: 2 of the 5 abort paths the task contract names were entirely unpinned.**
  The resolve-error path (`lib/runner.sh:224`) and the risk-gate refusal (`lib/runner.sh:283-285`)
  could both print a summary, and a mutation that made either do so was invisible to the whole
  3557-assert battery. The reviewer verified this by mutation, not by reading: adding
  `summary_report` to either `return 1` left 0 suites failing. The leak is not cosmetic — with
  the risk-gate mutation a user sees `0 modules ok . 0 skipped . 0 failed` printed immediately
  after the run said it would NOT touch the system, which is exactly the "true statement about
  an empty set" lie `lib/summary.sh`'s header says the reporter must not be reached to prevent.
  Fixed by adding `fx_out_not 'run complete'` to both existing cells
  (`tests/fixtures/runner.sh` unknown-profile cell, `tests/fixtures/risk_gate.sh` dep-edge
  refusal cell) and extending the `lib/summary.sh` header to enumerate all five abort paths.
  Both mutations are now caught with count deltas (133→132 and 57→56).
  Round-4 non-blocking fixes: every `hook exited 1` pin is now `$`-terminated so a status of 10
  cannot satisfy an expectation of 1 (mutation M36 caught, 100→94); the remaining prefix-tolerant
  count pins are terminated; the stale host facts in §1 are corrected (podman 5.8.7 IS installed,
  `unshare -Ur` succeeds, `/tmp/opencode/ubin` no longer exists and the battery is green with the
  real `rpm` 6.0.2); and the root-coverage wording now states that the SATISFIED postcondition is
  exercised by every real-install cell, so only the REFUSAL branch is root-uncovered.
  **Mutations: 36 applied and all 36 caught on uid 1000 (21 code mutations + 15
  test-strength mutations), plus 2 negative controls that escape by construction**
  **Senior Review round 5 (`ses_f0ca485fcffeJETHyftCchOnvO`) returned PASS, 0 blocking.**
  The reviewer ran ~47 of its own mutations (34 caught, 11 escaped -- 4 by-construction
  negative controls, 7 real non-blocking escapes) and independently reproduced every
  number above, including the round-4 B1 deltas (133→132 and 57→56) and the digest.
  Post-PASS non-blocking fixes: `fx_out_not 'run complete'` added to the family-gate and
  both arg-validation cells (closing the module_validate and `shift 4` abort paths the
  reviewer found unpinned); `summary_reset`'s clearing of `SUMMARY_SKIP_IDS` and
  `SUMMARY_FAIL_DETAIL` pinned (the detail one needed a ROW assertion -- a stale detail
  leaves the count right and only corrupts which module is named); the anti-counter regex
  wording in §1 corrected to match what it actually catches; three further defensive
  `return 1` sites (`if [[ -z ]]`, `profile_load`, `module_flatpak_alt`) recorded as
  uncovered in the `lib/summary.sh` header rather than pinned with contrived cells.
  **Mutations: 41 applied and all 41 caught on uid 1000 (26 code mutations + 15
  test-strength mutations), plus 2 negative controls that escape by construction**
  **P9 is COMPLETE.** All five P9 tasks (P9.1 check, P9.2 verify, P9.3 export, P9.4 update,
  P9.5 summary) are DONE and committed; the full CLI surface
  (`install|list|check|verify|export|update|help|version`) is functional and tested. P9.1
  shipped owner-approved WITHOUT a Senior Review (a known process gap, recorded in its ledger
  row); P9.2–P9.5 each reached Senior Review PASS.
  **P10 is CLOSED (implementation-complete and phase-approved by owner).** All five tasks
  (P10.1 bats harness, P10.2 static analysis, P10.4 mock-backend integration suite, P10.3
  container smoke + Actions matrix, P10.5 prototype-bug regressions) are DONE and committed
  (`fb42b43`/`6b92281`, `2d792cc`/`70727b3`, `7c83d77`/`f046f05`, `4607d5f`/`fe70695`+
  `ff96536`, `2e95428`/`2c430e0` — implementation then ledger, in that order). P10.3 and
  P10.5 reached genuine fresh-context Senior Review PASS; P10.1 and P10.4 each took three
  review rounds; P10.2 passed on round 1. **At the phase close the owner chose option (b):
  the §5/§8 GitHub Actions criterion is formally RECLASSIFIED as `UNVERIFIED-and-ACCEPTED`,
  and the real workflow run moves to follow-up ticket T-P10-1 (post-P11, owner-gated).**
  `.github/workflows/ci.yml` has NEVER been executed on a GitHub runner — there is no run id
  and no status URL, and none may be invented (P10.3 row, P10 §9). No complete four-distro
  matrix run was ever green. The shipped `FS_CTR_TIMEOUT=5400` has already gone red on the
  Flathub CDN, so a first run must be read as a sample, not a verdict. What is verified is
  strictly LOCAL: `make lint` OK, smoke 169/0 (stderr empty), `bash tests/run` rc 0
  (`1..59`, 59 ok / 0 not ok), 44 fixture suites / 3676 fixture asserts, and a full-battery
  digest byte-identical across 3 runs (`f844c619d560cf2c`). Local Podman `[REAL]` evidence
  and GitHub Actions evidence are DIFFERENT claims and are never added together.
  **Next: P11 needs owner approval.** P11 is NOT started; do not begin it without approval.
- **P11-R (Phase B readiness remediation) is in progress and A1/A2/B1/B2/B3/C1 are DONE
  and committed** — `fb3a7ab` (B1), `491df20` + `b74914e` (B2), `6337902` + `b2fe70e` (B3),
  `06886f0` + the C1 completion commit (C1). A1 and A2 were closed earlier and are unchanged
  by Phase B. **P11 itself remains NOT started** and still needs owner approval; Phase B work
  does not start it.
  **P11-R is COMPLETE.** All nine tasks (A1, A2, B1, B2, B3, C1, D1, D2, D3) are DONE and
  committed. **Note the numbering
  collision:** ROADMAP's F1–F4 are audit findings, so F2 belongs to D1 and F3 to C1 — Phase B
  addressed F1 (B1 + B3) and F4's write half (B2), **C1 fixed F3**, **D1 fixed
  F2** (commit `356b6ce`), **D2 closed F11's coverage gap** (F11 itself is recorded NOT
  REPRODUCIBLE), and **D3 fixed F4b** (CI timeouts + action pinning).
  **D3 (CI timeouts and action pinning, F4b) is DONE** — Senior Review
  `ses_ef739da3effePcJtG676m5NGPl` = **PASS**, 0 blocking, after round 1 returned PASS with
  3 non-blocking findings (all fixed). Two files changed: `.github/workflows/ci.yml` and
  `tests/fixtures/ci_lint.sh`. Every job declares `timeout-minutes` (lint 15, unit 30,
  container 150) and every action reference is pinned to a full 40-hex commit SHA with the
  release version in a trailing comment (`actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0`).
  The SHA is the one `refs/tags/v4` resolved to at pin time, verified with
  `git ls-remote --tags https://github.com/actions/checkout` (refs/tags/v4 = refs/tags/v4.4.0 =
  11d5960a...), so pinning that exact commit is a no-op for the first run and a freeze for
  every run after. The container job's 150-min cap must stay ABOVE `FS_CTR_TIMEOUT=5400`
  (90 min) — on that deadline the smoke script reports INCONCLUSIVE and exits non-zero, so a
  cap at or below it would replace a diagnosable failure with a bare 'exceeded timeout'.
  `ci_lint.sh` gained a 'D3 group 7' block (100 → 108 asserts) asserting both properties two
  ways: a PyYAML path (per job) and a parser-free text path (comment lines stripped first).
  Evidence: `make lint` OK; smoke **200/0** stderr 0; `bash tests/run` rc 0 **`1..61`**,
  61 ok / 0 not ok; **46 fixture suites / 4233 asserts**; full battery byte-identical across
  3 runs, digest `8d25355d2d1dd4e`. **Mutations: 13 applied, 11 caught, 2 escaped by
  construction, 0 broken.** **Honest limits:** group 7 is STATIC (reads files, executes
  nothing); the SHA↔tag correspondence is a trust anchor verified out of band; the text path
  cannot see a newly added unbounded job (the YAML path can); `actionlint` is NOT installed
  (absence recorded in the fixture header); the lint/unit timeout values are measured host
  figures, not tested constants. **The GitHub Actions workflow has STILL NEVER EXECUTED** —
  no run id, no status URL, none may be invented. That remains **T-P10-1** (owner-gated,
  post-P11). **P11 itself remains NOT started** and still needs owner approval.
  **D2 (permanent harness-failure canary, F11 coverage gap) is DONE** — Senior Review
  `ses_efa11e533ffeuOyG0eubcSJFCx` = **PASS**, 0 blocking, after round 1 returned **REVISE with
  2 blocking**. It adds exactly one file, `tests/fixtures/canary.sh` (35 asserts), and
  **deliberately does NOT modify `tests/run`** — the task forbids changing what it runs, and
  closing the gaps it records would change the runner's verdict logic. The canary builds a
  throwaway mini-repo holding a **byte copy** of the real `tests/run` + `tests/lib_tap.bash` +
  `tests/fixtures/lib.sh` and executes the real runner in it (re-deriving the runner's logic
  inside the canary would be the P9.3 "private parser" defect), classifies with
  `cn_verdict <out> <rc>` → `detected` (**`not ok` AND non-zero rc — the two signals
  `tests/run` itself uses**) or `missed`, and covers: a genuine `fx_bad`; a suite exiting 0
  with a `^FAIL ` line; **a suite exiting 7 with no `FAIL ` line, which isolates the rc leg**
  (`fx_bad` writes to stderr, so every fixture built from the real helpers is also caught by
  the text leg — without this suite nothing could tell the two legs apart); two planted at
  once; a failing bats layer pinned on both its rc and its `not ok` report; a **negative
  control** (a suite exiting 0 printing nothing must be reported MISSED, with an explicit
  maintenance contract so a future gap-fix turns that cell red on purpose); a
  classifier-discriminates check; and every real fixture's summary block still being the last
  thing it **executes**, with six shape controls. Round 1's two blocking findings were real
  and are the two general rules below; **two of the four gap measurements in the header were
  wrong on the first write and were corrected** — see the header and §12. Evidence: canary
  **35/0** rc 0 byte-identical across repeats; `make lint` OK; smoke **200/0** stderr 0;
  `bash tests/run` rc 0 **`1..61`**, 61 ok / 0 not ok (the recorded count change from D1's
  `1..60`, +1 suite); **46 fixture suites / 4225 asserts**; full battery byte-identical across
  3 runs, digest `793093fa120696c1`. **Mutations: 13 applied, 11 caught, 2 escaped by
  construction, 0 broken** (both non-vacuity checks per §7). The 2 escapes are a label-only
  negative control and **M12 — the canary cannot prove it is itself in the harness**: adding
  `canary.sh` to `tests/run`'s skip list leaves everything green. That is **structural, not a
  gap** (a test cannot prove its own membership); the only observable is `tests/run`'s plan
  count. Senior round 2 ran an **independent** harness: 49 mutations, 40 caught, 7 escaped,
  2 killed. **Honest limits:** the proven property is narrow (synthetic byte-identical runner
  copies turn planted synthetic failures into `not ok` + non-zero rc); it does NOT prove
  real-suite enumeration, silent/mis-reported summary detection, real bats health, or that the
  61-test battery is green. The GitHub Actions workflow has still **NEVER run** — that is
  **T-P10-1**, owner-gated.
  **D1 (CI lint tool provisioning, F2) is DONE and committed** (`356b6ce`; Senior Review
  `ses_efac2a9cbffeTSZPX0cl4vWGiF` = **PASS**, 0 blocking, after round 1 returned REVISE with
  3 blocking). The `lint` job **stays on `ubuntu-latest`** — an owner-gated alternative was
  available and is recorded in the `.github/workflows/ci.yml` header — and both tools are now
  pinned, SHA-256-verified **static release binaries** (shfmt `v3.7.0`, shellcheck `v0.11.0`),
  so the lint result no longer depends on the runner OS. Three findings worth carrying, because
  each is a general rule rather than a D1 detail:
  (1) **The old shfmt path was rpm-family-only (`dnf download` + `rpm2cpio | cpio`) on an
  `ubuntu-latest` job, and it failed SILENTLY** — `set -e` aborted the subshell *before* the
  step's own `shfmt download failed` guard could print, so the second guard was dead code.
  A guard placed after a subshell that cannot survive to reach it is not a guard.
  (2) **A staging filename must come from `mktemp`, never from `$$`.** `$dest.install.$$` is
  attacker-predictable and `cp -- src symlink` writes **through** a pre-created symlink:
  measured, a 24-byte file outside `tools/` grew to the full 2.9MB shfmt while the script
  printed nothing and exited 0. `mv -f` over a *destination* symlink is safe (it replaces,
  it does not follow), so the hazard is one-sided.
  (3) **An assertion about litter is vacuous when nothing ever creates the litter.** Cell 6c
  asserted "no staging file left behind" while its fake `cp` failed *before* creating one, so
  a fully non-atomic implementation with byte-identical diagnostics stayed green — measured
  escape, 91/0. The fix is to make the fake **contract-coupled**: `: >"$3"` creates the
  destination before failing, so the assertion can finally fail.
  Evidence: `tests/fixtures/ci_lint.sh` **100/0**; smoke **200/0** (stderr 0 bytes);
  `bash tests/run` rc 0 (`1..60`, 60 ok); `make lint` OK; **45 fixture suites / 4190 asserts**,
  0 failed, 0 skipped; full-battery digest byte-identical across 3 runs (`4320b5d7aee25ebd`,
  aggregation per §7). **19 mutations applied, 17 caught**, plus 2 negative controls that escape
  by construction, 0 broken — including the two round 1 measured as escaping (now 100→95 and
  100→99). **Known gap, do not over-read:** the GitHub Actions workflow has **NEVER run** —
  there is no run id and no status URL and none may be invented. The container evidence is
  about the *provisioning path on the base image* (`ubuntu:24.04`, on which `dnf`/`rpm`/`rpm2cpio`
  /`cpio` are all absent — provisioning succeeded, installed shfmt digest equals the pin,
  `make lint` rc 0; and on the bare image without `curl`/`xz` it failed **loudly** rc 2, not
  with a false PASS), **not** about the workflow. That remains **T-P10-1** (owner-gated).
  Carried: `scripts/install-tools.sh` is outside `scripts/lint`'s scope, so `make lint` does not
  cover it (adding `scripts/` would be a lint-scope change this task forbids).
  **B3 cell (v) — the contract-coupled
  fake that exits 0 without doing the work — is NOT implemented and is NOT claimed as
  covered.** **C1 (password-required sudo, F3):** `lib/sudo.sh` distinguishes "no sudo" from
  "sudo needs a password" via `FS_SUDO_PASSWORD`, `sudo_refresh` finally has a production
  caller, and the privilege decision is made ONCE in `lib/runner.sh` from exactly two
  sources — resolved SYSTEM packages, or module metadata `MODULE_PRIVILEGED=1`
  (`lib/modules.sh`, default `0`, reset before every textual parse, strict `0|1`) declared by
  the four genuinely privileged modules (`chrome`, `dns`, `locale`, `vscode`). `need_priv` is
  derived from the SAME `pkgs` array the batch consumes, so there is one planner and no
  hook/prerepo file-existence heuristic; order is resolve/validate → risk gate → **privilege**
  → prereq → batch → state → hooks. `/etc/sudoers` is still never read or written, the `sudo --`
  barrier and dry-run zero-probe are intact, and `lib/check.sh` now tells the truth
  ("non-root with passwordless sudo" vs "non-root; sudo requires a password, so privileged
  steps prompt for one"). **Known C1 limit:** the interactive **prompt itself** is `[MOCK]`-only
  per the task's scope boundary — a real password prompt was never exercised. Also, `vscode`
  in Flatpak-alternative mode **over-declares** privilege (measured refresh=1 / escalation=0):
  conformant, not a regression (the pre-C1 code refreshed unconditionally on every real
  install), and left unfixed by explicit owner boundary — **do not reopen it in D-tasks.**
  State as of C1, now superseded by D1 (which is authoritative for current totals):
  `make lint` OK, smoke **200/0** (stderr 0 bytes), `bash tests/run` rc 0
  (`1..59`, 59 ok), **44 fixture suites / 4090 asserts**, 0 failed, full-battery digest
  byte-identical across 3 runs (`da5a25f265f91c7e`); D1 moved these to `1..60`, 60 ok,
  **45 suites / 4190 asserts**, digest `4320b5d7aee25ebd`. C1 evidence: Dev 2 PASS + fresh-context
  Senior Review PASS, **0 blocking findings**; 8 mutations applied and **all 8 caught**, plus a
  comment-only negative control that correctly escaped (so the harness can report an escape).
  **Bookkeeping honesty carried forward:** the `6337902` commit message's own evidence
  (4128 asserts, digest `eb6be8ec…`, a "127 tests failed" mutation) does not reproduce and
  was corrected in the ROADMAP B3 row rather than amended in git, per §8. `491df20` is a
  stash merge commit carrying B2's production `lib/gnome.sh` change; `stash@{0}` is
  preserved deliberately — do not `git stash pop` it. **Do not rewrite or amend Phase B
  commits.** Branch is `dev/rebuild`; it was detached at `6337902` and fast-forwarded onto
  the branch, not recreated.
- Version: `FS_VERSION="0.1.0-dev"` (see `lib/bootstrap.sh`).

## 2. Repository structure

| Path | Responsibility |
|---|---|
| `setup` | Executable launcher. Resolves its own path from `$0` (no CWD assumption), `set -euo pipefail`, `readlink -f` canonicalization, then `exec`s `lib/bootstrap.sh "$@"`. |
| `lib/bootstrap.sh` | Entry: Bash≥4.3 check, tool/layout checks, sources `io.sh` + `cli.sh`, parses args, dispatches: `help`/`version`/`check`/`list`/`install`/`verify`/`export`/`update` rc0 (install = P4.7 real wiring; verify = P9.2; export = P9.3; update = P9.4); unknown → rc1. Also refuses `--pull` on any command other than `update`, and `_cli_update_sources`/`_cli_update_impl`. Also `_cli_manifest_tree_check`/`_cli_manifest_profile`/`_cli_manifest_check`, the `--manifest` re-import gate, and `_fs_open_run_log` (P9.5: opens this run's audit log on the real install path and **refuses** when the postcondition shows it was not written). |
| `lib/io.sh` | Leveled logging (error/warn/info/debug), TTY-only color, timestamps, progress/summary, audit-log init. `io_*` never abort the caller under `set -e`/`set -u`. `FS_NO_COLOR` is normalized to `0` at source time, so **every color gate must compare numerically** (`(( FS_NO_COLOR == 0 ))`) — a `-z` test is false for the string `"0"` and silently kills color (P8.3, §12). `io_alert` is the one stdout/un-timestamped emitter: it annotates a rendered plan, not the narration (P8.3, §12). P9.5 adds `_io_log_usable` — the ONE `-f && -w && -s` relation for "this run has a real, writable, non-empty audit trail", shared by the `install` guard and the summary's artifacts pointer (§12); `run.sh` keeps its own `-f && -w` check because it must accept a file it is about to write and additionally raises `FS_LOG_INFRA`. |
| `lib/cli.sh` | Flags `--yes/--dry-run/--verbose/--debug/--profile V/--list/--force/--browse/--manifest D/--pull`, `-h/--help`, `--` end-of-options; commands `install|list|check|verify|export|update|help|version`; unknown → rc1. `FS_MANIFEST` (P9.3) names a re-import tree; `FS_PROFILE_SET` records whether `--profile` was given explicitly. |
| `lib/distro.sh` | Reads `/etc/os-release` (or `FS_DISTRO_FILE`, or 1st arg — read-only input). Capability matrix: family/id/pkgmgr/localpkg/flatpak-default/gnome. Test seam `FS_DISTRO_PKGMGR_OVERRIDE`. |
| `lib/state.sh` | State root `$FS_HOME` (test) > `$XDG_STATE_HOME` > `$HOME`, joined with `/fedora-setup`. Run logs, module registry, backup registry. Symlink/confinement-guarded. P9.2 adds `state_root_path` — a pure reader that resolves the root WITHOUT creating it, so a read-only command can report "no state dir yet" instead of manufacturing one. P11-R A1: the module registry carries TWO recorded states, `done` and `skipped` (`MODULE_STATE_DONE`/`MODULE_STATE_SKIPPED`); `state_module_skip` writes the second, `state_module_state` is the single parser of the line, and `state_module_check` is "recorded done", implemented by calling that parser so its four callers cannot disagree. |
| `lib/fs.sh` | `fs_backup`, `fs_install`, `fs_managed_block`/`fs_managed_block_remove`. Atomic temp+rename; managed-block marker covenant (see §12). |
| `lib/sudo.sh` | `sudo_detect`, `sudo_refresh`, `sudo_exec`. Distinguishes **no sudo** (`FS_SUDO_PASSWORD=0`) from **sudo needs a password** (`FS_SUDO_PASSWORD=1`, the `sudo -n true` probe failed), and `sudo_refresh` now has a real production caller in `lib/runner.sh`'s privilege stage. Never touches `/etc/sudoers`. Dry-run keeps probe OFF and executes nothing. `run_sudo` keeps the `sudo --` option barrier and fails closed with `sudo unavailable; cannot escalate` when there is no sudo at all; a **failed refresh** is an error (`sudo credential refresh failed; privileged steps cannot run`), never a silent success. Sourced by `lib/bootstrap.sh` for non-`mock` installs only. |
| `lib/run.sh` | `run_cmd`/`run_sudo` with label, `--stop`, `[DESTROY]` forced stop, dry-run `# would run:` lines, `FS_LOG_FILE` audit trail + `FS_LOG_INFRA` halt. |
| `lib/gnome.sh` | P6.1: gsettings layer — availability checks; `gnome_gsettings_get`/`gnome_gsettings_set` (idempotent probe-then-write; real `gsettings get` renders string scalars single-quoted, so the compare also matches a bare target), strv parse/build/merge + custom-keybinding merge-add primitives; P6.5 capability gate `gnome_require_capable` (`FS_GNOME_FORCE` bypass > SSH-headless > non-GNOME XDG > gsettings-missing); P6.3 `gnome_shell_version`/`gnome_extensions_list`. |
| `lib/summary.sh` | P9.5: the end-of-run summary reporter — `summary_reset`, `summary_module_ok/_skip/_fail`, `summary_line`/`summary_report`, `summary_rc`. The ONLY place module outcomes are counted and where the install exit code is decided; the runner records outcomes and asks this for both. The three `SUMMARY_*_IDS` arrays are the only state, so the printed counts and the rc are one derivation (§12). Abort paths never reach it. |
| `lib/status.sh` | P9.1: the shared PASS/WARN/FAIL table + exit-code rule (`STATUS_PASS/WARN/FAIL`, `STATUS_WORST`, `STATUS_ROWS`, `status_reset`/`status_row`/`status_verdict`/`status_rc`/`status_report`). One implementation of the rule, consumed by both `check` (P9.1) and `verify` (P9.2) so the two tables cannot drift. `STATUS_ROWS` is an **array**, not a counter — count it with `${#STATUS_ROWS[@]}`. |
| `lib/verify.sh` | P9.2: `verify_run <root>` — the read-only audit. Generic layer (system packages via P3.9 `pkg_verify_packages`, flatpaks via the flatpak backend, the P7.5 alt id deduped against the module's own list) plus per-module `verify()` hooks in a subshell that mirrors the runner (exports `FS_MODULE_FAMILY`, `module_load` before sourcing). Rows are `<id>:packages` / `<id>:flatpaks` / `<id>:hook`. Selection: explicit ids → `--profile` closure → P4.6 registry → all modules. Never installs, never marks, never backs up, never sudoes, and does not create a state root. |
| `lib/export.sh` | P9.3: `export_run <root> <outdir> <family> <name> <mdir> <pdir>` — the snapshot writer. Allowlist by construction: manifest lists, the resolved profile conf, an allowlisted gsettings key set, enabled extensions, installed font markers, and the managed blocks only. Writes `export.meta` + `<profile>.conf` + `manifests/` + `state/` + `files/`, every file always present so the tree shape is host-independent. No timestamp anywhere (byte-identical re-exports); refuses a symlinked outdir and skips symlinked managed files. Never reads the state root. Format: `docs/export-format.md`. |
| `lib/update.sh` | P9.4: `update_run <root>` — version/identity reporting and the EXPLICIT self-update. Four states reported distinctly (up-to-date / behind / ahead / diverged); only "behind" may fast-forward, and every merge is `--ff-only`, so this tool can never create a merge commit or rewrite local history. Cleanliness (including **untracked** files) is checked BEFORE the fetch, so a refusal never half-happens. `update` reports; only `update --pull` moves the tree. Every git call carries `-C "$root"`. Depends on `lib/run.sh` (`run_cmd --stop`) + `lib/io.sh`. |
| `lib/runner.sh` | P4.6: `runner_run <modules_dir> <profiles_dir> <name> <family> [module...]` — resolve/plan/prereq/batch/hooks+state/summary stages; deps-first execution, destructive-stop policy, dry-run state-free, hook subshell sandbox. BATCH (P5.7): one batch per namespace — system pkg ids once via the active family backend, flatpak ids once via `( FS_PKG_BACKEND=flatpak; export FS_PKG_BACKEND; plan_install ... )` subshell (self-restoring), system first. PREREQ (P7.5): per module in resolved order, `prerepo.sh` (if present) is sourced in a subshell and `prerepo()` runs ONCE, always (never state-skipped) and BEFORE both batches; `state_init` stays after the batches. Any prerepo failure stops the run (rc1, no batch/hooks/summary) whatever the risk — including a `prerepo.sh` that never defines `prerepo()`. Both hook subshells get `FS_MODULE_FAMILY` **exported** and call `module_load <dir> strict` BEFORE sourcing the hook file, so a hook always sees its own metadata instead of the last module the PLAN stage loaded. SUMMARY (P9.5): the runner holds **no** counter and renders nothing — it records each outcome with `lib/summary.sh` as it happens and then calls `summary_report` + `summary_rc`, so the printed counts and the exit code are one derivation rather than two facts that happen to agree. The abort paths still return rc1 with no summary, which is why the reporter is never reached from them. SKIP (P11-R A1): a hook's `MODULE_HOOK_SKIP` return records `skipped` (never `done`) via `state_module_skip` and reports it as skipped, so a later run re-attempts the module; an unrecordable skip aborts rc1 with no summary, like an unrecordable `done`. RISK GATE (P8.3): refuses rc1 before any prerepo/batch/hook on a high/destructive module that is in the resolved set but NOT in the curated set (the passed module args, or the profile FILE's own ids via `profile_load`) — one `MODULE_DEPENDS` line must never put a destructive module on a system nobody named; a module the profile *does* name stays on the reviewed P4.7 drop-with-alert rc0 path (§12). PRIVILEGE (P11-R C1): between the risk gate and prereq, `need_priv` is derived from the SAME `pkgs` array the batch consumes, or from `MODULE_PRIVILEGED=1`; when set, `sudo_detect` then `sudo_refresh` run exactly once and a **failed refresh aborts rc1 before any privileged mutation**. There is no hook/prerepo file-existence heuristic and no second planner — the plan is the planner. |
| `lib/modules.sh` | Module contract: metadata loading/validation, `module_has_hooks`/`module_has_prerepo`, `list_packages`/`list_flatpaks` for a family, deps, and the P7.5 flatpak-alternative pair `MODULE_FLATPAK_ALT_ID` + `MODULE_FLATPAK_ALT_SEAM` resolved by `module_flatpak_alt` (truthy seam `1|true|yes|on`, case-insensitive). Metadata is parsed TEXTUALLY, never executed; every optional key is reset at load time so a module can never inherit another module's value, and the alt pair is all-or-nothing (id without seam, or a seam that is not an env-var name, fails validation). P11-R A1 adds `MODULE_HOOK_SKIP` (92), the reserved `run()` status for "nothing to do on this host" — distinct from `lib/verify.sh`'s 90/91. P11-R C1 adds `MODULE_PRIVILEGED` (`0|1`, default `0`, reset before every textual parse like every other key): a module declaring `1` requires sudo credential establishment even with no system packages, so `lib/runner.sh`'s privilege stage cannot be inferred from package lists alone. |
| `lib/ui.sh` | P4.7: `ui_multiselect`/`ui_confirm` selection + confirm layer (no external TUI tool — no ncurses; Bash + coreutils execs only). TTY raw-key re-render vs deterministic line-mode; high-risk rows never digit/`a`-toggleable (opt-in prompt is their only checklist route); EOF/`q` abort rc1 fail-closed; atomic sel-file write via `mv -fT`; `ui_confirm` returns 0 under `--yes`; color helpers must keep `return 0` (set -e safety). |
| `tests/smoke.sh` | Plain-bash smoke suite for P2.1–P2.8 + `setup install` dry-run (P4.7) + GNOME capability/`--force` cells (P6.5) + `setup check` (P9.1) + `setup verify` (P9.2) + the P9.5 summary line; 169 asserts. Still the fastest inner loop; P10.1 did **not** convert it to Bats — it kept `smoke.sh` as-is and **added** a Bats layer beside it, so both remain runnable. |
| `tests/run` | P10.1: the single CI entry point. Emits one valid TAP stream from the Bats suite **and** every `tests/fixtures/*.sh` (skipping `lib.sh`, the shared helper), renumbered as a single `1..N` plan. Auto-installs the pinned `bats-core` v1.14.0 if absent (pinned URL + SHA-256; the checkout is gitignored so it is not vendored). |
| `tests/bats/` | P10.1: pinned `bats-core` v1.14.0, **gitignored** (a pinned download in the CI install step, NOT a submodule — ROADMAP §7's stated risk). 24 Bats files. |
| `tests/containers/smoke.sh` | P10.3: the `[REAL]` container suite, run inside Podman against real distro images. Asserts `check` → dry-run fingerprint → plan render → flatpak-absent rc1 contract → real install + idempotency re-run, with GNOME steps **skipped with a printed reason**, never claimed as covered. A timeout prints `INCONCLUSIVE`, skips the asserts it could not reach, and is still recorded as a FAILURE. |
| `.github/workflows/ci.yml` | P10.3: jobs `lint`/`unit`/`container`; matrix `fedora:latest`, `fedora:41`, `debian:stable`, `archlinux:latest` on `fail-fast: false`; checkout bind-mounted READ-ONLY, `--privileged` deliberately not used; `permissions: contents: read`. **NEVER EXECUTED — no run id, no status URL. Do not claim CI is green.** |
| `.shellcheckrc`, `scripts/lint`, `Makefile` | P10.2: shellcheck + shfmt (`-i 4`) + `make lint`. Scope is `lib/`, `lib/pkg/`, `modules/*/*.sh`, `setup` — **`tests/` is deliberately excluded** because P10.4/P10.5 ship deliberately-broken fixture files that would fail lint by design. A consequence to carry: new test files are NOT lint-enforced, so their ShellCheck/shfmt must be run manually. `scripts/install-tools.sh` is **also outside that scope** (D1 added `scripts/lint`'s target list deliberately unchanged, since widening lint scope was forbidden), so it too must be checked by hand — D1 did this, and `tests/fixtures/ci_lint.sh` is the durable guard. |
| `tests/fixtures/regressions.sh` | P10.5: the six documented prototype bugs, one named cell each (sudoers, `.bashrc` overwrite, flatpak ordering, sed-gsettings rewrite, vendored fonts, self-re-exec tab loop). Reads the prototype's lines as **embedded controls**, never from git history, so it stays hermetic in a shallow clone. 76 asserts; 17 mutations caught. |
| `tests/fixtures/canary.sh` | P11-R D2: the **permanent harness-failure canary**. Tests the TEST HARNESS, never production code: it builds a throwaway mini-repo under `$FX_TMP` holding a byte copy of the real `tests/run`, `tests/lib_tap.bash` and `tests/fixtures/lib.sh` plus a stub `bats` and synthetic suites, and executes the real runner in it. Offline, deterministic, ~0.4s, leaves no temp litter. Runs with `set -uo pipefail` and **deliberately without `-e`** (§12). `tests/run` itself is **not** modified; four measured harness gaps (FG-1..FG-4) are **recorded in its header, not fixed** — an open owner item, and FG-2 is the negative control's deliberate subject. 35 asserts; 13 mutations, 11 caught, 2 escaped by construction. |
| `tests/fixtures/ci_lint.sh` | P11-R D1: the hermetic CI-provisioning guard. A fake `curl` serves real bytes and never touches the network; bindirs hold **COPIES**, never symlinks, because a redirect onto a symlinked bindir entry follows it to the host binary (a measured near-miss on `/usr/bin/curl` that would have been fatal as root). Skips are **visible**. Covers missing prerequisites, tampered downloads, stale tools, the failing-copy and failing-rename legs of the atomic install, the `mktemp` staging contract, rpm-free provisioning, the `make lint` invocation contract and its failure propagation, missing-tool behaviour, the real lint on real pinned tools, and the workflow's YAML validity. 108 asserts; 17 of 19 mutations caught. **Its fake tools must be contract-coupled** — a fake `cp` that fails *before* creating its destination makes any litter assertion vacuous (D1 round 1). |
| `modules/` | Module tree: `core`/`flatpak`/`git`/`fonts`/`terminal` (P5.1–P5.6) + `gnome-base`/`gnome-extensions`/`gnome-theme` (P6.2–P6.4) + `vscode` (P7.5) + `chrome` (P7.6) + `dns` (P8.1) + `locale` (P8.2), each `module.sh` + list/config data files, optional `hooks.sh` (`run()`/`verify()`) and optional `prerepo.sh` (`prerepo()`, P7.5). `vscode` is the first prerepo user: it adds the Microsoft repository and imports/dearmors the pinned key before the batch, and has NO `hooks.sh`. `chrome` is the first **hooks-only** module: no list file at all, because its bundle version floats and is resolved at run time. `dns`/`locale` are hooks-only **destructive** modules (`MODULE_DEFAULT=off`, in NO profile), mutating NetworkManager / the systemd locale and both reversible via a state-note record. |
| `config/` | Static repo data: `nerdfonts.sha256` (P5.7 pinned release digests), `extensions.compat` (P6.3 GNOME extension-version report windows), `vscode-gpg.fingerprint` (P7.5 pinned Microsoft repo signing-key fingerprint + provenance). |
| `assets/`, `docs/` | Stubs (tracked `.gitkeep` only). Content arrives in later phases. |
| `profiles/` | P4.5 loadable skeletons; P5.7 real sets: `minimal` = `core flatpak`, `desktop` = `core flatpak git fonts terminal` (comment-only `developer`/`full`). The P6 `gnome-*` modules are deliberately NOT wired into a profile (owner decision from the P6 closure; run them explicitly via `./setup install --yes <id>`). Consumed via `lib/profiles.sh`. P7 modules follow the same explicit-invocation pattern and need no wiring: `vscode` (P7.5) and `chrome` (P7.6) are run by id. `chrome` additionally contributes to *neither* batch namespace, since a hooks-only module ships no list file, so its native work happens entirely in `hooks.sh`. The P8 `dns`/`locale` modules are in **no** profile by design (P8 owner rule: never default-on); `./setup install --yes dns` is the only route, and a `MODULE_DEPENDS` edge cannot pull one in (`lib/runner.sh` refuses it — §12). |
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
- Module seams (P5 base set): `FS_GIT_CONFIG` + `FS_GIT_USER_NAME`/`FS_GIT_USER_EMAIL`, `FS_FONTS_DIR`/
  `FS_NERDFONT_SRC_DIR`/`FS_NERDFONT_CONFIG`/`FS_NERDFONT_SHA256_FILE`/`FS_NERDFONT_ASSETS_DIR`,
  `FS_TERM_ALIASES`/`FS_OMP_{VERSION,ARCH,SRC_DIR}`/`FS_ATUIN_{VERSION,ARCH,SRC_DIR,BIN}`.
- P7.5 seams: `FS_VSCODE_FLATPAK` (truthy `1|true|yes|on` swaps the native install for the
  Flatpak id — exclusive, never additive), `FS_VSCODE_KEY_FILE` (override the pinned
  fingerprint file), `FS_VSCODE_KEYRING` (override the tool-owned dearmored keyring path).
  `FS_MODULE_FAMILY` is not an input seam: the runner EXPORTS it into both `prerepo.sh` and
  `hooks.sh` subshells so a hook never re-detects the distro.
- P7.6 seams: `FS_CHROME_FLATPAK` (truthy `1|true|yes|on` swaps the native bundle for the
  Flatpak id — exclusive, never additive, same P7.5 pair), `FS_CHROME_ARCH` (host-arch override
  for the bundle/index URL, `x86_64|amd64|aarch64|arm64`; anything else is refused),
  `FS_CHROME_DESKTOP_DIR` (verify() target directory, default `/usr/share/applications`).
- P6 GNOME seams: `FS_WALLPAPER_ASSETS_DIR` (gnome-base), `FS_GNOME_BROWSE`/`FS_GNOME_COMPAT_FILE`
  (gnome-extensions), `FS_THEME_{NAME,SRC,ASSETS_DIR}`/`FS_CURSOR_{NAME,SRC,ASSETS_DIR}`/
  `FS_GTK_BOOKMARKS_FILE` (gnome-theme), `FS_GNOME_FORCE` (P6.5 capability-gate bypass).
- P8.1 seams: `FS_DNS_CONNECTION` (name the connection explicitly, so dry-run renders it exactly),
  `FS_DNS_SERVERS` (default `8.8.8.8 8.8.4.4`, space-in/comma-out for nmcli), `FS_DNS_REVERT=1`,
  `FS_DNS_REACTIVATE` (skip the best-effort `nmcli connection up`), `FS_DNS_CHECK_HOST` (default
  `flathub.org`), `FS_DNS_RESOLVE_ATTEMPTS` (clamped 1–5).
- P8.2 seams: `FS_LOCALE` (target locale, default `en_US.UTF-8`; this is the deliberate
  non-prompt alternative to the task's "language choice prompted" clause), `FS_LOCALE_CONF` (file
  to back up, default `/etc/locale.conf`), `FS_LOCALE_REVERT=1`.
- P9.4: **`FS_PULL` is deliberately NOT an env seam** — `cli_parse` resets it unconditionally, like `FS_MANIFEST`, because an inherited `FS_PULL=1` would reintroduce exactly the silent auto-pull P9.4 removes. There is no repo-root seam either: `update` resolves the root from `$0` (`lib/bootstrap.sh` `_fs_script_path`), and the fixture clones the tool into real git repositories rather than redirecting a path.
- P9.3 variables: `FS_MANIFEST` (the tree a re-import reads its ids from; unset = the live tree)
  and `FS_PROFILE_SET` (records whether `--profile` was given explicitly, so a re-import can take
  the profile from `export.meta` only when the user did not name one). These are **not** env
  seams: both are set only by their flags and `cli_parse` resets them unconditionally, so an
  inherited value in the environment can never redirect a run into an untrusted tree. Reach them
  with `--manifest <dir>`. The exporter reuses the existing
  module seams for what it reads — `FS_GIT_CONFIG`, `FS_BASHRC`/`FS_TERM_ALIASES`,
  `FS_FONTS_DIR`/`FS_NERDFONT_CONFIG` — so a fixture can fake the system's managed files.

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
  If a digest is quoted, **state the normalization AND the aggregation exactly** — the P9.5
  figures use this command, and its `sha256` is the one quoted in §1:
  `norm() { sed -E 's#/tmp/fedora-setup-pkg\.[A-Za-z0-9]+#/tmp/FX#g; s#run-[0-9]{8}T[0-9]{6}-[0-9]+\.log#run-TS-PID.log#g; s#\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]#[TS]#g'; }`
  then, once per run, `{ bash tests/smoke.sh; for f in tests/fixtures/*.sh; do [[ "$(basename "$f")" == "lib.sh" ]] && continue; bash "$f"; done; } 2>&1 | norm | sha256sum`
  — i.e. `tests/fixtures/*.sh` in sorted order with `lib.sh` (the shared helper) skipped, and
  **stderr merged into stdout** (`2>&1`, which is what makes FAIL lines part of the digest). A
  digest quoted without both is not re-derivable: normalizing the same bytes but aggregating
  them differently yields a different first-16 (P9.4 and P9.5 both record this). A digest is
  comparable like-for-like only.
- A mutation is only evidence if it is **non-vacuous**, and `cmp` on the edited file proves less
  than it looks (P9.5). Two independent checks are required: the file must differ from the
  baseline, AND the fixture's assert COUNT must differ from the baseline's. `cmp` alone passed a
  harness whose `python3 - args` form read its program from **stdin** — so every "edit" was a
  silent no-op, every "ESCAPED" result was the untouched suite re-reported, and the mutation
  count matched the baseline exactly. Conversely, a result identical to the baseline is a broken
  harness, not a finding; and a mutation that hits only a comment is worse than none. Keep the
  `cmp`, add the count comparison, and prefer `python3 script.py <args>` over `python3 -`.
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
- **A hook's return code is a VERDICT; the audit's "not applicable" signals are
  RESERVED (P9.2).** `lib/verify.sh` owns `_VERIFY_HOOK_NONE=90` and
  `_VERIFY_HOOK_UNDEFINED=91` and renders every OTHER value as a hook verdict,
  because a module `verify()` is free to return anything. An earlier revision
  used rc 2/3 for its own two "no hook" signals, so a `verify()` returning 2 to
  mean FAILURE was reported as WARN "module has no verify() hook" with process
  rc 0 — a real failure audited as clean, and the module's whole point inverted.
  No shipped hook may return 90/91 (all return 0 or 1). Even the residual case
  of a hook that *does* return one fails LOUD — a "no verify() hook" WARN —
  never silent. Three rules follow for anyone writing `verify()`: return 0 only
  for a clean audit, return 1 for a finding, **never** 90/91, and never lean on a
  bare `set -e` — both `_verify_hook` and the runner's hooks stage run as the
  right-hand side of `||`, which suspends `errexit` for the whole subshell.
- **"Nothing to do here" is a THIRD registry state, and it is never `done`
  (P11-R A1).** `lib/modules.sh` owns `MODULE_HOOK_SKIP=92`, the single reserved
  `run()` status for "this module had nothing to do on this host"; `lib/state.sh`
  records it as `skipped <ts>`, which `state_module_check` (implemented through the
  single parser `state_module_state`) does NOT report as done, so a later run
  re-attempts it. The runner counts it as skipped, never `ok` and never failed, so
  `summary_rc` is unaffected; a skip the registry cannot record aborts rc1 with no
  summary, exactly like an unrecordable `done`, because the registry is
  authoritative for both recorded states. A pre-A1 `done <ts>` line keeps meaning
  done — no migration — and an unrecognized state word is refused, never read as
  done. Corollaries: a `run()` returning 92 is the ONLY sanctioned way to say
  "unavailable here", and the three status constants are separate namespaces —
  `verify()` must never return 92, because 90/91 belong to the audit; the registry
  line is parsed with `cut -d' ' -f1`, not `read`, since `state_module_mark` writes
  no trailing newline; and a caller asking "is this module done?" must go through
  `state_module_check` rather than re-reading the file, so the four callers cannot
  disagree. Capability-gated `run()` sites return it; their `verify()` gates do
  not (that is A2's half).
- **`verify` distinguishes PASS / FAIL / SKIPPED (P11-R A2).** `lib/status.sh`
  adds `STATUS_SKIP=1` (`PASS 0 < SKIP 1 < WARN 2 < FAIL 3`), `status_label`
  renders `SKIP`, and `status_verdict` emits "N check(s) skipped". `lib/verify.sh`
  owns `_VERIFY_HOOK_SKIP=93` — a module `verify()` returns this when the check
  cannot be evaluated on this host (missing `gsettings`, non-GNOME session, SSH
  headless, absent optional tool). The harness remaps 90/91 → 200/201 inside
  the nested subshell `(verify)` so a hook returning 90/91 still fails LOUD
  (WARN "reserved audit signal") instead of becoming SKIP. A hook returning
  200/201 directly falls to the `*` arm → FAIL (cannot spoof). The rule for
  `verify()` writers is unchanged: return 0 for clean audit, 1 for finding,
  never 90/91/93, and never rely on bare `set -e`. Exit-code policy: only
  PASS/SKIP → rc0; any WARN → rc0 (known limitation, requires owner decision to
  change shared `lib/status.sh` rule); any FAIL → rc1.
- **An audit hook must check what the installer actually WRITES, not a hand-written
  subset (P9.2).** Three false-PASS defects in one review round were all this
  class: `git` checked the four config *values* but not the section headers, so a
  block git reads as entirely inert (a setting outside any section is ignored)
  audited clean; `terminal` asserted one of the five aliases it installs; and
  `fonts` dropped `list_parse`'s exit status inside a herestring, so an
  unreadable config yielded zero entries and reported "passed (0 sets
  installed)" while `run()` failed on the same file. Two rules, both now
  structural: compare against the **shared body-builder** `run()` itself uses
  (`_git_body`, `_term_aliases_body`/`_term_block`, `_font_marker`) so installer
  and auditor cannot drift, and **check every `rc` you consume** — a command
  substitution inside a herestring does not propagate the substituted command's
  status, so the parse must be captured and tested separately (the same
  postcondition rule as `pkg_add_repo`/`pkg_install_local` in P7.6).
  Corollary for tests: a fixture whose "known good" state is hand-written from
  the same reading of the module as the verifier shares its assumptions and can
  never catch these. Derive the oracle from the hook's own helpers.
- **A derived oracle closes shared-assumption drift; it does NOT close a defect in
  how the installer and the auditor COMPARE that oracle (P9.2, round 3).** B4 is
  the proof: after `git`/`terminal` were switched to the shared body-builders, a
  fully green suite still reported a REORDERED managed block as clean, because
  the auditor compared line **sets** while `fs_managed_block` — the writer —
  compares line **arrays** (`_fs_array_equal`: length first, then element-wise
  ordered). Every line was present and correct, so the set matched; the file was
  not what `run()` writes, so the writer would rewrite it. `git` is section-scoped,
  so the swapped pair had put both values in the wrong section and git read
  neither — audited "identical" in the one sense that mattered. The rule: **the
  auditor's comparison relation must BE the writer's relation, not merely be
  built from the writer's data.** Both hooks now use the same ordered,
  length-sensitive array comparison, applied to identically NORMALIZED lines
  (leading whitespace stripped, blank lines dropped) — normalization is
  deliberately strictly permissive, so it can only turn a mismatch into a match,
  never a false FAIL. Corollary for tests: a mutation cell must assert that its
  mutation is **not a no-op** (`cmp -s` against the good state) — the first
  reorder cell in this round silently changed nothing and would have passed
  vacuously. Corollary for reviews: mutating an *ordering* finds what mutating a
  *membership* cannot; B1–B4 were four different ways to check a weaker thing
  than claimed, and three were invisible to a 215-assert suite.
- **A re-import must consume the exported ids, and "absent" must be a distinct state from
  "no manifest" (P9.3).** `--manifest` replaces BOTH the profile source and the package source:
  `lib/lists.sh` resolves `manifests/<id>.list` and `manifests/<id>.flatpaks.list` instead of the
  module tree, so `install --manifest` reproduces what was exported even after the live lists move.
  The load-bearing rule is that a module ABSENT from the manifest contributes NOTHING and must never
  fall back to its live list. The first revision returned 1 from one helper for both "FS_MANIFEST is
  unset" and "the file is not in the tree", so the caller could not tell them apart and the fallback
  was the default: a re-import quietly consulted the very tree it was meant to replace, and the
  round trip appeared to work because the lists had not drifted yet. Three states are now explicit —
  present, absent, and a symlinked list (refused, since an export tree is untrusted input and a
  symlink would pull arbitrary lines into a package batch). Corollary: the ROADMAP criterion is
  "the re-import dry-runs identically", which is NOT a sufficient test on its own — it is satisfied by
  any implementation that re-reads the live tree. `tests/fixtures/export.sh` therefore pins drift
  detection separately, by mutating the live list after the export and asserting the profile install
  changes while the manifest install does not. Treat the equivalence cell and the authority cell as
  one criterion; either alone is satisfiable by the wrong code.
- **A validator must report WHY it refused, and it must run before the code that depends on it
  (P9.3).** `install --manifest` first resolved the profile from `export.meta` and only then
  validated the tree, and the "no metadata" branch returned 1 with no message — so a nonexistent
  directory, a non-tree directory and a symlink all aborted at rc1 in total silence. A silent rc1 is
  the worst of the three outcomes: it is indistinguishable from a crash, and it taught the fixture
  nothing until the stderr was dumped. The check is now split, and the dependency runs first:
  `_cli_manifest_tree_check` names the exact defect, and only a tree that passed it is asked for its
  profile. This is the same class as the P8.3 "condition that silently never fires" findings —
  plausible-looking code whose failure path was never observed.
- **A completion marker must be invalidated for the whole window in which the tree is being
  rewritten, not merely re-added at the end (P9.3).** `export.meta` is the *only* thing that
  distinguishes a good export tree from a half-written one, so it has to satisfy two symmetric
  conditions: written LAST, and dropped FIRST. Writing it first means a failed export leaves a
  directory a re-import accepts and silently half-populates. Writing it last alone is not enough
  either, because re-export over an existing tree is allowed: the previous run's marker is still
  sitting there, so a refresh that fails part way leaves the OLD marker describing the OLD profile
  next to the NEW manifests, and a re-import replays the previous profile with nothing reporting an
  error anywhere. Worse, the first write is not the profile conf but the **manifest loop** — one
  module at a time, any of which can fail — so a drop placed "next to the other setup" is still a
  hole. The drop goes after the output-path preflight and before the loop. Corollary: a fixture that
  injects its failure in a LATE stage cannot detect a drop placed too early; inject it at three
  different points (a late stage, inside the loop, and the last stage) or the ordering rule is only
  half-pinned. Deliberately NOT dropped during argument and profile validation: that writes
  nothing, and a run rejected for a bad `--profile` must leave a previous good tree valid.
- **A reader must call the writer's own locator, not re-derive the relation (P9.3).** An exporter
  that answers "which lines are the managed block" with its own `awk` is the P9.2 ordered-relation
  defect wearing different clothes: `fs_managed_block` owns that meaning, and a private parser is a
  second implementation that will diverge. The concrete cost found here: the writer demands exactly
  one BEGIN and one END, so it **refuses** a file with two same-name blocks, while a private parser
  concatenated both bodies into one "block" the tool would not manage. `lib/export.sh` now calls
  `_fs_validate_markers`/`_fs_locate`/`_fs_locate_ok` and extracts `_FS_B+1 … _FS_E-1`. Two
  corollaries: (a) **after a shared validator passes, a second check in the reader is often
  unreachable** — a mutation deleting my "unterminated" branch produced 0 FAILs, because
  `_fs_validate_markers` already ends with an open-state check and emits the message itself; dead
  guards were deleted, not kept as defence-in-depth; (b) refusal wording then comes from the shared
  library, so a fixture asserting it must say so, or the next reader will "fix" the apparent
  mismatch by re-adding the dead branch. Also keep **absence distinct from truncation** (no marker
  at all = silently no block; marker with no END = warn and skip) — conflating them makes every
  unconfigured dotfile warn and then contradict itself.
- **The ROADMAP criterion "the re-import dry-runs identically" is satisfied by the wrong code
  (P9.3).** Any implementation that quietly re-reads the live tree passes it. The equivalence cell
  and an authority cell (mutate the live list after the export, assert the profile install changes
  and the manifest install does not) are therefore ONE criterion — either alone is satisfiable by
  the wrong code, and a fixture carrying only the first certifies nothing. Same for the B2 shape in
  `lib/modules.sh`: a manifest-only module cannot be built from the shipped tree (every shipped
  module ships a list for its own family), so that cell uses a synthetic module.
- Module hooks are two separate, single-purpose files (P7.5): `hooks.sh`/`run()` runs AFTER the
  batches, `prerepo.sh`/`prerepo()` runs BEFORE them so a module can configure the repository its
  own `packages.*.list` entries resolve from. `prerepo()` is always-run and idempotent (never
  state-skipped — the P3 `add_repo` primitives are `--if-not-exists`, so it self-heals a deleted
  repo file) and is a **fail-fast** stage: any failure, including a `prerepo.sh` that forgets to
  define `prerepo()`, stops the whole run (rc1) regardless of risk, because the batch it precedes
  may depend on the repository the hook establishes. That is deliberately *not* the
  safe-continue-per-module policy a missing/failing `run()` gets: prerepo is detected before
  anything is installed, so stopping costs no work and no state, while continuing would install
  that module's packages anyway.
- A flatpak alternative is a static metadata pair, never an `if` in a list file (P7.5):
  `MODULE_FLATPAK_ALT_ID` + `MODULE_FLATPAK_ALT_SEAM` (an env-var name). When the seam variable is
  truthy (`1|true|yes|on`) the id goes to the FLATPAK namespace and the module contributes NOTHING
  to the SYSTEM namespace, so the two paths can never install side by side — the SYSTEM list files of
  that module are not even read, so a stale native id there can never reach a batch. The skip is
  scoped to the SYSTEM namespace: the module's own `flatpaks.list` is still read and is additive to
  whichever alternative it declares. "Never side by side" is a **within-one-run** guarantee: the
  state registry gates hooks only, not planning or batches (P4.6 design), so a user who installed
  natively and later flips the seam keeps both on disk. Switching is a manual uninstall, not a
  runner decision. A module without a native package (P7.5 `vscode` on Arch) still
  ships a family list file, even comment-only, because the P4.2 family gate requires one.
- A third-party repository key is **fetched and verified at run time, never vendored** (P7.5): the
  full 40-hex fingerprint from `gpg --show-keys --with-colons` must equal the committed pin, and a
  mismatch refuses everything (no import, no repo file, rc1). rpm imports the key into the rpmdb
  and the repo file relies on it (`gpgcheck=1`, no `gpgkey=`); deb dearmors to a TOOL-OWNED
  keyring and pins it with `signed-by=`. Never overwrite a distro-shipped keyring. `pkg_add_repo`'s
  rc is not trustworthy for a failed write, so the postcondition (repo file / keyring exists and is
  non-empty) is checked after the call, and `pkg_update_metadata` runs explicitly because the
  `_deb_repos_changed` flag cannot cross the prerepo subshell. A downloaded key file holding
  **more than one key** is refused outright, so a bundle cannot be made to satisfy a single-key
  fingerprint check with the expected key listed first. Trade-off, accepted deliberately: pinning
  means a *first* install cannot be done offline, because the key is fetched, never vendored — and
  the tool has no existing offline/cache story to borrow. Do not "fix" this by committing a key.
- A floating-version bundle resolves its `(URL, SHA-256)` pair **at run time from the vendor's own
  repo index** (P7.6 `chrome`); nothing about the version is pinned in-repo. Measured 2026-09-29:
  Google publishes a rolling `*_current_<arch>.deb`, but there is **no rolling rpm name at all**
  (`*_current.<arch>.rpm` is 404), so a "pinned arch URL" is achievable for deb and impossible for
  rpm. Hardcoding a version for either family would install a permanently stale browser. Instead
  both fields come from the SAME stanza of `dists/stable/main/binary-<arch>/Packages` (deb
  `Filename`+`SHA256`) or `repodata/primary.xml.gz` (rpm `<checksum type="sha256">`+
  `<location href>`), so the digest always describes the exact URL. **The rpm `<location href>` is
  repo-relative**: the URL must carry the per-arch repo dir (`.../stable/x86_64/<file>.rpm`); the
  base without it 404s. That was a real bug found while building P7.6 and is pinned by
  `mod_chrome.sh`. Resolution is a `while read` scan that selects the stanza by **exact** package
  name — the indexes carry decoys (`google-chrome-repo`, `-beta`, `-canary`, `-unstable`) with their
  own digests, so a substring or first-match read ships the wrong browser.
- **A SHA-256 check is not signature verification, and P7.6's is deliberately weaker than P7.5's.**
  The Chrome digest detects tampering and corruption in transit and pins the exact bytes the
  metadata described; the index itself is trusted **purely over HTTPS to `dl.google.com`**, and
  nothing verifies a vendor signature or a pinned key. P7.5 could pin a fingerprint because a
  repository key rotates rarely; Chrome's stable channel is expected to move every few weeks, so
  pinning its key into this repo would mean re-pinning constantly. Do not describe this as
  "signature verification", and do not "upgrade" it to a vendored key without an owner decision.
  Sharpening for the same reason: index and bundle arrive over the **same** TLS channel, so the
  digest does not compensate for that channel — it buys corruption detection and a divergent
  mirror/CDN edge, nothing against a compromised `dl.google.com` or a CA.
- **A seam whose rc cannot be trusted must be confirmed by its postcondition** (P7.6, and a real
  Senior Review blocking finding). `pkg_install_local` on rpm/deb calls `run_sudo` **without**
  `--stop`, and `run_cmd`'s keep-going default logs `command failed (rc=N)` then returns 0 — so
  that seam returns 0 for a failed install. Trusting it made the `chrome` module report `1 ok`,
  exit 0, and let `lib/runner.sh` **mark the module done**, permanently skipping the install on
  every later run. The fix is the same rule already recorded for `pkg_add_repo`: after the call,
  require `pkg_query_installed google-chrome-stable` to be rc0, else error + cleanup + rc1. Two
  consequences to preserve: (a) the P3 `run_sudo "install local package" -- …` missing-`--stop`
  gap is a **separate owner ticket**, deliberately not fixed inside P7.6 (§13); (b) the mock
  backend is NOT taught to record a local install, because `mock_install_local` receives only a
  file path and no package name — inventing a filename→package convention is a P3 design change.
  So the fixture drives the install-happy path through **real** rpm/deb seams with fakes that are
  coupled to each other (the fake installer records the package, the fake `rpm -q`/`dpkg-query`
  answers from that same file), which is also what makes the failure cell real. Honest limit of
  the postcondition: it asks "is it installed", not "did my command succeed", so a host that
  **already** has Chrome passes even if this run's install failed — a version bump that silently
  did not happen is the one case it cannot detect.
- A hooks-only module needs **no** list file (P7.6 `chrome`): `module_validate`'s family gate
  passes on the *absence* of all three list kinds, so a bundle resolved at run time ships no
  `packages.*.list` at all — which also removes any chance of a stale native id reaching a batch.
  Note the practical difference from the P7.5 `vscode`-on-Arch case, which still needs a
  comment-only family list to satisfy the gate: a hooks-only module is a separate case, and adding a
  native list file to `chrome` would break the Flatpak exclusivity the pair guarantees.
- **A dry run that cannot reach a seam must not fake it** (P7.6). The P3 `pkg_install_local` opens
  with `[[ ! -f "$file" ]]`, so it requires a real file; a side-effect-free dry run has none. The
  Chrome hook therefore renders the two `wget` steps (the metadata URL is statically derivable from
  family+arch; the bundle URL carries the literal `RESOLVED-AT-RUN-TIME` marker because it only
  exists after resolving the index) and **reports** the install step in an info line rather than
  executing a seam it cannot reach. Dry-run still writes nothing and never touches the network. Do
  not "fix" this by creating a placeholder file in dry-run or by relaxing the P3 precondition for
  every other caller; if a rendered install command is ever required, that is a P3 change and needs
  an owner decision.
- Bash `[[ "$x" == "$pat" ]]` is a **full-string glob match, not a substring test** (P7.6). A line
  read from an index carries leading whitespace, so an unanchored-looking comparison like
  `[[ "$line" == "<name>pkg</name>" ]]` silently never matches while reading as a substring test.
  Use `*"<name>pkg</name>"*` for a substring match, and `[[ "$x" == "exact" ]]` only when equality
  is what you want. This was a real P7.6 bug; `mod_chrome.sh` pins it.
- All code: `#!/usr/bin/env bash` + `set -euo pipefail`; **no comments inside function bodies**
  (file-level doc comments only); `set -e` rule of thumb: io_* wrappers must not abort callers.
- `gsettings` string scalars: real `gsettings get` renders them single-quoted (`'file:///x'`).
  Every compare-before-write must treat a bare target as equal to its quoted rendering
  (`lib/gnome.sh` `gnome_gsettings_set`; the `gnome-base` verify wallpaper compare too) —
  P6.6 found this was a real idempotency bug (wallpapers re-written on every real run). A value
  needing GVariant escapes never matches and is re-written — fails safe (extra write, never a
  skipped needed write).
- **A color gate must compare `FS_NO_COLOR` NUMERICALLY** (P8.3). `lib/io.sh` normalizes
  `FS_NO_COLOR="${FS_NO_COLOR:-0}"` at source time, so the variable is the *string* `"0"` for the
  rest of the run and a `-z "$FS_NO_COLOR"` test is false. `lib/ui.sh` gated its red
  `[high-risk]` flag exactly that way, so **the flag had never once rendered on any TTY** — the
  risk signal the P8.1/P8.2 ledger rows both cite as load-bearing was text-only. The rule is
  `(( FS_NO_COLOR == 0 ))` plus a separate `[[ -t fd ]]`; keep the TTY check so piped output stays
  byte-identical and fixtures never have to know about ANSI. This is the same class of bug as
  P8.1's/P8.2's untrustworthy-rc findings: a plausible-looking condition that silently never fires.
- **A risk gate must distinguish the CURATED set from the RESOLVED set** (P8.3).
  `lib/bootstrap.sh`'s pre-seed filter walks only the profile's curated ids, while
  `lib/profiles.sh` `profile_resolve` then closes that set over `MODULE_DEPENDS` with no risk
  awareness — so the filter had **no teeth over the closure**, exactly like the P4.6 note that the
  state registry gates hooks but not planning. Live repro: one `MODULE_DEPENDS="locale"` line on
  the safe `core` module made `--yes --profile minimal` run `sudo localectl set-locale` with no
  opt-in row, no confirmation, and `locale` in no profile at all. `lib/runner.sh` now refuses rc1
  on any high/destructive module in the resolved set that is not curated (module args, or the
  profile FILE's own ids via `profile_load`), **after** the plan loop — `module_validate` is what
  classifies risk, and planning is pure metadata reading, so rc1 there is as side-effect-free as a
  resolve error. Deliberately NOT extended to the curated case: a high-risk module a profile
  genuinely names is dropped from the checklist with a loud `io_alert` and the run continues rc0,
  which is the reviewed P4.7 contract `install.sh` still pins. Both halves are asserted.
- **A path handed to git is a PATHSPEC, so every per-path query needs
  `--literal-pathspecs` (P9.4, and it cost two rounds of review).** `--` ends option
  parsing; it does **not** end pathspec magic. `git ls-files --error-unmatch -- 'pkg1?2.deb'`
  is therefore answered by a tracked `pkg1x2.deb` and answers about a *different file*. In
  the collision guard that meant "this path is tracked, nothing to lose" — so git replaced the
  user's file, and the run reported `updated to <sha>`, rc 0. Two more measured details of the
  same family: `--literal-pathspecs` is a **git global option and must precede the
  subcommand** (after it, git rejects it with rc 129, so a fix that merely moves it one
  position fails closed rather than open — but the `rc 129` must still be treated as failure,
  not as "not tracked"); and `git check-ignore` accepts **neither** `:(literal)` nor
  `--literal-pathspecs` ("pathspec magic not supported by this command"), so the only correct
  way to ask about one literal path there is `--no-index`. `check-ignore` is also a pathspec
  command, so a glob argument silently answers about a tracked sibling — which is how the
  fixture's own precondition lied and had to be rewritten. Corollary: audit *every* call that
  receives a path, not just the one under review; `lib/update.sh` passes a path to git in
  exactly one place, and that is now the only one that needs the flag.
- **`[[ -e ]]` is not "exists on disk" (P9.4).** It follows symlinks, so it is FALSE for a
  **dangling** one — a symlink into an unmounted drive, or into a file not created yet, which
  is what users hold under `assets/wallpaper/` and `downloads/`. Any "would this clobber
  something?" predicate needs `[[ -e || -L ]]`. This is the same shape as the P8.3
  "condition that silently never fires": the test looks right and is right for regular files,
  which is why the mutation that removed `-L` was the only thing that exposed it.
- **`io_alert` goes to stdout and carries no timestamp** (P8.3) — the one deliberate departure
  from the timestamped `io_*` convention. It annotates a *rendered plan* (the dry-run `!!` warning
  for a high/destructive module), so it must interleave with the plan lines in order, and a
  timestamp would only blur that alignment. Bold+red on a TTY; byte-identical `!! <msg>` when
  piped, so no fixture assertion has to know about ANSI. Audit-logged via `_io_logline` under the
  same prefix.
- **A command that can mutate the tool's own checkout needs an EXPLICIT act, and the
  mutating half must be `--ff-only` (P9.4).** The deleted prototype auto-pulled itself silently;
  `lib/update.sh` inverts that — `update` reports, only `update --pull` moves the tree — and every
  merge is `git merge --ff-only "$up"`, so this tool can never be the thing that creates a merge
  commit or rewrites local history. Divergence is reported as its own state and refused under
  `--pull` with advice, never "resolved". Two consequences worth preserving: `FS_PULL` is NOT an
  env seam (`cli_parse` resets it unconditionally, like `FS_MANIFEST` — an inherited `FS_PULL=1`
  would reintroduce the exact silent auto-pull being removed), and the check order is load-bearing:
  cleanliness (including **untracked** files) is tested BEFORE the fetch, so a refusal never
  half-happens. Corollary for fixtures: an untracked file is a real reason to refuse, because git
  refuses to overwrite one — treating untracked as clean would turn an update into an unpredictable
  mid-way failure.
- **A tool that mutates a working tree must carry its own `-C`, and cleanliness/identity must come
  from the WRITER's notion of the tree, not the caller's (P9.4).** `update` resolves the root from
  `$0` and passes `git -C "$root"` on every call, because `./setup update` run from inside a
  different checkout must inspect THIS tool's repository. The cell that pins it invokes the launcher
  from an unrelated git repository with a dirty file: if any path ran git in the caller's cwd, that
  cell reports the other repository's state. Corollary for tests: a fixture cell that wants to prove
  "this run did not move anything" must compare **git refs**, not file presence — a file created by
  an earlier `publish()` is already in every later clone, so its presence proves nothing. Use
  `rev-parse HEAD` and `rev-parse '@{u}'`; a fetch moves only the latter, a merge only the former.
- **A dry run that cannot reach a seam must say so, and must not render a command it will not
  run (P9.4, extending P7.6).** A dry run may not probe, and comparing against a remote *requires* a
  fetch, so `update --dry-run` cannot know the remote state at all. It renders the fetch, renders
  the merge when `--pull` was given, and states plainly that the comparison was NOT performed. It
  must NOT guess from the last-fetched ref: a stale `@{u}` would let it print "already current"
  about a machine three commits behind. The rendered merge carries a literal
  `RESOLVED-AT-RUN-TIME` marker rather than a plausible-looking `@{u}`, because the real merge
  targets the resolved sha and a line that merely LOOKS runnable invites someone to paste it and get
  different behaviour (P7.6's `chrome` rule, same shape).
- **The postcondition rule applies to a merge exactly as it does to a package install (P9.4).**
  `run_cmd --stop` gives a propagating rc, but rc is not the postcondition: after a fast-forward HEAD
  must EQUAL the upstream sha that was compared against. A `git` that exits 0 without moving HEAD (a
  no-op wrapper, a git that decided there was nothing to do) would otherwise be a failed update
  reported as a success, leaving the tool claiming a version it is not running. The fixture pins
  this with a fake `git` that succeeds at everything and does nothing on `merge`. Corollary: a
  mutation that deletes a postcondition check must be caught by a cell whose fake is
  **contract-coupled** to the state (here: `merge` exits 0, HEAD stays put), not by asserting the
  error message alone.
- **A summary's counts and its exit code must be ONE derivation, and the reporter must own both
  (P9.5).** The old `install` summary was assembled inline by `lib/runner.sh` from three local
  counters, printed by `io_summary`, and turned into an exit code by a separate
  `if (( failed > 0 ))` — three expressions of one fact with nothing tying them together, which is
  the P9.2 B4 shape one level up. The rule is stronger than "keep them in sync": the runner must
  keep **no counter at all** and the reporter must derive every printed number from the *same
  records* the per-failure rows are printed from (`${#SUMMARY_*_IDS[@]}` at render time), so a
  line saying "0 failed" and an rc of 1 are not expressible. Corollary for tests: asserting the
  count and asserting the row list separately is weaker than asserting one line that carries all
  three counts, because only the latter fails when the count is derived from the wrong array —
  and the *combination* 0 ok / 2 skipped / 2 failed is the shape no single-outcome run can reach.
- **An artifacts pointer and the guard that enforces it must be ONE relation, not two tests of
  one property (P9.5).** `artifacts in <log>` is printed only when `lib/io.sh`'s
  `_io_log_usable` accepts the path, and `lib/bootstrap.sh` refuses an install without the SAME
  predicate — one implementation of "this run has a real, writable, non-empty audit trail",
  because the P9.2 B4 defect shape is not limited to module auditors: the first revision tested
  *existence* in the guard and *existence* in the pointer, and they disagreed. Given a
  pre-existing file this run cannot append to, `io_init` skips its write and only warns, the
  file is still there and still non-empty, so the guard passed and the summary named a log
  containing none of the run. With no usable log the clause names which of the two honest
  reasons applies (a dry run writes nothing / no run log was opened). Two corollaries, both
  measured: (a) a seam whose rc cannot be trusted (`io_init` warns and always returns 0) makes
  the FILE's own state the postcondition, and a run that cannot write its audit trail must
  refuse **before** mutating — the P7.6 `pkg_add_repo` rule and the P9.4 fast-forward rule,
  applied to the log; (b) check usability **before** the dry-run branch. A dry run that also has
  an exported `FS_LOG_FILE` (a documented audit seam) DOES print `artifacts in`, because that
  file exists, is writable and really holds the lines this run emitted — "a dry run writes
  nothing" is the fallback, not the rule, and conflating the two orderings makes one of them
  look like a bug. Do NOT fold `run.sh`'s own check into this predicate: run.sh legitimately
  accepts an EMPTY file (it is about to append to it) and additionally raises `FS_LOG_INFRA`,
  so this is a P9.5 notion about a run that has already written something.
- **A row is pinned by its EXACT text, and BOTH rows, not one (P9.5).** `FAIL <id>: hook
  exited <rc>` is a re-substitution of recorded data, and a reporter that rendered a constant
  status — or module A's status on module B's row — satisfied a suite that matched only the
  first row, under 89 green asserts. Match with `grep -qx` on **each** row, with **distinct**
  statuses (`7` and `12`) so neither row can satisfy the other's expectation, and pin the
  status with `$`: a trailing-space `hook exited ` pattern is satisfied by `hook exited 12`.
  The converse is worth proving rather than asserting — with the same recorded status changed to
  `70`, the pinned cell FAILS and the prefix cell PASSES. Note also that a cell comparing only
  the summary LINE and the rc never compared row text at all, so "the line and the rc agree" is
  not "the line is right".
- **A cell placed after the suite's summary block cannot fail the suite (P9.5).** A new cell
  was written, verified green, and provably useless: it sat below the final `summary:` print and
  the final exit-status decision, so its `fx_bad` incremented a counter nothing read. A mutation
  of that cell (dropping the skipped count from the root-run line) printed a `FAIL` line while
  the suite still reported `0 failed` and exited 0 — which is why an ESCAPED result is only
  believable if its counts match the baseline exactly. Rule: new cells go **above** the summary
  block, and the last thing a suite prints must be its verdict.
- **A root-only cell must be VISIBLE in the suite's result (P9.5).** "Prints a note and
  continues" reads as full coverage on a root CI while the branch is untested. Count skipped
  cells and print `summary: N passed, M failed, K skipped (root-only limitation)`. Say plainly
  which branch is unexercised on which host: on uid 1000 with no passwordless sudo, the branch
  that PRINTS the skip count never runs, so only its format is pinned — do not describe the
  unwritable-log refusal as root-covered, and qualify every "all mutations caught" claim with
  the uid it was measured on.
- **A variable that looks like an untrusted redirect may be a documented seam — check before
  "hardening" it (P9.5).** `FS_LOG_FILE` is shaped exactly like `FS_PULL`/`FS_MANIFEST` (a path
  inherited from the environment that redirects output), so `cli_parse` was changed to clear it.
  That broke `tests/fixtures/check.sh` cell 23, which pins that `setup check` appends its table
  to an exported `FS_LOG_FILE`: the variable is a deliberate audit seam for *every* command, and a
  dry run honouring it is consistent rather than a violation. Reverted, with the reporter keying
  off "configured AND exists" instead of "set by this run". Do not re-apply it.
- **A module-level run count is process-global state, so any per-run reset must be pinned by a
  cell that runs the runner TWICE in one process (P9.5).** One install per process is the only
  production path, which is exactly why a removed `summary_reset` was invisible: every fixture
  drove a fresh process, and the reporter's "after reset" cell called `summary_reset` itself
  rather than observing the runner's. The fixture now calls the real `runner_run` twice in one
  shell and asserts the second summary. Corollary, and the general form: when you delete a reset
  call, ask which single process would have observed the leak.
- **Refusing high-risk selections when stdin is not a TTY was written, measured, and REJECTED**
  (P8.3). It broke `tests/fixtures/install.sh` (4 FAILs) because those reviewed cells drive the
  high-risk opt-in + confirmation **entirely by piped stdin** — refusing every piped high-risk
  selection makes the whole P4.7 consent flow untestable without a pty. It also contradicts the
  P8.3 task text, which names a *direct `install dns` invocation* as consent in its own right, and
  it defends against nothing: a script able to pipe `y` into `./setup` can just run `nmcli`
  directly. The shipped contract is the pre-existing one — naming the module is consent, the
  confirmation is real, declining it aborts rc1 before any batch. Do not re-propose this gate
  without a new argument.
- **`--stop` belongs at every MUTATION call site (Phase B1, ROADMAP F1).** `lib/run.sh`
  deliberately maps a failed command to keep-going-returning-0 unless the caller passes
  `--stop` — that default is a reviewed P2.7 decision and callers depend on it, so the fix is
  never to invert it but to add `--stop` at each site that mutates. Every `dnf`/`apt-get`/
  `pacman`/`flatpak` call in `lib/pkg/{rpm,deb,arch,flatpak,mock}.sh` and the `gsettings set`
  in `lib/gnome.sh` relies on this seam, and without it a failed transaction reported success,
  the module was marked `done`, and every later run skipped it forever. Where an effect
  cannot be trusted from the rc at all, the established **postcondition rule** applies instead
  (or as well) — verify the effect, not the return code.
- **`--stop` alone is INSUFFICIENT when a later command can discard the rc (Phase B2 / N1).**
  This is the B2 and Flatpak finding in one shape, and it is strictly stronger than B1: B1's
  bug was a missing `--stop`, while these are call sites that *already* had `--stop` and were
  still wrong, because the function **fell through to the next step** and that step's own
  `return` overwrote the status. `lib/gnome.sh` had `|| rc=$?` then `return "$rc"` — correct in
  intent, inert in fact. `lib/pkg/flatpak.sh` `flatpak_install_batch` let a failed Flathub
  `remote-add` fall through to `flatpak install`, so a fake whose `remote-add` exits 7 and whose
  `install` succeeds made the whole batch report rc 0 for a remote that was never added. The
  rule: **after any `--stop` call inside a multi-step function, propagate immediately
  (`|| return $?`), because a keep-going seam returns 0 on success and the NEXT step is free
  to overwrite whatever you were holding.**
- **A canary must exercise the REAL harness, and a recorded measurement must be re-derivable
  (P11-R D2).** Two rules, both from D2's round-1 blocking findings, and both general:
  (a) **Copy the runner; never re-derive it.** The canary builds a throwaway mini-repo holding a
  **byte copy** of `tests/run` (+ `tests/lib_tap.bash` + `tests/fixtures/lib.sh`) and executes that.
  Re-implementing the runner's logic inside a test is the P9.3 "private parser" defect one level
  up: a second implementation that agrees with the first until it doesn't, and which can then be
  "fixed" to agree with a bug. Byte-identity of every copied file is asserted, so a `cn_build` that
  starts generating or patching the runner goes red instead of silently retargeting the canary.
  (b) **A permanent record of measured facts is a deliverable, so a wrong one is a defect.** D2's
  header shipped two false measurements on the first write: FG-1's plan line, and — worse — FG-3,
  whose *stated construction* (`fx_summary || true` after a real assertion failure) is actually
  **caught**, because `fx_bad` writes a `FAIL ` line. A gap record that names the wrong shape sends
  the next engineer to fix a non-bug. Corollaries: re-measure, do not re-reason; and when a
  measurement is corrected, **leave the wrong value and the reason it was wrong in the record**
  rather than silently overwriting it, because "we were wrong once here" is itself the warning that
  stops the next reader trusting the neighbouring claim.
- **An ordering invariant must be an ORDERING check, and its controls must cover the shape the
  hazard actually takes (P11-R D2).** AGENTS §12's "a cell placed after the summary block cannot
  fail the suite" is an ordering property, and D2's first implementation was a **text-presence**
  check: its `fi` arm reduced to `grep -q fx_summary "$1"` *anywhere in the file*, so it accepted
  `fx_summary` followed by `fx_bad` inside `if … fi` — the exact hazard — while falsely refusing a
  trailing comment. A presence check answers "is the token in the file", not "is the epilogue last";
  the difference is invisible until you build the adversarial input. Two rules: state the rule on
  the last two **executed** lines (here: last line is `fx_summary`, optionally with a trailing
  comment; or last line is `fi` AND the line before it is `fx_summary` — ignoring blank lines and
  whole-line comments), and give **every shape its own control**, because a single control does not
  cover the conditional form that two real suites actually use. Corollary: a deliberately tolerant
  rule must record what it tolerates and what it falsely refuses (here: 12 legitimate Bash epilogue
  shapes — `case…esac`, `…done`, `( )`, `{ }`, a function definition — none shipped, error
  direction a false RED, so it cannot hide a defect). Widening it requires a control for the new
  shape, never deleting the `fi` arm.
- **`errexit` must sometimes be OFF, and then the omission is load-bearing and must be documented
  (P11-R D2).** `tests/fixtures/canary.sh` runs with `set -uo pipefail` and **no `-e`**, the one
  place in the repo that omits it, because it exists to observe a **failing** `tests/run`: under
  `-e` the shell aborts inside `cn_exec` at the first deliberately-failing synthetic suite, so the
  suite dies with rc 1 and no summary instead of reporting anything (measured both ways). The
  general rule: a suite
  that drives a failing subject must either disable errexit or guard every such call, and **whichever
  it chose must be stated in the header** — an undocumented omission reads as an oversight and
  invites the next maintainer to "fix" it into a suite that cannot report anything.
- **A restricted-PATH (or otherwise narrowed-environment) negative control must PROVE harness
  completeness before any failure assertion on it can be trusted (Phase B3).** The B3 cells ran
  a minimal `PATH` to keep the run hermetic and guarantee "no flatpak binary anywhere" — and
  the `PATH` was missing `mkdir`, so `state_init` aborted *before* the stage under test and
  produced the very "rc1, no hooks, no state" shape the cell was asserting. The cell was green
  for the wrong reason and a removed guard still passed. Two rules follow, both load-bearing:
  (1) add a **positive control** that drives the SAME narrowed environment to a successful,
  fully-observable finish, so a later "nothing happened" can only come from the code under
  test — dropping one tool from the list must turn the control red, not just the failure cells;
  and (2) choose the environment **per cell** so the stage AFTER the one under test would
  otherwise SUCCEED — otherwise it fails at the same point with the same rc and masks the very
  guard being measured. The two guards must fail **disjointly** under mutation; if removing
  either one breaks the same assertions, they are not separately covered.
- **A static source-text grep is NOT a behavioural mutation test (Phase B3).** B3 "verified" its
  guards by grepping `lib/runner.sh` for the literal `|| {` after each `plan_install`. That
  asserts something about a file's TEXT: it survives any refactor that moves the logic, it
  cannot tell a working guard from a comment, and it was the *only* thing standing between the
  suite and a fully vacuous cell — the same commit's mutation claim (4128 asserts, digest
  `eb6be8ec…`, "127 tests failed") does not reproduce at all; measured at `6337902` the battery
  was 3950 asserts with digest `b02f62ac…` and the guard removal produced **2** failures, the
  behavioural one being a stderr match while every no-hooks/no-state assertion still passed.
  The check was replaced by real mutations. Corollary for reviewers: **a commit message's own
  evidence figures are a claim to be re-derived, not a fact** — and per §8 they are corrected in
  the ledger, never by amending the commit.
- **A fixture cell that mutates shared state must OWN that state (Phase B3 / N1).** The N1 cell's
  fake `flatpak` recorded into the suite-shared installed-set file; when a mutation *did* reach
  the install step, the app stayed recorded, every later cell then saw it as already installed,
  filtered it out of `missing`, and returned 0 — so one cell's bug silently cascaded into
  unrelated B1 cells and their results stopped meaning anything. Give each state-mutating cell
  private installed-set/list/log files under the temp root. Related: `set +e` must be scoped to
  the single call under test — left around the whole subshell it disables the suite's own
  errexit, and placed *outside* it (or absent) the cell's errexit manufactures the exact rc it
  is asserting, which makes the assertion unpinnable.

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