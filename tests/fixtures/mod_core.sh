#!/usr/bin/env bash
# tests/fixtures/mod_core.sh - P5.1 fixture for the `core` base module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`
# with hermetic seams (FS_HOME scratch, mock backend, FS_DISTRO_FAMILY).
# Covers: module metadata validation across all three families; the
# CLI-id form `setup install core --yes --dry-run` rendering EXACTLY one
# batched install line per family with the curated package merge (family
# overrides first, then common; no gnupg on rpm -- gnupg2 instead; no
# fastfetch on deb); real-mode mock run recording the same batch and the
# per-family entries landing in the mock installed set; registry marks;
# `setup list` showing the core row. Nothing outside FX_TMP + the real
# repo modules/profiles is touched; downloads never happen.
# Usage: bash tests/fixtures/mod_core.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h"

printf 'P5.1 core module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/core.log"
INST="$FX_TMP/I/core.inst"

core_cell() {
    local want_family="$1" want_batch="$2" label="$3"
    : >"$LOG"
    : >"$INST"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes core
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out "^# would run: mock install $want_batch\$"
    # exactly ONE batched install line
    if grep -q '^# would run: mock install ' "$FX_OUT"; then
        local n
        n="$(grep -c '^# would run: mock install ' "$FX_OUT")"
        if (( n == 1 )); then fx_ok; else fx_bad "$label single batch (got $n)"; fi
    fi
}

# rpm merge: family file entries first, then common (no gnupg in common)
core_cell rpm 'gnupg2 fastfetch git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak' "core dry-run rpm"

# deb merge: gnupg first, no fastfetch
core_cell deb 'gnupg git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak' "core dry-run deb"

# arch merge
core_cell arch 'gnupg fastfetch git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak' "core dry-run arch"

# dry-run purity (checked here, while $LOG still holds the last dry cell):
# no state dir created, no mock writes.
if [[ -e "$FX_TMP/h/.local/state/fedora-setup" ]]; then fx_bad "dry-run created state dir"; else fx_ok; fi
fx_empty "dry-run recorded nothing" "$LOG"

# real-mode mock run: same batch executed, packages land in the mock
# installed set, module marked done.
: >"$LOG"
: >"$INST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes core
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "core real-mode mock rc" 0
fx_out 'profile: selection'
fx_out 'module: core (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
if grep -qxF 'mock install gnupg2 fastfetch git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak' "$LOG"; then fx_ok; else fx_bad "core real batch"; cat "$LOG"; fi
for pkg in gnupg2 fastfetch git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak; do
    if grep -qxF "$pkg" "$INST"; then fx_ok; else fx_bad "mock installed missing $pkg"; fi
done
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/core" ]]; then fx_ok; else fx_bad "core not marked done"; fi

# module metadata sanity via the real launcher's list command (hermetic
# FS_HOME + FS_DISTRO_FAMILY, matching the modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^core\b' "$FX_OUT"; then fx_ok; else fx_bad "core row missing from list"; fi
if [[ ! -e "$FX_TMP/hlist/.local/state/fedora-setup" ]]; then
    fx_bad "list did not initialize state (state_init expected)"
else
    fx_ok
fi

fx_summary