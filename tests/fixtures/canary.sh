#!/usr/bin/env bash
# tests/fixtures/canary.sh - PERMANENT HARNESS FAILURE CANARY (P11-R D2).
#
# WHAT THIS TESTS: the TEST HARNESS, not production behaviour. Nothing here
# asserts anything about ./setup, a lib, or a module. Every subject under test
# is tests/run (and the tests/lib_tap.bash it sources).
#
# WHY IT EXISTS: the P11-R audit could not reproduce the claim that tests/run
# cannot fail (finding F11, "NOT REPRODUCIBLE" in ROADMAP section 9), but it
# also flagged the resulting COVERAGE GAP: the property had no permanent,
# in-repo proof, so it could silently regress. This suite is that proof. It
# plants a known failure and asserts the runner reports it.
#
# HOW IT STAYS HONEST (AGENTS section 7: a canary that merely prints a note is
# not a canary):
#   * It exercises the REAL tests/run, copied byte-for-byte into a throwaway
#     mini-repo, and asserts that copy is cmp-identical to the shipped file --
#     so it cannot drift into testing a private reimplementation. (Re-deriving
#     the runner's logic here would be the P9.3 "private parser" defect: a
#     second implementation that agrees with the first until it doesn't.)
#   * The planted failure is DETECTED end to end (a `not ok` line AND a
#     non-zero rc from the runner itself), not simulated.
#   * There is a NEGATIVE CONTROL (group 3): a planted failure the runner
#     MISSES must be reported as a miss, so this suite cannot self-satisfy by
#     always finding what it planted.
#   * There is a self-check (group 4) proving the classifier used by the
#     negative control actually discriminates instead of returning a constant.
#
# STRICT MODE: `set -uo pipefail`, deliberately WITHOUT `-e`. This is the one
# place in the repo that omits errexit, and it is load-bearing: cn_exec exists to
# observe a FAILING tests/run, and under `-e` the shell aborts inside cn_exec at
# the first deliberately-failing synthetic suite, so the canary dies with rc 1 and
# no summary line instead of reporting anything. Measured: adding `-e` (or `-eu`)
# kills the suite; adding `-u` alone is safe and is already present. Do not
# "fix" this into the repo-wide convention.
#
# DETERMINISM / COST: offline (a stub bats, no network, no package installs),
# no timing dependence, no PTY, no GitHub Actions. The real bats-core is NOT
# invoked: tests/run only requires an executable at tests/bats/bin/bats, and a
# stub keeps this suite fast and hermetic. The real bats layer is covered by
# tests/run itself.
#
# ---------------------------------------------------------------------------
# MEASURED HARNESS GAPS -- FOUND BY THIS INVESTIGATION, DELIBERATELY NOT
# FIXED HERE. D2's deliverable is the canary; changing tests/run's verdict logic
# is a separate, owner-gated decision that D2 does not make. They are recorded
# because an unrecorded gap is worse than a documented one.
#
# Every number below was MEASURED against the real tests/run in a throwaway
# mini-repo, not reasoned about. Two of the four were re-measured and CORRECTED
# during Senior review round 1, because the first draft of this header stated
# them wrongly -- which is the whole reason a permanent record of measured
# facts has to be re-derived rather than trusted.
#
#   FG-1  TRUE. With a real 15-test bats layer present and tests/fixtures/
#         holding nothing but lib.sh, tests/run emits "1..15", 15 ok and exits
#         0: GREEN. The whole fixture layer (46 suites, 4000+ asserts) can
#         disappear without anything going red.
#         CORRECTION: an earlier draft of this header claimed "1..0". That is
#         only reachable with no bats layer at all; with the bats layer intact
#         the plan simply shrinks to the bats count.
#   FG-2  TRUE. A fixture that exits 0 printing NOTHING is reported "ok" and the
#         run stays green. Silently-dead suites read as passes.
#         Group 3 below deliberately relies on this gap -- it is the negative
#         control's subject -- and pins that dependency in a maintenance
#         contract, so this is the ONE gap a cell depends on.
#   FG-3  TRUE, but NOT as first described. The real gap: a fixture that prints
#         "summary: 3 passed, 2 failed" and exits 0, with no "^FAIL " line, is
#         reported "ok" -- the count says failed and the verdict ignores it.
#         CORRECTION: an earlier draft claimed the gap was "an fx_summary whose
#         return value is swallowed". That is WRONG: fx_bad writes a "FAIL "
#         line, so `fx_summary || true` after any real assertion failure is
#         still caught and reported "not ok" (measured). Only a count-only
#         summary escapes.
#   FG-4  TRUE. A bats layer that emits nothing and exits 0 contributes 0 tests;
#         the plan collapses to the fixture count and the run is still green.
#
# WHAT THE RUNNER DOES CATCH: a non-zero fixture rc; a fixture printing a
# "^FAIL " line even when it exits 0; a non-zero bats rc. All three are planted
# and pinned below (groups 2 and 2d). A fourth -- a fixture killed by a signal --
# is also caught by the runner, but is measured and recorded here rather than
# planted, so nothing in this suite pins it.
#
# OWNER STATUS: no decision on FG-1..FG-4 has been recorded yet; they are
# carried as open items, not as accepted behaviour. See the D2 row in
# ROADMAP.md.
#
# Usage: bash tests/fixtures/canary.sh   (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

RUNNER="$ROOT/tests/run"
TAPLIB="$ROOT/tests/lib_tap.bash"

# ---------------------------------------------------------------------------
# cn_verdict <runner-output-file> <runner-rc> -> "detected" or "missed"
#
# The classifier the canary uses to judge the runner. "detected" requires BOTH
# a `not ok` line in the stream AND a non-zero runner rc -- mirroring the two
# independent signals tests/run itself uses, so the canary never calls a
# failure "detected" on one signal alone.
# ---------------------------------------------------------------------------
cn_verdict() {
    local out="$1" rc="$2"
    if [[ "$rc" -ne 0 ]] && grep -q '^not ok ' "$out" 2>/dev/null; then
        printf 'detected\n'
    else
        printf 'missed\n'
    fi
}

# cn_build <tag> <bats-mode> <suite>... -- throwaway mini-repo whose tests/run
# is the real one. bats-mode: pass | fail. Each <suite> is one of the
# synthetic fixtures below.
cn_build() {
    local tag="$1" mode="$2"
    shift 2
    local d="$FX_TMP/$tag" s
    rm -rf "$d"
    mkdir -p "$d/tests/bats/bin" "$d/tests/fixtures"
    # tests/run refuses to start without an executable $ROOT/setup.
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$d/setup"
    chmod +x "$d/setup"
    cp "$RUNNER" "$d/tests/run"
    cp "$TAPLIB" "$d/tests/lib_tap.bash"
    cp "$ROOT/tests/fixtures/lib.sh" "$d/tests/fixtures/lib.sh"
    # A stub bats: tests/run only requires an executable here. Keeping it a
    # stub is what makes this suite hermetic and fast.
    case "$mode" in
    pass)
        printf '%s\n' '#!/usr/bin/env bash' \
            'printf "%s\n" "1..1" "ok 1 - synthetic bats test"' 'exit 0' \
            >"$d/tests/bats/bin/bats"
        ;;
    fail)
        printf '%s\n' '#!/usr/bin/env bash' \
            'printf "%s\n" "1..1" "not ok 1 - synthetic bats test"' 'exit 1' \
            >"$d/tests/bats/bin/bats"
        ;;
    esac
    chmod +x "$d/tests/bats/bin/bats"
    # tests/run globs tests/*.bats; nullglob is not enabled at that point, so
    # the glob must match or bats receives a literal path.
    printf 'x\n' >"$d/tests/one.bats"
    for s in "$@"; do
        case "$s" in
        # Real assert helpers, real epilogue: rc 0 and a summary line.
        # Two distinct names, so a cell can ask for two green suites and
        # actually get two TAP results.
        green)
            printf '%s\n' '#!/usr/bin/env bash' \
                'source "$(dirname "$0")/lib.sh"' 'fx_init' \
                'printf "cn synthetic green\n"' 'fx_ok' 'fx_ok' 'fx_summary' \
                >"$d/tests/fixtures/a_green.sh"
            ;;
        green2)
            printf '%s\n' '#!/usr/bin/env bash' \
                'source "$(dirname "$0")/lib.sh"' 'fx_init' \
                'printf "cn synthetic green 2\n"' 'fx_ok' 'fx_summary' \
                >"$d/tests/fixtures/b_green2.sh"
            ;;
        # A genuine assertion failure: fx_summary returns non-zero.
        red_rc)
            printf '%s\n' '#!/usr/bin/env bash' \
                'source "$(dirname "$0")/lib.sh"' 'fx_init' \
                'fx_bad "cn planted failure (rc leg)"' 'fx_summary' \
                >"$d/tests/fixtures/b_red_rc.sh"
            ;;
        # Exits 0 yet prints a FAIL line: proves detection is not the rc
        # leg alone.
        red_text)
            printf '%s\n' '#!/usr/bin/env bash' \
                'printf "FAIL cn planted failure (text leg)\n"' 'exit 0' \
                >"$d/tests/fixtures/c_red_text.sh"
            ;;
        # Non-zero rc and NO "FAIL " line: isolates the rc leg. Needed
        # because fx_bad writes to stderr, so every fixture built from the real
        # helpers is ALSO caught by the text leg -- without this suite nothing
        # would tell the two detection legs apart.
        red_silent_rc)
            printf '%s\n' '#!/usr/bin/env bash' \
                'printf "cn planted failure (rc only, no FAIL line)\n"' 'exit 7' \
                >"$d/tests/fixtures/d_red_rc_only.sh"
            ;;
        # The negative control's subject: rc 0 and no output at all, so the
        # runner cannot see it. This is measured gap FG-2.
        silent)
            printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
                >"$d/tests/fixtures/d_silent.sh"
            ;;
        esac
    done
    printf '%s' "$d"
}

# cn_exec <root> -> runs the real runner; sets CN_OUT/CN_RC
cn_exec() {
    CN_OUT="$FX_TMP/out.$$.cn"
    bash "$1/tests/run" >"$CN_OUT" 2>&1
    CN_RC=$?
}

printf 'D2 group 1: the canary exercises the REAL tests/run, not a copy of its logic\n'
# --- 1a: build a healthy mini-repo.
CN_D="$(cn_build healthy pass green green2)"

# --- 1b: the three files the canary hands the runner must be byte-identical to
# the shipped originals. Without this the whole suite could pass against a
# reimplementation that happens to agree with tests/run today -- the P9.3
# "private parser" defect. cn_build only ever copies these three, so the
# identity is structural, but it is asserted anyway: it is what makes a future
# change to cn_build that starts generating or patching the runner RED here
# instead of silently retargeting the canary.
for cn_rel in tests/run tests/lib_tap.bash tests/fixtures/lib.sh; do
    if cmp -s "$ROOT/$cn_rel" "$CN_D/$cn_rel"; then
        fx_ok
    else
        fx_bad "mini-repo $cn_rel is not byte-identical to the shipped file"
    fi
done

# --- 1c: a healthy harness over green suites is green, and the plan agrees
# with the number of suites actually run.
cn_exec "$CN_D"
if [[ "$CN_RC" -eq 0 ]]; then
    fx_ok
else
    fx_bad "healthy mini-harness should exit 0 (got $CN_RC)"
    sed 's/^/    /' "$CN_OUT" >&2
fi
if grep -qx '1..3' "$CN_OUT"; then
    fx_ok
else
    fx_bad "healthy plan should be 1..3 (1 bats + 2 fixtures)"
    sed 's/^/    /' "$CN_OUT" >&2
fi
if [[ "$(grep -c '^ok ' "$CN_OUT")" -eq 3 ]]; then
    fx_ok
else
    fx_bad "healthy run should report 3 ok"
    sed 's/^/    /' "$CN_OUT" >&2
fi
if grep -q '^not ok ' "$CN_OUT"; then
    fx_bad "healthy run reported a failure"
else fx_ok; fi
if [[ "$(cn_verdict "$CN_OUT" "$CN_RC")" == missed ]]; then
    fx_ok
else fx_bad "classifier should report 'missed' when there is nothing to detect"; fi

printf 'D2 group 2: a planted failure IS detected by the runner\n'
# --- 2a: the canary's core. Plant a genuine assertion failure and require the
# runner itself to report it AND to exit non-zero. This is the cell that goes
# red if tests/run's failure propagation is broken -- it is what makes the
# canary non-vacuous.
CN_D="$(cn_build redrc pass green2 red_rc)"
cn_exec "$CN_D"
if [[ "$(cn_verdict "$CN_OUT" "$CN_RC")" == detected ]]; then
    fx_ok
else
    fx_bad "runner MISSED a planted failure (rc=$CN_RC) -- failure propagation is broken"
    sed 's/^/    /' "$CN_OUT" >&2
fi
# attributable: the failure names the suite we planted, not something else.
if grep -qx 'not ok [0-9][0-9]* - b_red_rc' "$CN_OUT"; then
    fx_ok
else
    fx_bad "planted failure was not attributed to b_red_rc"
    sed 's/^/    /' "$CN_OUT" >&2
fi
# not swallowed: the diagnostic is echoed into the TAP stream, and rc is
# non-zero rather than merely a printed warning.
if grep -qx '# FAIL cn planted failure (rc leg)' "$CN_OUT"; then
    fx_ok
else
    fx_bad "runner did not surface the planted FAIL diagnostic"
    sed 's/^/    /' "$CN_OUT" >&2
fi

# --- 2b: the second, independent detection leg. This suite exits 0, so only
# the "^FAIL " scan can catch it. If detection were rc-only this cell fails.
CN_D="$(cn_build redtext pass green2 red_text)"
# Pin the premise this cell's comment asserts: the planted suite must really
# exit 0, or the "text leg" it claims to isolate is not isolated at all.
# (Senior round 2, NB-3: changing this suite to `exit 1` left the suite green.)
if bash "$CN_D/tests/fixtures/c_red_text.sh" >/dev/null 2>&1; then
    fx_ok
else fx_bad "the text-leg suite must exit 0 for this cell to isolate the text leg"; fi
cn_exec "$CN_D"
if [[ "$(cn_verdict "$CN_OUT" "$CN_RC")" == detected ]]; then
    fx_ok
else
    fx_bad "runner MISSED a planted failure that exited 0 (text leg)"
    sed 's/^/    /' "$CN_OUT" >&2
fi

# --- 2c: both planted at once -- two distinct failures, both reported, and the
# plan grows by exactly two. (Guards against a detector that stops at the
# first `not ok`.)
CN_D="$(cn_build redboth pass green2 red_rc red_text)"
cn_exec "$CN_D"
if [[ "$(cn_verdict "$CN_OUT" "$CN_RC")" == detected ]]; then
    fx_ok
else fx_bad "runner missed planted failures when two are present"; fi
if [[ "$(grep -c '^not ok ' "$CN_OUT")" -eq 2 ]]; then
    fx_ok
else
    fx_bad "expected exactly 2 not-ok lines, got $(grep -c '^not ok ' "$CN_OUT")"
    sed 's/^/    /' "$CN_OUT" >&2
fi

# --- 2d: the bats leg is a real leg too, not decoration.
CN_D="$(cn_build batsfail fail green2)"
cn_exec "$CN_D"
if [[ "$CN_RC" -ne 0 ]]; then
    fx_ok
else fx_bad "runner ignored a failing bats layer"; fi
# The exit code alone is not the whole contract: Senior review round 1 found a
# tap_renumber that rewrote every bats result to "ok" left this cell green. The
# failing bats test must also be REPORTED as not ok.
if grep -qx 'not ok 1 - synthetic bats test' "$CN_OUT"; then
    fx_ok
else
    fx_bad "a failing bats test was not reported as not ok"
    sed 's/^/    /' "$CN_OUT" >&2
fi

# --- 2e: the rc leg in ISOLATION. This suite exits 7 and prints no "FAIL "
# line, so the text leg cannot help: only a runner that reads the exit status
# can detect it. It is the cell that dies if tests/run's rc propagation breaks
# while its text scan still works.
CN_D="$(cn_build redsrc pass green2 red_silent_rc)"
cn_exec "$CN_D"
if [[ "$(cn_verdict "$CN_OUT" "$CN_RC")" == detected ]]; then
    fx_ok
else
    fx_bad "runner MISSED a planted failure that only signals via exit status"
    sed 's/^/    /' "$CN_OUT" >&2
fi
if grep -qx 'not ok [0-9][0-9]* - d_red_rc_only' "$CN_OUT"; then
    fx_ok
else
    fx_bad "rc-only planted failure was not attributed to d_red_rc_only"
    sed 's/^/    /' "$CN_OUT" >&2
fi
# And its diagnostic really is absent, so this cell cannot be satisfied by the
# text leg.
if grep -q '^# FAIL' "$CN_OUT"; then
    fx_bad "rc-only fixture emitted a FAIL diagnostic; the rc leg is no longer isolated"
else fx_ok; fi

printf 'D2 group 3: NEGATIVE CONTROL -- a planted failure the runner MISSES is reported\n'
# --- 3a: the required negative control. Plant a suite that exits 0 and prints
# nothing (measured gap FG-2): the runner genuinely cannot see it. The canary
# must REPORT that miss rather than pass quietly, which is what stops this
# suite from self-satisfying.
#
# MAINTENANCE CONTRACT: this cell pins a RECORDED GAP. If FG-2 is ever fixed in
# tests/run, this cell will go red on purpose -- that is the signal to delete
# it and record the fix, not to weaken it.
CN_D="$(cn_build silent pass green2 silent)"
cn_exec "$CN_D"
CN_V="$(cn_verdict "$CN_OUT" "$CN_RC")"
if [[ "$CN_V" == missed ]]; then
    fx_ok
else
    fx_bad "negative control broke: a suite that exits 0 silently is now DETECTED, so FG-2 appears fixed -- update this cell and the D2 ledger row"
fi
# And the point of the control, stated as an assertion: the runner really did
# classify the silent suite as ok, so "missed" above is a MISS and not an
# artefact of the suite never having been built.
if [[ -f "$CN_D/tests/fixtures/d_silent.sh" ]]; then
    fx_ok
else fx_bad "cn_build did not create the silent fixture the control depends on"; fi
if grep -qx 'ok [0-9][0-9]* - d_silent' "$CN_OUT"; then
    fx_ok
else
    fx_bad "negative control premise changed: the runner no longer reports the silent suite as ok"
    sed 's/^/    /' "$CN_OUT" >&2
fi

printf 'D2 group 4: the canary classifier discriminates (it is not a constant)\n'
# --- 4a: feed cn_verdict two synthetic transcripts. This is what makes the
# negative control above meaningful: a classifier that always returned
# "missed" would satisfy 3a while proving nothing about group 2.
if [[ "$(cn_verdict /dev/null 0)" == missed ]]; then
    fx_ok
else fx_bad "classifier should report 'missed' for an empty stream at rc 0"; fi
CN_FAKE="$FX_TMP/fake.tap"
printf '1..1\nnot ok 1 - x\n' >"$CN_FAKE"
if [[ "$(cn_verdict "$CN_FAKE" 1)" == detected ]]; then
    fx_ok
else fx_bad "classifier should report 'detected' for a not-ok stream at rc 1"; fi
# A `not ok` line with rc 0 is NOT a detection: one signal alone is not enough.
# (tests/run requires both, and so does the canary.)
if [[ "$(cn_verdict "$CN_FAKE" 0)" == missed ]]; then
    fx_ok
else fx_bad "classifier should not accept a not-ok line at rc 0"; fi
# A non-zero rc with no `not ok` is likewise not a detection.
if [[ "$(cn_verdict /dev/null 1)" == missed ]]; then
    fx_ok
else fx_bad "classifier should not accept a bare non-zero rc"; fi

printf 'D2 group 5: the summary block is still the last thing each suite prints\n'
# AGENTS section 12: a cell placed AFTER the summary block cannot fail the
# suite, because its fx_bad increments a counter nothing reads. This pins that
# no real fixture has grown a statement after its epilogue.
#
# TOLERANCE, deliberately: 44 of 46 fixtures end in a literal `fx_summary`, and
# two (ci_lint.sh, summary.sh) end in `fi` because their epilogue is a
# conditional choosing between a skip-aware summary line and fx_summary.
# Requiring one literal shape would fail on a legitimate refactor, which is how
# a pin gets quietly weakened.
#
# It is an ORDERING check, not a text-presence check. Senior review round 1
# rejected the first version of this function because its `fi` arm reduced to
# `grep -q fx_summary "$1"` ANYWHERE in the file, which accepted the very
# hazard it names: `fx_summary` followed by `fx_bad` inside an `if ... fi`
# passed. It also falsely refused a harmless trailing comment. So the rule is
# stated on the last two EXECUTED lines:
#
#   * the last executed line is `fx_summary` (optionally with a trailing
#     comment); or
#   * the last executed line is `fi` AND the line immediately before it is
#     `fx_summary` -- i.e. the `fi` is only the conditional's terminator.
#
# Blank lines and whole-line comments are ignored, so a trailing comment is
# tolerated; an inline comment after fx_summary is tolerated; but a real
# statement between `fx_summary` and `fi` is rejected.
#
# KNOWN, DELIBERATE LIMIT: the rule is textual, so it also REJECTS twelve
# legitimate Bash epilogue shapes it does not model -- `case ... esac`,
# `for`/`while`/`until ... done`, `( ... )`, `{ ... }`, a function definition,
# `if true; then :; fi` on one line, and heredoc-terminated blocks. No shipped
# fixture uses any of them, and the error direction is a FALSE RED, which cannot
# hide a defect. The trade is deliberate: modelling them would mean executing
# each fixture, which is the whole battery. Widen this rule only together with a
# control for the new shape, never by deleting the `fi` arm.
CN_SUMMARY_RE='^[[:space:]]*fx_summary[[:space:]]*(#.*)?$'
CN_FI_RE='^[[:space:]]*fi[[:space:]]*(#.*)?$'
cn_tail_ok() { # $1=fixture path -> 0 if the epilogue is the last executed thing
    local body last prev
    body="$(grep -vE '^[[:space:]]*$|^[[:space:]]*#' "$1")"
    last="$(printf '%s\n' "$body" | tail -1)"
    if [[ "$last" =~ $CN_SUMMARY_RE ]]; then
        return 0
    fi
    if [[ ! "$last" =~ $CN_FI_RE ]]; then
        return 1
    fi
    prev="$(printf '%s\n' "$body" | tail -2 | head -1)"
    [[ "$prev" =~ $CN_SUMMARY_RE ]]
}
CN_APPENDED=0
CN_BADTAIL=0
for f in "$ROOT"/tests/fixtures/*.sh; do
    [[ "$(basename "$f")" == "lib.sh" ]] && continue
    CN_APPENDED=$((CN_APPENDED + 1))
    if ! cn_tail_ok "$f"; then
        CN_BADTAIL=$((CN_BADTAIL + 1))
        printf '  appended after the epilogue: %s (last line: %s)\n' \
            "$(basename "$f")" "$(grep -v '^[[:space:]]*$' "$f" | tail -1)" >&2
    fi
done
if [[ "$CN_APPENDED" -ge 40 ]]; then
    fx_ok
else fx_bad "only $CN_APPENDED fixtures were checked; expected the whole suite"; fi
if [[ "$CN_BADTAIL" -eq 0 ]]; then
    fx_ok
else fx_bad "$CN_BADTAIL fixture(s) have code after the summary block"; fi

# Positive AND negative controls for the tail rule, one cell per SHAPE. Without
# these the check above is decorative: Senior review round 1 found the single
# control it had did not exercise the conditional-append shape at all, which is
# the shape the hazard actually takes in ci_lint.sh and summary.sh.
#
#   shape                              want   why
#   plain epilogue                     accept  the common shape
#   plain epilogue + trailing comment  accept  a comment is not a statement
#   conditional epilogue               accept  the legitimate `fi` shape
#   plain append after epilogue        REJECT  the AGENTS section 12 hazard
#   append after epilogue inside `if`  REJECT  the same hazard, conditional form
#   epilogue only named in a comment    REJECT  presence is not ordering
CN_TAILSHAPES=0
cn_tail_shape() { # $1=label $2=want(0 accept/1 reject) ; body on stdin
    local label="$1" want="$2" p
    p="$FX_TMP/tail-$CN_TAILSHAPES.sh"
    cat >"$p"
    CN_TAILSHAPES=$((CN_TAILSHAPES + 1))
    if cn_tail_ok "$p"; then got=0; else got=1; fi
    if [[ "$got" -eq "$want" ]]; then
        fx_ok
    else
        fx_bad "tail rule: '$label' should be $([[ $want -eq 0 ]] && printf accepted || printf rejected) but was $([[ $got -eq 0 ]] && printf accepted || printf rejected)"
    fi
}
cn_tail_shape 'plain epilogue' 0 <<'EOF'
#!/usr/bin/env bash
fx_init
fx_ok
fx_summary
EOF
cn_tail_shape 'epilogue + trailing comment' 0 <<'EOF'
#!/usr/bin/env bash
fx_init
fx_ok
fx_summary
# a note after the verdict
EOF
cn_tail_shape 'conditional epilogue' 0 <<'EOF'
#!/usr/bin/env bash
fx_init
if (( FX_SKIPPED > 0 )); then
    printf 'summary: skipped
'
    (( FX_FAIL == 0 ))
else
    fx_summary
fi
EOF
cn_tail_shape 'plain append after epilogue' 1 <<'EOF'
#!/usr/bin/env bash
fx_init
fx_ok
fx_summary
fx_bad "appended after the summary block"
EOF
cn_tail_shape 'append after epilogue inside if' 1 <<'EOF'
#!/usr/bin/env bash
fx_init
if (( FX_SKIPPED > 0 )); then
    fx_summary
    fx_bad "appended inside the conditional epilogue"
fi
EOF
cn_tail_shape 'epilogue only named in a comment' 1 <<'EOF'
#!/usr/bin/env bash
fx_init
if (( FX_SKIPPED > 0 )); then
    printf 'summary: skipped
'
    (( FX_FAIL == 0 ))
# fx_summary
fi
EOF
fx_summary
