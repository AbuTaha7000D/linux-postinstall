#!/bin/bash
# Exercise the package module's real Arch dry-run plan and guard the fallback
# command against reintroducing an unattended full system upgrade.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$TEMP_DIR"' EXIT

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

cat > "$TEMP_DIR/os-release" <<'EOF'
ID=arch
NAME="Arch Linux"
EOF

cat > "$TEMP_DIR/probe-missing" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TEMP_DIR/probe-missing"

if env SETUP_DRY_RUN=1 \
    OS_RELEASE_FILE="$TEMP_DIR/os-release" \
    SETUP_PKG_PROBE="$TEMP_DIR/probe-missing" \
    bash "$REPO_DIR/modules/install_apps.sh" > "$TEMP_DIR/output" 2>&1; then
    pass "Arch package module dry-run succeeds with missing packages"
else
    fail "Arch package module dry-run failed"
fi

if grep -qF 'would run: sudo pacman -S --needed --noconfirm' "$TEMP_DIR/output"; then
    pass "dry-run prints the non-upgrading native package command"
else
    fail "dry-run did not print pacman -S --needed"
fi

if grep -qF 'pacman -Syu' "$REPO_DIR/modules/install_apps.sh"; then
    fail "package module contains a full system upgrade command"
else
    pass "batch and retry paths contain no pacman -Syu command"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All Arch package argument checks passed."
