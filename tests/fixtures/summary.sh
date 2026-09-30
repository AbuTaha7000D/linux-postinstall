#!/usr/bin/env bash
# tests/fixtures/summary.sh - P9.5 fixture for the end-of-run summary reporter.
#
# The ROADMAP's P9.5 criterion is one line: "Mock run with 1 failure renders
# correct summary; exit code non-zero." Block 1 IS that, driven through the
# real `./setup install` (mock backend, a synthetic module tree) rather than by
# calling the reporter directly, because the criterion is about what a user
# sees, not about what a function returns.
#
# The rest of this fixture exists because of what the one-line criterion does
# NOT cover. P9.2's audit shipped three false-PASS defects and P9.4's guard
# shipped three holes, all of the same shape: the thing under test was
# rendered, reported, or checked correctly with respect to a DIFFERENT thing
# than the thing that governs behaviour. So each block below pins one relation
# that a summary can get wrong while still looking right:
#
#   2. THE LINE AND THE EXIT CODE COME FROM ONE SOURCE. A summary reporter
#      that printed "0 failed" and returned 0, or printed "1 failed" and
#      returned 0, satisfies most of a naive criterion. The check is that
#      `summary_line` and `summary_rc` are both derived from the recorded
#      outcomes, asserted on the reporter directly (including across
#      summary_reset) and by a structural guard that lib/runner.sh carries no
#      parallel counter and no io_summary call of its own.
#   3. THE ARTIFACTS POINTER IS NOT A LIE. `artifacts in <log>` is only
#      printed when the file EXISTS, and block 3 proves the file it names
#      contains the failing step -- a pointer to a file that does not exist,
#      or to one that does not mention what failed, is worse than no pointer.
#   4. A DRY RUN CLAIMS NOTHING IT DID NOT DO: no log, no state root, and an
#      artifacts clause that says so instead of naming a path.
#   5. ALL THREE COUNTS AT ONCE. Every converted assertion in the other suites
#      sees 0-or-N for two of the three numbers; only this block puts a
#      non-zero ok, skipped and failed in the SAME line, which is where a
#      mis-derived count would actually show.
#   6. ACTIONABILITY IS TRUE, NOT DECORATIVE. The reporter says "re-run the
#      same command; completed modules are skipped", so block 6 re-runs and
#      proves the claim: the failed module is retried, the completed one is
#      skipped, and the retry's own line agrees.
#   7. AN UNUSABLE LOG REFUSES THE INSTALL. The pointer is only trustworthy
#      because a run that cannot write its audit trail stops BEFORE installing
#      anything (io_init cannot report failure through its rc -- it warns and
#      returns 0 -- so the postcondition is what decides, the same rule P7.6
#      applied to pkg_add_repo and P9.4 to the fast-forward).
#   8. ABORT PATHS STILL PRINT NO SUMMARY. A run that stops at a prereq or a
#      batch never reached the module loop, so it has no module outcomes to
#      report; "0 ok . 0 failed" there would read as success.
#
# Nothing outside FX_TMP is touched, no network, no privileges, mock backend.
# Usage: bash tests/fixtures/summary.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

# Cells that cannot run as root (a root process ignores directory permissions,
# so "make this log unwritable" is not expressible) are reported in the
# summary line rather than silently passed. A bare note on stdout reads as full
# coverage on a root CI while the guard is untested, which is worse than an
# explicit gap: it is what let the first version of this fixture claim
# coverage it did not have.
#
# HONEST LIMIT: on a NON-root run FX_SKIPPED is always 0, so the reporting
# branch below is not executed here and no cell in this file observes it being
# taken. What is verified on a non-root host is the FORMAT (last cell) and,
# on a root host, the branch. The literals in that cell are deliberately NOT
# this suite's totals: it pins the shape of the line, not how many asserts
# ran. The unwritable-log refusal (7b) is UNTESTED as root, so on a root CI the
# _fs_open_run_log postcondition's REFUSAL branch has no coverage (7a is a
# state_init cell, not one) -- see AGENTS.md, which says so rather than implying
# otherwise. The SATISFIED branch is exercised by every real-install cell.
#
# SHARPER: the `-w` LEG of _io_log_usable is uncovered on BOTH uids. As root
# `-w` is true for everything; as uid 1000 every shape 6c pins is decided by
# -f/-s, and on the install path the path is freshly minted by state_log and
# created by io_init, so it is writable by construction. It is defence in depth
# against an INHERITED unwritable FS_LOG_FILE, and this repo has no cell for
# that case. Do not claim the -w leg is tested.
FX_SKIPPED=0
fx_skip() {
    FX_SKIPPED=$((FX_SKIPPED + 1))
    printf '  SKIP: %s\n' "$1"
}
SETUP="$ROOT/setup"
BULLET=$'\xc2\xb7'

printf 'P9.5 summary reporter\n'

# A synthetic module tree: `good` succeeds, `bad` fails its hook, `fat`
# installs four packages, `pdep` fails in prerepo. Synthetic rather than
# shipped modules on purpose -- a fixture that used the real `fonts` or `core`
# module would break whenever that module's own behaviour changed, and the
# ROADMAP criterion is about the reporter.
MODS="$FX_TMP/mods"
PROFS="$FX_TMP/profs"
mkdir -p "$MODS/good" "$MODS/bad" "$MODS/bad2" "$MODS/fat" "$MODS/pdep" "$MODS/asnap" "$MODS/bmark" "$PROFS"
printf 'MODULE_ID=good\nMODULE_TITLE=Good\n' >"$MODS/good/module.sh"
printf 'run() { io_info "good hook ran"; return 0; }\n' >"$MODS/good/hooks.sh"
printf 'MODULE_ID=bad\nMODULE_TITLE=Bad\n' >"$MODS/bad/module.sh"
printf 'run() { io_error "bad hook exploded"; return 1; }\n' >"$MODS/bad/hooks.sh"
printf 'MODULE_ID=bad2\nMODULE_TITLE=Bad2\n' >"$MODS/bad2/module.sh"
printf 'run() { io_error "bad2 hook exploded"; return 1; }\n' >"$MODS/bad2/hooks.sh"
printf 'MODULE_ID=fat\nMODULE_TITLE=Fat\n' >"$MODS/fat/module.sh"
printf 'f1\nf2\nf3\nf4\n' >"$MODS/fat/packages.rpm.list"
printf 'run() { io_info "fat hook ran"; return 0; }\n' >"$MODS/fat/hooks.sh"
printf 'MODULE_ID=asnap\nMODULE_TITLE=Already\n' >"$MODS/asnap/module.sh"
printf 'MODULE_ID=bmark\nMODULE_TITLE=Blocked\n' >"$MODS/bmark/module.sh"
printf 'MODULE_ID=pdep\nMODULE_TITLE=Prerepo\n' >"$MODS/pdep/module.sh"
printf 'prerepo() { io_error "prerepo exploded"; return 1; }\n' >"$MODS/pdep/prerepo.sh"
printf 'good\nbad\n' >"$PROFS/mix.conf"
printf 'fat\ngood\n' >"$PROFS/fatgood.conf"
printf 'fat\ngood\nbad\nbad2\n' >"$PROFS/all.conf"
printf 'asnap\nbmark\n' >"$PROFS/markabort.conf"
printf 'pdep\ngood\n' >"$PROFS/pdep.conf"

# run <home> <rc> [args...] -- the real launcher, mock backend, our trees.
# <home> names the state root, so two calls with the same name RESUME the same
# state and the second one sees skipped modules; a fresh name starts over.
# Records the command in FX_OUT (stdout+stderr merged, so a `summary_report`
# row cannot be satisfied by an unrelated stream) for the fx_out assertions.
run() {
    local name="$1" want="$2"
    shift 2
    ( set +e
      env FS_HOME="$FX_TMP/h-$name" \
      FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$PROFS" \
      FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
      ${FX_LOGFILE:+"FS_LOG_FILE=$FX_LOGFILE"} \
      "$SETUP" install --yes "$@"
    ) >"$FX_OUT" 2>&1
    FX_BLOCK_RC=$?
    fx_block_rc "$name rc" "$want"
}

line_of() {
    grep -m1 '^  - [0-9]* modules ok ' "$FX_OUT" 2>/dev/null || true
}

# --- 1. THE ROADMAP CRITERION: one failure renders the summary, rc != 0 -----

run h1 1 --profile mix
if [[ "$(line_of)" == "  - 1 modules ok ${BULLET} 0 skipped ${BULLET} 1 failed ${BULLET} artifacts in "* ]]; then
    fx_ok
else
    fx_bad "mix summary line wrong: $(line_of)"
fi
# fx_out is an unanchored grep, so a status of 10 satisfies `hook exited 1`
# unless the pattern is terminated -- hence the `$` (see also :201, :311-312).
fx_out '  - FAIL bad: hook exited 1$'
fx_out '^  - retry: re-run the same command; completed modules are skipped$'
# The failure must ALSO be on stderr as the pre-existing runner message, so a
# user piping only stderr still learns which module died.
fx_out 'module failed: bad'
if grep -q 'run complete' "$FX_OUT"; then fx_ok; else fx_bad "mix printed no summary header"; fi
# And the good module still ran: a failure must not stop the loop for a
# non-destructive module (the reviewed P4.6 policy).
fx_out 'good hook ran'

# --- 2. one source for the line AND the exit code --------------------------

# Reporter-level: the counts in the line and the rc are read off the same
# records. A reporter that kept a private counter could satisfy either half
# alone; this asserts they cannot diverge, in both directions.
SRCC="source \"\$0/lib/io.sh\"; source \"\$0/lib/summary.sh\""
# One invocation, two answers: the body prints the line, then summary_rc
# becomes the exit code. Reading both from the SAME run is the point -- a cell
# that asked twice could see a line and an rc from different states.
probe() {
    local body="$1" out="" rc=0
    out="$(bash -c "$SRCC
$body
printf 'LINE %s\n' \"\$(summary_line)\"
summary_rc" "$ROOT" 2>/dev/null)" || rc=$?
    PROBE_LINE="$(printf '%s\n' "$out" | sed -n 's/^LINE //p')"
    PROBE_RC=$rc
}
agree_rc() {
    local want_line="$1" want_rc="$2" name="$3"
    probe "$4"
    if [[ "$PROBE_LINE" == "$want_line" ]]; then fx_ok
    else fx_bad "$name line (want '$want_line', got '$PROBE_LINE')"; fi
    if (( PROBE_RC == want_rc )); then fx_ok
    else fx_bad "$name rc (want $want_rc, got $PROBE_RC)"; fi
}
# ok only -> line says 0 failed AND rc 0 (the "reports success, exits
# non-zero" and "reports failure, exits zero" directions both live here)
agree_rc "2 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET} artifacts: none (no run log was opened)" 0 \
    "ok only" 'summary_reset; summary_module_ok a; summary_module_ok b'
# two failures -> line says 2 failed AND rc 1, and the rows match the count
agree_rc "0 modules ok ${BULLET} 0 skipped ${BULLET} 2 failed ${BULLET} artifacts: none (no run log was opened)" 1 \
    "two failures" 'summary_reset; summary_module_fail a "hook exited 3"; summary_module_fail b "hook exited 1"'
# summary_reset must clear the records: a second run in the same shell must
# not inherit the first run's failures (the runner calls it once per run).
agree_rc "0 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET} artifacts: none (no run log was opened)" 0 \
    "after reset" 'summary_module_fail a "hook exited 1"; summary_reset'
# summary_reset must clear the SKIP records too, not just the FAIL ones: a
# second run in the same shell must not inherit the first run's skips.
agree_rc "0 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET} artifacts: none (no run log was opened)" 0 \
    "after reset clears skips" 'summary_module_skip a; summary_reset'
# ...and the FAIL DETAIL array, so a later failure cannot inherit an earlier
# failure's recorded status.
agree_rc "0 modules ok ${BULLET} 0 skipped ${BULLET} 1 failed ${BULLET} artifacts: none (no run log was opened)" 1 \
    "after reset clears fail detail" 'summary_module_fail a "hook exited 1"; summary_reset; summary_module_fail b "hook exited 2"'
# The ROW must carry b's own status, not a's stale one: if summary_reset left
# SUMMARY_FAIL_DETAIL populated, b's row would read "hook exited 1" (index 0)
# while the count still said 1 failed -- a wrong statement about which module
# died, invisible to the line/rc check above.
ROWS="$(bash -c "$SRCC; summary_module_fail a 'hook exited 1'; summary_reset; summary_module_fail b 'hook exited 2'; summary_report" \
    "$ROOT" 2>/dev/null)"
printf '%s\n' "$ROWS" | grep -qx '  - FAIL b: hook exited 2$' && fx_ok \
    || fx_bad "after reset, a later failure inherited an earlier failure's detail"
# One row per failure, in RECORD order, and no row at all when clean. Both
# rows are matched with grep -qx against DISTINCT exit statuses: an earlier
# version of this cell checked only the first row, and a reporter that rendered
# a constant detail, or the wrong module's status, passed it. The statuses
# differ on purpose so neither row can satisfy the other's expectation.
ROWS="$(bash -c "$SRCC; summary_reset; summary_module_fail z 'hook exited 7'; summary_module_fail a 'hook exited 12'; summary_report" \
    "$ROOT" 2>/dev/null)"
printf '%s\n' "$ROWS" | grep -qx '  - FAIL z: hook exited 7' && fx_ok \
    || fx_bad "FAIL row for z is missing or carries the wrong status"
printf '%s\n' "$ROWS" | grep -qx '  - FAIL a: hook exited 12' && fx_ok \
    || fx_bad "FAIL row for a is missing or carries the wrong status"
# ...and in RECORD order: matching each row independently is order-insensitive,
# so a reporter printing them reversed satisfied the two assertions above.
ZLINE="$(printf '%s\n' "$ROWS" | grep -n 'FAIL z:' | cut -d: -f1)"
ALINE="$(printf '%s\n' "$ROWS" | grep -n 'FAIL a:' | cut -d: -f1)"
if [[ -n "$ZLINE" && -n "$ALINE" ]] && (( ZLINE < ALINE )); then fx_ok
else fx_bad "FAIL rows are not in record order (z at $ZLINE, a at $ALINE)"; fi
if bash -c "$SRCC; summary_reset; summary_module_ok a; summary_module_skip b; summary_report" "$ROOT" 2>/dev/null \
    | grep -q 'FAIL\|retry:'; then fx_bad "a clean run printed a failure row or retry advice"
else fx_ok; fi
# Structural: the runner must not keep a parallel counter, and must not render
# the summary itself. This is the P9.2-B4 lesson made checkable -- two
# implementations of one fact is the defect, and a behavioural cell cannot
# detect an unused second one.
# BEST-EFFORT structural guard, not a proof: it recognises the idiomatic
# increments (x=N, x=$(( )), ((x++)), ((x--)), (( ++x )), ((x += 1)), ((x = x + 1))
# and `let`, and it cannot be made complete. The behavioural cells are the real
# evidence; this one only catches the shape a reviewer would not think to add.
if grep -qE '(^|[^_[:alnum:]])(ok|failed|skipped)=|\(\([[:space:]]*(\+\+|--)?(ok|failed|skipped)[[:space:]]*(\+\+|--)?[[:space:]]*\)\)|let[[:space:]]+"?(ok|failed|skipped)' "$ROOT/lib/runner.sh"; then
    fx_bad "lib/runner.sh keeps a parallel outcome counter; the reporter owns the counts"
else fx_ok; fi
if grep -q 'io_summary' "$ROOT/lib/runner.sh"; then
    fx_bad "lib/runner.sh calls io_summary directly; only the reporter may render it"
else fx_ok; fi
if grep -q 'summary_rc' "$ROOT/lib/runner.sh" && grep -q 'summary_report' "$ROOT/lib/runner.sh"; then
    fx_ok
else fx_bad "lib/runner.sh does not take both the line and the rc from the reporter"; fi

# --- 3. the artifacts pointer names a real file holding the failure -------

LOGPATH="$(line_of | sed 's/.*artifacts in //')"
if [[ -n "$LOGPATH" && -f "$LOGPATH" ]]; then fx_ok
else fx_bad "artifacts path is not an existing file: '$LOGPATH'"; fi
if [[ -n "$LOGPATH" ]] && grep -q 'bad hook exploded' "$LOGPATH" 2>/dev/null; then fx_ok
else fx_bad "the named log does not contain the failing step"; fi
if [[ -n "$LOGPATH" ]] && grep -q 'FAIL bad: hook exited 1$' "$LOGPATH" 2>/dev/null; then fx_ok
else fx_bad "the named log does not contain the summary line it pointed at"; fi
# Each run into the SAME state root must open its OWN log: a run that appended
# to the previous run's file would make the pointer ambiguous about which
# artifacts are which. Counting across two different state roots would prove
# nothing, so both runs below share one home.
# A FRESH state root, so the counts are this cell's own: the first version of
# this cell reused the home of an earlier one and read "1 before" from a log
# that cell had left behind, which is why a mutation showing the two runs
# SHARING a file could not fail it.
LOGS="$FX_TMP/h-log2/.local/state/fedora-setup/logs"
run log2 1 --profile mix
n1="$(find "$LOGS" -name 'run-*.log' 2>/dev/null | wc -l)"
run log2 1 --profile mix
n2="$(find "$LOGS" -name 'run-*.log' 2>/dev/null | wc -l)"
if (( n1 == 1 && n2 == 2 )); then fx_ok
else fx_bad "a second run must open its own log (after run1=$n1 after run2=$n2, want 1 then 2)"; fi

# --- 4. a dry run claims nothing it did not do ----------------------------

run hdry 1 --dry-run --profile mix
fx_out "  - 1 modules ok ${BULLET} 0 skipped ${BULLET} 1 failed ${BULLET} artifacts: none (a dry run writes nothing)"
if [[ -e "$FX_TMP/h-hdry" ]]; then fx_bad "dry run created a state root"; else fx_ok; fi
fx_out_not 'artifacts in '
# The dry-run wording must be the dry-run wording, not the no-log one: a
# reader needs to know a dry run writes nothing BY DESIGN, not that the tool
# forgot to open a log.
if grep -q 'artifacts: none (no run log was opened)' "$FX_OUT"; then
    fx_bad "dry run reported a missing log instead of reporting that it writes nothing"
else fx_ok; fi

# A dry run that ALSO has an exported FS_LOG_FILE names that file, because it
# exists, is writable, and really does hold the lines this run emitted. Pinned
# because the two orderings of this feature are easy to conflate: the reporter
# checks usability FIRST, so "a dry run writes nothing" is the fallback, not
# the rule. A dry run writes nothing to the SYSTEM either way.
FX_LOGFILE="$FX_TMP/user.log"
run hdry2 0 --dry-run --profile fatgood
FX_LOGFILE=""
fx_out "  - 2 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET} artifacts in $FX_TMP/user.log"
if [[ -s "$FX_TMP/user.log" ]]; then fx_ok
else fx_bad "the named dry-run log holds none of this run's lines"; fi
if grep -q 'a dry run writes nothing' "$FX_OUT"; then
    fx_bad "a usable log was configured, so the fallback wording is wrong here"
else fx_ok; fi

# A CLEAN real install, which is the COMMON path and was the one combination
# the fixture never asserted: every other real install here has a failure in
# it. A reporter that cleared the log path when nothing failed satisfied all of
# them, and the user would be told "artifacts: none (no run log was opened)" by
# a run that opened a real one. So the clause is pinned here on 0 failed, plus
# the guarantee _fs_open_run_log exists to give: the named path IS this run's
# state-root log and it holds the run's own lines.
run hclean 0 --profile fatgood
fx_out "^  - 2 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET} artifacts in "
CLEANSUM="$(line_of)"
CLEANLOG="${CLEANSUM##*artifacts in }"
if [[ "$CLEANLOG" == "$FX_TMP/h-hclean/"*"/logs/run-"*.log ]]; then fx_ok
else fx_bad "a clean run did not name its own state-root log: $CLEANLOG"; fi
if [[ -s "$CLEANLOG" ]]; then fx_ok
else fx_bad "the log a clean run named is missing or empty: $CLEANLOG"; fi
if grep -q 'fat hook ran' "$CLEANLOG" && grep -q 'good hook ran' "$CLEANLOG"; then fx_ok
else fx_bad "the log a clean run named holds none of that run's hooks"; fi
if grep -q 'run complete' "$CLEANLOG"; then fx_ok
else fx_bad "the log a clean run named holds no summary line"; fi

# --- 5. all three counts non-zero in the same line ------------------------

# Every converted assertion in the other suites sees 0-or-N for two of the
# three numbers. This block puts a non-zero ok, a non-zero skipped AND a
# non-zero failed in the SAME line, which is the only shape where a count
# derived from the wrong array would be visible.
run hall 1 --profile all
fx_out "  - 2 modules ok ${BULLET} 0 skipped ${BULLET} 2 failed ${BULLET} artifacts in "
fx_out '^  - FAIL bad: hook exited 1$'
fx_out '^  - FAIL bad2: hook exited 1$'
rows="$(grep -c '^  - FAIL ' "$FX_OUT")"
if (( rows == 2 )); then fx_ok; else fx_bad "expected 2 FAIL rows, got $rows"; fi
# Two failures -> two rows AND a count of 2, i.e. the number in the line is
# derived from the same records the rows are printed from.
if [[ "$(grep -c '^  - FAIL ' "$FX_OUT")" == "$(line_of | sed -n 's/.* \([0-9]*\) failed .*/\1/p')" ]]; then
    fx_ok
else fx_bad "the failed count in the line disagrees with the number of FAIL rows"; fi

# Second run over the same profile: the two modules that succeeded are now
# skipped, the two that failed are retried and fail again. 0 ok / 2 skipped /
# 2 failed -- all three numbers non-zero, and the only shape asserted here.
run hall 1 --profile all
fx_out "  - 0 modules ok ${BULLET} 2 skipped ${BULLET} 2 failed ${BULLET} artifacts in "
# The skipped modules were NOT re-run; only the failed ones were.
if [[ "$(grep -c 'fat hook ran' "$FX_OUT")" == 0 && "$(grep -c 'good hook ran' "$FX_OUT")" == 0 ]]; then
    fx_ok
else fx_bad "a skipped module's hook ran again"; fi
fx_out '^  - FAIL bad: hook exited 1$'
fx_out '^  - FAIL bad2: hook exited 1$'

# --- 6. the retry advice is true, not decorative --------------------------

# The reporter claims a re-run retries exactly the failed modules. Prove it
# against the state: the completed modules kept their marks, the failed ones
# were never latched, so the advice describes what the runner actually does.
SDIR="$FX_TMP/h-hall/.local/state/fedora-setup/modules"
if [[ -f "$SDIR/fat" && -f "$SDIR/good" ]]; then fx_ok
else fx_bad "a completed module lost its completion mark, so the retry advice is false"; fi
if [[ -e "$SDIR/bad" || -e "$SDIR/bad2" ]]; then
    fx_bad "a failed module was latched done, so a re-run would skip it"
else fx_ok; fi
run hall 1 --profile all
fx_out "  - 0 modules ok ${BULLET} 2 skipped ${BULLET} 2 failed ${BULLET} artifacts in "
if grep -q '  - FAIL fat: \|  - FAIL good: ' "$FX_OUT"; then
    fx_bad "the retry reported a module that had already succeeded as failed"
else fx_ok; fi

# --- 6b. a configured log that is not a real file is not named ------------

# The clause promises "artifacts in <path>", so it may only print that for a
# path that IS a file. /dev/null is this project's own canonical unusable log
# (run.sh refuses it via FS_LOG_INFRA) and it is a character device, so
# [[ -f ]] is false and no run can make it one -- which is exactly the state
# this cell needs: configured, present, and not a log.
FX_LOGFILE=/dev/null
run hdevnull 0 --dry-run --profile fatgood
FX_LOGFILE=""
fx_out_not 'artifacts in '
fx_out "artifacts: none (a dry run writes nothing)"
if grep -q 'artifacts in /dev/null' "$FX_OUT"; then
    fx_bad "the summary pointed at /dev/null, which is not a log file"
else fx_ok; fi

# --- 6c. the shared predicate, on the shapes it must refuse ---------------

# The guard (lib/bootstrap.sh) and the pointer (lib/summary.sh) call ONE
# predicate, so the useful question is what it accepts. These shapes are
# root-proof: a directory, a FIFO, an empty file, a dangling symlink and an
# absent path are refused (or, for the symlink to a real file, accepted) for
# reasons that do not depend on permission bits, so they hold on a root CI too.
# The FIFO is removed by the loop below, so no cell ever blocks on one.
mkfifo "$FX_TMP/fifo.log" 2>/dev/null
: >"$FX_TMP/empty.log"
printf 'real\n' >"$FX_TMP/real.log"
ln -s "$FX_TMP/real.log" "$FX_TMP/link.log"
ln -s "$FX_TMP/nowhere" "$FX_TMP/dangling.log"
mkdir -p "$FX_TMP/adir"
PRED="$(bash -c 'source "$0/lib/io.sh"
for a in "$@"; do
    if _io_log_usable "$a"; then printf "ACCEPT %s\n" "$a"; else printf "REFUSE %s\n" "$a"; fi
done' "$ROOT" "$FX_TMP/real.log" "$FX_TMP/link.log" "$FX_TMP/empty.log" \
    "$FX_TMP/fifo.log" "$FX_TMP/adir" "$FX_TMP/dangling.log" "$FX_TMP/absent.log" "" 2>/dev/null)"
printf '%s\n' "$PRED" | grep -qx "ACCEPT $FX_TMP/real.log" && fx_ok \
    || fx_bad "predicate refused a usable log"
printf '%s\n' "$PRED" | grep -qx "ACCEPT $FX_TMP/link.log" && fx_ok \
    || fx_bad "predicate refused a symlink to a usable log (run.sh:56 follows it too)"
for bad in empty.log fifo.log adir dangling.log absent.log; do
    printf '%s\n' "$PRED" | grep -qx "REFUSE $FX_TMP/$bad" && fx_ok \
        || fx_bad "predicate accepted $bad, which is not a usable log"
done
printf '%s\n' "$PRED" | grep -qx "REFUSE " && fx_ok \
    || fx_bad "predicate accepted the empty path"
# One predicate, two call sites: if either re-implements the test, the B1
# disagreement comes straight back.
if grep -q '_io_log_usable "$log"' "$ROOT/lib/summary.sh" && grep -q '_io_log_usable "$log"' "$ROOT/lib/bootstrap.sh"; then
    fx_ok
else fx_bad "the summary and the bootstrap guard do not share _io_log_usable"; fi

# --- 7a. state_init refuses a logs/ path that is a regular file -----------

# 7a is a state_init cell, NOT a _fs_open_run_log cell. The first version of it
# made <state>/logs a regular file and claimed that state_log would refuse --
# but state_init validates every state subdir first (lib/state.sh
# _state_dir_content_ok), so the install dies at bootstrap.sh's `state_init
# || return 1` and state_log is never reached. The assertions below are
# therefore about state_init, and they would be unchanged if _fs_open_run_log
# were deleted; block 6c and 7b are what cover that function, and 7b is
# root-skipped. Do not read 7a as coverage of the run-log guard.
BADLOGS_HOME="$FX_TMP/h-badlogs"
mkdir -p "$BADLOGS_HOME/.local/state/fedora-setup"
: >"$BADLOGS_HOME/.local/state/fedora-setup/logs"
( set +e
  FS_HOME="$BADLOGS_HOME" FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$PROFS" \
  FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
  "$SETUP" install --yes --profile fatgood
) >"$FX_OUT" 2>&1
FX_BLOCK_RC=$?
fx_block_rc "state_init refuses a logs file rc" 1
fx_out 'state path exists and is not a directory'
fx_out_not '^== run complete ==$'
fx_out_not 'fat hook ran'

# --- 7b. an unwritable log directory refuses the install -----------------

# 7b. logs is a real but UNWRITABLE directory: state_log is happy (it only
# checks the shape) and returns a path, so the refusal has to come from
# checking that the file was actually written. io_init cannot do it -- it warns
# and still returns 0 -- which is why the postcondition exists.
#
# This cell used to have a first half that made <state>/logs a REGULAR FILE and
# claimed state_log refuses it. It does not: state_init validates every state
# subdirectory first (lib/state.sh _state_dir_content_ok), so that construction
# dies before state_log is called -- it reports "state path exists and is not a
# directory" -- which made it a duplicate of 7a. It was deleted rather than
# relabelled, because 7a already pins that construction.
#
# COVERAGE NOTE, stated rather than implied: state_log's OWN refusal branch
# (lib/state.sh, "log path not usable") has NO cell anywhere in this repo. It
# needs <state>/logs to be a real directory already holding a colliding
# run-<ts>-<pid>.log path, and the launcher mints a fresh name per run, so that
# branch is not reachable through ./setup. Read this task's coverage as: 7b
# covers the postcondition, 6c the predicate, neither covers that branch.
if (( EUID == 0 )); then
    fx_skip "7b (unwritable log dir): needs a non-root uid, so the -w leg of the postcondition is UNTESTED here"
else
    ROHOME="$FX_TMP/h-noperm"
    ROLOGS="$ROHOME/.local/state/fedora-setup/logs"
    mkdir -p "$ROLOGS"
    chmod 500 -- "$ROLOGS"
    ( set +e
      FS_HOME="$ROHOME" FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$PROFS" \
      FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
      "$SETUP" install --yes --profile fatgood
    ) >"$FX_OUT" 2>&1
    FX_BLOCK_RC=$?
    fx_block_rc "unwritable log dir rc" 1
    fx_out_not 'run complete'
    fx_out_not 'good hook ran'
    fx_out_not 'fat hook ran'
    if grep -q 'run log is unusable' "$FX_OUT"; then fx_ok
    else fx_bad "an unwritable log dir did not stop the install"; fi
    chmod 700 -- "$ROLOGS"
fi

# --- 7c. two runs in ONE process must not share outcomes ------------------

# The reporter's state is process-global, so a second runner_run in the same
# shell would inherit the first run's failures -- and report a clean run as a
# failed one. One install per process is the only production path, so this is
# pinned against the runner's own contract (it calls summary_reset once per
# run) by driving the real runner twice. Dry-run is used because it needs no
# state root and no backend; its hooks still execute, which is what makes the
# first run fail.
RSRC="source \"\$0/lib/io.sh\"; source \"\$0/lib/run.sh\"; source \"\$0/lib/pkg.sh\"
source \"\$0/lib/planner.sh\"; source \"\$0/lib/lists.sh\"; source \"\$0/lib/state.sh\"
source \"\$0/lib/modules.sh\"; source \"\$0/lib/depgraph.sh\"; source \"\$0/lib/profiles.sh\"
source \"\$0/lib/summary.sh\"; source \"\$0/lib/runner.sh\""
two_runs="$(bash -c "$RSRC
export FS_DRY_RUN=1 FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
runner_run \"\$1\" \"\$2\" mix rpm
runner_run \"\$1\" \"\$2\" fatgood rpm" "$ROOT" "$MODS" "$PROFS" 2>/dev/null | grep '^  - ')"
rc_second=0
bash -c "$RSRC
export FS_DRY_RUN=1 FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
runner_run \"\$1\" \"\$2\" mix rpm
runner_run \"\$1\" \"\$2\" fatgood rpm" "$ROOT" "$MODS" "$PROFS" >/dev/null 2>&1 || rc_second=$?
if printf '%s\n' "$two_runs" | grep -q "^  - 2 modules ok ${BULLET} 0 skipped ${BULLET} 0 failed ${BULLET}"; then
    fx_ok
else fx_bad "the second in-process run inherited the first run's outcomes: $two_runs"; fi
if (( rc_second == 0 )); then fx_ok
else fx_bad "the second in-process run exited $rc_second on a clean profile (stale failures)"; fi

# --- 7d. the two abort paths that previously had no cell ------------------

# 7d-i. the SYSTEM package batch failing (runner.sh:313). The flatpak batch,
# the destructive stop and both prerepo paths are already pinned by
# tests/fixtures/runner.sh; this is the fourth corner of the batch stage.
# The mock backend has no `mock` binary to fake: mock_install_batch fails when
# _mock_record cannot append to FS_MOCK_LOG, and _mock_record refuses a path
# that is not a regular file. Pointing FS_MOCK_LOG at a DIRECTORY therefore
# fails the batch for a reason that also holds as root.
mkdir -p "$FX_TMP/notafile"
( set +e
  env FS_MOCK_LOG="$FX_TMP/notafile" FS_HOME="$FX_TMP/h-badpkg" \
  FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$PROFS" \
  FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
  "$SETUP" install --yes --profile fatgood
) >"$FX_OUT" 2>&1
FX_BLOCK_RC=$?
fx_block_rc "system batch failure rc" 1
fx_out_not 'run complete'
fx_out 'package batch failed'
fx_out_not 'fat hook ran'
fx_out_not 'good hook ran'

# 7d-ii. state_module_mark failing AFTER an outcome was recorded. This is the
# one abort path that runs with records already in the reporter, so "the
# reporter is not reached" has to be verified rather than assumed -- a summary
# here would print the modules that had run so far, silently drop the rest, and
# exit 1 with a line that reads like a finished run.
#
# The construction has to reach state_module_mark, which the first version of
# this cell did NOT: it made <state>/modules a regular file, so state_init
# refused and the run died before the module loop. So <state>/modules stays a
# real directory, `asnap` is pre-marked (a real file) so the runner records a
# `skipped` outcome for it, and a DIRECTORY is placed at `bmark`'s mark path,
# which is what _state_write refuses ("state target is a directory"). Every
# step is uid-independent, so unlike 7b this cell also covers a root CI.
MSTATE="$FX_TMP/h-mark/.local/state/fedora-setup/modules"
mkdir -p "$MSTATE/bmark"
printf 'done 2026-01-01T00:00:00Z\n' >"$MSTATE/asnap"
( set +e
  FS_HOME="$FX_TMP/h-mark" FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$PROFS" \
  FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
  "$SETUP" install --yes --profile markabort
) >"$FX_OUT" 2>&1
FX_BLOCK_RC=$?
fx_block_rc "state_module_mark failure rc" 1
fx_out 'state target is a directory'
# The precondition the cell exists to establish: the skipped outcome really was
# recorded before the abort, so the absence of a summary is a decision.
fx_out 'already completed: asnap'
fx_out_not '^== run complete ==$'
fx_out_not '1 modules ok'
fx_out_not "1 modules ok ${BULLET}"
fx_out_not 'retry:'

# --- 8. abort paths still print no summary --------------------------------

run hpdep 1 --profile pdep
fx_out_not 'run complete'
fx_out 'prerepo exploded'
fx_out_not 'good hook ran'
fx_out_not 'mock install'

# The skip REPORTING is only reachable on a root run, which this host cannot
# provide (no passwordless sudo), so what is pinned here is the FORMAT, not the
# branch: the line a root run emits must carry the skipped count. Whether the
# branch is taken is stated in the header and in AGENTS.md as unexercised --
# pretending otherwise is the mistake this cell exists to prevent.
# Comparing a printf against its own expansion is a tautology, so this pins the
# FORMAT against the source that emits it. The pattern is anchored on the
# reporting printf itself (comment prose deliberately does not repeat it, or the
# pin would match its own explanation -- which is how the first version of this
# cell escaped a mutation). The BRANCH that chooses that line is still
# unexercised on uid 1000; only its text is pinned.
# The bracket in each pattern is not decoration: it is what stops the pattern
# from matching ITS OWN line, which is the defect the first version of this cell
# had (a mutation of the reporting printf left 0 fails, because the pin still
# matched the text of its own grep).
if grep -q "printf 'summary: %s passed, %s failed, %s skippe[d] (root-only" "$0"; then fx_ok
else fx_bad "the root-run reporting line no longer carries the skipped count"; fi
if grep -q 'fx_ski[p]() {' "$0" && grep -q 'FX_SKIPPED=$((FX_SKIPPE[D] + 1))' "$0"; then fx_ok
else fx_bad "root-only cells are no longer counted through fx_skip"; fi

if (( FX_SKIPPED > 0 )); then
    printf 'summary: %s passed, %s failed, %s skipped (root-only limitation)\n' \
        "$FX_PASS" "$FX_FAIL" "$FX_SKIPPED"
    (( FX_FAIL == 0 ))
else
    fx_summary
fi

