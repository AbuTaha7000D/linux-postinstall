#!/usr/bin/env bash
# tests/lib_tap.sh - TAP helpers shared by tests/run and the self-test (P10.1).

# tap_renumber <input> - renumber a bats TAP stream into a continuous
# sequence, stripping bats' own plan line. `not ok` is a TWO-word status token
# ($1 is "not", $2 is "ok"); the strip regex must match the full token or a
# failing bats test emits a mangled line and desyncs every later test number.
tap_renumber() {
    awk '
        /^1\.\.[0-9]+$/ { next }
        /^(not ok|ok) [0-9]+ / {
            status = $1
            if (status == "not") status = "not ok"
            sub(/^(not ok|ok) [0-9]+ /, "")
            printf "%s %d %s\n", status, ++n, $0
            next
        }
        { print }
    '
}
