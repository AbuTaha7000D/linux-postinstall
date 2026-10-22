#!/bin/bash
# Focused checks that native package lists provide commands used by modules and
# configured shortcuts. The fonts module requires `fc-cache` (`fontconfig`);
# the bundled GNOME shortcuts require `kitty` and `amixer` (`alsa-utils`).
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
    assert_list_has "$family" kitty
    assert_list_has "$family" alsa-utils
done

if grep -q $'^Terminal\t<Alt>T\tkitty$' "$REPO_DIR/config/shortcuts.txt"; then
    pass "Terminal shortcut uses installed kitty command"
else
    fail "Terminal shortcut does not use the installed kitty command"
fi

if grep -q $'^Toggle Mic\t<Alt>1\tamixer set Capture toggle$' "$REPO_DIR/config/shortcuts.txt"; then
    pass "microphone shortcut uses amixer from alsa-utils"
else
    fail "microphone shortcut command changed; revisit its package dependency"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All package-list checks passed."
