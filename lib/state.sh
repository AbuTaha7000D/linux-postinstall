#!/usr/bin/env bash
# lib/state.sh - state dir, run logs, module registry, backup registry,
# and single-line notes.
# Depends on lib/io.sh for io_error (source io.sh first).
# State root: $FS_HOME (test override) > $XDG_STATE_HOME > $HOME, joined
# with /fedora-setup. Single-writer assumption: callers use one process.
#
# Two registries with different shapes, deliberately not merged:
#   - backups/registry (state_backup_add/get) records FILE copies:
#     "<src>|<backup path>|<timestamp>", one line per backup.
#   - notes/<key> (state_note/get/remove) records a single opaque
#     single-line VALUE under a validated key. It exists for the P8.1
#     "registry of changed connections": the dns module stores the prior
#     NetworkManager connection properties there so its revert can
#     restore exactly what was there before. A value must not contain a
#     newline or CR, so a record can never be mistaken for several lines;
#     the field encoding inside a value belongs to the caller.
# Every write is atomic (temp+rename) and confined by _state_chain_ok /
# _state_subdir_ok, exactly like the module and backup registries.

FS_STATE_BASE=""
FS_STATE_DIR=""

_state_valid_name() {
    local name="$1"
    case "$name" in
        "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

_state_dir_content_ok() {
    local parent="$1" sub p
    shift
    for sub in "" "$@"; do
        p="$parent"
        if [[ -n "$sub" ]]; then
            p="$parent/$sub"
        fi
        if [[ -L "$p" ]]; then
            io_error "state path is a symlink: $p"
            return 1
        fi
        if [[ -e "$p" && ! -d "$p" ]]; then
            io_error "state path exists and is not a directory: $p"
            return 1
        fi
    done
    return 0
}

_state_subdir_ok() {
    local sub p
    sub="$1"
    p="$FS_STATE_DIR/$sub"
    if [[ -L "$p" || ! -d "$p" ]]; then
        io_error "state dir not usable: $p"
        return 1
    fi
    return 0
}

_state_chain_ok() {
    local target="$1" cur="" part="" rest=""
    if [[ -z "$FS_STATE_DIR" || -z "$FS_STATE_BASE" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if [[ "$target" != "$FS_STATE_DIR" && "$target" != "$FS_STATE_DIR"/* ]]; then
        io_error "state target outside state dir: $target"
        return 1
    fi
    rest="${target#/}"
    while [[ -n "$rest" ]]; do
        part="${rest%%/*}"
        if [[ "$part" == "$rest" ]]; then
            rest=""
        else
            rest="${rest#*/}"
        fi
        cur="$cur/$part"
        if [[ -L "$cur" ]]; then
            io_error "state path component is a symlink: $cur"
            return 1
        fi
    done
    return 0
}

_state_write() {
    local file="$1" content="$2" tmp=""
    if [[ -d "$file" ]]; then
        io_error "state target is a directory: $file"
        return 1
    fi
    tmp="$(mktemp "${file}.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create temp in: ${file%/*}"
        return 1
    }
    if ! printf '%s' "$content" >"$tmp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot write temp: $tmp"
        return 1
    fi
    if ! mv -fT -- "$tmp" "$file" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot move temp into place: $file"
        return 1
    fi
    return 0
}

state_init() {
    local base dir
    FS_STATE_BASE=""
    FS_STATE_DIR=""
    if [[ -n "${FS_HOME:-}" ]]; then
        base="$FS_HOME/.local/state"
    elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
        base="$XDG_STATE_HOME"
    elif [[ -n "${HOME:-}" ]]; then
        base="$HOME/.local/state"
    else
        io_error "no state root: set FS_HOME, XDG_STATE_HOME, or HOME"
        return 1
    fi
    if ! base="$(readlink -m -- "$base" 2>/dev/null)"; then
        io_error "cannot resolve state root: $base"
        return 1
    fi
    dir="$base/fedora-setup"
    if ! _state_dir_content_ok "$dir" logs modules backups notes; then
        return 1
    fi
    if ! mkdir -p -- "$dir/logs" "$dir/modules" "$dir/backups" "$dir/notes" 2>/dev/null; then
        io_error "cannot create state dir: $dir"
        return 1
    fi
    FS_STATE_BASE="$base"
    FS_STATE_DIR="$dir"
    return 0
}

state_log() {
    local ts log
    if [[ -z "$FS_STATE_DIR" || -z "$FS_STATE_BASE" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    printf -v ts '%(%Y%m%dT%H%M%S)T' -1
    log="$FS_STATE_DIR/logs/run-$ts-$$.log"
    _state_chain_ok "$log" || return 1
    _state_subdir_ok logs || return 1
    if [[ -e "$log" && ! -f "$log" ]]; then
        io_error "log path not usable: $log"
        return 1
    fi
    printf '%s' "$log"
}

state_module_mark() {
    local name="${1:-}" ts
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if ! _state_valid_name "$name"; then
        io_error "invalid module name"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/modules" || return 1
    _state_subdir_ok modules || return 1
    printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1
    _state_write "$FS_STATE_DIR/modules/$name" "done $ts"
}

state_module_check() {
    local name="${1:-}"
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    _state_valid_name "$name" || return 1
    _state_chain_ok "$FS_STATE_DIR/modules/$name" || return 1
    _state_subdir_ok modules || return 1
    if [[ -L "$FS_STATE_DIR/modules/$name" ]]; then
        return 1
    fi
    [[ -f "$FS_STATE_DIR/modules/$name" ]]
}

state_module_unmark() {
    local name="${1:-}" rc
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if ! _state_valid_name "$name"; then
        io_error "invalid module name"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/modules" || return 1
    _state_subdir_ok modules || return 1
    rm -f -- "$FS_STATE_DIR/modules/$name" 2>/dev/null
    rc=$?
    return "$rc"
}

state_backup_add() {
    local src="${1:-}" bkp="${2:-}" ts regfile prev="" line
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if [[ -z "$src" || -z "$bkp" ]]; then
        io_error "backup_add requires source and backup paths"
        return 1
    fi
    if [[ "$src" == *[$'\n'$'\r']* || "$bkp" == *[$'\n'$'\r']* ]]; then
        io_error "backup path must not contain newlines"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/backups" || return 1
    _state_subdir_ok backups || return 1
    regfile="$FS_STATE_DIR/backups/registry"
    printf -v ts '%(%Y%m%dT%H%M%S)T' -1
    line="$src|$bkp|$ts"
    if [[ -e "$regfile" || -L "$regfile" ]]; then
        if [[ -L "$regfile" || ! -f "$regfile" ]]; then
            io_error "registry not usable: $regfile"
            return 1
        fi
        if ! prev="$(cat -- "$regfile" 2>/dev/null)"; then
            io_error "cannot read registry: $regfile"
            return 1
        fi
        if [[ -n "$prev" && "$prev" != *$'\n' ]]; then
            prev="${prev}"$'\n'
        fi
    fi
    _state_write "$regfile" "${prev}${line}"$'\n' || return 1
}

state_backup_get() {
    local src="${1:-}" regfile line
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if [[ -z "$src" ]]; then
        io_error "backup_get requires a source path"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/backups" || return 1
    _state_subdir_ok backups || return 1
    regfile="$FS_STATE_DIR/backups/registry"
    if [[ -L "$regfile" ]]; then
        io_error "registry not usable: $regfile"
        return 1
    fi
    if [[ -e "$regfile" && ! -f "$regfile" ]]; then
        io_error "registry is not a regular file: $regfile"
        return 1
    fi
    [[ -r "$regfile" ]] || return 1
    while IFS= read -r line; do
        if [[ "$line" == "$src|"* ]]; then
            printf '%s\n' "${line#*|}"
        fi
    done <"$regfile"
    return 0
}

state_note() {
    local key="${1:-}" value="${2:-}" file=""
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if ! _state_valid_name "$key"; then
        io_error "invalid state note key"
        return 1
    fi
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        io_error "state note value must be a single line"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/notes" || return 1
    _state_subdir_ok notes || return 1
    file="$FS_STATE_DIR/notes/$key"
    if [[ -L "$file" ]]; then
        io_error "state note is a symlink: $file"
        return 1
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        io_error "state note is not a regular file: $file"
        return 1
    fi
    _state_write "$file" "$value"
}

state_note_get() {
    local key="${1:-}" file=""
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if ! _state_valid_name "$key"; then
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/notes" || return 1
    _state_subdir_ok notes || return 1
    file="$FS_STATE_DIR/notes/$key"
    if [[ -L "$file" ]]; then
        io_error "state note is a symlink: $file"
        return 1
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        io_error "state note is not a regular file: $file"
        return 1
    fi
    [[ -f "$file" && -r "$file" ]] || return 1
    cat -- "$file"
}

state_note_remove() {
    local key="${1:-}" file=""
    if [[ -z "$FS_STATE_DIR" ]]; then
        io_error "state not initialized (call state_init first)"
        return 1
    fi
    if ! _state_valid_name "$key"; then
        io_error "invalid state note key"
        return 1
    fi
    _state_chain_ok "$FS_STATE_DIR/notes" || return 1
    _state_subdir_ok notes || return 1
    file="$FS_STATE_DIR/notes/$key"
    if [[ -L "$file" ]]; then
        io_error "state note is a symlink: $file"
        return 1
    fi
    rm -f -- "$file" 2>/dev/null
    return $?
}