#!/usr/bin/env bash
# tests/fixtures/pkg_flatpak.sh - P3.6 fixture for lib/pkg/flatpak.sh.
# Mock strategy mirrors pkg_rpm.sh/pkg_arch.sh: a PATH-visible fake
# `flatpak` logs invocations to $FAKE_LOG and answers queries from
# $FAKE_USER_INSTALLED / $FAKE_SYSTEM_INSTALLED and list calls from
# $FAKE_USER_LIST / $FAKE_SYSTEM_LIST (user/system install detection).
# Every mutating step is unprivileged via run_cmd (never sudo), dry-run is
# pure (only '# would run:' lines, zero fake invocations logged), and the
# FS_LOG_FILE audit trail is assertable. Blocks that inspect $FAKE_LOG
# truncate it first so each assert sees only that block's invocations.
# P3.6 verification: dry-run prints the flathub remote-add-if-not-exists
# line + a single install command; a query of a missing app is not
# installed (and of a present app is installed, no stdout).
# Usage: bash tests/fixtures/pkg_flatpak.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.6 flatpak backend\n'

mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools"

FAKE_USER_INSTALLED="$FX_TMP/user-installed"
FAKE_SYSTEM_INSTALLED="$FX_TMP/system-installed"
FAKE_USER_LIST="$FX_TMP/user-list"
FAKE_SYSTEM_LIST="$FX_TMP/system-list"
FAKE_LOG="$FX_TMP/fake.log"
: >"$FAKE_LOG"
printf 'org.foo.App\n' >"$FAKE_USER_INSTALLED"
printf 'org.sys.App\n' >"$FAKE_SYSTEM_INSTALLED"
printf 'org.foo.App\norg.dup.App\n' >"$FAKE_USER_LIST"
printf 'org.sys.App\norg.dup.App\n' >"$FAKE_SYSTEM_LIST"

cat >"$FX_TMP/fakebin/flatpak" <<'EOF'
#!/usr/bin/env bash
printf 'flatpak: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    info)
        case "$2" in
            --user) grep -qxF -- "${3:-}" "$FAKE_USER_INSTALLED" 2>/dev/null ;;
            --system) grep -qxF -- "${3:-}" "$FAKE_SYSTEM_INSTALLED" 2>/dev/null ;;
            *) exit 0 ;;
        esac
        ;;
    list)
        case "$2" in
            --user) cat "$FAKE_USER_LIST" 2>/dev/null ;;
            --system) cat "$FAKE_SYSTEM_LIST" 2>/dev/null ;;
            *) exit 0 ;;
        esac
        ;;
    *) exit 0 ;;
esac
EOF

chmod +x "$FX_TMP/fakebin/flatpak"

cat >"$FX_TMP/fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo: %s\n' "$*" >>"$FAKE_LOG" 2>/dev/null || :
exit 1
EOF
chmod +x "$FX_TMP/fakebin/sudo"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: flatpak present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: flatpak absent" 1

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_query_installed org.foo.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query installed user scope" 0
fx_empty "query installed user scope no stdout"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_query_installed org.sys.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query installed system scope" 0
fx_empty "query installed system scope no stdout"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_query_installed org.missing.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query missing app not installed" 1
fx_empty "query missing no stdout"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_list_installed
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "list installed" 0
fx_out '^org\.dup\.App$'
fx_out '^org\.foo\.App$'
fx_out '^org\.sys\.App$'
if [[ "$(cat "$FX_OUT")" == "org.dup.App
org.foo.App
org.sys.App" ]]; then
    fx_ok
else
    fx_bad "list sorted unique merge"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_install_batch org.dup.App org.net.App org.sys.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch filters installed" 0
r="$(grep -n '^flatpak: remote-add --user --if-not-exists flathub ' "$FAKE_LOG" | cut -d: -f1 | head -1)"
i="$(grep -n '^flatpak: install ' "$FAKE_LOG" | cut -d: -f1 | head -1)"
c="$(grep -c '^flatpak: install ' "$FAKE_LOG" || :)"
if [[ -n "$r" && -n "$i" && "$r" -lt "$i" && "$c" == 1 ]] \
    && grep -q '^flatpak: install --user --noninteractive --assumeyes org.dup.App org.net.App$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "flathub remote-add must precede a single install transaction"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_install_batch org.foo.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch all installed skips" 0
if grep -q '^flatpak: install ' "$FAKE_LOG" || grep -q '^flatpak: remote-add ' "$FAKE_LOG"; then
    fx_bad "all-installed batch must run nothing"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_install_batch org.net.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch dry pure" 0
fx_out '^# would run: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo$'
fx_out '^# would run: flatpak install --user --noninteractive --assumeyes org.net.App$'
r="$(grep -n '^# would run: flatpak remote-add --user --if-not-exists flathub ' "$FX_OUT" | cut -d: -f1 | head -1)"
i="$(grep -n '^# would run: flatpak install ' "$FX_OUT" | cut -d: -f1 | head -1)"
c="$(grep -c '^# would run: flatpak install ' "$FX_OUT" || :)"
ra="$(grep -c '^# would run: flatpak remote-add ' "$FX_OUT" || :)"
if [[ -n "$r" && -n "$i" && "$r" -lt "$i" && "$c" == 1 && "$ra" == 1 ]]; then
    fx_ok
else
    fx_bad "dry remote-add must precede a single would-run install command"
fi
if [[ -s "$FAKE_LOG" ]]; then
    fx_bad "dry install must not invoke flatpak"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    export FS_LOG_FILE="$FX_TMP/audit.log"
    : >"$FS_LOG_FILE"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_install_batch org.net.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install audit trail via run_cmd" 0
if grep -q 'run: flatpak install ' "$FX_TMP/audit.log"; then
    fx_ok
else
    fx_bad "FS_LOG_FILE audit missing for flatpak install"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata" 0
if grep -q '^flatpak: update --appstream$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "appstream refresh missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata dry pure" 0
fx_out '^# would run: flatpak update --appstream$'
if [[ -s "$FAKE_LOG" ]]; then
    fx_bad "dry update must not invoke flatpak"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" TMPDIR="$FX_TMP"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    printf 'fake bundle\n' >"$FX_TMP/bundle.flatpak"
    pkg_install_local "$FX_TMP/bundle.flatpak"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local bundle" 0
if grep -q "^flatpak: install --user --noninteractive --assumeyes $FX_TMP/bundle.flatpak\$" "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "local bundle install transaction missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_install_local "$FX_TMP/no-such-bundle.flatpak"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local missing file errors" 1
fx_err 'local flatpak bundle not found'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_install_local "$FX_TMP/bundle.flatpak"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local dry pure" 0
fx_out "^# would run: flatpak install --user --noninteractive --assumeyes $FX_TMP/bundle.flatpak\$"
if [[ -s "$FAKE_LOG" ]]; then
    fx_bad "dry local install must not invoke flatpak"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_add_repo testrepo https://example.test/repo.flatpakrepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo" 0
if grep -q '^flatpak: remote-add --user --if-not-exists testrepo https://example.test/repo.flatpakrepo$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "flatpak remote-add default missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_add_repo testrepo https://example.test/repo.flatpakrepo /tmp/custom.gpg
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo with key" 0
if grep -q '^flatpak: remote-add --user --if-not-exists testrepo https://example.test/repo.flatpakrepo --gpg-import /tmp/custom.gpg$' "$FAKE_LOG"; then
    fx_ok
else
    fx_bad "flatpak remote-add gpg-import missing"
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_add_repo '../evil' https://example.test/repo.flatpakrepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects path id" 1
fx_err 'invalid flatpak remote id'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_add_repo '' https://example.test/repo.flatpakrepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects empty id" 1

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    pkg_add_repo testrepo $'https://example.test/\nrepo.flatpakrepo'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects newline url" 1
fx_err 'invalid flatpak remote url'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FS_DRY_RUN=1
    export FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_add_repo testrepo https://example.test/repo.flatpakrepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo dry pure" 0
fx_out '^# would run: flatpak remote-add --user --if-not-exists testrepo https://example.test/repo.flatpakrepo$'
if [[ -s "$FAKE_LOG" ]]; then
    fx_bad "dry add repo must not invoke flatpak"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_USER_INSTALLED FAKE_SYSTEM_INSTALLED FAKE_USER_LIST FAKE_SYSTEM_LIST FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=flatpak
    : >"$FAKE_LOG"
    pkg_install_batch org.dup.App org.sys.App
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install paths never use sudo" 0
if grep -q 'sudo' "$FAKE_LOG"; then
    fx_bad "flatpak installs must be unprivileged"
else
    fx_ok
fi

fx_summary