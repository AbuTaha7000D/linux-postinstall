#!/usr/bin/env bash
# lib/sudo.sh - privilege policy for fedora-setup.
# Depends on lib/io.sh. Honors FS_DRY_RUN / FS_VERBOSE / FS_DEBUG.
# Never reads or writes /etc/sudoers. Call sudo_detect() once before
# relying on the cached policy globals (FS_RUNNING_AS_ROOT,
# FS_SUDO_AVAILABLE). FS_EUID is a test-only override of the effective
# uid used to exercise the running-as-root path. Under dry-run nothing
# is probed and nothing executes; the only stdout is a single
# '# would run:' line per call.
# Auditing contract: sudo_exec is a low-level primitive and does NOT
# tee to FS_LOG_FILE. The CLI dispatches privileged steps through
# run_sudo (lib/run.sh), which provides the FS_LOG_FILE audit trail and
# the FS_LOG_INFRA halt for broken logs.

FS_RUNNING_AS_ROOT=0
FS_SUDO_AVAILABLE=0
FS_DRY_RUN="${FS_DRY_RUN:-0}"
FS_VERBOSE="${FS_VERBOSE:-0}"
FS_DEBUG="${FS_DEBUG:-0}"

_sudo_render() {
    local a IFS=' '
    local -a parts=()
    for a in "$@"; do
        parts+=("$(printf '%q' "$a")")
    done
    printf '%s\n' "${parts[*]}"
}

sudo_detect() {
    local euid="${FS_EUID:-$EUID}"
    if ((euid == 0)); then
        FS_RUNNING_AS_ROOT=1
        FS_SUDO_AVAILABLE=0
        io_warn "running as root (euid $euid); proceeding without sudo"
        return 0
    fi
    if ((FS_DRY_RUN == 1)); then
        return 0
    fi
    FS_RUNNING_AS_ROOT=0
    FS_SUDO_AVAILABLE=0
    if ! command -v sudo >/dev/null 2>&1; then
        io_debug "sudo not present in PATH"
        return 0
    fi
    if sudo -n true >/dev/null 2>&1; then
        FS_SUDO_AVAILABLE=1
    else
        io_debug "sudo present but not usable without a password prompt"
    fi
    return 0
}

sudo_refresh() {
    if ((FS_DRY_RUN == 1)); then
        return 0
    fi
    if ((FS_RUNNING_AS_ROOT == 1)); then
        return 0
    fi
    if ((FS_SUDO_AVAILABLE != 1)); then
        io_warn "sudo unavailable; skipping credential refresh"
        return 0
    fi
    if ((FS_VERBOSE == 1)); then
        sudo -v 2>/dev/null || io_warn "sudo credential refresh failed"
    fi
    return 0
}

sudo_exec() {
    local IFS=' '
    local -a cmd=("$@")
    if ((${#cmd[@]} == 0)) || [[ -z "${cmd[0]}" ]]; then
        io_error "sudo_exec requires a command"
        return 1
    fi
    if ((FS_DRY_RUN == 1)); then
        if ((FS_RUNNING_AS_ROOT == 1)); then
            printf '# would run: %s\n' "$(_sudo_render "${cmd[@]}")"
        else
            printf '# would run: %s\n' "$(_sudo_render sudo "${cmd[@]}")"
        fi
        return 0
    fi
    if ((FS_RUNNING_AS_ROOT == 1)); then
        "${cmd[@]}" || return $?
        return 0
    fi
    if ((FS_SUDO_AVAILABLE != 1)); then
        io_error "sudo unavailable; cannot escalate: $(_sudo_render "${cmd[@]}")"
        return 1
    fi
    sudo -- "${cmd[@]}" || return $?
    return 0
}
