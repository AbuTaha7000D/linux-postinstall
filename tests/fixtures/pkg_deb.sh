#!/usr/bin/env bash
# tests/fixtures/pkg_deb.sh - P3.3 fixture for lib/pkg/deb.sh.
# Mock strategy mirrors pkg_rpm.sh: PATH-visible fake `dpkg-query`/`apt-get`
# binaries log invocations to $FAKE_LOG and answer queries from
# $FAKE_INSTALLED. Privileged steps route through run_sudo (root=1 direct,
# plus one root=0 block proving the sudo -- barrier), keeping dry-run pure
# (only '# would run:' lines). Usage: bash tests/fixtures/pkg_deb.sh
# (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.3 deb backend\n'

mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/sources" "$FX_TMP/drysources" "$FX_TMP/tmpdir"

printf 'vim\nhtop\n' >"$FX_TMP/installed"

cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$*" in
    *'db:Status-Status'*)
        pkg="${3:-}"
        if grep -qxF -- "$pkg" "$FAKE_INSTALLED" 2>/dev/null; then
            printf 'installed\n'
        else
            exit 1
        fi
        ;;
    *'${Package}'*)
        cat "$FAKE_INSTALLED" 2>/dev/null ;;
    *) exit 0 ;;
esac
EOF

cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
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

FAKE_INSTALLED="$FX_TMP/installed"
FAKE_LOG="$FX_TMP/fake.log"
: >"$FAKE_LOG"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: apt-get present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$FX_TMP/notools"
    export FS_DISTRO_FILE="$FX_TMP/os-debian"
    {
        printf 'NAME="Debian GNU/Linux"\nID=debian\nVERSION_ID="12"\n'
    } >"$FX_TMP/os-debian"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    unset FS_PKG_BACKEND
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dispatch fallback reaches deb backend" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: no apt tools errors" 1
fx_err 'need apt-get and dpkg-query'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
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
    export FS_PKG_BACKEND=deb
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
    export FS_PKG_BACKEND=deb
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
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch vim htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch all installed skips apt" 0
if grep -q '^apt-get: install ' "$FAKE_LOG"; then
    fx_bad "batch ran apt for already-installed packages"
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
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch vim htop emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch mixed installs pending only" 0
cnt="$(grep -c '^apt-get: install ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$cnt" == 1 ]]; then
    fx_ok
else
    fx_bad "expected exactly one apt install transaction, got $cnt"
fi
line="$(grep '^apt-get: install ' "$FAKE_LOG" 2>/dev/null || :)"
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
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    : >"$FX_TMP/audit.log"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch audits the transaction" 0
if grep -q 'apt-get install -y emacs git' "$FX_TMP/audit.log" 2>/dev/null; then
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
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch non-root goes through sudo" 0
if grep -q '^sudo: -- apt-get install ' "$FAKE_LOG" && grep -q '^apt-get: install -y emacs$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "sudo barrier or apt invocation missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata rc0" 0
if grep -q '^apt-get: update$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "apt-get update not invoked"
fi

touch "$FX_TMP/example.deb"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.deb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local ok" 0
if grep -q "apt-get: install -y $FX_TMP/example.deb" "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "local install not invoked"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
    pkg_install_local "/nonexistent/file.deb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local missing file errors" 1
fx_err 'local package file not found'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_SOURCES_DIR="$FX_TMP/sources"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    pkg_add_repo myrepo "https://example.invalid/repo stable main"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo writes source list" 0
if [[ -f "$FX_TMP/sources/myrepo.list" ]]; then
    fx_ok
else
    fx_bad "source list not created"
fi
fx_deb_repo() {
    grep -q "$1" "$FX_TMP/sources/myrepo.list" 2>/dev/null
}
if fx_deb_repo '^deb https://example.invalid/repo stable main$'; then
    fx_ok
else
    fx_bad "source list content malformed"
fi

printf '# keep-marker\n' >>"$FX_TMP/sources/myrepo.list"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_SOURCES_DIR="$FX_TMP/sources"
    export TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    pkg_add_repo myrepo "https://example.invalid/repo stable main"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo if-not-exists skips" 0
if grep -q '# keep-marker' "$FX_TMP/sources/myrepo.list" 2>/dev/null; then
    fx_ok
else
    fx_bad "existing source list was overwritten"
fi

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb FS_SOURCES_DIR="$FX_TMP/sources"
    pkg_add_repo "../evil" "https://example.invalid/repo stable main"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects path id" 1
fx_err 'refusing invalid repo id'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1 FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    export FS_SOURCES_DIR="$FX_TMP/drysources" TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
    pkg_add_repo myother "https://example.invalid/repo2 stable main"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo dry rc0" 0
if [[ $(grep -c '^# would run: sudo install -m 0644 .*fedora-setup-repo-myother.dry .*drysources/myother.list$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry repo-add line"
fi
if [[ ! -e "$FX_TMP/drysources/myother.list" ]]; then
    fx_ok
else
    fx_bad "dry-run wrote a source list"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG FS_DRY_RUN=1
    export FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "batch dry rc0" 0
if [[ $(grep -c '^# would run: sudo apt-get install -y emacs git$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
    fx_ok
else
    fx_bad "expected single dry apt transaction"
fi
if [[ ! -s "$FAKE_LOG" ]]; then
    fx_ok
else
    fx_bad "dry-run invoked tools (no queries allowed)"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG
    export FS_SOURCES_DIR="$FX_TMP/sources" TMPDIR="$FX_TMP/tmpdir"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_add_repo newsrc "https://example.invalid/newsrc stable main"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "new repo triggers update before batch" 0
u="$(grep -n '^apt-get: update$' "$FAKE_LOG" 2>/dev/null | cut -d: -f1 | head -1)"
i="$(grep -n '^apt-get: install ' "$FAKE_LOG" 2>/dev/null | cut -d: -f1 | head -1)"
if [[ -n "$u" && -n "$i" && "$u" -lt "$i" ]]; then
    fx_ok
else
    fx_bad "apt-get update must precede the batch (u=$u i=$i)"
fi
cnt="$(grep -c '^apt-get: install ' "$FAKE_LOG" 2>/dev/null || :)"
if [[ "$cnt" == 1 ]]; then
    fx_ok
else
    fx_bad "expected one install transaction, got $cnt"
fi

fx_summary