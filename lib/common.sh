#!/usr/bin/env bash
# lib/common.sh - logging, command execution, sudo, dry-run.
#
# Every command that changes the system goes through run() or run_root().
# Both refuse to continue when the command fails: a failed install must never
# be reported as a successful setup. FS_DRY_RUN=1 turns them into print-only.
#
# Sourced by setup; not executable on its own.

FS_ROOT="${FS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
FS_DRY_RUN="${FS_DRY_RUN:-0}"

case "$FS_DRY_RUN" in 0 | 1) ;; *) printf 'error: FS_DRY_RUN must be 0 or 1\n' >&2; exit 1 ;; esac

_ts() { printf '[%s]' "$(date +%H:%M:%S)"; }

log_info() { printf '%s %s\n' "$(_ts)" "$*"; }
log_warn() { printf '%s WARNING: %s\n' "$(_ts)" "$*" >&2; }
log_error() { printf '%s ERROR: %s\n' "$(_ts)" "$*" >&2; }

die() {
    log_error "$*"
    exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

_shown() {
    local out="" a
    for a in "$@"; do
        printf -v a '%q' "$a"
        out+="$a "
    done
    printf '%s' "${out% }"
}

# run <label> <cmd...> -- run a command; die unless it exits 0.
run() {
    local label="$1"
    shift
    if ((FS_DRY_RUN)); then
        log_info "would $label: $(_shown "$@")"
        return 0
    fi
    log_info "$label: $(_shown "$@")"
    "$@" || die "$label failed: $(_shown "$@")"
}

# run_root <label> <cmd...> -- run a command as root.
# Prompts for a password if sudo wants one. Dry-run never calls sudo.
run_root() {
    local label="$1"
    shift
    if ((FS_DRY_RUN)); then
        log_info "would $label: sudo $(_shown "$@")"
        return 0
    fi
    if ((EUID == 0)); then
        run "$label" "$@"
        return
    fi
    have sudo || die "$label needs root privileges and sudo is not installed"
    log_info "$label: sudo $(_shown "$@")"
    sudo "$@" || die "$label failed: sudo $(_shown "$@")"
}

# read_list <file> -- print the non-blank, non-comment lines of a config file.
#
# Trailing whitespace is trimmed. Leading whitespace is kept, because some of
# these files are fed to programs that care about indentation (gitconfig).
# Indented comments and indented blank lines are still skipped.
read_list() {
    local file="$1" line trimmed
    [[ -f "$file" ]] || die "config file not found: $file"
    [[ -r "$file" ]] || die "config file not readable: $file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" || "$trimmed" == '#'* ]] && continue
        printf '%s\n' "${line%"${line##*[![:space:]]}"}"
    done <"$file"
}

# write_atomic <file> -- replace the file with stdin, via a temp file + rename.
write_atomic() {
    local file="$1" dir tmp

    if ((FS_DRY_RUN)); then
        log_info "would write: $file"
        return 0
    fi
    dir="$(dirname -- "$file")"
    run "create dir" mkdir -p -- "$dir"
    tmp="$(mktemp -- "$dir/.postinstall.XXXXXX")" || die "cannot create temp file in $dir"
    cat >"$tmp" || {
        rm -f -- "$tmp"
        die "cannot write $tmp"
    }
    chmod 0644 "$tmp"
    mv -f -- "$tmp" "$file" || {
        rm -f -- "$tmp"
        die "cannot replace $file"
    }
}
