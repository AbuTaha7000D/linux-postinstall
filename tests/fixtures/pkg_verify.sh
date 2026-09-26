#!/usr/bin/env bash
# tests/fixtures/pkg_verify.sh - P3.9 fixture for pkg_verify_packages in
# lib/pkg.sh. The verification bullet: "Fixture backends: present +
# missing mix reported correctly." Mock (pure seam: installed state in
# $FS_MOCK_INSTALLED, every query recorded to $FS_MOCK_LOG) exercises the
# per-package machinery; rpm (PATH-fake `rpm` answering -q) proves a REAL
# backend reports the mix the same way. Verify is a write-free diagnostic:
# it must never render `# would run:` lines even under FS_DRY_RUN, and it
# keeps reporting ground truth in dry mode (no planning/probing purity
# applies). Asserted: rc semantics (1 iff any missing, 0 on empty/all
# present), exact ordered present/missing output, no stdout leakage from
# queries, query log records, and no render lines under dry.
# Usage: bash tests/fixtures/pkg_verify.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin"
FX_EXPECT="$FX_TMP/expect"

printf 'P3.9 verify primitives\n'

export FS_MOCK_LOG="$FX_TMP/mock.log"
export FS_MOCK_INSTALLED="$FX_TMP/installed"

(
    set -euo pipefail
    : >"$FS_MOCK_LOG"
    printf 'vim\nhtop\n' >"$FS_MOCK_INSTALLED"
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_verify_packages vim git curl htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "mix reports missing rc1" 1
printf "present: vim\nmissing: git\nmissing: curl\npresent: htop\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "mix output present/missing in order"
if [[ $(grep -c '^mock query ' "$FS_MOCK_LOG") -eq 4 ]] && \
    [[ "$(cat "$FS_MOCK_LOG")" == "$(printf 'mock query vim\nmock query git\nmock query curl\nmock query htop')" ]]; then
    fx_ok
else
    fx_bad "verify records one query per input in order"
fi

(
    set -euo pipefail
    : >"$FS_MOCK_LOG"
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_verify_packages
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty list rc0" 0
fx_empty "empty list no output" "$FX_OUT"
if [[ ! -s "$FS_MOCK_LOG" ]]; then fx_ok; else fx_bad "empty list records no queries"; fi

(
    set -euo pipefail
    : >"$FS_MOCK_LOG"
    export FS_MOCK_LOG FS_MOCK_INSTALLED
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_verify_packages vim htop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "all present rc0" 0
printf "present: vim\npresent: htop\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "all present output"

(
    set -euo pipefail
    : >"$FS_MOCK_LOG"
    printf 'vim\nhtop\n' >"$FS_MOCK_INSTALLED"
    export FS_MOCK_LOG FS_MOCK_INSTALLED FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=mock
    pkg_verify_packages git vim
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry mode reports truth rc1" 1
printf "missing: git\npresent: vim\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "dry mode ground truth output"
if grep -q 'would run' "$FX_OUT"; then fx_bad "dry mode renders no command lines"; else fx_ok; fi
if [[ $(grep -c '^mock query ' "$FS_MOCK_LOG") -eq 2 ]]; then fx_ok; else fx_bad "dry verify still records its queries"; fi

cat >"$FX_TMP/fakebin/rpm" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-q" ]] || exit 0
[[ "$2" == "git" ]] && exit 0
exit 1
EOF
chmod +x "$FX_TMP/fakebin/rpm"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_verify_packages git vim curl
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm backend mix rc1" 1
printf "present: git\nmissing: vim\nmissing: curl\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "rpm backend present/missing output"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    export FS_PKG_BACKEND=rpm
    pkg_verify_packages
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm backend empty rc0" 0
fx_empty "rpm backend empty no output" "$FX_OUT"

true
fx_summary