#!/bin/bash
# The terminal module uses `cp -p` for the bundled Starship config, so its
# source mode must not make the installed user config writable by other users.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_DIR/config/starship.toml"
TEMP_DIR="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$TEMP_DIR"' EXIT

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

if [ "$(stat -c '%a' "$SOURCE")" = "644" ]; then
    pass "bundled Starship config mode is 644"
else
    fail "bundled Starship config must have mode 644"
fi

cp -p -- "$SOURCE" "$TEMP_DIR/starship.toml"
if [ "$(stat -c '%a' "$TEMP_DIR/starship.toml")" = "644" ]; then
    pass "cp -p preserves a private user config mode"
else
    fail "cp -p would install an unsafe Starship config mode"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All Starship config mode checks passed."
