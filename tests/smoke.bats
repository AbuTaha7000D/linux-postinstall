#!/usr/bin/env bats
# tests/smoke.bats - Bats suite converted from tests/smoke.sh (P10.1).
# Each @test wraps one smoke_* function from helpers.bash and asserts it
# reported zero failures. Run via `tests/run` (or `bats tests/smoke.bats`).

load helpers

setup() {
    # Bats runs each test with `set -e` (errexit). The smoke_* helpers use the
    # capture-failure pattern (`cmd >out 2>err; rc=$?`), which errexit breaks:
    # a command expected to fail would exit the test before rc is captured.
    set +e
    _this="${BATS_TEST_FILENAME}"
    if [[ -z "$_this" ]]; then
        printf '%s\n' "cannot resolve tests/smoke.bats" >&2
        return 1
    fi
    _this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
    ROOT="$(cd "$(dirname "$_this")/.." && pwd)"
    if [[ ! -x "$ROOT/setup" ]]; then
        printf '%s\n' "repo root not found (expected $ROOT/setup)" >&2
        return 1
    fi

    TMP="$(mktemp -d -- "${TMPDIR:-/tmp}/fedora-setup-smoke.XXXXXX")" || {
        printf '%s\n' "cannot create scratch dir" >&2
        return 1
    }
    OUT="$TMP/out" ERR="$TMP/err"
    export TMPDIR="$TMP"

    unset -v FS_VERBOSE FS_DEBUG FS_DRY_RUN FS_YES FS_LOG_FILE FS_HOME FS_EUID \
        FS_DISTRO_FILE FS_RUNNING_AS_ROOT FS_SUDO_AVAILABLE FS_GNOME_BROWSE \
        FS_GNOME_COMPAT_FILE FS_GNOME_FORCE FS_THEME_NAME FS_THEME_SRC FS_THEME_ASSETS_DIR \
        FS_CURSOR_NAME FS_CURSOR_SRC FS_CURSOR_ASSETS_DIR FS_GTK_BOOKMARKS_FILE \
        FS_STATE_DIR SSH_CONNECTION SSH_CLIENT SSH_TTY DISPLAY WAYLAND_DISPLAY \
        XDG_CURRENT_DESKTOP FS_DNS_CONNECTION FS_DNS_SERVERS FS_DNS_REVERT \
        FS_DNS_REACTIVATE FS_DNS_CHECK_HOST FS_DNS_RESOLVE_ATTEMPTS \
        2>/dev/null || :

    pass=0
    fail=0
    block_rc_last=-1
}

teardown() {
    rm -rf -- "$TMP"
}

@test "P2.1 io" {
    smoke_io
    [ "$fail" -eq 0 ]
}

@test "P2.2 cli" {
    smoke_cli
    [ "$fail" -eq 0 ]
}

@test "P2.3 distro" {
    smoke_distro
    [ "$fail" -eq 0 ]
}

@test "P2.4 state" {
    smoke_state
    [ "$fail" -eq 0 ]
}

@test "P2.5 fs" {
    smoke_fs
    [ "$fail" -eq 0 ]
}

@test "P2.5b fs_dedupe" {
    smoke_fs_dedupe
    [ "$fail" -eq 0 ]
}

@test "P2.6 sudo" {
    smoke_sudo
    [ "$fail" -eq 0 ]
}

@test "P2.7 run" {
    smoke_run
    [ "$fail" -eq 0 ]
}

@test "P2.8 entry" {
    smoke_entry
    [ "$fail" -eq 0 ]
}

@test "P9.2 verify" {
    smoke_verify
    [ "$fail" -eq 0 ]
}

@test "P9.3 export" {
    smoke_export
    [ "$fail" -eq 0 ]
}
