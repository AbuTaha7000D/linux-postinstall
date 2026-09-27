#!/usr/bin/env bash
# tests/fixtures/lib.sh - assertion helpers for package-backend fixtures.
# Modeled on tests/smoke.sh (battle-tested): hermetic blocks under
# set -euo pipefail, FX_BLOCK_RC captured after each ( ... ) block, and a
# gating epilogue. Every fixture ends with fx_summary as its LAST statement
# so the exit status reflects failures faithfully.
# Source this file first, then call fx_init.

FX_PASS=0
FX_FAIL=0
FX_BLOCK_RC=-1

fx_ok() {
    FX_PASS=$((FX_PASS + 1))
}

fx_bad() {
    FX_FAIL=$((FX_FAIL + 1))
    printf 'FAIL %s\n' "$1" >&2
}

fx_init() {
    FX_TMP="$(mktemp -d -- "${TMPDIR:-/tmp}/fedora-setup-pkg.XXXXXX")" || {
        printf '%s\n' "cannot create scratch dir" >&2
        exit 1
    }
    FX_OUT="$FX_TMP/out"
    FX_ERR="$FX_TMP/err"
    trap 'rm -rf -- "$FX_TMP"' EXIT
    unset -v FS_VERBOSE FS_DEBUG FS_DRY_RUN FS_YES FS_LOG_FILE FS_HOME FS_EUID \
        FS_DISTRO_FILE FS_DISTRO_PKGMGR_OVERRIDE FS_DISTRO_FAMILY \
        FS_DISTRO_SELECTED FS_DISTRO_ID FS_DISTRO_ID_LIKE FS_DISTRO_PKGMGR \
        FS_DISTRO_LOCALPKG FS_DISTRO_FLATPAK_DEFAULT FS_DISTRO_GNOME \
        FS_NO_COLOR FS_LOG_INFRA FS_PKG_BACKEND FS_MODULES_DIR \
        FS_PROFILES_DIR FS_PROFILE \
        FS_FONTS_DIR FS_NERDFONT_SRC_DIR FS_NERDFONT_CONFIG \
        FS_BASHRC FS_TERM_ALIASES FS_OMP_BIN FS_OMP_THEME FS_OMP_ARCH \
        FS_OMP_SRC_DIR FS_OMP_VERSION \
        FS_RUNNING_AS_ROOT FS_SUDO_AVAILABLE 2>/dev/null || :
}

fx_rc() {
    local want="$1" name="$2"
    shift 2
    local rc
    "$@" >"$FX_OUT" 2>"$FX_ERR"
    rc=$?
    if (( rc == want )); then
        fx_ok
    else
        fx_bad "$name (want rc $want, got rc $rc)"
        printf '  stdout:\n' >&2
        sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
        printf '  stderr:\n' >&2
        sed 's/^/    /' "$FX_ERR" >&2 2>/dev/null
    fi
}

fx_block_rc() {
    local name="$1" want="$2"
    if [[ "$FX_BLOCK_RC" =~ ^-?[0-9]+$ ]] && (( FX_BLOCK_RC == want )); then
        fx_ok
    else
        fx_bad "$name (want rc $want, got rc $FX_BLOCK_RC)"
    fi
}

fx_out() {
    local pat="$1"
    if grep -q -- "$pat" "$FX_OUT" 2>/dev/null; then
        fx_ok
    else
        fx_bad "stdout did not contain: $pat"
        printf '  stdout:\n' >&2
        sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
    fi
}

fx_out_not() {
    local pat="$1"
    if grep -q -- "$pat" "$FX_OUT" 2>/dev/null; then
        fx_bad "stdout must NOT contain: $pat"
    else
        fx_ok
    fi
}

fx_err() {
    local pat="$1"
    if grep -q -- "$pat" "$FX_ERR" 2>/dev/null; then
        fx_ok
    else
        fx_bad "stderr did not contain: $pat"
        printf '  stderr:\n' >&2
        sed 's/^/    /' "$FX_ERR" >&2 2>/dev/null
    fi
}

fx_err_not() {
    local pat="$1"
    if grep -q -- "$pat" "$FX_ERR" 2>/dev/null; then
        fx_bad "stderr must NOT contain: $pat"
    else
        fx_ok
    fi
}

fx_empty() {
    local name="$1" file="$2"
    if [[ ! -s "$file" ]]; then
        fx_ok
    else
        fx_bad "$name (expected empty, found $(wc -c <"$file") bytes)"
    fi
}

fx_summary() {
    printf 'summary: %s passed, %s failed\n' "$FX_PASS" "$FX_FAIL"
    (( FX_FAIL == 0 ))
}