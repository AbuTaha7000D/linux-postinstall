#!/usr/bin/env bash
# lib/sudo.sh - privilege policy for fedora-setup.
# Depends on lib/io.sh. Honors FS_DRY_RUN / FS_VERBOSE / FS_DEBUG.
# Never reads or writes /etc/sudoers.
#
# POLICY GLOBALS. Call sudo_detect() once before relying on them. There
# are three states, not two, because "sudo is absent" and "sudo needs a
# password" demand opposite handling:
#   FS_RUNNING_AS_ROOT=1  euid 0; commands run directly, sudo unused.
#   FS_SUDO_AVAILABLE=1   sudo can be used to escalate. This is 1 for
#                         BOTH passwordless sudo and password-required
#                         sudo: the second one still works, it prompts.
#   FS_SUDO_PASSWORD=1    sudo is present but `sudo -n true` failed, so
#                         escalation needs an interactive password.
# A host with no sudo at all leaves both flags at 0 and every escalation
# refuses to run, unchanged and fail closed.
#
# DETECTION IS NEVER A PROMPT. sudo_detect probes with `sudo -n` only,
# which cannot block on a password, so it is safe on any path - including
# `check`, which must never hang. The interactive half is sudo_refresh,
# which runs `sudo -v`; lib/runner.sh calls it once, after detection and
# before any privileged work, so one password entry serves the run. That
# call is CONDITIONED on the resolved plan actually being able to escalate
# (see the PRIVILEGE STAGE in lib/runner.sh): a selection with no
# system-namespace packages and no module declaring MODULE_PRIVILEGED=1
# provably cannot escalate, so it must not be made to authenticate for work
# it will never do.
# sudo_refresh is a no-op when root, when there is no sudo to refresh, or
# in a dry run, and returns 1 - after an io_error - when a refresh that
# was actually needed fails. A credential that cannot be established is
# an error, never a silent success.
#
# DRY RUN probes nothing at all: sudo_detect performs only the euid test
# before its dry-run early return, so a root dry run renders exactly what
# a root real run executes, and a non-root dry run renders the `sudo --`
# barrier the real exec uses. Renders and real execs carry the same
# `sudo --` option barrier.
#
# FS_EUID is a test-only override of the effective uid used to exercise
# the running-as-root path.
# Auditing contract: sudo_exec is a low-level primitive and does NOT
# tee to FS_LOG_FILE. The CLI dispatches privileged steps through
# run_sudo (lib/run.sh), which provides the FS_LOG_FILE audit trail and
# the FS_LOG_INFRA halt for broken logs.

FS_RUNNING_AS_ROOT=0
FS_SUDO_AVAILABLE=0
FS_SUDO_PASSWORD=0
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
        FS_SUDO_PASSWORD=0
        io_warn "running as root (euid $euid); proceeding without sudo"
        return 0
    fi
    if ((FS_DRY_RUN == 1)); then
        return 0
    fi
    FS_RUNNING_AS_ROOT=0
    FS_SUDO_AVAILABLE=0
    FS_SUDO_PASSWORD=0
    if ! command -v sudo >/dev/null 2>&1; then
        io_debug "sudo not present in PATH"
        return 0
    fi
    FS_SUDO_AVAILABLE=1
    if sudo -n true >/dev/null 2>&1; then
        FS_SUDO_PASSWORD=0
        return 0
    fi
    FS_SUDO_PASSWORD=1
    io_debug "sudo present; escalation requires a password and will prompt"
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
    if ! sudo -v; then
        io_error "sudo credential refresh failed; privileged steps cannot run"
        return 1
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
            printf '# would run: %s\n' "$(_sudo_render sudo -- "${cmd[@]}")"
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
