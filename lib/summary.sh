#!/usr/bin/env bash
# lib/summary.sh - end-of-run summary reporter for `install` (P9.5).
# Depends on: lib/io.sh (io_summary). Bash >= 4.3 safe (no namerefs; every
# array expansion guarded; counts taken with ${#arr[@]}).
#
# WHY THIS EXISTS. `install` had a summary that was assembled inline by
# lib/runner.sh from three local counters, printed by io_summary, and turned
# into an exit code by a separate `if (( failed > 0 ))`. That is three places
# describing one run, and nothing tied them together: the printed numbers and
# the process exit code were independent expressions of the same fact, which is
# exactly the P9.2 B4 shape (a fully green suite over an auditor that compared
# a weaker thing than the writer wrote). A module that failed could be
# reported "0 failed" and still exit 0, or reported "1 failed" by a counter the
# exit code never read. The reporter now owns all three: the runner records
# OUTCOMES and asks the reporter for the line and the code.
#
# THE COUNTS ARE DERIVED, NOT COUNTED. The three arrays below are the ONLY
# state. Every number printed comes from ${#SUMMARY_*_IDS[@]} at render time,
# and summary_rc reads the same array the "K failed" in the line is derived
# from -- so the line and the exit code cannot disagree by construction, and a
# caller cannot forget to increment a counter. Do NOT add a parallel counter:
# that is the defect this file removes. (lib/status.sh made the same move for
# check/verify, where STATUS_ROWS is an array rather than a counter.)
#
# WHAT IS REPORTED. One line carries every count the ROADMAP asks for --
# "N modules ok . M skipped . K failed" plus where the run's artifacts are --
# followed by one row per failed module and, when something failed, the
# recovery action. `skipped` means the registry already had the module marked
# done (state_module_check), so it counts as neither ok nor failed: the work is
# finished, just not by this run.
#
# FAILED STEPS MUST BE ACTIONABLE, which needs three things a bare count does
# not give: WHICH module, WHY (the hook's own exit status, as recorded by the
# caller), and WHAT TO DO (re-run the same command -- completed modules are
# skipped by the registry, so exactly the failed ones are retried). The action
# line is only rendered when there is a failure, because advice with nothing
# to advise about is noise.
#
# THE ARTIFACTS CLAUSE NEVER FAKES A FILE. It prints "artifacts in <path>" only
# when io.sh's `_io_log_usable` accepts the path -- the SAME predicate
# lib/bootstrap.sh refuses an install without, and the same `-f` AND `-w` rule
# lib/run.sh:56 has always used. It is deliberately one predicate and not two
# tests of one property: the first revision of this file checked existence here
# and existence in the bootstrap, and the two disagreed, so a log this run
# could not append to was still named as this run's artifacts while stderr said
# the log was unusable.
#
# With no usable log the clause says which of the two honest reasons applies --
# a dry run writes nothing at all, or a real run opened no log, which is a
# wiring bug worth seeing. Note the ORDER: a dry run that ALSO has an exported
# FS_LOG_FILE (a documented audit seam, lib/cli.sh) DOES print "artifacts in",
# because that file exists, is writable, and genuinely holds the lines this run
# emitted. A dry run writes nothing to the SYSTEM; honouring a log path the user
# chose is not fabrication, and claiming otherwise would be the lie.
#
# THE ABORT PATHS DELIBERATELY DO NOT REACH THIS FILE. All five fail with rc1
# and NO summary:
#   1. profile_resolve error            (lib/runner.sh, resolve stage)
#   2. the P8.3 risk-gate refusal       (high/destructive pulled in by a dep)
#   3. a prerepo() failure              (P7.5, fail-fast, pre-batch)
#   4. a package/flatpak batch failure  (P5.7 batches)
#   5. a state_module_mark failure      (the run cannot record its own result)
# The first two were unpinned until round 4, where a mutation that added
# `summary_report` to either left all 3557 asserts green -- a reviewed
# P4.6/P7.5/P8.3 contract that the fixture now pins with fx_out_not on each.
# Three further `return 1` sites are DEFENSIVE and unreachable through the
# fixture, so they are recorded as uncovered rather than pinned with a contrived
# cell: the `if [[ -z ]]` arg check (lib/runner.sh:219, needs 4 args with one
# empty -- the misuse cells pass 3 and hit the `shift 4` branch instead),
# `profile_load` failure (lib/runner.sh:242, needs a malformed profile file),
# and `module_flatpak_alt` failure (lib/runner.sh:260, needs a malformed alt
# pair). The summary reports MODULE outcomes, and a run that never reached the
# module loop has none; printing "0 ok . 0 failed" there would be a true
# statement about an empty set, which is how a reader concludes nothing went
# wrong.

SUMMARY_OK_IDS=()
SUMMARY_SKIP_IDS=()
SUMMARY_FAIL_IDS=()
SUMMARY_FAIL_DETAIL=()

summary_reset() {
    SUMMARY_OK_IDS=()
    SUMMARY_SKIP_IDS=()
    SUMMARY_FAIL_IDS=()
    SUMMARY_FAIL_DETAIL=()
    return 0
}

# summary_module_ok <id> | summary_module_skip <id> | summary_module_fail <id> <detail>
# A recorder, so every one of them returns 0 and none can abort a caller.
summary_module_ok() {
    SUMMARY_OK_IDS+=("${1:-}")
    return 0
}

summary_module_skip() {
    SUMMARY_SKIP_IDS+=("${1:-}")
    return 0
}

summary_module_fail() {
    SUMMARY_FAIL_IDS+=("${1:-}")
    SUMMARY_FAIL_DETAIL+=("${2:-}")
    return 0
}

# The one line: counts and the artifact pointer, in the order the ROADMAP
# specifies. The separator is the middot the task text uses.
summary_line() {
    local log="${FS_LOG_FILE:-}" artifacts=""
    if _io_log_usable "$log"; then
        artifacts="artifacts in $log"
    elif ((${FS_DRY_RUN:-0} == 1)); then
        artifacts="artifacts: none (a dry run writes nothing)"
    else
        artifacts="artifacts: none (no run log was opened)"
    fi
    printf '%s modules ok · %s skipped · %s failed · %s' \
        "${#SUMMARY_OK_IDS[@]}" "${#SUMMARY_SKIP_IDS[@]}" \
        "${#SUMMARY_FAIL_IDS[@]}" "$artifacts"
}

summary_report() {
    local -a rows=()
    local i=0
    local -i n=${#SUMMARY_FAIL_IDS[@]}
    rows+=("$(summary_line)")
    while ((i < n)); do
        rows+=("FAIL ${SUMMARY_FAIL_IDS[i]}: ${SUMMARY_FAIL_DETAIL[i]}")
        i=$((i + 1))
    done
    if ((n > 0)); then
        rows+=("retry: re-run the same command; completed modules are skipped")
    fi
    io_summary "run complete" ${rows[@]+"${rows[@]}"}
    return 0
}

summary_rc() {
    if ((${#SUMMARY_FAIL_IDS[@]} > 0)); then
        return 1
    fi
    return 0
}
