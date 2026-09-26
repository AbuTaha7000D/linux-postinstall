#!/usr/bin/env bash
# tests/fixtures/pkg_rpm.sh - P3.2 fixture for lib/pkg/rpm.sh.
# Mock strategy: PATH-visible fake `rpm`/`dnf5`/`dnf`/`sudo` binaries log
# invocations to $FAKE_LOG and answer queries from $FAKE_INSTALLED. Privileged
# steps route through run_sudo (root=1 direct, plus one root=0 block proving
# the sudo -- barrier), keeping dry-run pure (only '# would run:' lines).
# Usage: bash tests/fixtures/pkg_rpm.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.2 rpm backend\n'

mkdir -p "$FX_TMP/fakebin" "$FX_TMP/fakebin-dnf" "$FX_TMP/notools" "$FX_TMP/repos" "$FX_TMP/dryrepos" "$FX_TMP/tmpdir"

printf 'vim\nhtop\n' >"$FX_TMP/installed"

cat >"$FX_TMP/fakebin/rpm" <<'EOF'
#!/usr/bin/env bash
printf 'rpm: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "${1:-}" in
    -q) grep -qxF -- "${2:-}" "$FAKE_INSTALLED" 2>/dev/null ;;
    -qa) cat "$FAKE_INSTALLED" 2>/dev/null ;;
    *) exit 0 ;;
esac
EOF

cat >"$FX_TMP/fakebin/dnf5" <<'EOF'
#!/usr/bin/env bash
printf 'dnf5: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF

cat >"$FX_TMP/fakebin/dnf" <<'EOF'
#!/usr/bin/env bash
printf 'dnf: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
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

chmod +x "$FX_TMP"/fakebin/*
cp "$FX_TMP/fakebin/rpm" "$FX_TMP/fakebin/dnf" "$FX_TMP/fakebin-dnf/"

FAKE_INSTALLED="$FX_TMP/installed"
FAKE_LOG="$FX_TMP/fake.log"
: >"$FAKE_LOG"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: dnf5 present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    export FS_DISTRO_FILE="$FX_TMP/os-fedora"
    {
        printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="41"\n'
    } >"$FX_TMP/os-fedora"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    unset FS_PKG_BACKEND
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dispatch fallback reaches rpm backend" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: no dnf tool errors" 1
fx_err 'need dnf5 or dnf plus rpm'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin-dnf:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: dnf-only accepted" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
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
    export FS_PKG_BACKEND=rpm
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
    export FS_PKG_BACKEND=rpm
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
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_install_batch vim htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch all installed skips dnf" 0
if grep -q '^dnf5: install ' "$FAKE_LOG"; then
    fx_bad "batch ran dnf for already-installed packages"
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
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_install_batch vim htop emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch mixed installs pending only" 0
cnt="$(grep -c '^dnf5: install ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$cnt" == 1 ]]; then
    fx_ok
else
    fx_bad "expected exactly one dnf install transaction, got $cnt"
fi
line="$(grep '^dnf5: install ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$line" == *"emacs git"* ]]; then
    fx_ok
else
    fx_bad "single transaction missing full list: $line"
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
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    : >"$FX_TMP/audit.log"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch audits the transaction" 0
if grep -q 'dnf5 install -y emacs git' "$FX_TMP/audit.log" 2>/dev/null; then
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
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch non-root goes through sudo" 0
if grep -q '^sudo: -- dnf5 install ' "$FAKE_LOG" && grep -q '^dnf5: install -y emacs$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "sudo barrier or dnf invocation missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata rc0" 0
if grep -q '^dnf5: makecache$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "makecache not invoked"
fi

touch "$FX_TMP/example.rpm"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local ok" 0
if grep -q "dnf5: install -y $FX_TMP/example.rpm" "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "local install not invoked"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_install_local "/nonexistent/file.rpm"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local missing file errors" 1
fx_err 'local package file not found'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_REPOS_DIR="$FX_TMP/repos"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=rpm
    pkg_add_repo myrepo https://example.invalid/repo/dists
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo writes repo file" 0
if [[ -f "$FX_TMP/repos/myrepo.repo" ]]; then
    fx_ok
else
    fx_bad "repo file not created"
fi
fx_rpm_repo() {
    grep -q "$1" "$FX_TMP/repos/myrepo.repo" 2>/dev/null
}
if fx_rpm_repo '^\[myrepo\]$' && fx_rpm_repo '^baseurl=https://example.invalid/repo/dists$' && fx_rpm_repo '^enabled=1$' && fx_rpm_repo '^gpgcheck=1$'; then
    fx_ok
else
    fx_bad "repo content malformed"
fi

printf '# keep-marker\n' >>"$FX_TMP/repos/myrepo.repo"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_REPOS_DIR="$FX_TMP/repos"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=rpm
    pkg_add_repo myrepo https://example.invalid/repo/dists
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo if-not-exists skips" 0
if grep -q '# keep-marker' "$FX_TMP/repos/myrepo.repo" 2>/dev/null; then
    fx_ok
else
    fx_bad "existing repo was overwritten"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1 FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    export FS_REPOS_DIR="$FX_TMP/dryrepos" TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_add_repo myother https://example.invalid/repo2
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo dry rc0" 0
if [[ $(grep -c '^# would run: sudo install -m 0644 .*fedora-setup-repo-myother.dry .*dryrepos/myother.repo$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry repo-add line"
fi
if [[ ! -e "$FX_TMP/dryrepos/myother.repo" ]]; then
    fx_ok
else
    fx_bad "dry-run wrote a repo file"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG FS_DRY_RUN=1
    export FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    : >"$FAKE_LOG"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch dry rc0" 0
if [[ $(grep -c '^# would run: sudo dnf5 install -y emacs git$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry dnf transaction"
fi
if [[ ! -s "$FAKE_LOG" ]]; then
    fx_ok
else
    fx_bad "dry-run invoked tools (no queries allowed)"
fi

fx_summary