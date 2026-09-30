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

# _git_body prints the exact managed-block body run() writes, and sets
# _GIT_SKIP_USER=1 when a configured identity was rejected as unsafe. run() and
# verify() BOTH call it, so the installer and the audit can never disagree about
# what the block should contain -- the section headers are part of the contract,
# not decoration. Checking only the values would audit a block that git itself
# reads as entirely inert.
_git_body() {
    local name="${FS_GIT_USER_NAME:-}" email="${FS_GIT_USER_EMAIL:-}"
    _GIT_SKIP_USER=0
    GIT_BODY="[init]"
    GIT_BODY+=$'\n\tdefaultBranch = main'
    GIT_BODY+=$'\n[merge]'
    GIT_BODY+=$'\n\tconflictstyle = zdiff3'
    GIT_BODY+=$'\n[diff]'
    GIT_BODY+=$'\n\tcolorMoved = zebra'
    GIT_BODY+=$'\n[color]'
    GIT_BODY+=$'\n\tui = auto'
    if [[ -n "$name" && -n "$email" ]]; then
        if [[ "$name" == *$'\n'* || "$name" == *$'\r'* || "$email" == *$'\n'* || "$email" == *$'\r'* ]] ||
            [[ "${name: -1}" == '\' || "${email: -1}" == '\' ]]; then
            _GIT_SKIP_USER=1
        else
            GIT_BODY+=$'\n[user]'
            GIT_BODY+=$'\n\tname = '"$name"
            GIT_BODY+=$'\n\temail = '"$email"
        fi
    fi
    return 0
}

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
    _git_body
    if ((_GIT_SKIP_USER == 1)); then
        io_warn "git identity values must not contain CR/LF or a trailing backslash; skipping [user]"
    fi
    want="$GIT_BODY"
    if ((FS_DRY_RUN == 1)); then
        printf '# would run: merge fedora-setup git block into %q\n' "$cfg"
        return 0
    fi
    fs_managed_block "$cfg" "git" "$want"
}
# verify() (P9.2) is the read-only audit of the managed block this module owns.
# It re-derives the SAME target path run() resolves (so the two cannot drift)
# and then only READS the file. The comparison is not a hand-written list of
# keys: it is the EXACT body run() would write, produced by the shared
# _git_body helper, compared with the SAME relation fs_managed_block itself
# uses to decide whether a block is already correct -- ORDERED and
# LENGTH-SENSITIVE. Both properties are load-bearing, and both were found by
# review after an earlier, looser version:
#   * values without their section headers. git reads a setting outside any
#     section as inert, so that block configures nothing while every value it
#     "contains" is present.
#   * a REORDERED block. git is section-scoped, so swapping two values moves
#     each into the wrong section and git reads none of them. A set-based
#     comparison called that clean; fs.sh, which writes the block, calls the
#     same state drift and rewrites it. Length sensitivity additionally rejects
#     a REPEATED line, which a set cannot see either.
# So the relation the auditor uses is the relation the writer uses, and the
# per-line reporting below is DIAGNOSTIC ONLY -- the verdict comes from the
# strict comparison, never from the diagnostics. Leading whitespace is stripped
# on both sides because run() writes these keys TAB-indented, and blank lines
# are ignored on purpose. The [user] pair is expected only when a clean
# identity is configured, because _git_body omits it for an unsafe one -- the
# same reason run() does.
verify() {
    local root cfg block="" line="" rc=0
    local -a got=() want=()
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    declare -F io_error >/dev/null 2>&1 || source "$root/lib/io.sh"
    if ((${FS_DRY_RUN:-0} == 1)); then
        io_info "git: verify skipped in dry-run (no probing)"
        return 0
    fi
    cfg="${FS_GIT_CONFIG:-}"
    if [[ -z "$cfg" ]]; then
        cfg="${HOME:-}/.gitconfig"
        if [[ "$cfg" == "/.gitconfig" || "$cfg" == "//.gitconfig" ]]; then
            io_error "git: cannot verify without FS_GIT_CONFIG or a HOME"
            return 1
        fi
    fi
    if [[ ! -f "$cfg" ]]; then
        io_error "git: config not found: $cfg"
        return 1
    fi
    block="$(sed -n '/^# BEGIN fedora-setup git$/,/^# END fedora-setup git$/p' -- "$cfg" |
        sed '1d;$d;s/^[[:space:]]*//')"
    if [[ -z "$block" ]]; then
        io_error "git: managed block missing in $cfg"
        return 1
    fi
    if grep -q '^# BEGIN fedora-setup ' <<<"$block"; then
        io_error "git: more than one managed block in $cfg; run() would rewrite it"
        return 1
    fi
    _git_body
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" ]] && want+=("$line")
    done <<<"$GIT_BODY"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] && got+=("$line")
    done <<<"$block"
    if [[ "${#got[@]}" -ne "${#want[@]}" ]]; then
        io_error "git: managed block has ${#got[@]} line(s), run() writes ${#want[@]}"
        rc=1
    else
        for line in "${!want[@]}"; do
            if [[ "${got[$line]}" != "${want[$line]}" ]]; then
                io_error "git: managed block differs from what run() writes at line $((line + 1)): expected ${want[$line]}, found ${got[$line]}"
                rc=1
            fi
        done
    fi
    for line in "${want[@]}"; do
        if ! printf '%s\n' "${got[@]}" | grep -qxF -- "$line"; then
            io_error "git: managed block is missing: $line"
            rc=1
        fi
    done
    for line in "${got[@]}"; do
        if ! printf '%s\n' "${want[@]}" | grep -qxF -- "$line"; then
            io_error "git: managed block has an unexpected line: $line"
            rc=1
        fi
    done
    if ((rc != 0)); then
        return 1
    fi
    io_info "git: verify passed (managed block in $cfg)"
    return 0
}
