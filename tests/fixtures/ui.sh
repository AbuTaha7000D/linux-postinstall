#!/usr/bin/env bash
# tests/fixtures/ui.sh - P4.7 fixture for lib/ui.sh.
# Exercises the line-mode surface (the fully scriptable, deterministic
# path -- TTY/raw-key mode is a thin per-key loop over the same state
# machine, not testable headlessly): ui_confirm defaults/FS_YES bypass/
# retry/EOF, and ui_multiselect defaults, digit+tone grid, a/n/q/Enter,
# EOF fail-closed, high-risk rows refusing row toggles, the opt-in prompt
# being the ONLY way to enable them, empty entries, and atomic selection
# writes. ui_multiselect reads a tsv entries file AND an initial selection
# file (defaults); the writes we care about land under FX_TMP so nothing
# outside the scratch dir is touched.
# Usage: bash tests/fixtures/ui.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/U"

printf 'P4.7 selection ui\n'

SRC="source \"\$ROOT/lib/io.sh\"; source \"\$ROOT/lib/ui.sh\""

# --- ui_confirm ----------------------------------------------------------

set +e
(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'y\n' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm yes" 0
fx_out '^proceed? \[y/N\] $'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'n\n' | ui_confirm "proceed?" y
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm no" 1

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf '\n' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm empty default no" 1

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf '\n' | ui_confirm "proceed?" y
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm empty default yes" 0

(   set -euo pipefail
    export FS_YES=1
    eval "$SRC"
    printf '' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm FS_YES bypass" 0
fx_empty "confirm FS_YES never prompts" "$FX_OUT"

(   set -euo pipefail
    unset FS_YES 2>/dev/null || :
    eval "$SRC"
    printf 'n\n' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm unset FS_YES prompts (default no)" 1
fx_out '^proceed? \[y/N\] $'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'x\ny\n' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm invalid retries to yes" 0

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf '' | ui_confirm "proceed?" n
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "confirm EOF fail-closed default no" 1

# --- ui_multiselect ------------------------------------------------------

E="$FX_TMP/U/e"
S="$FX_TMP/U/s"
printf 'alpha\tAlpha one\tnone\nbeta\tBeta two\tlow\nrisky\tRisky three\thigh\nboom\tBoom four\tdestructive\n' >"$E"

mk_sel() {
    printf '%s\n' "${1:-}" >"$S"
}

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'alpha\nbeta\n' >"$S"
    printf '\n\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "defaults show prechecked" 0
fx_out '^\[x\] alpha - Alpha one$'
fx_out '^\[x\] beta - Beta two$'
fx_out '^\[ \] risky - Risky three  \[high-risk\]$'
fx_out '^\[ \] boom - Boom four  \[high-risk\]$'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    mk_sel ""
    printf '1 3\n\n\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "digit toggle works, high-risk refused" 0
fx_err 'high-risk module risky cannot be toggled here (use the opt-in prompt)'
if [[ "$(tr -d '\n' <"$S")" == "alpha" ]]; then fx_ok; else fx_bad "selection after toggle (want alpha)"; cat "$S"; fi

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'risky\n' >"$S"
    printf '\nrisky\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "opt-in adds high-risk only" 0
fx_out '^\[x\] risky - Risky three  \[high-risk\]$'
if [[ "$(tr -d '\n' <"$S")" == "risky" ]]; then fx_ok; else fx_bad "opt-in selection (want risky)"; cat "$S"; fi

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    mk_sel ""
    printf 'a\n\n\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "a selects non-high-risk only" 0
fx_out '^\[x\] alpha - Alpha one$'
fx_out '^\[x\] beta - Beta two$'
fx_out '^\[ \] risky - Risky three  \[high-risk\]$'
if [[ "$(tr -d '\n' <"$S")" == "alphabeta" ]]; then fx_ok; else fx_bad "a selection (want alphabeta)"; cat "$S"; fi

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'alpha\nboom\n' >"$S"
    printf 'n\n\n\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "n clears all" 0
fx_empty "n clears to empty selection" "$S"

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'q\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "q aborts rc1" 1
fx_err_not "no such row"

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    : >"$S"
    printf '' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "EOF aborts rc1" 1

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'q\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "q leaves selection untouched" 1
fx_empty "q aborted selection file unchanged" "$S"

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf '3\n\nboom\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "high-risk refused by row, enabled by opt-in" 0
if [[ "$(tr -d '\n' <"$S")" == "boom" ]]; then fx_ok; else fx_bad "destructive opt-in (want boom)"; cat "$S"; fi

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'alpha\nboom\n' >"$S"
    printf '5\nq\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "out-of-range row warns, q aborts" 1
fx_err 'no such row: 5'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    : >"$S"
    printf '08\n\n\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "08 leading-zero row warns cleanly" 0
fx_err 'no such row: 08'
fx_err_not 'value too great for base'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    rm -rf -- "$FX_TMP/U/seldir"
    mkdir -p -- "$FX_TMP/U/seldir"
    printf '\n\n\n' | ui_multiselect "Pick" "$E" "$FX_TMP/U/seldir"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "sel path is a directory rc1" 1
fx_err 'cannot commit selection file'

E2="$FX_TMP/U/e2"
: >"$E2"

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    : >"$S"
    printf '\n\n' | ui_multiselect "Pick" "$E2" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty entries accept rc0" 0
fx_empty "empty entries select empty file" "$S"

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf '\n\n' | ui_multiselect "Pick" "$E" "/nonexistent/dir/s"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing selection dir rc1" 1
fx_err 'selection directory missing'

(   set -euo pipefail
    export FS_YES=0
    eval "$SRC"
    printf 'q\n' | ui_multiselect "Pick" "$E" "$S"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "title printed on first render" 1
fx_out '^Pick$'
fx_empty "q abort left selection file untouched" "$S"

fx_summary