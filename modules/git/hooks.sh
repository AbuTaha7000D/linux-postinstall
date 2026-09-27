#!/usr/bin/env bash
# modules/git/hooks.sh - git config via a managed block (P5.3, P2.5).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4) and run()
# called once. The runner's shell already provides io_*/run_cmd and FS_*
# seams; this hook sources lib/fs.sh itself (fs_managed_block) because the
# runner does not. fs writes are internal APIs (atomic temp+rename, backup
# registry), so dry-run renders an honest `# would run:` plan line rather
# than a fake command.
# Real mode: fs_managed_block merges the fedora-setup `git` block into the
# target gitconfig, preserving every other line; idempotent (identical block
# -> no write, no backup) and replace-in-place on drift. A matching block
# means the hook makes no writes and no backup-registry entry. Note: git
# resolves duplicate keys last-wins, so a managed [user] block appended at
# EOF wins over any earlier user section; a pre-existing marker-like comment
# anywhere in the file makes fs_managed_block refuse (P2.5 fail-closed) and
# the module reports failed. User identity is applied ONLY when both
# FS_GIT_USER_NAME and FS_GIT_USER_EMAIL are set and are single clean lines
# (CR/LF or trailing backslash rejected -> skipped with io_warn); an existing
# [user] section elsewhere in the file is never touched. Target:
# "${FS_GIT_CONFIG:-$HOME/.gitconfig}" (FS_GIT_CONFIG is the hermetic seam);
# HOME unset (or "/") with no FS_GIT_CONFIG fails closed with io_error.
# Bash >= 4.3 safe (no namerefs beyond fs.sh's own).

run() {
    local root cfg want name email
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/fs.sh"
    cfg="${FS_GIT_CONFIG:-}"
    if [[ -z "$cfg" ]]; then
        cfg="${HOME:-}/.gitconfig"
        if [[ "$cfg" == "/.gitconfig" || "$cfg" == "//.gitconfig" ]]; then
            io_error "git config target requires FS_GIT_CONFIG or a HOME"
            return 1
        fi
    fi
    name="${FS_GIT_USER_NAME:-}"
    email="${FS_GIT_USER_EMAIL:-}"
    want="[init]"
    want+=$'\n\tdefaultBranch = main'
    want+=$'\n[merge]'
    want+=$'\n\tconflictstyle = zdiff3'
    want+=$'\n[diff]'
    want+=$'\n\tcolorMoved = zebra'
    want+=$'\n[color]'
    want+=$'\n\tui = auto'
    if [[ -n "$name" && -n "$email" ]]; then
        if [[ "$name" == *$'\n'* || "$name" == *$'\r'* || "$email" == *$'\n'* || "$email" == *$'\r'* ]] \
            || [[ "${name: -1}" == '\' || "${email: -1}" == '\' ]]; then
            io_warn "git identity values must not contain CR/LF or a trailing backslash; skipping [user]"
        else
            want+=$'\n[user]'
            want+=$'\n\tname = '"$name"
            want+=$'\n\temail = '"$email"
        fi
    fi
    if (( FS_DRY_RUN == 1 )); then
        printf '# would run: merge fedora-setup git block into %q\n' "$cfg"
        return 0
    fi
    fs_managed_block "$cfg" "git" "$want"
}