#!/usr/bin/env bash
# tests/fixtures/install.sh - P4.7 fixture for `./setup install` (P2.8
# installer command, first real wiring in P4.7).
# Drives the actual launcher binary with hermetic env seams (FS_HOME state
# root, FS_PKG_BACKEND=mock, FS_MODULES_DIR/FS_PROFILES_DIR overrides,
# FS_DISTRO_FAMILY) and scripted stdin through the line-mode UI. Covers:
# interactive defaults -> profile run; edits -> `selection` sentinel run;
# --yes never prompting; --yes + CLI module ids; high-risk opt-in gated
# behind an explicit confirmation (decline aborts rc1; --yes bypass);
# dry-run purity (no state dir, no mock mutations, toggles still redraw
# the plan); unknown profile/id fail loud; distro-file detection; bare-CLI
# family->backend resolution (no FS_PKG_BACKEND, no FS_DISTRO_FAMILY: the
# family detected in-caller must reach pkg_backend and select the real rpm
# backend, proven by the dnf5 dry-render); module
# registry marks persist. Nothing outside FX_TMP is touched. Mock backend
# seams: FS_MOCK_LOG + FS_MOCK_INSTALLED.
# Usage: bash tests/fixtures/install.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/M" "$FX_TMP/P" "$FX_TMP/I"

printf 'P4.7 install wiring\n'

M="$FX_TMP/M"
P="$FX_TMP/P"
SETUP="$ROOT/setup"

mkmod() {
    local id="$1" risk="${2:-none}"
    mkdir -p "$M/$id"
    {
        printf 'MODULE_ID=%s\n' "$id"
        printf 'MODULE_TITLE=Title %s\n' "$id"
        printf 'MODULE_RISK=%s\n' "$risk"
        printf 'MODULE_DEFAULT=off\n'
    } >"$M/$id/module.sh"
    printf '%s\n' "${id}1" >"$M/$id/packages.list"
}

mkmod a
mkmod b
mkmod c
mkmod extra
mkmod z high

printf 'a\nb\nc\n' >"$P/full.conf"
printf 'a\nb\nz\n' >"$P/risky.conf"
printf '# empty skeleton\n' >"$P/minimal.conf"
printf '# internal sentinel: never edited by hand\n' >"$P/selection.conf"

RUN_I=0
LAST_LOG=""
LAST_INST=""
LAST_ST=""

inst_cell() {
    local want="$1" label="$2" stdin_file="$3"
    shift 3
    RUN_I=$((RUN_I + 1))
    LAST_LOG="$FX_TMP/I/m$RUN_I.log"
    LAST_INST="$FX_TMP/I/i$RUN_I"
    LAST_ST="$FX_TMP/h$RUN_I/.local/state/fedora-setup"
    : >"$LAST_LOG"
    : >"$LAST_INST"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h$RUN_I"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
        export FS_MOCK_LOG="$LAST_LOG" FS_MOCK_INSTALLED="$LAST_INST"
        unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install "$@" <"$stdin_file"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

# --- interactive: accept defaults -> real profile name ---------------------

printf '\n\n\n' >"$FX_TMP/I/in1"
inst_cell 0 "interactive defaults run" "$FX_TMP/I/in1"
fx_out 'Select modules for profile'
fx_out '^\[x\] a - Title a$'
fx_out '^\[ \] z - Title z  \[high-risk\]$'
fx_out 'profile: full'
fx_out '^== run complete ==$'
if grep -qxF 'mock install a1 b1 c1' "$LAST_LOG"; then fx_ok; else fx_bad "defaults batch"; cat "$LAST_LOG"; fi
if [[ -f "$LAST_ST/modules/a" && -f "$LAST_ST/modules/c" ]]; then fx_ok; else fx_bad "registry marks missing"; fi

# --- selection path pre-created as a directory fails loud (mv -fT) ---------

RUN_I=$((RUN_I + 1))
mkdir -p "$FX_TMP/hs/.local/state/fedora-setup/selections/full.sel"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hs"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_MOCK_LOG="$FX_TMP/I/sel.log" FS_MOCK_INSTALLED="$FX_TMP/I/seli"
    : >"$FX_TMP/I/sel.log"
    : >"$FX_TMP/I/seli"
    unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
    printf '\n\n\n' | "$SETUP" install
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "sel path is a directory rc1" 1
fx_err 'cannot write defaults to'

# --- interactive: edit selection -> sentinel profile -----------------------

printf '3\n\n\n' >"$FX_TMP/I/in2"
inst_cell 0 "edited selection sentinel" "$FX_TMP/I/in2"
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1' "$LAST_LOG"; then fx_ok; else fx_bad "edited batch"; cat "$LAST_LOG"; fi
if grep -q '^mock install .*c1' "$LAST_LOG"; then fx_bad "deselected module still batched"; else fx_ok; fi

# --- --yes never prompts ---------------------------------------------------

printf '' >"$FX_TMP/I/in3"
inst_cell 0 "yes bypass no prompts" "$FX_TMP/I/in3" --yes
fx_out 'profile: full'
fx_out_not 'Select modules for profile'
fx_out_not 'toggle (ids'
fx_out_not 'Enable high-risk modules'
if grep -qxF 'mock install a1 b1 c1' "$LAST_LOG"; then fx_ok; else fx_bad "yes batch"; cat "$LAST_LOG"; fi

# --- --yes + CLI ids -------------------------------------------------------

inst_cell 0 "yes cli ids appended" "$FX_TMP/I/in3" --yes extra
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 extra1' "$LAST_LOG"; then fx_ok; else fx_bad "cli batch"; cat "$LAST_LOG"; fi

# --- high-risk: opt-in + confirmation decline aborts -----------------------

printf '\nz\nn\n' >"$FX_TMP/I/in4"
inst_cell 1 "high-risk confirm declined" "$FX_TMP/I/in4"
fx_err 'installation aborted (high-risk confirmation declined)'
if [[ ! -e "$LAST_ST/modules/z" ]]; then fx_ok; else fx_bad "aborted run marked state"; fi
if grep -q '^mock install ' "$LAST_LOG"; then fx_bad "declined run still batched"; else fx_ok; fi

# --- high-risk: opt-in + confirmation accepted ----------------------------

printf '\nz\ny\n' >"$FX_TMP/I/in5"
inst_cell 0 "high-risk confirm accepted" "$FX_TMP/I/in5"
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 z1' "$LAST_LOG"; then fx_ok; else fx_bad "high-risk batch"; cat "$LAST_LOG"; fi

# --- high-risk with --yes: bypass confirm, profile closure STILL excluded --

inst_cell 0 "yes bypass high-risk excluded" "$FX_TMP/I/in3" --yes
fx_out 'profile: full'
if grep -q '^mock install .*z1' "$LAST_LOG"; then fx_bad "closure high-risk ran under --yes"; else fx_ok; fi

# --- profile-listed high-risk is STILL never seeded (preseed filter) --------

inst_cell 0 "closure high-risk never seeded" "$FX_TMP/I/in3" --yes --profile risky
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1' "$LAST_LOG"; then fx_ok; else fx_bad "risky closure batch"; cat "$LAST_LOG"; fi
if grep -q '^mock install .*z1' "$LAST_LOG"; then fx_bad "closure high-risk seeded"; else fx_ok; fi
if [[ ! -e "$LAST_ST/modules/z" ]]; then fx_ok; else fx_bad "closure high-risk marked"; fi

# --- explicit CLI id can still reach a high-risk module under --yes --------

inst_cell 0 "yes cli high-risk explicit" "$FX_TMP/I/in3" --yes z
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 z1' "$LAST_LOG"; then fx_ok; else fx_bad "cli high-risk batch"; cat "$LAST_LOG"; fi

# --- dry-run: editable, nothing persists -----------------------------------

printf '3\n\n\n' >"$FX_TMP/I/in6"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hdry"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_MOCK_LOG="$FX_TMP/I/dry.log" FS_MOCK_INSTALLED="$FX_TMP/I/dryi"
    : >"$FX_TMP/I/dry.log"
    : >"$FX_TMP/I/dryi"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install <"$FX_TMP/I/in6"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry-run edited rc" 0
fx_out '^# would run: mock install a1 b1$'
fx_out 'profile: selection'
if grep -q '^mock install ' "$FX_TMP/I/dry.log"; then fx_bad "dry run recorded mock"; else fx_ok; fi
if [[ -e "$FX_TMP/hdry/.local/state/fedora-setup" ]]; then fx_bad "dry run created state dir"; else fx_ok; fi

# --- unknown profile -------------------------------------------------------

printf '' >"$FX_TMP/I/in7"
inst_cell 1 "unknown profile" "$FX_TMP/I/in7" --yes --profile ghost
fx_err 'list file missing or not a regular file'
if [[ ! -e "$LAST_ST/modules" ]]; then fx_ok; else fx_bad "unknown profile wrote state"; fi

# --- unknown CLI id --------------------------------------------------------

inst_cell 1 "unknown cli id" "$FX_TMP/I/in3" --yes ghostid
fx_err ': ghostid'

# --- distro-file detection (no FS_DISTRO_FAMILY) ---------------------------

printf 'ID=fedora\nID_LIKE=""\n' >"$FX_TMP/I/osrel"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hdt" FS_PKG_BACKEND=mock FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/I/osrel"
    unset FS_DISTRO_FAMILY FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes <"$FX_TMP/I/in3"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "distro-file detection rc" 0
fx_out 'profile: full'

# --- bare CLI: family resolved in-caller must reach pkg_backend ------------
# Regression (pre-fix): bootstrap resolved the family via command
# substitution (subshell), so FS_DISTRO_FAMILY never reached the caller env
# and the backend selection fell through with "no package backend selected".
# A bare run -- no FS_PKG_BACKEND, no FS_DISTRO_FAMILY -- must detect the
# family from the distro file in the caller shell and then select the real
# rpm backend through it (proven by the dnf5 dry-render, not the mock).

FBIN="$FX_TMP/I/fbin"
mkdir -p "$FBIN"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/dnf5"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/dnf"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/rpm"
chmod +x "$FBIN"/*
printf 'ID=fedora\nID_LIKE=""\n' >"$FX_TMP/I/osrel2"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hbare" FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/I/osrel2"
    export PATH="$FBIN:$PATH"
    unset FS_PKG_BACKEND FS_DISTRO_FAMILY FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare family->backend resolution rc" 0
fx_out 'profile: full'
fx_out 'module: a (none)'
fx_out 'module: b (none)'
fx_out 'module: c (none)'
fx_out '^# would run: sudo dnf5 install -y a1 b1 c1$'
fx_out '^== run complete ==$'
fx_out '3 ok'
fx_err_not 'no package backend selected'
if [[ -e "$FX_TMP/hbare/.local/state/fedora-setup" ]]; then fx_bad "bare dry run created state dir"; else fx_ok; fi

# --- empty profile (minimal skeleton) via --yes ----------------------------

(   set -euo pipefail
    export FS_HOME="$FX_TMP/hempty" FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    printf '' | "$SETUP" install --profile minimal --yes </dev/null
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile rc" 0
fx_out 'profile: minimal'
fx_out '^== run complete ==$'
fx_out '0 ok'

fx_summary