#!/bin/bash
# Focused static checks that the native package lists provide commands the
# modules require but cannot install themselves. It currently guards the fonts
# dependency: modules/install_fonts.sh runs `fc-cache` (provided by the
# `fontconfig` package) and deliberately installs no packages, so every
# supported family list must install `fontconfig` before the fonts step runs.
#
# Run: bash tests/test_package_lists.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

# assert_list_has <family> <package>: exactly one uncommented entry in the list.
assert_list_has(){
    local family="$1" pkg="$2" file="$REPO_DIR/config/packages/$1.txt" count
    if [ ! -f "$file" ]; then
        fail "$family: missing package list $file"
        return
    fi
    count=$(grep -cE "^${pkg}\$" "$file" || true)
    case "$count" in
        1) pass "$family: lists $pkg exactly once" ;;
        0) fail "$family: does not list $pkg" ;;
        *) fail "$family: lists $pkg $count times (duplicate entry)" ;;
    esac
}

# The fonts module must keep using fc-cache; if that changes, this guard no
# longer applies and should be revisited rather than silently passing.
if grep -qE '[^[:alnum:]_]fc-cache([^[:alnum:]_]|$)' "$REPO_DIR/modules/install_fonts.sh"; then
    pass "fonts module uses fc-cache"
else
    fail "fonts module no longer uses fc-cache; revisit this package-list guard"
fi

for family in arch fedora debian; do
    assert_list_has "$family" fontconfig
done

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All package-list checks passed."
