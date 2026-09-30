#!/usr/bin/env bats
# tests/tap_renumber.bats - self-test for the TAP renumbering in tests/run (P10.1).
# Pins the `not ok` two-word status token handling: a failing bats test must
# renumber cleanly, not emit a mangled line or desync the numbering.

load lib_tap

@test "renumbers a clean bats stream" {
    input="1..3
ok 1 first
ok 2 second
ok 3 third"
    got="$(printf '%s\n' "$input" | tap_renumber)"
    [ "$got" = "ok 1 first
ok 2 second
ok 3 third" ]
}

@test "renumbers a failing bats stream without mangling" {
    input="1..3
ok 1 first
not ok 2 second
# diagnostic line
ok 3 third"
    got="$(printf '%s\n' "$input" | tap_renumber)"
    [ "$got" = "ok 1 first
not ok 2 second
# diagnostic line
ok 3 third" ]
}

@test "strips bats' own plan line" {
    input="1..2
ok 1 a
not ok 2 b"
    got="$(printf '%s\n' "$input" | tap_renumber)"
    [ "$got" = "ok 1 a
not ok 2 b" ]
}

@test "preserves diagnostic comment lines" {
    local in exp out
    in="$(mktemp)" exp="$(mktemp)" out="$(mktemp)"
    cat >"$in" <<'EOF'
1..2
not ok 1 failing
# (in test file x.bats, line 2)
#   `false' failed
ok 2 passing
EOF
    cat >"$exp" <<'EOF'
not ok 1 failing
# (in test file x.bats, line 2)
#   `false' failed
ok 2 passing
EOF
    tap_renumber <"$in" >"$out"
    cmp -s "$out" "$exp"
    local rc=$?
    rm -f -- "$in" "$exp" "$out"
    return "$rc"
}
