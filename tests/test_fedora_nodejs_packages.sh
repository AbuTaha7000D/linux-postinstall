#!/bin/bash
# Fedora 43 and 44 split the unversioned Node/npm commands into different
# package names. Guard both the release selector and the packages-stage plan.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
FAILURES=0
trap 'rm -rf "$TEMP_DIR"' EXIT

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

cat > "$TEMP_DIR/pkg-missing" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TEMP_DIR/pkg-missing"

# Keep normal host utilities visible while making node/npm absent so the dev
# module has to exercise its package mapping. Dry-run prevents package changes.
mkdir "$TEMP_DIR/bin"
while IFS= read -r command_path; do
    case "${command_path##*/}" in node|npm|npx|node-*) continue ;; esac
    ln -s "$command_path" "$TEMP_DIR/bin/${command_path##*/}" 2>/dev/null || true
done < <(find /usr/bin -maxdepth 1 \( -type f -o -type l \) -print)

for version in 43 44 45; do
    cat > "$TEMP_DIR/os-release" <<EOF
ID=fedora
VERSION_ID="$version"
EOF

    if [ "$version" -ge 44 ]; then
        expected=nodejs24-npm-bin
    else
        expected=nodejs-npm
    fi

    selected=$(OS_RELEASE_FILE="$TEMP_DIR/os-release" bash -c \
        'source "$1/lib/common.sh"; fedora_node_npm_package' _ "$REPO_DIR")
    if [ "$selected" = "$expected" ]; then
        pass "Fedora $version selects $expected"
    else
        fail "Fedora $version selected '$selected', expected '$expected'"
    fi

    if env SETUP_DRY_RUN=1 \
        OS_RELEASE_FILE="$TEMP_DIR/os-release" \
        SETUP_PKG_PROBE="$TEMP_DIR/pkg-missing" \
        bash "$REPO_DIR/modules/install_apps.sh" > "$TEMP_DIR/output" 2>&1; then
        if grep -qF "$expected" "$TEMP_DIR/output"; then
            pass "Fedora $version packages dry-run includes $expected"
        else
            fail "Fedora $version packages dry-run omitted $expected"
        fi
    else
        fail "Fedora $version packages dry-run failed"
    fi

    if env SETUP_DRY_RUN=1 \
        OS_RELEASE_FILE="$TEMP_DIR/os-release" \
        PATH="$TEMP_DIR/bin" \
        /bin/bash "$REPO_DIR/modules/dev.sh" > "$TEMP_DIR/dev-output" 2>&1; then
        if grep -qE "missing development package\(s\): .*${expected}([[:space:]]|$)" "$TEMP_DIR/dev-output"; then
            pass "Fedora $version dev dry-run plans $expected for node and npm"
        else
            fail "Fedora $version dev dry-run did not plan $expected"
        fi
    else
        fail "Fedora $version dev dry-run failed"
    fi
done

if ! grep -qF 'node_npm_package=$(fedora_node_npm_package)' "$REPO_DIR/modules/dev.sh" \
    || ! grep -qF 'add_missing node "$node_npm_package"' "$REPO_DIR/modules/dev.sh" \
    || ! grep -qF 'add_missing npm "$node_npm_package"' "$REPO_DIR/modules/dev.sh"; then
    fail "dev module does not use the selected Fedora package for both commands"
else
    pass "dev module uses the selected Fedora package for node and npm"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES Fedora Node/npm check(s) failed." >&2
    exit 1
fi
echo "All Fedora Node/npm package checks passed."
