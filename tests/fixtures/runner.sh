#!/usr/bin/env bash
# tests/fixtures/runner.sh - P4.6 fixture for lib/runner.sh.
# End-to-end mock run of the full resolve -> plan -> ONE batch -> ordered
# hooks -> state-marking -> summary pipeline, plus resume (already-
# completed modules skipped), safe-continue vs destructive stop, family
# gate, dry-run side-effect-freedom, CLI override, hookless modules, and
# hook-subshell isolation. State, mock installed-set and mock call log
# all live under FX_TMP so no system path or privilege is touched.
# Usage: bash tests/fixtures/runner.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/M" "$FX_TMP/P" "$FX_TMP/inst" "$FX_TMP/hh"

printf 'P4.6 module runner\n'

FAKE="$FX_TMP/fakebin"
M="$FX_TMP/M"
P="$FX_TMP/P"

printf '#!/usr/bin/env bash\nprintf '"'"'%%s\\n'"'"' "${1:?}" >>"${HOOK_LOG:?}${HMARK:-}"\n' >"$FAKE/logrec"
printf '#!/usr/bin/env bash\nexit "${1:-1}"\n' >"$FAKE/failrun"
printf '#!/usr/bin/env bash\n: >"${1:?}"\n' >"$FAKE/touchfile"
chmod +x "$FAKE/logrec" "$FAKE/failrun" "$FAKE/touchfile"

# --- module tree ---------------------------------------------------------

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

mkmod a;      standard_hook a
mkmod b none a; standard_hook b
mkmod c none b; standard_hook c
mkmod d destructive c
printf '#!/usr/bin/env bash\nrun() {\n    run_cmd "d fail" --stop -- "$FAKE/failrun" 7\n}\n' >"$M/d/hooks.sh"
mkmod e none d; standard_hook e
mkmod cfg
mkmod exo; printf 'x-contents\n' >"$M/exo/packages.deb.list"
mkmod leak
{
    printf '#!/usr/bin/env bash\n'
    printf 'LEAKY=top\n'
    printf 'run() {\n    LEAKY="$LEAKY-r"\n    run_cmd "hook leak" "$FAKE_LOG_REC" leak\n}\n'
} >"$M/leak/hooks.sh"
mkmod bare
mkmod norun
printf '#!/usr/bin/env bash\necho "no run defined here"\n' >"$M/norun/hooks.sh"

printf 'a1\na2\n' >"$M/a/packages.list"
printf 'b1\n'     >"$M/b/packages.list"
printf 'c1\n'     >"$M/c/packages.list"
printf 'org.sample.C\n' >"$M/c/flatpaks.list"
printf 'd1\n'     >"$M/d/packages.list"
printf 'e1\n'     >"$M/e/packages.list"
printf 'cfgx\n'   >"$M/cfg/packages.list"
printf 'leakp\n'  >"$M/leak/packages.list"
: >"$M/bare/packages.list"

# --- profiles ------------------------------------------------------------

printf 'c\nb\na\n' >"$P/full.conf"
printf '# comment-only skeleton\n' >"$P/minimal.conf"
printf 'exo\n' >"$P/fam.conf"
printf 'cfg\n' >"$P/cfgx.conf"
printf 'leak\n' >"$P/leak.conf"
printf 'bare\n' >"$P/bare.conf"
printf 'norun\n' >"$P/norun.conf"
printf 'd\ne\n' >"$P/nav.conf"

SRC="source \"\$ROOT/lib/io.sh\"; source \"\$ROOT/lib/run.sh\"; source \"\$ROOT/lib/pkg.sh\"; source \"\$ROOT/lib/planner.sh\"; source \"\$ROOT/lib/state.sh\"; source \"\$ROOT/lib/lists.sh\"; source \"\$ROOT/lib/modules.sh\"; source \"\$ROOT/lib/depgraph.sh\"; source \"\$ROOT/lib/profiles.sh\"; source \"\$ROOT/lib/runner.sh\""

STATE_DIR() { printf '%s/.local/state/fedora-setup/modules' "$1"; }

# --- happy path: deps-first order, one batch, state, summary ------------

HOOK_LOG="$FX_TMP/hook1.log"
MOCK_LOG="$FX_TMP/m1.log"
INSTALLED="$FX_TMP/i1"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "happy path rc0" 0
fx_out 'profile: full'
if [[ "$(cat "$HOOK_LOG")" == "A
B
C" ]]; then fx_ok; else fx_bad "hooks ran in deps-first order"; fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "batch ran exactly once (got $RCMI)"; fi
if grep -qxF 'mock install a1 a2 b1 c1 org.sample.C' "$MOCK_LOG"; then
    fx_ok
else
    fx_bad "batch content mismatch"
fi
fx_out '^== run complete ==$'
fx_out '^  - 3 ok$'
fx_out '^  - 0 failed$'
fx_out '^  - 0 skipped$'
fx_out 'module: a (none)'
fx_out 'module: c (none)'
for id in a b c; do
    if [[ -f "$(STATE_DIR "$FX_TMP")/$id" && "$(head -1 "$(STATE_DIR "$FX_TMP")/$id")" == done* ]]; then fx_ok; else fx_bad "state marked for $id"; fi
done

# --- dry run: renders, touches nothing, ignores resume state ------------

HOOK_LOG="$FX_TMP/hook2.log"
MOCK_LOG="$FX_TMP/m2.log"
INSTALLED="$FX_TMP/i2"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP" FS_DRY_RUN=1 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry run rc0" 0
fx_out '^# would run: mock install a1 a2 b1 c1 org.sample.C$'
fx_out '^  - 3 ok$'
fx_out_not '^  - 3 skipped$'
fx_empty "dry run wrote no hook side effects" "$HOOK_LOG"
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "dry run recorded no mock ops"; fi
if [[ "$(wc -c <"$INSTALLED")" == "0" ]]; then fx_ok; else fx_bad "dry run mutated installed set"; fi

# dry run into a fresh home creates no state root at all
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$FX_TMP/m2b.log" FS_MOCK_INSTALLED="$FX_TMP/i2b"
    export FS_HOME="$FX_TMP/fresh" FS_DRY_RUN=1 HOOK_LOG="$FX_TMP/hook2b.log" FAKE_LOG_REC="$FAKE/logrec"
    : >"$FX_TMP/m2b.log"; : >"$FX_TMP/i2b"; : >"$FX_TMP/hook2b.log"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry run fresh home rc0" 0
fx_out '^# would run: mock install a1 a2 b1 c1 org.sample.C$'
if [[ ! -e "$FX_TMP/fresh/.local/state" ]]; then fx_ok; else fx_bad "dry run created a state root"; fi

# --- mid-run failure: safe-continue, log, resume skips completed ---------

{
    printf '#!/usr/bin/env bash\n'
    printf 'run() {\n'
    printf '    if [[ ! -f "$B_FLAG" ]]; then\n'
    printf '        run_cmd "b mark" -- "$FAKE/touchfile" "$B_FLAG"\n'
    printf '        run_cmd "b fail" --stop -- "$FAKE/failrun" 9\n'
    printf '    fi\n'
    printf '}\n'
} >"$M/b/hooks.sh"

HOOK_LOG="$FX_TMP/hook3.log"
MOCK_LOG="$FX_TMP/m3.log"
INSTALLED="$FX_TMP/i3"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m3" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export FAKE B_FLAG="$FX_TMP/m3-flag"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "mid-run failure rc1" 1
fx_err 'module failed: b'
fx_err_not 'stopping run'
if [[ "$(cat "$HOOK_LOG")" == "A
C" ]]; then fx_ok; else fx_bad "hooks before and after failure ran"; fi
fx_out '^  - 2 ok$'
fx_out '^  - 1 failed$'
if [[ -f "$(STATE_DIR "$FX_TMP/m3")/a" && -f "$(STATE_DIR "$FX_TMP/m3")/c" && ! -e "$(STATE_DIR "$FX_TMP/m3")/b" ]]; then
    fx_ok
else
    fx_bad "only succeeded modules marked"
fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "run1 batch once (got $RCMI)"; fi

# resume: a and c skipped, b retried and completed, no new batch
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m3" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export FAKE B_FLAG="$FX_TMP/m3-flag"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resume rc0" 0
fx_out 'already completed: a'
fx_out 'already completed: c'
fx_out '^  - 1 ok$'
fx_out '^  - 2 skipped$'
if [[ -f "$(STATE_DIR "$FX_TMP/m3")/b" ]]; then fx_ok; else fx_bad "resume marked b"; fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "resume added a batch (total $RCMI)"; fi
if [[ "$(cat "$HOOK_LOG")" == "A
C" ]]; then fx_ok; else fx_bad "resume re-ran completed hooks"; fi

# --- destructive module stops the run immediately -----------------------

standard_hook b
HOOK_LOG="$FX_TMP/hook4.log"
MOCK_LOG="$FX_TMP/m4.log"
INSTALLED="$FX_TMP/i4"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m4" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "nav" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "destructive failure rc1" 1
fx_err 'module failed: d'
fx_err 'stopping run (destructive module d)'
fx_out_not 'run complete'
if grep -qx 'E' "$HOOK_LOG"; then fx_bad "destructive stop left module e hook log"; else fx_ok; fi
if [[ ! -e "$(STATE_DIR "$FX_TMP/m4")/d" && ! -e "$(STATE_DIR "$FX_TMP/m4")/e" ]]; then
    fx_ok
else
    fx_bad "destructive module and dependents not marked"
fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "destructive run batch once (got $RCMI)"; fi
if [[ "$(cat "$HOOK_LOG")" == "A
B
C" ]]; then fx_ok; else fx_bad "hooks before destructive stop ran in order"; fi

# --- family gate: module unusable on family aborts before any effect ----

MOCK_LOG="$FX_TMP/m5.log"
INSTALLED="$FX_TMP/i5"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m5" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook5.log" FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "fam" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "family gate rc1" 1
fx_err "has no package list usable on family 'rpm'"
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "family gate ran a batch"; fi
if [[ ! -e "$FX_TMP/m5/.local/state" ]]; then fx_ok; else fx_bad "family gate created state"; fi

# --- empty profile: nothing, no batch, no state, rc0 ---------------------

MOCK_LOG="$FX_TMP/m6.log"
INSTALLED="$FX_TMP/i6"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m6" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook6.log" FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "minimal" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile rc0" 0
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "empty profile ran a batch"; fi
if [[ ! -e "$FX_TMP/m6/.local/state" ]]; then fx_ok; else fx_bad "empty profile created state"; fi
fx_out '^  - 0 ok$'
fx_out '^  - 0 failed$'
fx_out '^  - 0 skipped$'

# --- CLI module ids run through the resolver ----------------------------

standard_hook b
MOCK_LOG="$FX_TMP/m7.log"
INSTALLED="$FX_TMP/i7"
HOOK_LOG="$FX_TMP/hook7.log"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m7" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "minimal" "rpm" c
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "CLI module rc0" 0
if [[ "$(cat "$HOOK_LOG")" == "A
B
C" ]]; then fx_ok; else fx_bad "CLI module closure ran deps-first"; fi
if grep -qxF 'mock install a1 a2 b1 c1 org.sample.C' "$MOCK_LOG"; then
    fx_ok
else
    fx_bad "CLI batch content mismatch"
fi
fx_out '^  - 3 ok$'
fx_out 'profile: minimal'

# --- hookless module: configuration-only, marked done -------------------

MOCK_LOG="$FX_TMP/m8.log"
INSTALLED="$FX_TMP/i8"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m8" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook8.log" FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "cfgx" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hookless module rc0" 0
if grep -qxF 'mock install cfgx' "$MOCK_LOG"; then fx_ok; else fx_bad "hookless batch content"; fi
fx_out '^  - 1 ok$'
if [[ -f "$(STATE_DIR "$FX_TMP/m8")/cfg" ]]; then fx_ok; else fx_bad "hookless module marked"; fi

# --- hooks.sh runs in a subshell: no global leakage ---------------------

MOCK_LOG="$FX_TMP/m9.log"
INSTALLED="$FX_TMP/i9"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m9" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook9.log" FAKE_LOG_REC="$FAKE/logrec"
    rc=0
    eval "$SRC"
    runner_run "$M" "$P" "leak" "rpm" || rc=$?
    if [[ -n "${LEAKY:-}" ]]; then
        exit 42
    fi
    exit "$rc"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hook sandbox rc0" 0
fx_out '^  - 1 ok$'

# --- bare module: zero packages, no batch call at all --------------------

MOCK_LOG="$FX_TMP/m10.log"
INSTALLED="$FX_TMP/i10"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m10" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook10.log" FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "bare" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare module rc0" 0
fx_empty "bare module made no mock calls" "$MOCK_LOG"
fx_out '^  - 1 ok$'

# --- hooks.sh with no run(): module fails, not marked, run continues ------

MOCK_LOG="$FX_TMP/m11.log"
INSTALLED="$FX_TMP/i11"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m11" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook11.log" FAKE_LOG_REC="$FAKE/logrec"
    eval "$SRC"
    runner_run "$M" "$P" "norun" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no run() hook rc1" 1
fx_err 'module failed: norun'
fx_err ': run: command not found'
fx_out '^  - 0 ok$'
fx_out '^  - 1 failed$'
if [[ ! -e "$(STATE_DIR "$FX_TMP/m11")/norun" ]]; then fx_ok; else fx_bad "no-run module was marked"; fi

# --- misuse and resolve-through errors -----------------------------------

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_HOME="$FX_TMP/mx"
    eval "$SRC"
    runner_run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no arguments rc1" 1
fx_err "runner_run requires a modules dir, a profiles dir, a name, and a family"

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_HOME="$FX_TMP/mx"
    eval "$SRC"
    runner_run "$M" "$P" "full"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing family rc1" 1
fx_err "runner_run requires a modules dir, a profiles dir, a name, and a family"

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_HOME="$FX_TMP/mx"
    eval "$SRC"
    runner_run "$M" "$P" "ghost" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown profile rc1" 1
fx_err 'list file missing or not a regular file'

fx_summary