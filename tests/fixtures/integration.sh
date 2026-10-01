#!/usr/bin/env bash
# tests/fixtures/integration.sh - P10.4 mock-backend integration suite.
# Full planning/batching/module-run flows on the mock backend, plus the
# failure paths the per-lib fixtures do not isolate: PARTIAL install (only the
# missing packages are batched), MISSING FLATHUB (the remote is added before
# the first flatpak install), an INTERRUPTED run resumed through the state
# registry, and a DELIBERATELY-BROKEN module that fails on every run without
# the resume recursing into already-completed modules.
#
# Everything runs through the real launcher (./setup install) against the mock
# family backend and a stateful fake flatpak binary, so the whole install path
# (cli -> bootstrap -> profile_resolve -> dep_toposort -> plan_install -> batch
# -> state registry -> summary) is exercised end to end. State, mock
# installed-set/call log, and the flatpak fake log/installed set all live under
# FX_TMP so no system path or privilege is touched.
#
# NOTE on the two non-obvious couplings below, both pinned by cells here:
#   * plan order is deps-first and, at equal depth, LC_ALL=C lexicographic --
#     so a profile reading "core apps" EXECUTES apps before core. An assertion
#     on hook order must use the real order, not the profile's. The tie-break is
#     load-bearing HERE even with no MODULE_DEPENDS edge in the profile: the
#     profile order (core, apps) differs from the executed order (apps, core),
#     so a plan that skipped dep_toposort entirely and used profile order would
#     fail the hook-order cell (measured).
#   * a module hook runs in a subshell that is the right-hand side of `||`, so
#     errexit is suspended for its whole body (AGENTS.md 12). A hook that
#     relies on a bare `set -e` therefore SWALLOWS a failed run_cmd and returns
#     the last command's status -- the module is then marked done despite
#     having failed. The flaky/broken hooks below propagate EXPLICITLY with
#     `|| return 5` / `|| return 3` (see MEASURED LIMITS for why the status
#     matters).
#
# The fake flatpak wins over this host's REAL /usr/bin/flatpak purely by being
# first on PATH (run_install puts $FAKE ahead of $PATH, and ./setup is exec'd
# as a fresh bash so the command hash starts empty). Proof that the fake -- not
# the real binary -- is what runs: FS_FAKE_INSTALLED receives the app id, and
# only the fake writes it.
#
# MEASURED LIMITS of this suite (do not read the cells as more than they are):
#   * "only the missing packages are batched" is filtered in TWO independent
#     places -- lib/planner.sh plan_pending AND lib/pkg/mock.sh
#     mock_install_batch. Removing EITHER layer alone is invisible here (both
#     single-layer mutations were measured to ESCAPE, 40/40 green), so cell 2
#     pins the end-to-end property and neither layer on its own. Only the
#     combined removal is caught.
#   * cell 3 pins remote-add BEFORE install, not that the remote-add is
#     idempotent; the `--if-not-exists` flag itself is covered by pkg.sh's cells.
#   * the fake flatpak records argv, so it cannot detect a wrong flag VALUE
#     (e.g. --user becoming --system) beyond what the recorded line shows.
#   * the "exactly one transaction" asserts in cells 4/5 measure RUN 1's
#     batching. The resume genuinely re-enters plan_install (the batch stage
#     precedes state_init); it records no new transaction only because every
#     package is already installed. So those cells do not prove the resume
#     skipped planning -- the hook-log and 'already completed' pins do.
#   * the FAIL rows ARE pinned with DISTINCT statuses (flaky exits 5, broken
#     exits 3), so a reporter rendering a constant status, or the other
#     module's, is caught here (both mutations measured CAUGHT). The hooks
#     substitute the status with `|| return N` because lib/run.sh's run_cmd
#     normalizes a failed command to 1 even under --stop -- but that rc governs
#     only how the HOOK reacts, since lib/runner.sh records the hook subshell's
#     own status verbatim. tests/fixtures/summary.sh covers the same property
#     with its own distinct statuses (7 and 12).
#   * the flatpak "exactly one transaction" COUNT pin does not prove one batch
#     invocation per run: duplicating the batch block is invisible, because the
#     second plan_install re-enters the same already-installed filter and
#     records nothing (measured to ESCAPE). The count pins the transaction
#     count, not the invocation count -- the same double-layer mask as cells
#     4/5.
#   * measured on uid 1000 with no passwordless sudo. No cell is
#     root-conditional (the mock backend skips sudo_detect and no run_sudo is on
#     the path), so the suite is uid-independent BY REASONING -- but the
#     measurement itself is uid-1000 only. Do not call it root-covered.
#
# Usage: bash tests/fixtures/integration.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/M" "$FX_TMP/P"

printf 'P10.4 mock-backend integration\n'

FAKE="$FX_TMP/fakebin"
M="$FX_TMP/M"
P="$FX_TMP/P"

printf '#!/usr/bin/env bash\nprintf '"'"'%%s\\n'"'"' "${1:?}" >>"${HOOK_LOG:?}"\n' >"$FAKE/logrec"
printf '#!/usr/bin/env bash\nexit "${1:-1}"\n' >"$FAKE/failrun"
printf '#!/usr/bin/env bash\n: >"${1:?}"\n' >"$FAKE/touchfile"
{
    printf '#!/usr/bin/env bash\n'
    printf 'printf '"'"'flatpak %%s\\n'"'"' "$*" >>"${FS_FAKE_LOG:?}"\n'
    printf 'case "${1:-}" in\n'
    printf '  info)\n'
    printf '    app="${3:-}"\n'
    printf '    grep -qxF -- "$app" "${FS_FAKE_INSTALLED:?}" 2>/dev/null\n'
    printf '    exit $?\n'
    printf '    ;;\n'
    printf '  install)\n'
    printf '    shift\n'
    printf '    for a in "$@"; do\n'
    printf '        case "$a" in --*) continue;; esac\n'
    printf '        grep -qxF -- "$a" "${FS_FAKE_INSTALLED:?}" 2>/dev/null || printf '"'"'%%s\\n'"'"' "$a" >>"${FS_FAKE_INSTALLED:?}"\n'
    printf '    done\n'
    printf '    exit 0\n'
    printf '    ;;\n'
    printf 'esac\n'
    printf 'exit 0\n'
} >"$FAKE/flatpak"
chmod +x "$FAKE/logrec" "$FAKE/failrun" "$FAKE/touchfile" "$FAKE/flatpak"

mkmod() {
    local id="$1" risk="${2:-none}" deps="${3:-}"
    mkdir -p "$M/$id"
    {
        printf 'MODULE_ID=%s\n' "$id"
        printf 'MODULE_RISK=%s\n' "$risk"
        printf 'MODULE_DEFAULT=off\n'
    } >"$M/$id/module.sh"
    if [[ -n "$deps" ]]; then
        printf 'MODULE_DEPENDS=%s\n' "$deps" >>"$M/$id/module.sh"
    fi
}

standard_hook() {
    local id="$1"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'run() {\n    run_cmd "hook %s" "$FAKE_LOG_REC" %s\n}\n' "$id" "${id^^}"
    } >"$M/$id/hooks.sh"
}

# --- modules -------------------------------------------------------------

mkmod core
standard_hook core
printf 'core1\ncore2\n' >"$M/core/packages.list"

mkmod apps
standard_hook apps
printf 'apps1\n' >"$M/apps/packages.list"
# TWO apps on purpose: with a single app a backend that installed one-app-per-
# transaction would be indistinguishable from a correct single transaction,
# and the "exactly one flatpak transaction" pin below would be vacuous.
printf 'org.sample.App\norg.sample.B\n' >"$M/apps/flatpaks.list"

mkmod flonly
printf 'org.sample.F\n' >"$M/flonly/flatpaks.list"

# a module whose hook fails on the FIRST run only (flag file): the resume
# must retry it, not re-process the modules that already completed.
#
# The hook propagates EXPLICITLY (`|| return`) because the subshell suspends
# errexit, and it substitutes a DISTINCT status (5) rather than run_cmd's
# normalized 1. lib/run.sh's run_cmd returns 1 for a failed command even under
# --stop, but that rc governs only how the HOOK reacts -- lib/runner.sh records
# the hook subshell's own status verbatim in `hook exited $rc`, so `|| return 5`
# is what reaches the reporter. Two failing modules with DIFFERENT statuses (5
# and 3) mean a reporter rendering a constant, or the other module's, status
# is caught here rather than looking correct (both measured CAUGHT).
mkmod flaky
printf 'flaky1\n' >"$M/flaky/packages.list"
{
    printf '#!/usr/bin/env bash\n'
    printf 'run() {\n'
    printf '    if [[ ! -f "$FLAKY_FLAG" ]]; then\n'
    printf '        run_cmd "flaky mark" -- "$FAKE/touchfile" "$FLAKY_FLAG" || return 1\n'
    printf '        run_cmd "flaky fail" --stop -- "$FAKE/failrun" 5 || return 5\n'
    printf '    fi\n'
    printf '    run_cmd "flaky done" "$FAKE_LOG_REC" FLAKY\n'
    printf '    return 0\n'
    printf '}\n'
} >"$M/flaky/hooks.sh"

# a DELIBERATELY-BROKEN module: its hook always fails. It is never marked done,
# so every run retries it exactly once -- and the resume must not recurse into
# the modules that already completed.
mkmod broken
printf 'broken1\n' >"$M/broken/packages.list"
printf '#!/usr/bin/env bash\nrun() {\n    run_cmd "broken fail" --stop -- "$FAKE/failrun" 3 || return 3\n}\n' \
    >"$M/broken/hooks.sh"

printf 'core\napps\n' >"$P/full.conf"
printf 'core\n' >"$P/core.conf"
printf 'flonly\n' >"$P/flonly.conf"
printf 'core\nflaky\n' >"$P/flaky.conf"
printf 'core\nbroken\n' >"$P/bkonly.conf"

STATE_DIR() { printf '%s/.local/state/fedora-setup/modules' "$1"; }

run_install() {
    local home="$1" profile="$2"
    (
        set -euo pipefail
        export FS_PKG_BACKEND=mock FS_HOME="$home" FS_DISTRO_FAMILY=rpm
        export FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
        export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
        export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
        export FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
        export FAKE FLAKY_FLAG="${FLAKY_FLAG:-}" PATH="$FAKE:$PATH"
        "$ROOT/setup" install --yes --profile "$profile"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
}

# --- 1. happy path: full flow, one batch per namespace, state, summary -----

HOOK_LOG="$FX_TMP/hook1.log"
MOCK_LOG="$FX_TMP/m1.log"
INSTALLED="$FX_TMP/i1"
FAKE_LOG="$FX_TMP/f1.log"
FAKEST="$FX_TMP/fs1"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"

run_install "$FX_TMP/h1" full
fx_block_rc "happy path rc0" 0
fx_out '^  - 2 modules ok · 0 skipped · 0 failed · '
fx_out '^== run complete ==$'
# the batch must contain all three system packages (order is the runner's
# deps-first plan, not the profile order, so match on content not sequence)
BATCH_LINE="$(grep '^mock install ' "$MOCK_LOG")"
if [[ "$BATCH_LINE" == *"core1"* && "$BATCH_LINE" == *"core2"* && "$BATCH_LINE" == *"apps1"* ]]; then fx_ok
else fx_bad "system batch installed all three packages in one transaction"; fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.sample.App org.sample.B' "$FAKE_LOG"; then fx_ok
else fx_bad "flatpak batch installed both apps in one transaction"; fi
# exactly ONE flatpak install transaction for the TWO apps above, so a backend
# that installed one-app-per-transaction is caught rather than looking correct.
# This pins the TRANSACTION count, not the invocation count (see header).
if [[ "$(grep -c '^flatpak install ' "$FAKE_LOG")" == "1" ]]; then fx_ok
else fx_bad "flatpak namespace was not exactly one transaction"; fi
if grep -qxF 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$FAKE_LOG"; then fx_ok
else fx_bad "flathub remote was added"; fi
if [[ -f "$(STATE_DIR "$FX_TMP/h1")/core" && -f "$(STATE_DIR "$FX_TMP/h1")/apps" ]]; then fx_ok
else fx_bad "both modules marked done"; fi
if [[ "$(cat "$HOOK_LOG")" == "APPS
CORE" ]]; then fx_ok; else fx_bad "hooks ran in order"; fi

# --- 2. partial install: only the missing packages are batched -----------

HOOK_LOG="$FX_TMP/hook2.log"
MOCK_LOG="$FX_TMP/m2.log"
INSTALLED="$FX_TMP/i2"
FAKE_LOG="$FX_TMP/f2.log"
FAKEST="$FX_TMP/fs2"
: >"$MOCK_LOG"; : >"$FAKE_LOG"; : >"$FAKEST"
printf 'core1\n' >"$INSTALLED"

run_install "$FX_TMP/h2" core
fx_block_rc "partial install rc0" 0
# core1 was already installed: the batch must contain ONLY core2.
if grep -qxF 'mock install core2' "$MOCK_LOG"; then fx_ok
else fx_bad "partial install batched only the missing package"; fi
if grep -qxF 'mock install core1 core2' "$MOCK_LOG"; then
    fx_bad "partial install re-installed an already-present package"
else fx_ok; fi
if grep -qxF 'core1' "$INSTALLED" && grep -qxF 'core2' "$INSTALLED"; then fx_ok
else fx_bad "installed set has both packages"; fi

# --- 3. missing flathub: remote added before the first install -----------

HOOK_LOG="$FX_TMP/hook3.log"
MOCK_LOG="$FX_TMP/m3.log"
INSTALLED="$FX_TMP/i3"
FAKE_LOG="$FX_TMP/f3.log"
FAKEST="$FX_TMP/fs3"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"

run_install "$FX_TMP/h3" flonly
fx_block_rc "missing flathub rc0" 0
# the remote-add must come BEFORE the install in the fake flatpak log.
RA_LINE=$(grep -n 'flatpak remote-add' "$FAKE_LOG" | head -1 | cut -d: -f1)
IN_LINE=$(grep -n 'flatpak install' "$FAKE_LOG" | head -1 | cut -d: -f1)
if [[ -n "$RA_LINE" && -n "$IN_LINE" && "$RA_LINE" -lt "$IN_LINE" ]]; then fx_ok
else fx_bad "flathub remote-add did not precede the install (ra=$RA_LINE in=$IN_LINE)"; fi
if grep -qxF 'org.sample.F' "$FAKEST"; then fx_ok
else fx_bad "flatpak recorded installed"; fi

# --- 4. interrupted run -> resume: completed modules are not re-processed -

HOOK_LOG="$FX_TMP/hook4.log"
MOCK_LOG="$FX_TMP/m4.log"
INSTALLED="$FX_TMP/i4"
FAKE_LOG="$FX_TMP/f4.log"
FAKEST="$FX_TMP/fs4"
FLAKY_FLAG="$FX_TMP/flaky-flag"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"; rm -f -- "$FLAKY_FLAG"

run_install "$FX_TMP/h4" flaky
fx_block_rc "interrupted run rc1" 1
fx_err 'module failed: flaky$'
fx_out '^  - FAIL flaky: hook exited 5$'
fx_out '^  - 1 modules ok · 0 skipped · 1 failed · '
if [[ -f "$(STATE_DIR "$FX_TMP/h4")/core" && ! -e "$(STATE_DIR "$FX_TMP/h4")/flaky" && ! -L "$(STATE_DIR "$FX_TMP/h4")/flaky" ]]; then fx_ok
else fx_bad "only the completed module is marked"; fi
if [[ "$(cat "$HOOK_LOG")" == "CORE" ]]; then fx_ok; else fx_bad "flaky hook did not complete"; fi

# resume: core is skipped, flaky is retried and now succeeds.
run_install "$FX_TMP/h4" flaky
fx_block_rc "resume rc0" 0
fx_out 'already completed: core$'
fx_out '^  - 1 modules ok · 1 skipped · 0 failed · '
if [[ -f "$(STATE_DIR "$FX_TMP/h4")/flaky" ]]; then fx_ok; else fx_bad "resume marked flaky"; fi
if [[ "$(cat "$HOOK_LOG")" == "CORE
FLAKY" ]]; then fx_ok; else fx_bad "resume re-ran the completed core hook"; fi
# run 1 issued exactly ONE system transaction. The resume DOES reach
# plan_install again (the batch stage runs before state_init), but both
# packages are already in FS_MOCK_INSTALLED, so it records no new
# transaction -- see the double-filter note in the header. This count is
# therefore about run 1's batching, NOT about the resume skipping work.
if [[ "$(grep -c '^mock install ' "$MOCK_LOG")" == "1" ]]; then fx_ok
else fx_bad "system batch was not exactly one transaction"; fi

# --- 5. deliberately-broken module: fails every run, no recursion -------

HOOK_LOG="$FX_TMP/hook5.log"
MOCK_LOG="$FX_TMP/m5.log"
INSTALLED="$FX_TMP/i5"
FAKE_LOG="$FX_TMP/f5.log"
FAKEST="$FX_TMP/fs5"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"

run_install "$FX_TMP/h5" bkonly
fx_block_rc "broken run 1 rc1" 1
fx_err 'module failed: broken$'
fx_out '^  - FAIL broken: hook exited 3$'
fx_out '^  - 1 modules ok · 0 skipped · 1 failed · '
if [[ -f "$(STATE_DIR "$FX_TMP/h5")/core" && ! -e "$(STATE_DIR "$FX_TMP/h5")/broken" && ! -L "$(STATE_DIR "$FX_TMP/h5")/broken" ]]; then fx_ok
else fx_bad "broken module was marked done despite failing"; fi

# resume: core is skipped (no recursion), broken is retried and fails again.
run_install "$FX_TMP/h5" bkonly
fx_block_rc "broken run 2 rc1" 1
fx_out 'already completed: core$'
fx_out '^  - FAIL broken: hook exited 3$'
fx_out '^  - 0 modules ok · 1 skipped · 1 failed · '
if [[ ! -e "$(STATE_DIR "$FX_TMP/h5")/broken" && ! -L "$(STATE_DIR "$FX_TMP/h5")/broken" ]]; then fx_ok
else fx_bad "broken module marked done on the second failure"; fi
# core's hook ran exactly once across both runs (no recursion into completed).
if [[ "$(cat "$HOOK_LOG")" == "CORE" ]]; then fx_ok
else fx_bad "resume re-ran the completed core hook"; fi
# the system batch ran once; the resume added no new batch.
if [[ "$(grep -c '^mock install ' "$MOCK_LOG")" == "1" ]]; then fx_ok
else fx_bad "resume added a system batch"; fi

fx_summary
