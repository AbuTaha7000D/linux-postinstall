#!/bin/bash
# Focused sandboxed tests for the sudo prerequisite handling in lib/common.sh
# (ensure_sudo / run_root). The real sudo is never invoked and no host state
# changes: the helper is sourced with a private PATH (stubs only) and a sandbox
# HOME, so the tests behave the same whether or not the host has sudo.
#
# Run: bash tests/test_sudo_prereq.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

SANDBOX=""
cleanup(){ [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

SANDBOX=$(mktemp -d)
NOSUDO_BIN="$SANDBOX/nosudo"
SUDOFAIL_BIN="$SANDBOX/sudofail"
SUDOOK_BIN="$SANDBOX/sudook"
mkdir -p "$NOSUDO_BIN" "$SUDOFAIL_BIN" "$SUDOOK_BIN"

# sudo whose credential probes always fail (authentication failure).
cat > "$SUDOFAIL_BIN/sudo" <<'EOF'
#!/bin/bash
exit 1
EOF

# sudo whose non-interactive probe succeeds.
cat > "$SUDOOK_BIN/sudo" <<'EOF'
#!/bin/bash
case "${1:-}" in
    -n|-v) exit 0 ;;
esac
exit 0
EOF

chmod +x "$SUDOFAIL_BIN/sudo" "$SUDOOK_BIN/sudo"
ERR="$SANDBOX/err"
BASH_BIN="$(command -v bash)"

# call_helper <path> <dry-run 0|1> <code after sourcing>: prints RC=<n> and
# FLAG=<n> on stdout and leaves the helper's stderr in "$ERR".
call_helper(){
    env -u SUDO_AUTH_FAILED SETUP_DRY_RUN="$2" PATH="$1" HOME="$SANDBOX" \
        "$BASH_BIN" -c 'source "$1"; '"$3"'; rc=$?; printf "RC=%s\n" "$rc"; printf "FLAG=%s\n" "${SUDO_AUTH_FAILED:-0}"' \
        _ "$REPO_DIR/lib/common.sh" 2>"$ERR"
}
field(){ printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# --- 1. sudo not installed: clear prerequisite error, nonzero -----------------
out=$(call_helper "$NOSUDO_BIN" 0 'ensure_sudo')
if [ "$(field "$out" RC)" = "1" ]; then pass "missing sudo: ensure_sudo exits nonzero"; else fail "missing sudo: expected rc 1 (got $(field "$out" RC))"; fi
if [ "$(field "$out" FLAG)" = "1" ]; then pass "missing sudo: SUDO_AUTH_FAILED is set"; else fail "missing sudo: expected SUDO_AUTH_FAILED=1"; fi
if grep -qF "sudo is required" "$ERR"; then pass "missing sudo: reports the prerequisite"; else fail "missing sudo: expected a 'sudo is required' message (got: $(cat "$ERR"))"; fi
if grep -qiF "authentication failed" "$ERR"; then fail "missing sudo: must not report an authentication failure"; else pass "missing sudo: does not misreport authentication failure"; fi

# --- 2. sudo present but authentication fails: existing message kept ---------
out=$(call_helper "$SUDOFAIL_BIN" 0 'ensure_sudo')
if [ "$(field "$out" RC)" = "1" ]; then pass "auth failure: ensure_sudo exits nonzero"; else fail "auth failure: expected rc 1 (got $(field "$out" RC))"; fi
if grep -qF "sudo authentication failed" "$ERR"; then pass "auth failure: reports authentication failure"; else fail "auth failure: expected 'sudo authentication failed' (got: $(cat "$ERR"))"; fi
if grep -qF "sudo is required" "$ERR"; then fail "auth failure: must not claim sudo is not installed"; else pass "auth failure: does not claim sudo is missing"; fi

# --- 3. sudo usable: no error, zero ------------------------------------------
out=$(call_helper "$SUDOOK_BIN" 0 'ensure_sudo')
if [ "$(field "$out" RC)" = "0" ]; then pass "usable sudo: ensure_sudo exits 0"; else fail "usable sudo: expected rc 0 (got $(field "$out" RC))"; fi
if [ "$(field "$out" FLAG)" = "0" ]; then pass "usable sudo: SUDO_AUTH_FAILED unset"; else fail "usable sudo: expected SUDO_AUTH_FAILED=0"; fi
if [ -s "$ERR" ]; then fail "usable sudo: unexpected stderr: $(cat "$ERR")"; else pass "usable sudo: no stderr"; fi

# --- 4. run_root with sudo missing: nonzero and command not executed ---------
out=$(call_helper "$NOSUDO_BIN" 0 'run_root echo hi')
if [ "$(field "$out" RC)" = "1" ]; then pass "run_root missing sudo: exits nonzero"; else fail "run_root missing sudo: expected rc 1 (got $(field "$out" RC))"; fi
if printf '%s\n' "$out" | grep -qx 'hi'; then fail "run_root missing sudo: ran the privileged command"; else pass "run_root missing sudo: command not executed"; fi

# --- 5. dry-run never needs sudo ---------------------------------------------
out=$(call_helper "$NOSUDO_BIN" 1 'run_root echo hi')
if [ "$(field "$out" RC)" = "0" ]; then pass "dry-run missing sudo: run_root exits 0"; else fail "dry-run missing sudo: expected rc 0 (got $(field "$out" RC))"; fi
if printf '%s\n' "$out" | grep -qF "would run: sudo echo hi"; then pass "dry-run missing sudo: prints the plan"; else fail "dry-run missing sudo: expected the would-run plan"; fi
if [ -s "$ERR" ]; then fail "dry-run missing sudo: unexpected stderr: $(cat "$ERR")"; else pass "dry-run missing sudo: no error output"; fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All sudo prerequisite checks passed."
