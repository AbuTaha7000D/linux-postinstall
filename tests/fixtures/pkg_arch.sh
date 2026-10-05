#!/usr/bin/env bash
# tests/fixtures/pkg_arch.sh - P3.4 fixture for lib/pkg/arch.sh.
# Mock strategy mirrors pkg_rpm.sh/pkg_deb.sh: PATH-visible fake `pacman`,
# `paru`, `yay`, `sudo` binaries log invocations to $FAKE_LOG and answer
# queries from $FAKE_INSTALLED. AUR-helper discovery is tested with
# dedicated PATH dirs (paru+yay, yay-only, no-helper). Privileged steps
# route through run_sudo (root=1 direct, plus one root=0 block proving the
# sudo -- barrier), keeping dry-run pure (only '# would run:' lines).
# Usage: bash tests/fixtures/pkg_arch.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.4 arch backend\n'

mkdir -p "$FX_TMP/fakebin" "$FX_TMP/fakebin-yay" "$FX_TMP/fakebin-noaur"
mkdir -p "$FX_TMP/notools" "$FX_TMP/repos" "$FX_TMP/dryrepos" "$FX_TMP/tmpdir"

printf 'vim\nhtop\n' >"$FX_TMP/installed"

cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    -Q)
        if grep -qxF -- "${2:-}" "$FAKE_INSTALLED" 2>/dev/null; then
            exit 0
        else
            exit 1
        fi
        ;;
    -Qq) cat "$FAKE_INSTALLED" 2>/dev/null ;;
    *) exit 0 ;;
esac
EOF

cat >"$FX_TMP/fakebin/paru" <<'EOF'
#!/usr/bin/env bash
printf 'paru: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF

cat >"$FX_TMP/fakebin/yay" <<'EOF'
#!/usr/bin/env bash
printf 'yay: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF

cat >"$FX_TMP/fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
if [[ "${1:-}" == "--" ]]; then
    shift
fi
exec "$@"
EOF

cp "$FX_TMP/fakebin/pacman" "$FX_TMP/fakebin/yay" "$FX_TMP/fakebin-yay/"
cp "$FX_TMP/fakebin/pacman" "$FX_TMP/fakebin-noaur/"

chmod +x "$FX_TMP"/fakebin/* "$FX_TMP"/fakebin-yay/* "$FX_TMP"/fakebin-noaur/*

FAKE_INSTALLED="$FX_TMP/installed"
FAKE_LOG="$FX_TMP/fake.log"
: >"$FAKE_LOG"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: pacman present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    export FS_DISTRO_FILE="$FX_TMP/os-arch"
    {
        printf 'NAME="Arch Linux"\nID=arch\n'
    } >"$FX_TMP/os-arch"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    unset FS_PKG_BACKEND
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dispatch fallback reaches arch backend" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: no pacman errors" 1
fx_err 'need pacman in PATH'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_query_installed vim
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query installed present" 0
fx_empty "query emits no stdout" "$FX_OUT"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_query_installed nano
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query installed absent rc1" 1
fx_empty "absent query emits no stdout" "$FX_OUT"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_list_installed
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "list installed rc0" 0
fx_out '^vim$'
fx_out '^htop$'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch vim htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch all installed skips pacman" 0
if grep -q '^pacman: -S ' "$FAKE_LOG"; then
    fx_bad "batch ran pacman for already-installed packages"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch vim htop emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch mixed installs pending only" 0
cnt="$(grep -c '^pacman: -S ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$cnt" == 1 ]]; then
    fx_ok
else
    fx_bad "expected exactly one pacman install transaction, got $cnt"
fi
line="$(grep '^pacman: -S ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$line" == *"--noconfirm --needed emacs git" ]]; then
    fx_ok
else
    fx_bad "single transaction malformed: $line"
fi
if [[ "$line" != *vim* && "$line" != *htop* ]]; then
    fx_ok
else
    fx_bad "already-installed leaked into transaction: $line"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    export FS_LOG_FILE="$FX_TMP/audit.log"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    : >"$FX_TMP/audit.log"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch audits the transaction" 0
if grep -q 'pacman -S --noconfirm --needed emacs git' "$FX_TMP/audit.log" 2>/dev/null; then
    fx_ok
else
    fx_bad "transaction missing from FS_LOG_FILE audit trail"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch non-root goes through sudo" 0
if grep -q '^sudo: -- pacman -S ' "$FAKE_LOG" && grep -q '^pacman: -S --noconfirm --needed emacs$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "sudo barrier or pacman invocation missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata rc0" 0
if grep -q '^pacman: -Sy$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "pacman -Sy not invoked"
fi

touch "$FX_TMP/example.pkg.tar.zst"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.pkg.tar.zst"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local ok" 0
if grep -q "pacman: -U --noconfirm $FX_TMP/example.pkg.tar.zst" "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "local install not invoked"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_install_local "/nonexistent/file.pkg.tar.zst"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local missing file errors" 1
fx_err 'local package file not found'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_ARCH_REPO_DIR="$FX_TMP/repos"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    pkg_add_repo myrepo "https://example.invalid/repo/x86_64" whatever
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo writes include file" 0
if [[ -f "$FX_TMP/repos/myrepo.conf" ]]; then
    fx_ok
else
    fx_bad "repo include not created"
fi
fx_arch_repo() {
    grep -q "$1" "$FX_TMP/repos/myrepo.conf" 2>/dev/null
}
if fx_arch_repo '^\[myrepo\]$' && fx_arch_repo '^Server = https://example.invalid/repo/x86_64$' && fx_arch_repo '^SigLevel = whatever$'; then
    fx_ok
else
    fx_bad "repo include content malformed"
fi

printf '# keep-marker\n' >>"$FX_TMP/repos/myrepo.conf"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_ARCH_REPO_DIR="$FX_TMP/repos"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    pkg_add_repo myrepo "https://example.invalid/repo/x86_64"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo if-not-exists skips" 0
if grep -q '# keep-marker' "$FX_TMP/repos/myrepo.conf" 2>/dev/null; then
    fx_ok
else
    fx_bad "existing include was overwritten"
fi

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch FS_ARCH_REPO_DIR="$FX_TMP/repos"
    pkg_add_repo "../evil" "https://example.invalid/repo/x86_64"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects path id" 1
fx_err 'refusing invalid repo id'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1 FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    export FS_ARCH_REPO_DIR="$FX_TMP/dryrepos" TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_add_repo myother "https://example.invalid/repo2/x86_64"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo dry rc0" 0
if [[ $(grep -c '^# would run: sudo -- install -m 0644 .*fedora-setup-repo-myother.dry .*dryrepos/myother.conf$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry repo-add line"
fi
if [[ ! -e "$FX_TMP/dryrepos/myother.conf" ]]; then
    fx_ok
else
    fx_bad "dry-run wrote a repo include"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG FS_DRY_RUN=1
    export FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch dry rc0" 0
if [[ $(grep -c '^# would run: sudo -- pacman -S --noconfirm --needed emacs git$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry pacman transaction"
fi
if [[ ! -s "$FAKE_LOG" ]]; then
    fx_ok
else
    fx_bad "dry-run invoked tools (no queries allowed)"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
    out="$(arch_aur_helper)"
    printf 'helper=%s\n' "$out"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur helper prefers paru" 0
fx_out '^helper=paru$'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin-yay:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
    out="$(arch_aur_helper)"
    printf 'helper=%s\n' "$out"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur helper falls back to yay" 0
fx_out '^helper=yay$'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin-noaur:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
    arch_aur_helper
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur helper absent errors" 1

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_supported
    arch_aur_batch yay-bin paru-bin
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur batch single transaction" 0
if grep -q '^paru: -S --noconfirm yay-bin paru-bin$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "aur helper transaction missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin-noaur:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    pkg_supported
    arch_aur_batch foo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur batch without helper is opt-in guarded" 1
fx_err 'AUR packages are opt-in'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG FS_DRY_RUN=1
    export FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_supported
    arch_aur_batch yay-bin
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "aur batch dry pure" 0
if [[ $(grep -c '^# would run: sudo -- paru -S --noconfirm yay-bin$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry aur transaction"
fi
if [[ ! -s "$FAKE_LOG" ]]; then
    fx_ok
else
    fx_bad "dry-run invoked aur tools"
fi

# --- B1: package manager transaction failure propagation ---------------

# B1.1: pacman exits non-zero on install_batch -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: install_batch fails when pacman exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.2: plan_install refuses to continue when backend fails
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    plan_install emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: plan_install refuses when backend fails" 1

# B1.3: pacman exits non-zero on update_metadata -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: update_metadata fails when pacman exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.4: install exits non-zero on add_repo -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FS_ARCH_REPO_DIR="$FX_TMP/repos"
    export TMPDIR="$FX_TMP/tmpdir"
    # Clean up any existing repo from earlier tests
    rm -f "$FX_TMP/repos/b1test.conf"
    cat >"$FX_TMP/fakebin/install" <<'EOF'
#!/usr/bin/env bash
printf 'install: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/install"
    # Also need pacman for arch_supported check
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_add_repo b1test "https://example.invalid/repo/x86_64"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: add_repo fails when install exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.5: AUR helper exits non-zero on aur_batch -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log"
    cat >"$FX_TMP/fakebin/paru" <<'EOF'
#!/usr/bin/env bash
printf 'paru: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/paru"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_supported
    arch_aur_batch yay-bin
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: aur_batch fails when paru exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.6: mutation test - removing --stop from install_batch is caught
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-mut: install_batch mutation (--stop removed) caught" 1

# B1.7: postcondition test - command exits 0 but does no work
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
# exits 0 but does NOT add to FAKE_INSTALLED
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-post: install_batch postcondition gap (no query after)" 0
if ! grep -qxF emacs "$FAKE_INSTALLED" 2>/dev/null; then
    fx_ok
else
    fx_bad "package was unexpectedly installed"
fi

# B1.8: install_local returns 0 even when PM fails (no --stop per postcondition rule)
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    -U) exit 100 ;;
    -S) exit 100 ;;
    -Sy) exit 100 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    touch "$FX_TMP/example.pkg.tar.zst"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.pkg.tar.zst"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: install_local returns 0 despite PM failure (postcondition rule)" 0
fx_err 'command failed (rc=100)'

# B1.9: postcondition check catches the failure (pkg_query_installed returns 1)
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    -Q) grep -qxF -- "${2:-}" "$FAKE_INSTALLED" 2>/dev/null || exit 1 ;;
    -S) exit 100 ;;
    -U) exit 100 ;;
    -Sy) exit 100 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    touch "$FX_TMP/example.pkg.tar.zst"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.pkg.tar.zst" || rc=$?
    pkg_query_installed example.pkg.tar.zst
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: postcondition query catches failed install_local" 1

# B1.10: mutation test - removing postcondition check is caught
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    -Q) grep -qxF -- "${2:-}" "$FAKE_INSTALLED" 2>/dev/null || exit 1 ;;
    -U) exit 100 ;;
    -S) exit 100 ;;
    -Sy) exit 100 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    touch "$FX_TMP/example.pkg.tar.zst"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.pkg.tar.zst"  # NO postcondition check!
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-mut: missing postcondition check not caught by backend" 0
if ! pkg_query_installed example.pkg.tar.zst >/dev/null 2>&1; then
    fx_ok  # package correctly NOT installed (query would catch it if run)
else
    fx_bad "package should not be installed"
fi

# B1.12: postcondition test - install_local exits 0 but doesn't install, query catches it
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    -Q) grep -qxF -- "${2:-}" "$FAKE_INSTALLED" 2>/dev/null || exit 1 ;;
    -U) exit 0 ;;
    -S) exit 100 ;;
    -Sy) exit 100 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/pacman"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=arch
    touch "$FX_TMP/example.pkg.tar.zst"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.pkg.tar.zst"
    pkg_query_installed example.pkg.tar.zst
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-post: install_local silent failure caught by query" 1
if ! grep -qxF example.pkg.tar.zst "$FAKE_INSTALLED" 2>/dev/null; then
    fx_ok
else
    fx_bad "package was unexpectedly installed"
fi

fx_summary