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
if [[ $(grep -c '^# would run: sudo -- install -m 0644 .*fedora-setup-repo-myother.dry .*drysources/myother.list$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
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
if [[ $(grep -c '^# would run: sudo -- apt-get install -y emacs git$' "$FX_OUT" 2>/dev/null || :) == 1 ]]; then
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

# --- B1: package manager transaction failure propagation ---------------

# B1.1: apt-get exits non-zero on install_batch -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: install_batch fails when apt-get exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.2: plan_install refuses to continue when backend fails
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    plan_install emacs git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: plan_install refuses when backend fails" 1

# B1.3: apt-get exits non-zero on update_metadata -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
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
fx_block_rc "B1: update_metadata fails when apt-get exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.4: install exits non-zero on add_repo -> backend returns non-zero
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FS_SOURCES_DIR="$FX_TMP/sources"
    export TMPDIR="$FX_TMP/tmpdir"
    # Clean up any existing repo from earlier tests
    rm -f "$FX_TMP/sources/b1test.list"
    cat >"$FX_TMP/fakebin/install" <<'EOF'
#!/usr/bin/env bash
printf 'install: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/install"
    # Also need apt-get for deb_supported check
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    # Need dpkg-query for deb_supported check
    cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/dpkg-query"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_add_repo b1test "https://example.invalid/repo stable main"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: add_repo fails when install exits non-zero" 1
fx_err 'command failed (rc=100)'

# B1.5: mutation test - removing --stop from install_batch is caught
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    : >"$FAKE_LOG"
    pkg_install_batch emacs
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-mut: install_batch mutation (--stop removed) caught" 1

# B1.6: postcondition test - command exits 0 but does no work
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
# exits 0 but does NOT add to FAKE_INSTALLED
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
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

# B1.7: install_local returns 0 even when PM fails (no --stop per postcondition rule)
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    touch "$FX_TMP/example.deb"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.deb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: install_local returns 0 despite PM failure (postcondition rule)" 0
fx_err 'command failed (rc=100)'

# B1.8: postcondition check catches the failure (pkg_query_installed returns 1)
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "${1:-}" in
    -W)
        if [[ "${2:-}" == "-f="*'${db:Status-Status}'* ]]; then
            grep -qxF -- "${3:-}" "$FAKE_INSTALLED" 2>/dev/null && echo "installed" || echo "not-installed"
        elif [[ "${2:-}" == "-f="*'${Package}'* ]]; then
            cat "$FAKE_INSTALLED" 2>/dev/null
        fi
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dpkg-query"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    touch "$FX_TMP/example.deb"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.deb" || rc=$?
    pkg_query_installed example.deb
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: postcondition query catches failed install_local" 1

# B1.9: mutation test - removing postcondition check is caught
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 100
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "${1:-}" in
    -W)
        if [[ "${2:-}" == "-f="*'${db:Status-Status}'* ]]; then
            grep -qxF -- "${3:-}" "$FAKE_INSTALLED" 2>/dev/null && echo "installed" || echo "not-installed"
        elif [[ "${2:-}" == "-f="*'${Package}'* ]]; then
            cat "$FAKE_INSTALLED" 2>/dev/null
        fi
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dpkg-query"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    touch "$FX_TMP/example.deb"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.deb"  # NO postcondition check!
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-mut: missing postcondition check not caught by backend" 0
if ! pkg_query_installed example.deb >/dev/null 2>&1; then
    fx_ok  # package correctly NOT installed (query would catch it if run)
else
    fx_bad "package should not be installed"
fi

# B1.10: postcondition test - install_local exits 0 but doesn't install, query catches it
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_LOG="$FX_TMP/fake.log" FAKE_INSTALLED="$FX_TMP/installed"
    : >"$FAKE_INSTALLED"
    cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
# exits 0 but does NOT add to FAKE_INSTALLED
exit 0
EOF
    chmod +x "$FX_TMP/fakebin/apt-get"
    cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "${1:-}" in
    -W)
        if [[ "${2:-}" == "-f="*'${db:Status-Status}'* ]]; then
            grep -qxF -- "${3:-}" "$FAKE_INSTALLED" 2>/dev/null && echo "installed" || echo "not-installed"
        elif [[ "${2:-}" == "-f="*'${Package}'* ]]; then
            cat "$FAKE_INSTALLED" 2>/dev/null
        fi
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dpkg-query"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=deb
    touch "$FX_TMP/example.deb"
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/example.deb"
    pkg_query_installed example.deb
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-post: install_local silent failure caught by query" 1
if ! grep -qxF example.deb "$FAKE_INSTALLED" 2>/dev/null; then
    fx_ok
else
    fx_bad "package was unexpectedly installed"
fi

fx_summary