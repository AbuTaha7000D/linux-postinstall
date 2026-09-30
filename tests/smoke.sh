#!/usr/bin/env bash
# tests/smoke.sh - plain-bash smoke suite for fedora-setup core libs (P2.1-P2.8).
# Usage: bash tests/smoke.sh   (exit 0 on success, non-zero on any regression)

# Root resolution: works from any CWD.
_this="${BASH_SOURCE[0]}"
if [[ -z "$_this" ]]; then
    printf '%s\n' "cannot resolve tests/smoke.sh" >&2
    exit 1
fi
_this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
ROOT="$(cd "$(dirname "$_this")/.." && pwd)"
if [[ ! -x "$ROOT/setup" ]]; then
    printf '%s\n' "repo root not found (expected $ROOT/setup)" >&2
    exit 1
fi

TMP="$(mktemp -d -- "${TMPDIR:-/tmp}/fedora-setup-smoke.XXXXXX")" || {
    printf '%s\n' "cannot create scratch dir" >&2
    exit 1
}
OUT="$TMP/out" ERR="$TMP/err"
export TMPDIR="$TMP"
trap 'rm -rf -- "$TMP"' EXIT

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

ok() {
    pass=$((pass + 1))
}
bad() {
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$1" >&2
}

t_rc() {
    local want="$1" name="$2"
    shift 2
    local rc
    "$@" >"$OUT" 2>"$ERR"
    rc=$?
    if (( rc == want )); then
        ok
    else
        bad "$name (want rc $want, got rc $rc)"
        printf '  stdout:\n' >&2
        sed 's/^/    /' "$OUT" >&2 2>/dev/null
        printf '  stderr:\n' >&2
        sed 's/^/    /' "$ERR" >&2 2>/dev/null
    fi
}

t_out() {
    local pat="$1"
    if grep -q -- "$pat" "$OUT" 2>/dev/null; then
        ok
    else
        bad "stdout did not contain: $pat"
        printf '  stdout:\n' >&2
        sed 's/^/    /' "$OUT" >&2 2>/dev/null
    fi
}

t_out_not() {
    local pat="$1"
    if grep -q -- "$pat" "$OUT" 2>/dev/null; then
        bad "stdout must NOT contain: $pat"
    else
        ok
    fi
}

t_err() {
    local pat="$1"
    if grep -q -- "$pat" "$ERR" 2>/dev/null; then
        ok
    else
        bad "stderr did not contain: $pat"
        printf '  stderr:\n' >&2
        sed 's/^/    /' "$ERR" >&2 2>/dev/null
    fi
}

t_err_not() {
    local pat="$1"
    if grep -q -- "$pat" "$ERR" 2>/dev/null; then
        bad "stderr must NOT contain: $pat"
    else
        ok
    fi
}

# Assert the exit code of the most recent `( ... )` block, which ran with
# `set -euo pipefail` inside. No redirection: preserves $OUT/$ERR for the
# t_out/t_err assertions that follow.
t_block_rc() {
    local name="$1" want="$2"
    if [[ "$block_rc_last" =~ ^-?[0-9]+$ ]] && (( block_rc_last == want )); then
        ok
    else
        bad "$name (want rc $want, got rc $block_rc_last)"
    fi
}

t_empty() {
    local name="$1" file="$2"
    if [[ ! -s "$file" ]]; then
        ok
    else
        bad "$name (expected empty, found $(wc -c <"$file") bytes)"
    fi
}

printf 'P2.1 io\n'
smoke_io() {
    local log="$TMP/io.log"
    (
        set -euo pipefail
        FS_LOG_FILE="$log"
        . "$ROOT/lib/io.sh"
        io_init "$log"
        io_info "hello from smoke"
        io_debug "debug noise"
        io_progress 1 2 "installing"
        io_progress_end
        io_summary
        io_summary "done" "label"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "io block" 0
    t_out "hello from smoke"
    t_out_not "debug noise"
    t_out '^== done ==$'
    t_rc 0 "io_init write log" test -f "$log"
    t_rc 0 "log contains info" grep -q "hello from smoke" "$log"
}
smoke_io

printf 'P2.2 cli\n'
smoke_cli() {
    cli_one() {
        local args
        (
            set -euo pipefail
            unset -v FS_VERBOSE FS_DEBUG FS_DRY_RUN FS_YES 2>/dev/null || :
            . "$ROOT/lib/io.sh"
            . "$ROOT/lib/cli.sh"
            cli_parse "$@"
            printf 'cmd=%s yes=%s dry=%s verbose=%s debug=%s list=%s profile=%s browse=%s force=%s args=%s\n' \
                "${FS_CMD:-}" "$FS_YES" "$FS_DRY_RUN" "$FS_VERBOSE" "$FS_DEBUG" \
                "$FS_LIST" "${FS_PROFILE:-}" "$FS_GNOME_BROWSE" "$FS_GNOME_FORCE" "${FS_CMD_ARGS[*]:-}"
        )
    }
    t_rc 0 "bare help default" cli_one
    t_out "cmd=help"
    t_rc 0 "explicit command" cli_one install foo
    t_out "cmd=install yes=0.*args=foo"
    t_rc 0 "list alias" cli_one --list
    t_out "cmd=list"
    t_rc 0 "flags" cli_one --yes --dry-run check
    t_out "yes=1 dry=1"
    t_rc 0 "browse flag" cli_one --browse install
    t_out "cmd=install.*browse=1"
    t_rc 0 "force flag" cli_one --force install
    t_out "cmd=install.*force=1"
    (
        set -euo pipefail
        export FS_GNOME_FORCE=1
        cli_one install
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "force env seam block" 0
    t_out "force=1"
    t_rc 0 "profile value" cli_one --profile smoke install
    t_out "cmd=install.*profile=smoke"
    t_rc 0 "verbose flag" cli_one --verbose check
    t_out "cmd=check.*verbose=1"
    t_rc 0 "end of options" cli_one install -- --weird
    t_out "cmd=install.*args=--weird"
    t_rc 1 "unknown command" cli_one bogus
    t_err "unknown command"
    t_rc 1 "flag requires value" cli_one --profile
    t_err "requires a value"
}
smoke_cli

printf 'P2.3 distro\n'
smoke_distro() {
    local fixture="$TMP/os-release"
    printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora Linux 41 (Workstation)"\n' >"$fixture"
    (
        set -euo pipefail
        export FS_DISTRO_PKGMGR_OVERRIDE=dnf5
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/distro.sh"
        distro_detect "$fixture"
        printf 'fam=%s id=%s pkg=%s localpkg=%s gnome=%s flatpak=%s\n' \
            "$FS_DISTRO_FAMILY" "$FS_DISTRO_ID" "$FS_DISTRO_PKGMGR" \
            "$FS_DISTRO_LOCALPKG" "$FS_DISTRO_GNOME" "$FS_DISTRO_FLATPAK_DEFAULT"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "distro fedora block" 0
    t_out "^fam=rpm id=fedora pkg=dnf5 localpkg=dnf5 localinstall gnome=1 flatpak=flathub\$"
    (
        set -euo pipefail
        export FS_DISTRO_PKGMGR_OVERRIDE=apotest
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/distro.sh"
        distro_detect "$fixture"
        printf 'pkg=%s\n' "$FS_DISTRO_PKGMGR"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "distro pkgmgr override block" 0
    t_out "^pkg=apotest\$"
    printf 'ID=unknownos\n' >"$TMP/os-unknown"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/distro.sh"
        distro_detect "$TMP/os-unknown"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "distro unsupported block" 1
    t_err "unsupported distro"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/distro.sh"
        distro_detect "/nonexistent/os-release"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "distro missing-file block" 1
    t_err "cannot read distro file"
    printf 'NAME="Bare"\n' >"$TMP/os-noid"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/distro.sh"
        distro_detect "$TMP/os-noid"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "distro no-ID block" 1
    t_err "has no ID"
}
smoke_distro

printf 'P2.4 state\n'
smoke_state() {
    (
        set -euo pipefail
        export FS_HOME="$TMP/home"
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/state.sh"
        state_init
        [[ "$FS_STATE_DIR" == "$TMP/home/.local/state/fedora-setup" ]]
        state_log >/dev/null
        state_module_mark "networking"
        state_module_check "networking"
        state_module_mark "graphics"
        state_module_unmark "graphics"
        state_module_check "graphics" || true
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "state block" 0
    t_rc 0 "module marker persisted" test -f "$TMP/home/.local/state/fedora-setup/modules/networking"
    t_rc 0 "unmarked module removed" test ! -e "$TMP/home/.local/state/fedora-setup/modules/graphics"
    (
        set -euo pipefail
        export FS_HOME="$TMP/home"
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/state.sh"
        state_init
        rm -rf -- "$FS_STATE_DIR/modules"
        mkdir -p -- "$TMP/mods-real"
        ln -s -- "$TMP/mods-real" "$FS_STATE_DIR/modules"
        if state_module_mark "evil"; then
            rm -f -- "$FS_STATE_DIR/modules"
            rmdir -- "$TMP/mods-real" 2>/dev/null || :
            exit 0
        fi
        rm -f -- "$FS_STATE_DIR/modules"
        rmdir -- "$TMP/mods-real" 2>/dev/null || :
        exit 1
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "state symlink guard block aborts" 1
    t_rc 0 "no marker through symlink target" test ! -e "$TMP/mods-real/evil"
}
smoke_state

printf 'P2.5 fs\n'
smoke_fs() {
    local target="$TMP/home/dotfile" src="$TMP/src"
    printf 'line one\n' >"$src"
    (
        set -euo pipefail
        export FS_HOME="$TMP/home"
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/state.sh"
        . "$ROOT/lib/fs.sh"
        state_init
        fs_install "$src" "$target"
        [[ -f "$target" ]]
        fs_managed_block "$target" "smokeblock" 'echo "managed line"'
        grep -q -- '# BEGIN fedora-setup smokeblock' "$target"
        grep -q -- 'echo "managed line"' "$target"
        grep -q -- '# END fedora-setup smokeblock' "$target"
        fs_managed_block "$target" "smokeblock" 'echo "managed line updated"'
        grep -q -- 'echo "managed line updated"' "$target"
        grep -q -- 'echo "managed line"' "$target" && exit 9
        fs_managed_block_remove "$target" "smokeblock"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "fs block" 0
    t_rc 0 "block removed leaves content" grep -q "line one" "$target"
    t_rc 1 "block gone" grep -q "smokeblock" "$target"
    t_rc 0 "no block markers after remove" test "$(grep -c '# BEGIN fedora-setup' "$target")" -eq 0
}
smoke_fs

printf 'P2.5b fs_dedupe_lines (P6.4)\n'
smoke_fs_dedupe() {
    local f="$TMP/home/dedupe.txt" g="$TMP/home/dedupe_blank.txt" h="$TMP/home/dedupe_nl.txt"
    printf 'x\ny\nx\nz\nx\n' >"$f"
    printf 'x\ny\nz\n' >"$TMP/home/dedupe_expected.txt"
    (
        set -euo pipefail
        export FS_HOME="$TMP/home"
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/state.sh"
        . "$ROOT/lib/fs.sh"
        state_init
        printf 'dedupe_count:%s\n' "$(fs_dedupe_lines "$f")"
        printf 'blank_count:%s\n' "$(printf 'a\n\na\n' >"$g"; fs_dedupe_lines "$g")"
        printf '\n' >"$h"
        cp "$h" "$TMP/home/dedupe_nl_copy.txt"
        printf 'nl_count:%s\n' "$(fs_dedupe_lines "$h")"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "dedupe block" 0
    t_out "dedupe_count:2"
    t_out "blank_count:1"
    t_out "nl_count:0"
    t_err_not "bad array subscript"
    t_rc 0 "first-seen order kept" cmp -s "$f" "$TMP/home/dedupe_expected.txt"
    t_rc 0 "blank line kept once" cmp -s "$g" <(printf 'a\n\n')
    t_rc 0 "newline-only file untouched" cmp -s "$h" "$TMP/home/dedupe_nl_copy.txt"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/fs.sh"
        rc=0
        fs_dedupe_lines "$f" || rc=$?
        printf 'no_state:%s\n' "$rc"
        exit 0
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "no-state block" 0
    t_out "no_state:1"
    t_err "requires initialized state"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/fs.sh"
        rc=0
        fs_dedupe_lines "$TMP/../x" || rc=$?
        printf 'dotdot:%s\n' "$rc"
        exit 0
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "dotdot block" 0
    t_out "dotdot:1"
    t_err "invalid dedupe target"
}
smoke_fs_dedupe

printf 'P2.6 sudo\n'
smoke_sudo() {
    local bindir="$TMP/bin" suff="$TMP/fake.log"
    mkdir -p -- "$bindir"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$FAKE_LOG"\nif [[ "${1:-}" == "-n" && "${2:-}" == "true" ]]; then exit 0; fi\nshift 1\nif [[ "${1:-}" == "--" ]]; then shift 1; fi\nexec "$@"\n' \
        >"$bindir/sudo"
    chmod +x "$bindir/sudo"
    (
        set -euo pipefail
        export PATH="$bindir:$PATH" FAKE_LOG="$suff" FS_EUID=1000
        unset -v FS_SUDO_AVAILABLE FS_RUNNING_AS_ROOT 2>/dev/null || :
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        sudo_detect
        printf 'avail=%s\n' "$FS_SUDO_AVAILABLE"
        sudo_exec touch "$TMP/probe-marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "sudo detect/exec block" 0
    t_out "avail=1"
    t_rc 0 "probe via fake sudo" grep -q -- "-n true" "$suff"
    t_rc 0 "real exec escalated with -- barrier" grep -q -- "-- touch" "$suff"
    t_rc 0 "simulated privileged command ran" test -f "$TMP/probe-marker"
    local probe_before probe_after
    probe_before="$(wc -l <"$suff")"
    (
        set -euo pipefail
        export PATH="$bindir:$PATH" FAKE_LOG="$suff" FS_EUID=1000 FS_DRY_RUN=1 FS_VERBOSE=0 FS_DEBUG=0 FS_RUNNING_AS_ROOT=0
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        FS_SUDO_AVAILABLE=1
        sudo_detect
        printf 'avail2=%s line=%s\n' "$FS_SUDO_AVAILABLE" "$(wc -l <"$suff")"
        sudo_exec touch "$TMP/dry-marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "sudo dry block" 0
    t_out "avail2=1"
    t_out "line=${probe_before}\$"
    t_out "# would run: sudo touch"
    t_rc 0 "dry sudo left no marker" test ! -f "$TMP/dry-marker"
    probe_after="$(wc -l <"$suff")"
    t_rc 0 "dry sudo never probed nor ran" test "$probe_after" -eq "$probe_before"
    (
        set -euo pipefail
        export PATH="$bindir:$PATH" FAKE_LOG="$suff" FS_EUID=0 FS_DRY_RUN=1 FS_VERBOSE=0 FS_DEBUG=0 FS_RUNNING_AS_ROOT=1 FS_SUDO_AVAILABLE=0
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        sudo_detect
        sudo_exec printf 'rootshell\n'
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "sudo root dry block" 0
    t_out "rootshell"
    t_out "# would run: printf rootshell"
    (
        set -euo pipefail
        export PATH="/usr/bin:/bin" FS_EUID=1000 FS_RUNNING_AS_ROOT=0 FS_DRY_RUN=0 FS_VERBOSE=0 FS_DEBUG=0 FS_SUDO_AVAILABLE=0
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        sudo_exec true
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "sudo unavailable real block aborts" 1
    t_err "sudo unavailable"
}
smoke_sudo

printf 'P2.7 run\n'
smoke_run() {
    local marker="$TMP/ran.txt" log="$TMP/audit.log"
    rm -f -- "$marker" "$log"
    : >"$log"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_DRY_RUN=1 run_cmd "dry one" -- sh -c "printf x >>'$marker'"
        FS_DRY_RUN=1 run_cmd "dry two" -- sh -c "printf y >>'$marker'"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run dry block" 0
    t_out '^# would run: sh -c printf'
    t_out 'printf\\ x'
    t_out 'printf\\ y'
    t_rc 0 "dry runs leave no marker" test ! -e "$marker"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_LOG_FILE="$log" run_cmd "fail softly" -- sh -c "exit 3"
        run_cmd "after fail" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_err "command failed"
    t_block_rc "run keep-going block" 0
    t_rc 0 "keep-going runs the next step" test -f "$marker"
    rm -f -- "$marker"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_LOG_FILE="$log" run_cmd "stop now" --stop -- sh -c "exit 3"
        run_cmd "must not run" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run stop block aborts" 1
    t_rc 0 "--stop halts with clean marker" test ! -f "$marker"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_LOG_FILE="$log" run_cmd "[DESTROY] wipe" -- sh -c "exit 3"
        run_cmd "must not run" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run destroy block aborts" 1
    t_rc 0 "[DESTROY] halts with clean marker" test ! -f "$marker"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_LOG_FILE="$log" run_cmd "clean label" -- sh -c 'printf "[DESTROY]"'
        run_cmd "still runs" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run content-only destroy keeps going" 0
    t_rc 0 "label gating confirmed" test -f "$marker"
    rm -f -- "$marker"
    (
        set -euo pipefail
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/run.sh"
        FS_LOG_FILE="$TMP/nowhere/x.log" run_cmd "broken" -- sh -c "printf y >>'$marker'"
        run_cmd "also broken" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run unusable-log block aborts" 1
    t_rc 0 "unusable log leaves no side effect" test ! -f "$marker"
    (
        set -euo pipefail
        export PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/fake.log" FS_RUNNING_AS_ROOT=0 FS_SUDO_AVAILABLE=1
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        . "$ROOT/lib/run.sh"
        FS_DRY_RUN=1 run_sudo "priv dry" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run_sudo dry block" 0
    t_out '# would run: sudo touch'
    t_rc 0 "run_sudo dry-run leaves no marker" test ! -f "$marker"
    (
        set -euo pipefail
        export PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/fake.log" FS_SUDO_AVAILABLE=0
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/sudo.sh"
        . "$ROOT/lib/run.sh"
        FS_RUNNING_AS_ROOT=1
        : >"$TMP/fake.log"
        run_sudo "as root" -- touch "$marker"
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "run_sudo root direct block" 0
    t_rc 0 "root path runs without sudo" test -f "$marker"
    t_rc 0 "fake sudo untouched in root path" test "$(wc -l <"$TMP/fake.log")" -eq 0
}
smoke_run

printf 'P2.8 entry\n'
smoke_entry() {
    t_rc 0 "version rc" "$ROOT/setup" version
    t_out "fedora-setup 0.1.0-dev"
    t_rc 0 "help rc" "$ROOT/setup" --help
    t_out "Usage:"
    t_rc 0 "positional help rc" "$ROOT/setup" help
    t_rc 0 "check rc" env FS_HOME="$TMP/checkh" FS_PKG_BACKEND=mock FS_EUID=0 "$ROOT/setup" check
    t_out "== preflight check =="
    t_out "PASS distro:"
    t_out "preflight OK"
    t_rc 0 "list rc" env FS_HOME="$TMP/listh" FS_DISTRO_FAMILY=rpm "$ROOT/setup" list
    if grep -q '^core\b' "$OUT" 2>/dev/null; then ok; else bad "list shows core module"; fi
    t_rc 0 "--list alias rc" env FS_HOME="$TMP/listh" FS_DISTRO_FAMILY=rpm "$ROOT/setup" --list
    if grep -q '^core\b' "$OUT" 2>/dev/null; then ok; else bad "--list shows core module"; fi
    t_rc 1 "unknown command rc" "$ROOT/setup" bogus
    t_err "unknown command"
    # P9.4: `update` is implemented. Asserted through --dry-run so this suite
    # never reaches the network: the dry run reports the version and RENDERS the
    # fetch instead of running it, which is the whole promise worth pinning here.
    # The state matrix needs real repositories and lives in
    # tests/fixtures/update.sh; what matters here is that the command dispatches
    # into lib/update.sh rather than the old stub.
    t_rc 0 "update dry-run rc" env FS_HOME="$TMP/uph" "$ROOT/setup" update --dry-run
    t_out "update: fedora-setup "
    t_out "^# would run: git -C "
    t_out "were NOT performed"
    if grep -q "not implemented yet" "$OUT" "$ERR" 2>/dev/null; then
        bad "update is still the not-implemented stub"
    else
        ok
    fi
    t_rc 1 "--pull outside update rc" "$ROOT/setup" check --pull
    t_err "only valid with the 'update' command"
    t_rc 0 "help rc" "$ROOT/setup" help
    t_out "^  update    "
    t_out "^  --pull"
    t_rc 0 "install dry-run empty repo rc" env FS_HOME="$TMP/ihome" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm "$ROOT/setup" install --dry-run --yes
    t_out "profile: full"
    t_out "^== run complete ==$"
    t_out "^  - 0 modules ok · 0 skipped · 0 failed ·"
    (
        cd -- "$TMP" || exit 1
        out="$("$ROOT/setup" version 2>&1)"
        [[ "$out" == 'fedora-setup 0.1.0-dev' ]]
    ) >"$OUT" 2>"$ERR"
    block_rc_last=$?
    t_block_rc "runs from other CWD with correct output" 0
}
smoke_verify() {
    : >"$TMP/empty-installed"
    printf 'wget\nvim\n' >"$TMP/installed-core"
    t_rc 1 "verify FAIL rc" env FS_HOME="$TMP/vh" FS_PKG_BACKEND=mock \
        FS_MOCK_INSTALLED="$TMP/empty-installed" FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" verify core
    t_out "== verify =="
    t_out "FAIL core:packages: missing: gnupg2"
    t_out "WARN core:hook: module has no verify() hook"
    t_out "verify FAILED"
    (
        set +e
        . "$ROOT/lib/io.sh"
        . "$ROOT/lib/lists.sh"
        . "$ROOT/lib/distro.sh"
        list_packages "$ROOT/modules/core" rpm
    ) >"$TMP/installed-core" 2>/dev/null
    t_block_rc "seed core installed set" 0
    t_rc 0 "verify PASS rc" env FS_HOME="$TMP/vh" FS_PKG_BACKEND=mock \
        FS_MOCK_INSTALLED="$TMP/installed-core" FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" verify core
    t_out "PASS core:packages: all "
    t_out "verify OK with warnings"
    t_rc 1 "verify unknown module rc" env FS_HOME="$TMP/vh" FS_PKG_BACKEND=mock \
        FS_DISTRO_FAMILY=rpm "$ROOT/setup" verify nosuchmodule
    t_err "module not found: nosuchmodule"
    t_rc 1 "verify invalid id rc" env FS_HOME="$TMP/vh" FS_PKG_BACKEND=mock \
        FS_DISTRO_FAMILY=rpm "$ROOT/setup" verify 'bad id!'
    t_err "invalid module id: bad id!"
}
smoke_export() {
    local tree="$TMP/xtree"
    rm -rf -- "$tree"
    mkdir -p "$TMP/xhome"
    t_rc 1 "export with no outdir rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm "$ROOT/setup" export
    t_err "export requires an output directory"
    t_rc 0 "export minimal rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" export "$tree" --profile minimal
    t_out "export: 2 module(s) for profile 'minimal'"
    t_block_rc "export wrote export.meta" 0
    (
        set +e
        grep -qx 'profile=minimal' "$tree/export.meta"
    ) >"$OUT" 2>"$ERR"
    t_block_rc "export.meta records the profile" 0
    t_block_rc "export wrote the profile conf" 0
    (
        set +e
        [[ -f "$tree/minimal.conf" ]]
    ) >"$OUT" 2>"$ERR"
    t_block_rc "minimal.conf exists" 0
    t_block_rc "export wrote a manifest per module" 0
    (
        set +e
        [[ -f "$tree/manifests/core.list" && -f "$tree/manifests/flatpak.flatpaks.list" ]]
    ) >"$OUT" 2>"$ERR"
    t_block_rc "manifests exist" 0
    t_rc 1 "export refuses a non-empty foreign dir rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" export "$TMP" --profile minimal
    t_err "refusing to write into a non-empty directory"
    t_rc 0 "export dry-run rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" export --dry-run "$TMP/never" --profile minimal
    t_out "export (dry run)"
    t_out "nothing was written"
    t_block_rc "a dry run created nothing" 0
    (
        set +e
        [[ ! -e "$TMP/never" ]]
    ) >"$OUT" 2>"$ERR"
    t_block_rc "no tree from a dry run" 0
    t_rc 0 "re-import rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" install --dry-run --yes --manifest "$tree"
    t_out "re-importing the exported tree"
    t_out "profile: minimal"
    t_out "^# would run: mock install"
    t_rc 1 "re-import of a bad tree rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" install --dry-run --yes --manifest "$TMP"
    t_err "not an export tree"
    t_rc 1 "re-import of a missing tree rc" env HOME="$TMP/xhome" FS_HOME="$TMP/xh" \
        FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
        "$ROOT/setup" install --dry-run --yes --manifest "$TMP/nosuchtree"
    t_err "manifest directory not found"
}
smoke_entry
smoke_verify
smoke_export
printf 'summary: %s passed, %s failed\n' "$pass" "$fail"
(( fail == 0 ))