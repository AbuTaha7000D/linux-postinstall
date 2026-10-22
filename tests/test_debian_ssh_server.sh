#!/bin/bash
# Guard against installing Debian's OpenSSH server package in the dev module:
# its package maintainer scripts can enable or start the service.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_MODULE="$REPO_DIR/modules/dev.sh"
FAILURES=0

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

debian_case=$(awk '
    /    "debian"\)/ { in_debian=1; next }
    in_debian && /        ;;$/ { exit }
    in_debian { print }
' "$DEV_MODULE")

if grep -qF 'add_missing ssh openssh-client' <<< "$debian_case"; then
    pass "Debian dev installs the OpenSSH client"
else
    fail "Debian dev must retain the OpenSSH client"
fi

if grep -Eq 'openssh-server|add_missing sshd' <<< "$debian_case"; then
    fail "Debian dev must not install or probe for the OpenSSH server"
else
    pass "Debian dev does not install or probe for the OpenSSH server"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All Debian SSH package checks passed."
