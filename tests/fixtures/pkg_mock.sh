#!/usr/bin/env bash
# tests/fixtures/pkg_mock.sh - P3.7 fixture for lib/pkg/mock.sh.
# No fake binaries needed: the mock backend is a pure seam. Installed
# state lives in $FS_MOCK_INSTALLED and every invocation is appended to
# $FS_MOCK_LOG, so the expected call sequence for an install_batch is
# asserted line-exactly (the P3.7 verification), dry-run renders
# '# would run: mock ...' lines with no recording/mutation, and the
# installed-state is honored by a follow-up query/list. Blocks that
# inspect the log truncate it first.
# Usage: bash tests/fixtures/pkg_mock.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.7 mock backend\n'

FS_MOCK_LOG="$FX_TMP/mock.log"
FS_MOCK_INSTALLED="$FX_TMP/installed"
: >"$FS_MOCK_LOG"
printf 'org.alpha\norg.beta\n' >"$FS_MOCK_INSTALLED"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "capability: mock always supported" 0

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_query_installed org.alpha
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query installed" 0
fx_empty "query installed no stdout" "$FX_OUT"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_query_installed org.gamma
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query missing" 1
fx_empty "query missing no stdout" "$FX_OUT"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_list_installed
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "list installed" 0
fx_out '^org\.alpha$'
fx_out '^org\.beta$'

printf 'org.gamma\norg.gamma\n' >>"$FS_MOCK_INSTALLED"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_list_installed
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "list dedupes installed set" 0
if [[ "$(cat "$FX_OUT")" == "org.alpha
org.beta
org.gamma" ]]; then
    fx_ok
else
    fx_bad "list must be sorted unique"
fi

printf 'org.alpha\norg.beta\n' >"$FS_MOCK_INSTALLED"
: >"$FS_MOCK_LOG"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_install_batch org.alpha org.gamma org.beta
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch single transaction" 0
if [[ "$(cat "$FS_MOCK_LOG")" == "mock query org.alpha
mock query org.gamma
mock query org.beta
mock install org.gamma" ]]; then
    fx_ok
else
    fx_bad "install_batch call sequence mismatch"
fi
if [[ "$(sort -u "$FS_MOCK_INSTALLED")" == "org.alpha
org.beta
org.gamma" ]]; then
    fx_ok
else
    fx_bad "installed set not updated by install"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_query_installed org.gamma
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "installed-state honored after install" 0

: >"$FS_MOCK_LOG"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_install_batch org.alpha org.gamma
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch all installed skips" 0
if grep -q '^mock install ' "$FS_MOCK_LOG"; then
    fx_bad "all-installed batch must not record install"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_install_batch org.delta org.alpha
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install batch dry pure" 0
fx_out '^# would run: mock install org.delta org.alpha$'
if [[ "$(wc -l <"$FX_OUT")" == 1 ]]; then
    fx_ok
else
    fx_bad "dry run must emit exactly one line"
fi
if [[ -s "$FS_MOCK_LOG" || "$(grep -c '^org.delta$' "$FS_MOCK_INSTALLED" || :)" != "0" ]]; then
    fx_bad "dry install must not record or mutate state"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata" 0
if grep -q '^mock update$' "$FS_MOCK_LOG"; then
    fx_ok
else
    fx_bad "update invocation not recorded"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "update metadata dry pure" 0
fx_out '^# would run: mock update$'
if [[ "$(wc -l <"$FX_OUT")" == 1 ]]; then
    fx_ok
else
    fx_bad "dry run must emit exactly one line"
fi
if [[ -s "$FS_MOCK_LOG" ]]; then
    fx_bad "dry update must not record"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    printf 'bundle\n' >"$FX_TMP/pkg.pkg"
    pkg_install_local "$FX_TMP/pkg.pkg"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local" 0
if grep -q "^mock install-local $FX_TMP/pkg.pkg\$" "$FS_MOCK_LOG"; then
    fx_ok
else
    fx_bad "install-local invocation not recorded"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_install_local "$FX_TMP/no-such.pkg"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local missing file errors" 1
fx_err 'mock local package file not found'

(
    set -euo pipefail
    export FS_MOCK_LOG FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_install_local "$FX_TMP/pkg.pkg"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install local dry pure" 0
fx_out "^# would run: mock install-local $FX_TMP/pkg.pkg\$"
if [[ "$(wc -l <"$FX_OUT")" == 1 ]]; then
    fx_ok
else
    fx_bad "dry run must emit exactly one line"
fi
if [[ -s "$FS_MOCK_LOG" ]]; then
    fx_bad "dry install-local must not record"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_add_repo testrepo https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo" 0
if grep -q '^mock add-repo testrepo https://example.test/repo$' "$FS_MOCK_LOG"; then
    fx_ok
else
    fx_bad "add-repo invocation not recorded"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_add_repo testrepo https://example.test/repo /tmp/key.gpg
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo with key" 0
if grep -q '^mock add-repo testrepo https://example.test/repo /tmp/key.gpg$' "$FS_MOCK_LOG"; then
    fx_ok
else
    fx_bad "add-repo key argument not recorded"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo '../evil' https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects path id" 1
fx_err 'invalid mock repo id'

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo '' https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects empty id" 1

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo testrepo $'https://example.test/\nrepo'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects newline url" 1
fx_err 'invalid mock repo url'

(
    set -euo pipefail
    export FS_MOCK_LOG FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    pkg_add_repo testrepo https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo dry pure" 0
fx_out '^# would run: mock add-repo testrepo https://example.test/repo$'
if [[ "$(wc -l <"$FX_OUT")" == 1 ]]; then
    fx_ok
else
    fx_bad "dry run must emit exactly one line"
fi
if [[ -s "$FS_MOCK_LOG" ]]; then
    fx_bad "dry add-repo must not record"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_query_installed org.alpha
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unusable mock log halts query" 1
fx_err 'mock log not usable'

(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_update_metadata
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unusable mock log halts update" 1

(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_install_batch org.delta
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unusable mock log halts batch" 1
if grep -q '^org.delta$' "$FS_MOCK_INSTALLED"; then
    fx_bad "install must not mutate state without a record"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_install_local "$FX_TMP/pkg.pkg"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unusable mock log halts install-local" 1

(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo testrepo https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unusable mock log halts add-repo" 1

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    unset FS_MOCK_INSTALLED FS_MOCK_LOG
    pkg_query_installed org.alpha || true
    pkg_list_installed
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no seams: empty set, silent" 0
fx_empty "no seams: empty list on stdout" "$FX_OUT"

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_query_installed ''
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "query rejects empty package" 1
fx_err 'query_installed requires a package name'

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo .. https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "add repo rejects dot-dot id" 1
fx_err 'invalid mock repo id'

fx_summary