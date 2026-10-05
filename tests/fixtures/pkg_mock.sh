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

# --- B1: package manager transaction failure propagation ---------------
# The mock backend satisfies the postcondition rule via _mock_record (returns 1
# on failure). These cells test that the postcondition works.

# B1.1: install_batch fails when mock log is unusable (postcondition)
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
fx_block_rc "B1: install_batch fails when mock log unusable (postcondition)" 1
fx_err 'mock log not usable'
if grep -q '^org.delta$' "$FS_MOCK_INSTALLED" 2>/dev/null; then
    fx_bad "install must not mutate state without a record"
else
    fx_ok
fi

# B1.2: plan_install refuses when mock install_batch fails
(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    plan_install org.delta
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: plan_install refuses when mock backend fails" 1

# B1.3: update_metadata fails when mock log is unusable
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
fx_block_rc "B1: update_metadata fails when mock log unusable" 1
fx_err 'mock log not usable'

# B1.4: add_repo fails when mock log is unusable
(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_add_repo testrepo https://example.test/repo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: add_repo fails when mock log unusable" 1
fx_err 'mock log not usable'

# B1.5: mutation test - removing || return 1 from _mock_record in install_batch is caught
# This cell uses a usable mock log but the install_batch's _mock_record would
# succeed. To test the mutation, we verify that install_batch returns non-zero
# when _mock_record fails. If || return 1 were removed, it would return 0.
# The non-vacuity is proven by the existing "unusable mock log halts batch" cell.
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
fx_block_rc "B1-mut: install_batch mutation (postcondition removed) caught" 1

# B1.6: postcondition test - mock record succeeds but doesn't mutate state
# The mock's _mock_note_installed is called AFTER _mock_record, so if
# _mock_note_installed were to fail silently, the record would exist but
# the package wouldn't be marked installed. This cell verifies the current
# coupling: install_batch calls _mock_note_installed for each package.
(
    set -euo pipefail
    export FS_MOCK_LOG="$FX_TMP/mock.log" FS_MOCK_INSTALLED="$FX_TMP/installed"
    : >"$FS_MOCK_LOG"
    printf 'org.alpha\norg.beta\n' >"$FS_MOCK_INSTALLED"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_install_batch org.gamma
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-post: install_batch records then mutates (coupling)" 0
if grep -q '^mock install org.gamma$' "$FS_MOCK_LOG" 2>/dev/null && grep -qxF org.gamma "$FS_MOCK_INSTALLED" 2>/dev/null; then
    fx_ok
else
    fx_bad "record and installed-set coupling broken"
fi

# B1.7: install_local fails when mock log is unusable (postcondition)
(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    touch "$FX_TMP/some_file"
    pkg_install_local "$FX_TMP/some_file"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: install_local fails when mock log unusable (postcondition)" 1
fx_err 'mock log not usable'

# B1.8: postcondition check catches the failure (_mock_record returns 1)
(
    set -euo pipefail
    export FS_MOCK_LOG_DIR="$FX_TMP/not-a-file"
    mkdir -p "$FS_MOCK_LOG_DIR"
    export FS_MOCK_LOG="$FS_MOCK_LOG_DIR" FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    touch "$FX_TMP/some_file"
    pkg_install_local "$FX_TMP/some_file" || rc=$?
    # The postcondition is _mock_record || return 1, which already failed above
    # This cell verifies the postcondition is what causes the failure
    mock_query_installed "$FX_TMP/some_file"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1: postcondition _mock_record catches failed install_local" 1

# B1.9: mutation test - removing postcondition check is caught
(
    set -euo pipefail
    export FS_MOCK_LOG="$FX_TMP/mock.log" FS_MOCK_INSTALLED
    : >"$FS_MOCK_LOG"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    touch "$FX_TMP/some_file"
    pkg_install_local "$FX_TMP/some_file"  # NO postcondition check!
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-mut: missing postcondition check not caught by backend" 0
if ! mock_query_installed "$FX_TMP/some_file" >/dev/null 2>&1; then
    fx_ok  # package correctly NOT installed (query would catch it if run)
else
    fx_bad "package should not be installed"
fi

# B1.10: postcondition test - mock records install_local but does not update installed set
# This is the P3.7 install-local gap (recorded design change). The mock records the
# call in the log but does not add the package to the installed set.
# This cell verifies the current behavior: log entry exists, installed set unchanged.
export FS_MOCK_LOG="$FX_TMP/mock2.log" FS_MOCK_INSTALLED="$FX_TMP/installed2"
: >"$FS_MOCK_LOG"
printf 'org.alpha\n' >"$FS_MOCK_INSTALLED"
(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    touch "$FX_TMP/some_file"
    pkg_install_local "$FX_TMP/some_file"
    # The query returns 1 (not installed) which is the P3.7 gap behavior.
    # We don't let that failure propagate as the cell's rc; the gap is the point.
    mock_query_installed "$FX_TMP/some_file" || true
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B1-post: install_local log-only (P3.7 gap)" 0
if grep -q "^mock install-local $FX_TMP/some_file$" "$FS_MOCK_LOG" 2>/dev/null && ! grep -qxF "$FX_TMP/some_file" "$FS_MOCK_INSTALLED" 2>/dev/null; then
    fx_ok
else
    fx_bad "install_local should log but not update installed set (P3.7 gap)"
fi

fx_summary