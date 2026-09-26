#!/usr/bin/env bash
# tests/fixtures/planner.sh - P3.8 fixture for lib/planner.sh.
# Union-diff-batch semantics with the mock backend (installed-state
# honored end-to-end) and the rpm fakebin backend for the dry-run
# "exactly one dnf line" criterion; FS_MOCK_* and FAKE_LOG give the
# single-transaction proof. Uses FS_MOCK_INSTALLED (one pkg/line) and
# FS_MOCK_LOG (recorded call sequence) so asserts are exact.
# Usage: bash tests/fixtures/planner.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin"

printf 'P3.8 planner\n'

FS_MOCK_LOG="$FX_TMP/plan.log"
FS_MOCK_INSTALLED="$FX_TMP/plan-installed"
: >"$FS_MOCK_LOG"
printf 'vim\ncurl\n' >"$FS_MOCK_INSTALLED"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    plan_dedupe vim git curl vim htop git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dedupe keeps first-seen order" 0
if [[ "$(cat "$FX_OUT")" == "vim
git
curl
htop" ]]; then
    fx_ok
else
    fx_bad "dedupe output mismatch"
fi

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    plan_dedupe '' vim ''
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dedupe skips empty args" 0
fx_out '^vim$'

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    plan_pending vim git curl htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "pending diffs against installed" 0
if [[ "$(cat "$FX_OUT")" == "git
htop" ]]; then
    fx_ok
else
    fx_bad "pending must contain only uninstalled"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock FS_DRY_RUN=1
    : >"$FS_MOCK_LOG"
    plan_pending vim git curl htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "pending dry passes through no probe" 0
if [[ "$(cat "$FX_OUT")" == "vim
git
curl
htop" ]]; then
    fx_ok
else
    fx_bad "dry pending must not filter"
fi
if [[ -s "$FS_MOCK_LOG" ]]; then
    fx_bad "dry pending must not probe installed state"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    unset FS_MOCK_INSTALLED
    plan_pending vim git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "pending with no installed seam lists all" 0
fx_out '^vim$'
fx_out '^git$'

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    plan_install vim git curl vim git curl htop git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "plan_install overlaps -> one transaction" 0
if [[ "$(cat "$FS_MOCK_LOG")" == "mock query vim
mock query git
mock query curl
mock query htop
mock query git
mock query htop
mock install git htop" ]]; then
    fx_ok
else
    fx_bad "plan_install call sequence mismatch"
fi
if [[ "$(grep -c '^mock install ' "$FS_MOCK_LOG" || :)" == "1" ]]; then
    fx_ok
else
    fx_bad "plan_install must emit a single install transaction"
fi
if [[ "$(sort -u "$FS_MOCK_INSTALLED")" == "curl
git
htop
vim" ]]; then
    fx_ok
else
    fx_bad "installed set not updated by plan_install"
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    plan_install vim curl
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "plan_install all installed skips" 0
if grep -q '^mock install ' "$FS_MOCK_LOG"; then
    fx_bad "all-installed plan must not install"
else
    fx_ok
fi

(
    set -euo pipefail
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    export FS_PKG_BACKEND=mock
    : >"$FS_MOCK_LOG"
    plan_install
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "plan_install empty input silent" 0
fx_empty "plan_install empty input no stdout" "$FX_OUT"
if [[ -s "$FS_MOCK_LOG" ]]; then
    fx_bad "empty plan must not record"
else
    fx_ok
fi

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH" FAKE_INSTALLED FAKE_LOG FS_DRY_RUN=1
    printf 'vim\n' >"$FX_TMP/installed"
    {
        printf '#!/usr/bin/env bash\nprintf "dnf5: %%s\\n" "$*" >>"$FAKE_LOG" 2>/dev/null || :\nexit 0\n'
    } >"$FX_TMP/fakebin/dnf5"
    chmod +x "$FX_TMP/fakebin/dnf5"
    FAKE_LOG="$FX_TMP/dry.log"
    : >"$FAKE_LOG"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/sudo.sh"
    source "$ROOT/lib/pkg.sh"
    source "$ROOT/lib/planner.sh"
    FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
    export FS_PKG_BACKEND=rpm
    plan_install vim git curl vim
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm dry plan_install single line" 0
fx_out '^# would run: sudo dnf5 install -y vim git curl$'
if [[ "$(grep -c '^# would run: sudo dnf5 install ' "$FX_OUT" || :)" == "1" ]]; then
    fx_ok
else
    fx_bad "dry plan must render exactly one dnf line"
fi
if [[ -s "$FAKE_LOG" ]]; then
    fx_bad "dry plan must not execute dnf5"
else
    fx_ok
fi

true
fx_summary