#!/usr/bin/env bash
# modules/git.sh - git defaults in ~/.gitconfig.
#
# Applied through a managed block, so any other git config in the file is left
# alone. Set FS_GIT_USER_NAME and FS_GIT_USER_EMAIL to add a [user] section:
#
#   FS_GIT_USER_NAME="Ada" FS_GIT_USER_EMAIL="ada@example.com" ./setup git

install_git() {
    local body
    body="$(read_list "$FS_ROOT/config/gitconfig.txt")"
    [[ -n "$body" ]] || die "config/gitconfig.txt is empty"

    if [[ -n "${FS_GIT_USER_NAME:-}" && -n "${FS_GIT_USER_EMAIL:-}" ]]; then
        body+=$'\n[user]\n\tname = '"${FS_GIT_USER_NAME}"$'\n\temail = '"${FS_GIT_USER_EMAIL}"
    fi

    printf '%s\n' "$body" | write_block "$HOME/.gitconfig" git
}
