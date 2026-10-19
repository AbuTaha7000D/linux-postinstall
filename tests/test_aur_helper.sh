#!/bin/bash
# Focused sandboxed tests for the shared yay bootstrap (lib/common.sh
# ensure_yay) and the Arch AUR call sites in modules/install_apps.sh and
# modules/dev.sh.
#
# Nothing real is installed and no sudo credential is touched: every external
# command the modules reach is a stub on a private PATH, and all state lives in
# a temporary directory. The stub PATH deliberately excludes `yay` and `code`
# so the Arch bootstrap path is exercised regardless of the host.
#
# Run: bash tests/test_aur_helper.sh

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

SANDBOX=""
cleanup(){ [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

# sandbox_init builds a private PATH with stubbed commands plus symlinks to the
# real system tools (excluding yay and code) and an Arch os-release fixture.
sandbox_init(){
    SANDBOX=$(mktemp -d)
    BIN="$SANDBOX/bin"
    STATE="$SANDBOX/state"
    HOME_DIR="$SANDBOX/home"
    mkdir -p "$BIN" "$STATE" "$HOME_DIR"
    : > "$SANDBOX/log"
    export SANDBOX BIN STATE HOME_DIR LOG="$SANDBOX/log"

    cat > "$SANDBOX/os-release" <<'EOF'
ID=arch
NAME="Arch Linux"
EOF

    # yay stub used after a (simulated) build and in the already-installed case.
    cat > "$SANDBOX/yay_stub.sh" <<'YAY'
#!/bin/bash
printf 'yay %s\n' "$*" >> "$LOG"
if [ "${1:-}" = "-S" ]; then
    pkg="${!#}"
    : > "$STATE/installed-$pkg"
fi
exit 0
YAY
    chmod +x "$SANDBOX/yay_stub.sh"

    REAL_RM="$(command -v rm)"

    # sudo: succeed for the lazy credential probes, otherwise run the command.
    cat > "$BIN/sudo" <<'EOF'
#!/bin/bash
case "${1:-}" in
    -n|-v) exit 0 ;;
esac
exec "$@"
EOF

    # mktemp: always create a directory under the sandbox so the test can both
    # observe and (optionally) fail the per-build cleanup.
    cat > "$BIN/mktemp" <<'EOF'
#!/bin/bash
printf 'mktemp %s\n' "$*" >> "$LOG"
d="$STATE/mk-$$-$RANDOM"
mkdir -p "$d"
echo "$d"
EOF

    # rm: log, optionally fail the yay build-directory cleanup, otherwise run
    # the real rm.
    cat > "$BIN/rm" <<EOF
#!/bin/bash
printf 'rm %s\n' "\$*" >> "\$LOG"
if [ "\${RM_CLEANUP_FAIL:-0}" = "1" ]; then
    for a in "\$@"; do
        case "\$a" in
            "\$STATE"/mk-*) echo "rm: cannot remove '\$a'" >&2; exit 1 ;;
        esac
    done
fi
exec $REAL_RM "\$@"
EOF

    # pacman: log everything; -Qi reads simulated installed state.
    cat > "$BIN/pacman" <<'EOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >> "$LOG"
if [ "${1:-}" = "-Qi" ]; then
    if [ -f "$STATE/installed-$2" ]; then
        echo "Name            : $2"
        exit 0
    fi
    echo "error: package '$2' was not found" >&2
    exit 1
fi
exit 0
EOF

    # git: log; a clone creates the destination with a PKGBUILD unless GIT_FAIL=1.
    cat > "$BIN/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >> "$LOG"
if [ "${GIT_FAIL:-0}" = "1" ]; then
    echo "fatal: unable to access 'https://aur.archlinux.org/yay.git/'" >&2
    exit 1
fi
dest="${!#}"
mkdir -p "$dest"
: > "$dest/PKGBUILD"
exit 0
EOF

    # makepkg: log; "build" yay by dropping the stub onto PATH.
    cat > "$BIN/makepkg" <<'EOF'
#!/bin/bash
printf 'makepkg %s\n' "$*" >> "$LOG"
cp "$SANDBOX/yay_stub.sh" "$BIN/yay"
chmod +x "$BIN/yay"
exit 0
EOF

    # Probe override: report every native package and Flatpak as installed so
    # install_apps.sh reaches the vendor step without invoking a package manager.
    cat > "$BIN/probe_installed" <<'EOF'
#!/bin/bash
exit 0
EOF

    chmod +x "$BIN/sudo" "$BIN/mktemp" "$BIN/rm" "$BIN/pacman" "$BIN/git" "$BIN/makepkg" "$BIN/probe_installed"

    local src name
    for src in /usr/bin/* /bin/*; do
        name="${src##*/}"
        case "$name" in
            yay|code) continue ;;
        esac
        [ -e "$BIN/$name" ] && continue
        ln -s "$src" "$BIN/$name" 2>/dev/null || true
    done
}

# run_install_apps runs the real package module against the stubbed environment.
run_install_apps(){
    env -u SETUP_DRY_RUN \
        OS_RELEASE_FILE="$SANDBOX/os-release" \
        SETUP_PKG_PROBE="$BIN/probe_installed" \
        SETUP_FLATPAK_PROBE="$BIN/probe_installed" \
        HOME="$HOME_DIR" \
        PATH="$BIN" \
        bash "$REPO_DIR/modules/install_apps.sh" > "$SANDBOX/out" 2>&1
}

count_log(){ grep -cE "$1" "$LOG" 2>/dev/null || true; }
line_of(){ grep -nE "$1" "$LOG" | head -n1 | cut -d: -f1; }

assert_eq(){
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_contains(){
    if grep -qF -- "$2" "$3"; then pass "$1"; else fail "$1 (missing '$2' in $3)"; fi
}
assert_not_contains(){
    if grep -qF -- "$2" "$3"; then fail "$1 (unexpected '$2' in $3)"; else pass "$1"; fi
}

# --- 1. yay already installed: bootstrap is skipped -------------------------
sandbox_init
cp "$SANDBOX/yay_stub.sh" "$BIN/yay"

rc=0; run_install_apps || rc=$?
assert_eq "already-installed: install_apps exits 0" "0" "$rc"
assert_eq "already-installed: no base-devel install" "0" "$(count_log '^pacman -S --needed --noconfirm base-devel')"
assert_eq "already-installed: no git clone" "0" "$(count_log '^git clone')"
assert_eq "already-installed: no makepkg" "0" "$(count_log '^makepkg')"
assert_eq "already-installed: VS Code installed via yay" "1" "$(count_log '^yay -S --needed --noconfirm visual-studio-code-bin')"
assert_eq "already-installed: Chrome installed via yay" "1" "$(count_log '^yay -S --needed --noconfirm google-chrome')"
assert_contains "already-installed: reports Chrome installed" "INSTALLED: Google Chrome" "$SANDBOX/out"

# --- 2. yay missing: bootstrap runs before the AUR install ------------------
sandbox_init

rc=0; run_install_apps || rc=$?
assert_eq "bootstrap: install_apps exits 0" "0" "$rc"
assert_eq "bootstrap: base-devel installed once" "1" "$(count_log '^pacman -S --needed --noconfirm base-devel')"
assert_eq "bootstrap: git clone once" "1" "$(count_log '^git clone')"
assert_eq "bootstrap: makepkg once" "1" "$(count_log '^makepkg')"
assert_eq "bootstrap: VS Code installed via yay" "1" "$(count_log '^yay -S --needed --noconfirm visual-studio-code-bin')"
assert_eq "bootstrap: Chrome installed via yay" "1" "$(count_log '^yay -S --needed --noconfirm google-chrome')"

pacman_line=$(line_of '^pacman -S --needed --noconfirm base-devel')
git_line=$(line_of '^git clone')
make_line=$(line_of '^makepkg -si')
yay_line=$(line_of '^yay -S')
if [ -n "$pacman_line" ] && [ -n "$git_line" ] && [ -n "$make_line" ] && [ -n "$yay_line" ] \
    && [ "$pacman_line" -lt "$git_line" ] && [ "$git_line" -lt "$make_line" ] && [ "$make_line" -lt "$yay_line" ]; then
    pass "bootstrap: base-devel < clone < makepkg < yay -S"
else
    fail "bootstrap: expected order base-devel < clone < makepkg < yay -S (got $pacman_line/$git_line/$make_line/$yay_line)"
fi
assert_eq "bootstrap: temp build dir removed" "1" "$(count_log '^rm -rf .*mk-')"

# --- 3. bootstrap failure: the AUR package is never installed ---------------
sandbox_init

rc=0; GIT_FAIL=1 run_install_apps || rc=$?
if [ "$rc" -ne 0 ]; then pass "failure: install_apps exits nonzero"; else fail "failure: install_apps must exit nonzero"; fi
assert_eq "failure: no yay -S attempted" "0" "$(count_log '^yay -S')"
assert_contains "failure: VS Code reported failed" "FAILED: VS Code" "$SANDBOX/out"
assert_contains "failure: Chrome reported failed" "FAILED: Google Chrome" "$SANDBOX/out"

# --- 3b. bootstrap returns nonzero after yay appears on PATH ---------------
# Forces the exact short-circuit the modules rely on: ensure_yay fails (here the
# build-directory cleanup fails) even though a yay binary now exists, so the
# failing vendor package must NOT be installed. A regression such as
# `ensure_yay || true` followed by an unconditional `yay -S` would install VS
# Code and fail these checks.
sandbox_init

rc=0; RM_CLEANUP_FAIL=1 run_install_apps || rc=$?
if [ "$rc" -ne 0 ]; then pass "cleanup-failure: install_apps exits nonzero"; else fail "cleanup-failure: install_apps must exit nonzero"; fi
assert_contains "cleanup-failure: VS Code reported failed" "FAILED: VS Code" "$SANDBOX/out"
assert_eq "cleanup-failure: VS Code not installed via yay" "0" "$(count_log '^yay -S --needed --noconfirm visual-studio-code-bin')"
assert_eq "cleanup-failure: only the next entry uses the existing yay" "1" "$(count_log '^yay -S')"
assert_eq "cleanup-failure: build-directory cleanup was attempted" "1" "$(count_log '^rm -rf .*mk-')"

# --- 4. dev.sh reuses the shared bootstrap in dry-run -----------------------
sandbox_init

rc=0; env -u SETUP_DRY_RUN \
    SETUP_DRY_RUN=1 \
    OS_RELEASE_FILE="$SANDBOX/os-release" \
    HOME="$HOME_DIR" \
    PATH="$BIN" \
    bash "$REPO_DIR/modules/dev.sh" > "$SANDBOX/dev_out" 2>&1 || rc=$?
assert_eq "dev dry-run: exits 0" "0" "$rc"
assert_contains "dev dry-run: shared bootstrap plan" "would run: git clone --depth 1 https://aur.archlinux.org/yay.git" "$SANDBOX/dev_out"
assert_contains "dev dry-run: makepkg plan" "would run: makepkg -si --noconfirm" "$SANDBOX/dev_out"
assert_contains "dev dry-run: base-devel plan" "would run: sudo pacman -S --needed --noconfirm base-devel" "$SANDBOX/dev_out"
assert_contains "dev dry-run: VS Code AUR install announced" "bootstrap yay if needed and install VS Code via yay (AUR)" "$SANDBOX/dev_out"
assert_eq "dev dry-run: no yay -S executed" "0" "$(count_log '^yay -S')"

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES check(s) failed." >&2
    exit 1
fi
echo "All AUR helper checks passed."
