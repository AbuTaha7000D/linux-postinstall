#!/usr/bin/env bash
# tests/fixtures/pkg_contract.sh - P3.1 contract fixture for lib/pkg.sh.
# Covers: env override beats distro family; family fallback; no-selection
# error; unknown backend error; unimplemented backend errors clearly.
# Usage: bash tests/fixtures/pkg_contract.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

printf 'P3.1 pkg.sh contract\n'
{
    printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="41"\n'
} >"$FX_TMP/os-fedora"

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    pkg_backend
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "env selects mock backend" 0
fx_out '^mock$'

(
    set -euo pipefail
    export FS_PKG_BACKEND=mock
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unimplemented backend errors" 1
fx_err 'package backend not implemented: mock'

(
    set -euo pipefail
    export FS_PKG_BACKEND=deb FS_DISTRO_FILE="$FX_TMP/os-fedora"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    pkg_backend
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "env override beats distro family" 0
fx_out '^deb$'

(
    set -euo pipefail
    export FS_DISTRO_FILE="$FX_TMP/os-fedora"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    pkg_backend
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "distro family fallback" 0
fx_out '^rpm$'

(
    set -euo pipefail
    export FS_DISTRO_FILE="$FX_TMP/os-fedora"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/distro.sh"
    source "$ROOT/lib/pkg.sh"
    distro_detect
    unset FS_PKG_BACKEND
    pkg_backend
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fallback survives unset seam" 0
fx_out '^rpm$'

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    pkg_backend
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no selection errors" 1
fx_err 'no package backend selected'

(
    set -euo pipefail
    export FS_PKG_BACKEND=goofy
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    pkg_supported
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown backend errors" 1
fx_err 'unknown package backend: goofy'

(
    set -euo pipefail
    export FS_PKG_BACKEND=arch
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/pkg.sh"
    pkg_query_installed foo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dispatch to unbuilt backend errors" 1
fx_err 'package backend not implemented: arch'

(
    set -euo pipefail
    cd -- "$ROOT/lib" || exit 1
    source pkg.sh
    printf 'dir=%s\n' "$_pkg_dir"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare-name source survives set -e" 0
fx_out '^dir=\.$'

(
    set -euo pipefail
    cd -- "$ROOT" || exit 1
    source lib/pkg.sh
    printf 'dir=%s\n' "${_pkg_dir##*/}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relative source resolves dir" 0
fx_out '^dir=lib$'

fx_summary