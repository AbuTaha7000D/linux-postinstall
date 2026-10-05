#!/usr/bin/env bash
# tests/fixtures/runner.sh - P4.6 fixture for lib/runner.sh.
# End-to-end mock run of the full resolve -> plan -> prereq -> per-
# namespace batch (system through the mock family backend, flatpaks
# through a stateful fake flatpak binary, one transaction per backend)
# -> ordered hooks -> state-marking -> summary pipeline, plus resume
# (already-completed modules skipped), safe-continue vs destructive
# stop, family gate, dry-run side-effect-freedom, CLI override and
# hookless modules. P7.5 adds: the prereq stage (order relative to both
# batches, always-run, fail-fast even for a low-risk module, a
# prerepo.sh with no prerepo() function, dry-run rendering), hook-
# subshell isolation (FS_MODULE_FAMILY exported, and each hook seeing
# its OWN module's metadata when it does not sort last), and the
# flatpak-alternative pair (exclusive with the native SYSTEM path,
# additive with the module's own flatpaks.list). A1 adds: a run()
# that reports not-applicable (MODULE_HOOK_SKIP) is recorded as the
# registry's `skipped` state and counted as skipped -- NOT ok and NOT
# done -- is re-invoked on the next run, still stops the run (rc1, no
# summary) when the registry cannot record the skip, and leaves a
# `done` entry (and an unrecognized state word) behaving exactly as
# before. State, mock
# installed-set/call log, and the flatpak fake log/installed set all
# live under FX_TMP so no system path or privilege is touched.
# B3 adds batch-failure ABORT semantics: a failing system transaction and a
# failing flatpak transaction each stop the run (rc1, no hooks, no state,
# no summary) instead of falling through to the next stage. Both guards are
# covered behaviourally, and the cells carry three properties that make that
# coverage real rather than nominal: a restricted PATH that is COMPLETE for
# every stage (proved by a positive-control cell that drives the same PATH to
# a successful finish), `set +e` around runner_run so the cell's own errexit
# cannot manufacture the very rc being asserted, and a PATH chosen per cell
# so the stage AFTER the one under test would otherwise SUCCEED -- otherwise
# a removed guard would still be masked by the next stage failing. The old
# static grep for the guards' source text is deliberately gone.
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
chmod +x "$FAKE/flatpak"

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
mkmod notapp
mkmod okmod
printf '#!/usr/bin/env bash\nrun() { printf "run id=%%s okmod\\n" "${MODULE_ID:-NONE}" >>"${ORDER:?}"; }\n' \
    >"$M/okmod/hooks.sh"
# A1: run() reports NOT-APPLICABLE via the reserved status. It still records
# that it ran, so a cell can prove a second run re-invokes it.
{
    printf '#!/usr/bin/env bash\n'
    printf 'run() {\n'
    printf '    printf "run id=%%s notapp\\n" "${MODULE_ID:-NONE}" >>"${ORDER:?}"\n'
    printf '    return "$MODULE_HOOK_SKIP"\n'
    printf '}\n'
} >"$M/notapp/hooks.sh"
printf 'notapp\n' >"$P/notapp.conf"
printf 'okmod\nnotapp\n' >"$P/a1mix.conf"
printf 'notapp\nbadmod\n' >"$P/a1mixfail.conf"
mkmod badmod
printf '#!/usr/bin/env bash\nrun() {\n    return 7\n}\n' >"$M/badmod/hooks.sh"
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

# `prep` carries a prerepo hook that records WHERE it ran: before both
# batches ("before") or after one of them ("late"). Its run() hook records
# the mirror image, so the cell can prove the whole stage order and that
# FS_MODULE_FAMILY is exported into BOTH hook subshells.
mkmod prep
printf 'p1\n' >"$M/prep/packages.list"
printf 'org.sample.P\n' >"$M/prep/flatpaks.list"
cat >"$M/prep/prerepo.sh" <<'HOOK'
#!/usr/bin/env bash
prerepo() {
    local phase=prebatch
    if [[ -s "${FS_MOCK_LOG:?}" || -s "${FS_FAKE_INSTALLED:?}" ]]; then phase=postbatch; fi
    printf 'prerepo id=%s family=%s phase=%s child=%s\n' \
        "${MODULE_ID:-NONE}" "${FS_MODULE_FAMILY:-NONE}" "$phase" \
        "$(bash -c 'printf %s "${FS_MODULE_FAMILY:-UNSET}"')" >>"${ORDER:?}"
}
HOOK
cat >"$M/prep/hooks.sh" <<'HOOK'
#!/usr/bin/env bash
run() {
    local phase=postbatch
    if [[ -z "${FS_MOCK_LOG:?}" ]]; then phase=prebatch; fi
    printf 'run id=%s family=%s phase=%s child=%s\n' \
        "${MODULE_ID:-NONE}" "${FS_MODULE_FAMILY:-NONE}" "$phase" \
        "$(bash -c 'printf %s "${FS_MODULE_FAMILY:-UNSET}"')" >>"${ORDER:?}"
}
HOOK

# a LOW-risk module whose prerepo fails: the stage must abort the run anyway
mkmod badprep
printf 'p2\n' >"$M/badprep/packages.list"
printf '#!/usr/bin/env bash\nprerepo() {\n    printf "badprep ran\\n" >>"${ORDER:?}"\n    echo "prerepo refused" >&2\n    return 1\n}\n' \
    >"$M/badprep/prerepo.sh"

# a prerepo.sh that forgets to define prerepo()
mkmod noprep
printf 'p3\n' >"$M/noprep/packages.list"
printf '#!/usr/bin/env bash\nsetup_stuff() { :; }\n' >"$M/noprep/prerepo.sh"

# dry mode: prerepo is still CALLED, and whatever it renders precedes the batch
mkmod dryprep
printf 'p4\n' >"$M/dryprep/packages.list"
{
    printf '#!/usr/bin/env bash\n'
    printf 'prerepo() {\n'
    printf '    printf "prerepo ran\\n" >>"${ORDER:?}"\n'
    printf '    run_cmd "prep prerepo" -- echo prerepo-rendered\n'
    printf '}\n'
} >"$M/dryprep/prerepo.sh"

# --- profiles ------------------------------------------------------------

printf 'c\nb\na\n' >"$P/full.conf"
printf '# comment-only skeleton\n' >"$P/minimal.conf"
printf 'exo\n' >"$P/fam.conf"
printf 'cfg\n' >"$P/cfgx.conf"
printf 'leak\n' >"$P/leak.conf"
printf 'bare\n' >"$P/bare.conf"
printf 'norun\n' >"$P/norun.conf"
printf 'd\ne\n' >"$P/nav.conf"
mkdir -p "$M/dual" "$P"
printf 'MODULE_ID=dual\nMODULE_RISK=none\nMODULE_DEFAULT=off\nMODULE_FLATPAK_ALT_ID=org.example.Alt\nMODULE_FLATPAK_ALT_SEAM=FX_DUAL_SEAM\n' >"$M/dual/module.sh"
printf 'dual-native\n' >"$M/dual/packages.list"
printf 'org.example.Own\n' >"$M/dual/flatpaks.list"
printf 'dual\n' >"$P/dual.conf"

mkmod zafter
printf 'z1\n' >"$M/zafter/packages.list"
printf '#!/usr/bin/env bash\nrun() { printf "run id=%%s after\\n" "${MODULE_ID:-NONE}" >>"${ORDER:?}"; }\n' \
    >"$M/zafter/hooks.sh"
printf 'prep\nzafter\n' >"$P/prep.conf"
printf 'badprep\n' >"$P/badprep.conf"
printf 'noprep\n' >"$P/noprep.conf"
printf 'dryprep\n' >"$P/dryprep.conf"

SRC="source \"\$ROOT/lib/io.sh\"; source \"\$ROOT/lib/run.sh\"; source \"\$ROOT/lib/pkg.sh\"; source \"\$ROOT/lib/planner.sh\"; source \"\$ROOT/lib/state.sh\"; source \"\$ROOT/lib/lists.sh\"; source \"\$ROOT/lib/modules.sh\"; source \"\$ROOT/lib/depgraph.sh\"; source \"\$ROOT/lib/profiles.sh\"; source \"\$ROOT/lib/summary.sh\"; source \"\$ROOT/lib/runner.sh\""

STATE_DIR() { printf '%s/.local/state/fedora-setup/modules' "$1"; }

# --- happy path: deps-first order, one batch, state, summary ------------

HOOK_LOG="$FX_TMP/hook1.log"
MOCK_LOG="$FX_TMP/m1.log"
INSTALLED="$FX_TMP/i1"
FAKE_LOG="$FX_TMP/f1.log"
FAKEST="$FX_TMP/fs1"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
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
if grep -qxF 'mock install a1 a2 b1 c1' "$MOCK_LOG"; then
    fx_ok
else
    fx_bad "system batch content mismatch"
fi
if grep -qxF 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "flatpak remote-add missing"
fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.sample.C' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "flatpak install missing"
fi
if ! grep -qxF 'org.sample.C' "$FAKEST"; then fx_bad "flatpak installed state not recorded"; fi
fx_out '^== run complete ==$'
fx_out '^  - 3 modules ok · 0 skipped · 0 failed · '
fx_out 'module: a (none)'
fx_out 'module: c (none)'
for id in a b c; do
    if [[ -f "$(STATE_DIR "$FX_TMP")/$id" && "$(head -1 "$(STATE_DIR "$FX_TMP")/$id")" == done* ]]; then fx_ok; else fx_bad "state marked for $id"; fi
done

# --- restricted-PATH harness (B3) --------------------------------------
# The two batch-failure cells below run with a PATH holding ONLY the tools the
# runner/state/mock layers need, so the cells stay hermetic and the flatpak one
# can guarantee "no flatpak binary anywhere" (flatpak_supported then fails
# regardless of what the host has). That hermeticity is also a hazard: a tool
# the run needs but MINBIN lacks aborts the run at an INCIDENTAL point --
# state_init's `mkdir -p`, or a hook's `#!/usr/bin/env bash` -- and produces
# the very "no hooks / no state" outcome the cell is supposed to attribute to
# the batch guard. The earlier MINBIN listed only grep/sort/uniq/readlink/
# mktemp, so the flatpak cell aborted in state_init and proved nothing.
# Two things prevent that, and both are load-bearing:
#   1. minbin below is COMPLETE for every stage the run reaches.
#   2. the control cell that follows drives the SAME restricted PATH to a
#      SUCCESSFUL finish (hook loop reached, `done` state recorded), so a later
#      "no hooks / no state" can only come from the guard under test.
MINBIN="$FX_TMP/minbin"
mkdir -p "$MINBIN"
for t in bash env grep sort uniq cut head tail cat mkdir rm mv cp ln readlink \
    mktemp stat tee date chmod touch basename dirname tr wc sed awk; do
    src="$(command -v "$t" 2>/dev/null)"
    if [[ -n "$src" ]]; then ln -sf "$src" "$MINBIN/$t"; fi
done

# Control: same restricted PATH, same profile, batch SUCCEEDING. If this ever
# fails, the restricted PATH is incomplete and the two failure cells below are
# vacuous -- so it is asserted rather than assumed.
HOOK_LOG="$FX_TMP/hook1p.log"
MOCK_LOG="$FX_TMP/m1p.log"
INSTALLED="$FX_TMP/i1p"
: >"$HOOK_LOG"; : >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FX_TMP/f1p.log" FS_FAKE_INSTALLED="$FX_TMP/fs1p"
    export FS_HOME="$FX_TMP/mpctrl" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    : >"$FS_FAKE_LOG"; : >"$FS_FAKE_INSTALLED"
    export PATH="$FAKE:$MINBIN"
    eval "$SRC"
    set +e
    runner_run "$M" "$P" "full" "mock"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "restricted PATH completes a run (control) rc0" 0
if [[ "$(cat "$HOOK_LOG")" == "A
B
C" ]]; then fx_ok; else fx_bad "restricted PATH reached the hook loop (control)"; fi
for id in a b c; do
    if [[ -f "$(STATE_DIR "$FX_TMP/mpctrl")/$id" ]]; then fx_ok; else fx_bad "restricted PATH recorded state for $id (control)"; fi
done

# --- flatpak batch failure: backend gate absent -> rc1, no hooks, no state
# Run the full profile (c carries a flatpak) against MINBIN, which contains no
# flatpak binary at all, so flatpak_supported fails regardless of the host.
# The system batch (mock) commits; the flatpak batch then aborts with `flatpak
# batch failed`, rc1, and no hooks/state follow.
# `set +e` around runner_run is LOAD-BEARING, not hygiene: under `set -e` the
# failing command inside the runner kills the cell's subshell with rc1 no matter
# what the guard does next, which made the guard's removal unpinnable here.
HOOK_LOG="$FX_TMP/hook1b.log"
MOCK_LOG="$FX_TMP/m1b.log"
INSTALLED="$FX_TMP/i1b"
: >"$HOOK_LOG"; : >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/mflatfail" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export PATH="$MINBIN"
    eval "$SRC"
    set +e
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "flatpak batch failure rc1" 1
fx_err 'flatpak batch failed'
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "system batch committed before flatpak failure (got $RCMI)"; fi
fx_empty "flatpak failure ran no hooks" "$HOOK_LOG"
fx_out_not '^== run complete ==$'
for id in a b c; do
    if [[ -e "$(STATE_DIR "$FX_TMP/mflatfail")/$id" ]]; then fx_bad "state written after flatpak failure"; else fx_ok; fi
done

# --- system package batch failure: mock backend forced failure -> rc1, no hooks, no state ---
# Run with FS_MOCK_BATCH_FAIL=1 to force the mock backend's install_batch to fail.
# The system batch should fail, no hooks should run, no state should be marked.
# PATH is $FAKE:$MINBIN, NOT MINBIN: the profile carries a flatpak (c), so the
# flatpak batch runs next. With no flatpak binary available it would fail too
# and, with the system guard removed, would stop the run at the SAME place with
# the SAME rc and no hooks -- making this cell blind to the system guard. Giving
# the flatpak stage a working fake means the system guard is the only thing that
# can stop this run, which is what the cell claims to measure.
HOOK_LOG="$FX_TMP/hook1c.log"
MOCK_LOG="$FX_TMP/m1c.log"
INSTALLED="$FX_TMP/i1c"
: >"$HOOK_LOG"; : >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_MOCK_BATCH_FAIL=1
    export FS_FAKE_LOG="$FX_TMP/f1c.log" FS_FAKE_INSTALLED="$FX_TMP/fs1c"
    export FS_HOME="$FX_TMP/msysfail" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    : >"$FS_FAKE_LOG"; : >"$FS_FAKE_INSTALLED"
    export PATH="$FAKE:$MINBIN"
    eval "$SRC"
    set +e
    runner_run "$M" "$P" "full" "mock"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "system package batch failure rc1" 1
fx_err 'package batch failed'
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "system batch attempted but should fail (got $RCMI)"; fi
fx_empty "system package failure ran no hooks" "$HOOK_LOG"
fx_out_not '^== run complete ==$'
for id in a b c; do
    if [[ -e "$(STATE_DIR "$FX_TMP/msysfail")/$id" ]]; then fx_bad "state written after system package failure"; else fx_ok; fi
done

# The batch-failure guards used to be "verified" by grepping runner.sh's source
# for the literal `|| {` after each plan_install. That was a static check of the
# file's TEXT, so it kept passing while the cells above proved nothing, and it
# read as a mutation test while asserting no runtime behaviour at all. It is
# deliberately GONE: the guards are now covered behaviourally by the two cells
# above, whose rc / no-hooks / no-state assertions are each proven to flip when
# the corresponding guard is removed (an actual source mutation, not a grep).

# --- dry run: renders, touches nothing, ignores resume state ------------

HOOK_LOG="$FX_TMP/hook2.log"
MOCK_LOG="$FX_TMP/m2.log"
INSTALLED="$FX_TMP/i2"
FAKE_LOG="$FX_TMP/f2.log"
FAKEST="$FX_TMP/fs2"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP" FS_DRY_RUN=1 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry run rc0" 0
fx_out '^# would run: mock install a1 a2 b1 c1$'
fx_out '^# would run: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo$'
fx_out '^# would run: flatpak install --user --noninteractive --assumeyes org.sample.C$'
fx_out '^  - 3 modules ok · 0 skipped · 0 failed · '
fx_empty "dry run wrote no hook side effects" "$HOOK_LOG"
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "dry run recorded no mock ops"; fi
if [[ "$(wc -c <"$INSTALLED")" == "0" ]]; then fx_ok; else fx_bad "dry run mutated installed set"; fi
fx_empty "dry run recorded no flatpak ops" "$FAKE_LOG"
if [[ "$(wc -c <"$FAKEST")" == "0" ]]; then fx_ok; else fx_bad "dry run mutated flatpak installed set"; fi

# dry run into a fresh home creates no state root at all
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$FX_TMP/m2b.log" FS_MOCK_INSTALLED="$FX_TMP/i2b"
    export FS_FAKE_LOG="$FX_TMP/f2b.log" FS_FAKE_INSTALLED="$FX_TMP/fs2b"
    export FS_HOME="$FX_TMP/fresh" FS_DRY_RUN=1 HOOK_LOG="$FX_TMP/hook2b.log" FAKE_LOG_REC="$FAKE/logrec"
    : >"$FX_TMP/m2b.log"; : >"$FX_TMP/i2b"; : >"$FX_TMP/hook2b.log"; : >"$FX_TMP/f2b.log"; : >"$FX_TMP/fs2b"
    export PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry run fresh home rc0" 0
fx_out '^# would run: mock install a1 a2 b1 c1$'
fx_out '^# would run: flatpak install --user --noninteractive --assumeyes org.sample.C$'
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
FAKE_LOG="$FX_TMP/f3.log"
FAKEST="$FX_TMP/fs3"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m3" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export FAKE B_FLAG="$FX_TMP/m3-flag" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "mid-run failure rc1" 1
fx_err 'module failed: b'
fx_err_not 'stopping run'
if [[ "$(cat "$HOOK_LOG")" == "A
C" ]]; then fx_ok; else fx_bad "hooks before and after failure ran"; fi
fx_out '^  - 2 modules ok · 0 skipped · 1 failed · '
fx_out '^  - FAIL b: hook exited 1$'
if [[ -f "$(STATE_DIR "$FX_TMP/m3")/a" && -f "$(STATE_DIR "$FX_TMP/m3")/c" && ! -e "$(STATE_DIR "$FX_TMP/m3")/b" ]]; then
    fx_ok
else
    fx_bad "only succeeded modules marked"
fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "run1 batch once (got $RCMI)"; fi
RFI=$(grep -c '^flatpak install ' "$FAKE_LOG")
if [[ "$RFI" == "1" ]]; then fx_ok; else fx_bad "run1 flatpak batch once (got $RFI)"; fi
if grep -qxF 'org.sample.C' "$FAKEST"; then fx_ok; else fx_bad "run1 recorded flatpak installed"; fi

# resume: a and c skipped, b retried and completed, no new batch
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m3" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export FAKE B_FLAG="$FX_TMP/m3-flag" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "full" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resume rc0" 0
fx_out 'already completed: a'
fx_out 'already completed: c'
fx_out '^  - 1 modules ok · 2 skipped · 0 failed · '
if [[ -f "$(STATE_DIR "$FX_TMP/m3")/b" ]]; then fx_ok; else fx_bad "resume marked b"; fi
RCMI=$(grep -c '^mock install ' "$MOCK_LOG")
if [[ "$RCMI" == "1" ]]; then fx_ok; else fx_bad "resume added a batch (total $RCMI)"; fi
RFI=$(grep -c '^flatpak install ' "$FAKE_LOG")
if [[ "$RFI" == "1" ]]; then fx_ok; else fx_bad "resume re-ran flatpak batch (total $RFI)"; fi
if [[ "$(cat "$HOOK_LOG")" == "A
C" ]]; then fx_ok; else fx_bad "resume re-ran completed hooks"; fi

# --- destructive module stops the run immediately -----------------------

standard_hook b
HOOK_LOG="$FX_TMP/hook4.log"
MOCK_LOG="$FX_TMP/m4.log"
INSTALLED="$FX_TMP/i4"
FAKE_LOG="$FX_TMP/f4.log"
FAKEST="$FX_TMP/fs4"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m4" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec"
    export PATH="$FAKE:$PATH"
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
    export FS_HOME="$FX_TMP/m5" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook5.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "fam" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "family gate rc1" 1
fx_err "has no package list usable on family 'rpm'"
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "family gate ran a batch"; fi
if [[ ! -e "$FX_TMP/m5/.local/state" ]]; then fx_ok; else fx_bad "family gate created state"; fi
# module_validate failure is an ABORT path: it must not reach the reporter.
# Without this, adding `summary_report` to that `return 1` left the battery green.
fx_out_not 'run complete'

# --- empty profile: nothing, no batch, no state, rc0 ---------------------

MOCK_LOG="$FX_TMP/m6.log"
INSTALLED="$FX_TMP/i6"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m6" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook6.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "minimal" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile rc0" 0
if [[ "$(wc -c <"$MOCK_LOG")" == "0" ]]; then fx_ok; else fx_bad "empty profile ran a batch"; fi
if [[ ! -e "$FX_TMP/m6/.local/state" ]]; then fx_ok; else fx_bad "empty profile created state"; fi
fx_out '^  - 0 modules ok · 0 skipped · 0 failed · '

# --- CLI module ids run through the resolver ----------------------------

standard_hook b
MOCK_LOG="$FX_TMP/m7.log"
INSTALLED="$FX_TMP/i7"
HOOK_LOG="$FX_TMP/hook7.log"
FAKE_LOG="$FX_TMP/f7.log"
FAKEST="$FX_TMP/fs7"
: >"$MOCK_LOG"; : >"$INSTALLED"; : >"$HOOK_LOG"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m7" FS_DRY_RUN=0 HOOK_LOG FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "minimal" "rpm" c
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "CLI module rc0" 0
if [[ "$(cat "$HOOK_LOG")" == "A
B
C" ]]; then fx_ok; else fx_bad "CLI module closure ran deps-first"; fi
if grep -qxF 'mock install a1 a2 b1 c1' "$MOCK_LOG"; then
    fx_ok
else
    fx_bad "CLI system batch content mismatch"
fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.sample.C' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "CLI flatpak batch missing"
fi
fx_out '^  - 3 modules ok · 0 skipped · 0 failed · '
fx_out 'profile: minimal'

# --- hookless module: configuration-only, marked done -------------------

MOCK_LOG="$FX_TMP/m8.log"
INSTALLED="$FX_TMP/i8"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m8" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook8.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "cfgx" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hookless module rc0" 0
if grep -qxF 'mock install cfgx' "$MOCK_LOG"; then fx_ok; else fx_bad "hookless batch content"; fi
fx_out '^  - 1 modules ok · 0 skipped · 0 failed · '
if [[ -f "$(STATE_DIR "$FX_TMP/m8")/cfg" ]]; then fx_ok; else fx_bad "hookless module marked"; fi

# --- hooks.sh runs in a subshell: no global leakage ---------------------

MOCK_LOG="$FX_TMP/m9.log"
INSTALLED="$FX_TMP/i9"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m9" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook9.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
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
fx_out '^  - 1 modules ok · 0 skipped · 0 failed · '

# --- bare module: zero packages, no batch call at all --------------------

MOCK_LOG="$FX_TMP/m10.log"
INSTALLED="$FX_TMP/i10"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m10" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook10.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "bare" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare module rc0" 0
fx_empty "bare module made no mock calls" "$MOCK_LOG"
fx_out '^  - 1 modules ok · 0 skipped · 0 failed · '

# --- hooks.sh with no run(): module fails, not marked, run continues ------

MOCK_LOG="$FX_TMP/m11.log"
INSTALLED="$FX_TMP/i11"
: >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m11" FS_DRY_RUN=0 HOOK_LOG="$FX_TMP/hook11.log" FAKE_LOG_REC="$FAKE/logrec" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "norun" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no run() hook rc1" 1
fx_err 'module failed: norun'
fx_err ': run: command not found'
fx_out '^  - 0 modules ok · 0 skipped · 1 failed · '
fx_out '^  - FAIL norun: hook exited 127$'
fx_out '^  - retry: re-run the same command; completed modules are skipped$'
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
# arg-validation failure is an ABORT path: it must not reach the reporter.
fx_out_not 'run complete'

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_HOME="$FX_TMP/mx"
    eval "$SRC"
    runner_run "$M" "$P" "full"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing family rc1" 1
fx_err "runner_run requires a modules dir, a profiles dir, a name, and a family"
# arg-validation failure is an ABORT path: it must not reach the reporter.
fx_out_not 'run complete'

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_HOME="$FX_TMP/mx"
    eval "$SRC"
    runner_run "$M" "$P" "ghost" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown profile rc1" 1
fx_err 'list file missing or not a regular file'
# A resolve failure is an ABORT path: it must not reach the reporter. Without
# this, changing lib/runner.sh:224 to `|| { summary_report; return 1; }` printed
# "0 modules ok . 0 failed" after the run had already refused, and the whole
# 3557-assert battery stayed green.
fx_out_not 'run complete'

# --- prerepo stage: order, family export, isolation ---------------------

ORDER="$FX_TMP/order12.log"
MOCK_LOG="$FX_TMP/m12.log"
INSTALLED="$FX_TMP/i12"
FAKE_LOG="$FX_TMP/f12.log"
FAKEST="$FX_TMP/fs12"
: >"$ORDER"; : >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m12" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/hook12.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "prep" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "prerepo stage order rc0" 0
fx_out '^  - 2 modules ok · 0 skipped · 0 failed · '
if grep -qxF 'prerepo id=prep family=rpm phase=prebatch child=rpm' "$ORDER"; then fx_ok; else fx_bad "prerepo did not run before both batches with its own metadata and FS_MODULE_FAMILY exported"; fi
if grep -qxF 'run id=prep family=rpm phase=postbatch child=rpm' "$ORDER"; then fx_ok; else fx_bad "run hook did not run after the batches with its own metadata and FS_MODULE_FAMILY exported"; fi
if grep -q '^prerepo .*phase=postbatch\|^run .*phase=prebatch' "$ORDER"; then fx_bad "a hook ran in the wrong order relative to the batches"; else fx_ok; fi
if grep -q 'id=NONE\|family=NONE\|child=UNSET' "$ORDER"; then fx_bad "a hook subshell saw no module metadata or no FS_MODULE_FAMILY"; else fx_ok; fi
if grep -qxF 'mock install p1 z1' "$MOCK_LOG"; then fx_ok; else fx_bad "system batch content"; fi
if grep -qxF 'org.sample.P' "$FAKEST"; then fx_ok; else fx_bad "flatpak batch content"; fi
if [[ -f "$(STATE_DIR "$FX_TMP/m12")/prep" ]]; then fx_ok; else fx_bad "prep not marked done"; fi

# --- the alt pair replaces the NATIVE SYSTEM path only -------------------
# The module's own flatpaks.list is still collected, and its packages.list
# is never even read, so a stale native id cannot reach a batch.
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$FX_TMP/dual.inst"
    export FS_MOCK_LOG="$FX_TMP/dual.log" FX_DUAL_SEAM=1
    export FS_FAKE_LOG="$FX_TMP/dual.fake" FS_FAKE_INSTALLED="$FX_TMP/dual.fakest"
    export FS_HOME="$FX_TMP/mdual" FS_DRY_RUN=0 PATH="$FAKE:$PATH"
    : >"$FX_TMP/dual.fakest"; : >"$FX_TMP/dual.log"
    eval "$SRC"
    runner_run "$M" "$P" "dual" "mock"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "alt + own flatpaks + stale native rc0" 0
if grep -qxF 'mock install' "$FX_TMP/dual.log"; then
    fx_bad "a stale native package reached the system batch"
else
    fx_ok
fi
if grep -qxF 'org.example.Alt' "$FX_TMP/dual.fakest" && grep -qxF 'org.example.Own' "$FX_TMP/dual.fakest"; then fx_ok; else fx_bad "both the alternative and the module's own flatpak are missing"; fi
if [[ -s "$FX_TMP/dual.inst" ]]; then fx_bad "a native package was installed from the alt path"; else fx_ok; fi
fx_out_not 'dual-native'

# --- prerepo failure aborts the run even for a low-risk module ----------

ORDER="$FX_TMP/order13.log"
MOCK_LOG="$FX_TMP/m13.log"
INSTALLED="$FX_TMP/i13"
FAKE_LOG="$FX_TMP/f13.log"
FAKEST="$FX_TMP/fs13"
: >"$ORDER"; : >"$MOCK_LOG"; : >"$INSTALLED"; : >"$FAKE_LOG"; : >"$FAKEST"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_FAKE_LOG="$FAKE_LOG" FS_FAKE_INSTALLED="$FAKEST"
    export FS_HOME="$FX_TMP/m13" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/hook13.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "badprep" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "prerepo failure rc1" 1
fx_err 'prerepo refused'
fx_err 'module prerepo failed: badprep'
fx_err 'stopping run (prerepo failed for badprep)'
fx_out_not 'run complete'
fx_empty "prerepo failure skipped the system batch" "$MOCK_LOG"
fx_empty "prerepo failure skipped the flatpak batch" "$FAKE_LOG"
if [[ ! -e "$(STATE_DIR "$FX_TMP/m13")/badprep" ]]; then fx_ok; else fx_bad "failed prerepo was marked done"; fi

# --- prerepo.sh without prerepo(): module fails, nothing installed -------

ORDER="$FX_TMP/order14.log"
MOCK_LOG="$FX_TMP/m14.log"
INSTALLED="$FX_TMP/i14"
: >"$ORDER"; : >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/m14" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/hook14.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "noprep" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no prerepo() rc1" 1
fx_err 'module prerepo failed: noprep'
fx_err 'stopping run (prerepo failed for noprep)'
fx_out_not 'run complete'
fx_empty "no prerepo() skipped the batches" "$MOCK_LOG"
if [[ ! -e "$(STATE_DIR "$FX_TMP/m14")/noprep" ]]; then fx_ok; else fx_bad "module without prerepo() was marked done"; fi

# --- dry run still calls prerepo, and renders it before the batch -------

ORDER="$FX_TMP/order15.log"
MOCK_LOG="$FX_TMP/m15.log"
INSTALLED="$FX_TMP/i15"
: >"$ORDER"; : >"$MOCK_LOG"; : >"$INSTALLED"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/dryprep-home" FS_DRY_RUN=1 ORDER HOOK_LOG="$FX_TMP/hook15.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "dryprep" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry prerepo rc0" 0
if grep -qxF 'prerepo ran' "$ORDER"; then fx_ok; else fx_bad "dry run did not call prerepo"; fi
fx_out '^# would run: echo prerepo-rendered$'
if grep -qxF 'mock install p4' "$MOCK_LOG"; then fx_bad "dry run executed the batch"; else fx_ok; fi
if [[ ! -e "$FX_TMP/dryprep-home/.local/state" ]]; then fx_ok; else fx_bad "dry run created a state root"; fi
_dr="$(grep -n 'echo prerepo-rendered' "$FX_OUT" | head -1 | cut -d: -f1)"
_db="$(grep -n 'mock install p4' "$FX_OUT" | head -1 | cut -d: -f1)"
if [[ -n "$_dr" && -n "$_db" ]] && (( _dr < _db )); then fx_ok; else fx_bad "dry prerepo render must precede the batch render (prerepo line $_dr, batch line $_db)"; fi

# --- A1.1 not-applicable is recorded `skipped`, never `done` -------------
echo "--- cell: A1 skip is skipped not done"
: >"$ORDER"
rm -rf "$FX_TMP/a1home"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1home" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "a1mix" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 skip rc0 (a skip is not a failure)" 0
fx_out '^  - 1 modules ok · 1 skipped · 0 failed · '
fx_err_not 'module failed: notapp'
if [[ "$(head -1 "$(STATE_DIR "$FX_TMP/a1home")/notapp" 2>/dev/null)" == skipped* ]]; then
    fx_ok
else
    fx_bad "not-applicable module must be recorded skipped, got: $(head -1 "$(STATE_DIR "$FX_TMP/a1home")/notapp" 2>/dev/null)"
fi
if grep -qxF 'run id=notapp notapp' "$ORDER"; then fx_ok; else fx_bad "not-applicable hook did not run"; fi
if grep -q '^FAIL' "$FX_OUT"; then fx_bad "a skip must not emit a FAIL row"; else fx_ok; fi

# --- A1.2 a skipped module is retried on the next run --------------------
echo "--- cell: A1 second run re-invokes a skipped module"
# $ORDER is deliberately NOT truncated here: the count below spans BOTH runs,
# which is the whole point -- the latch this task removes would leave it at 1.
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1home" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "a1mix" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 second run rc0" 0
# TWO invocations across the two runs: the latch this task removes would make
# this 1, and "already completed" in the output is the tell-tale.
if [[ "$(grep -c '^run id=notapp notapp$' "$ORDER")" == "2" ]]; then
    fx_ok
else
    fx_bad "skipped module was not re-invoked (count $(grep -c '^run id=notapp notapp$' "$ORDER"), expected 2)"
fi
fx_out_not 'already completed: notapp'
# okmod really did complete in run 1, so this run skips for TWO different
# reasons: one because it is done, one because it is not applicable. Both
# count as skipped, and neither counts as ok.
fx_out '^  - 0 modules ok · 2 skipped · 0 failed · '

# --- A1.3 skip + failure: counts, rc and rows agree -----------------------
echo "--- cell: A1 skip and failure together"
rm -rf "$FX_TMP/a1failhome"
: >"$ORDER"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1failhome" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook2.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "a1mixfail" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 skip+fail rc1" 1
# The combination no single-outcome run reaches: the skip must still be
# counted as skipped even while a sibling fails, or the counts and rc are
# describing different runs.
fx_out '^  - 0 modules ok · 1 skipped · 1 failed · '
if grep -qx '  - FAIL badmod: hook exited 7$' "$FX_OUT"; then fx_ok; else fx_bad "missing exact FAIL row"; fi
if grep -q 'FAIL notapp' "$FX_OUT"; then fx_bad "skipped module must not appear in a FAIL row"; else fx_ok; fi

# --- A1.4 a `done` module is still short-circuited (legacy format) -------
echo "--- cell: A1 done still short-circuits"
rm -rf "$FX_TMP/a1donehome"
mkdir -p "$(STATE_DIR "$FX_TMP/a1donehome")"
printf 'done 2026-01-01T00:00:00' >"$(STATE_DIR "$FX_TMP/a1donehome")/notapp"
: >"$ORDER"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1donehome" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook3.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "notapp" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 done module rc0" 0
fx_out 'already completed: notapp'
# The gate must NOT fire: a pre-A1 "done <ts>" entry, written with no trailing
# newline exactly as state_module_mark wrote it, still means done.
if [[ -s "$ORDER" ]]; then fx_bad "a done module's hook must not be re-invoked"; else fx_ok; fi
fx_out '^  - 0 modules ok · 1 skipped · 0 failed · '

# --- A1.5 an unrecognized state word is refused, never read as done ------
echo "--- cell: A1 unknown state word fails closed"
rm -rf "$FX_TMP/a1boghom"
mkdir -p "$(STATE_DIR "$FX_TMP/a1boghom")"
printf 'finished 2026-01-01T00:00:00' >"$(STATE_DIR "$FX_TMP/a1boghom")/notapp"
: >"$ORDER"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1boghom" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook4.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "notapp" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 unknown state rc0 (treated as not-done)" 0
fx_err 'unrecognized module state in registry: notapp'
if grep -qxF 'run id=notapp notapp' "$ORDER"; then fx_ok; else fx_bad "unknown state must not short-circuit the module"; fi
fx_out_not 'already completed: notapp'

# --- A1.5b more malformed shapes are refused the same way ----------------
# Same contract as A1.5 (a record the registry cannot parse must never be read
# as done), reached through the two shapes a hand-edit or a foreign writer can
# produce. Disclosed as unpinned by the A1 Senior Review.
for shape in 'empty' 'leading-space' 'word-only'; do
    rm -rf "$FX_TMP/a1shapehome"
    mkdir -p "$(STATE_DIR "$FX_TMP/a1shapehome")"
    case "$shape" in
    empty) : >"$(STATE_DIR "$FX_TMP/a1shapehome")/notapp" ;;
    leading-space) printf ' done 2026-01-01T00:00:00' >"$(STATE_DIR "$FX_TMP/a1shapehome")/notapp" ;;
    word-only) printf 'skipped' >"$(STATE_DIR "$FX_TMP/a1shapehome")/notapp" ;;
    esac
    : >"$ORDER"
    (
        set -euo pipefail
        export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
        export FS_HOME="$FX_TMP/a1shapehome" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook7.log" PATH="$FAKE:$PATH"
        eval "$SRC"
        runner_run "$M" "$P" "notapp" "rpm"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "A1 $shape registry entry rc0 (not read as done)" 0
    fx_out_not 'already completed: notapp'
    if grep -qxF 'run id=notapp notapp' "$ORDER"; then fx_ok; else fx_bad "$shape entry must not short-circuit the module"; fi
done

# --- A1.6 a skip the registry cannot record aborts rc1 with no summary ----
echo "--- cell: A1 state_module_skip failure aborts"
rm -rf "$FX_TMP/a1rohome"
mkdir -p "$(STATE_DIR "$FX_TMP/a1rohome")/notapp"
: >"$ORDER"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1rohome" FS_DRY_RUN=0 ORDER HOOK_LOG="$FX_TMP/a1hook5.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "notapp" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 unrecordable skip rc1" 1
# The registry is authoritative for BOTH recorded states, so a skip it cannot
# write stops the run exactly as an unrecordable `done` does -- and, like it,
# must NOT fall through to the reporter with half a run's records.
fx_out_not 'run complete'
fx_out_not 'modules ok'

# --- A1.7 a dry run reports the skip and writes no state at all ----------
echo "--- cell: A1 dry run counts the skip and writes nothing"
rm -rf "$FX_TMP/a1dryhome"
: >"$ORDER"
(
    set -euo pipefail
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$MOCK_LOG" FS_MOCK_INSTALLED="$INSTALLED"
    export FS_HOME="$FX_TMP/a1dryhome" FS_DRY_RUN=1 ORDER HOOK_LOG="$FX_TMP/a1hook6.log" PATH="$FAKE:$PATH"
    eval "$SRC"
    runner_run "$M" "$P" "notapp" "rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "A1 dry skip rc0" 0
# The summary is not state: a dry run still reports the skip, but it must not
# record one -- `state_module_skip` is behind the same dry-run guard as
# `state_module_mark`, so no state root is created at all.
fx_out '^  - 0 modules ok · 1 skipped · 0 failed · '
if [[ -e "$FX_TMP/a1dryhome/.local/state" ]]; then
    fx_bad "dry run created a state root for a skip"
else
    fx_ok
fi

fx_summary
