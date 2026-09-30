#!/usr/bin/env bash
# lib/update.sh - version reporting and an EXPLICIT self-update (P9.4).
# Depends on lib/io.sh and lib/run.sh (source them first), and on cli_parse having
# already run: it is the single writer of FS_PULL, and this file deliberately
# neither sets nor defaults it. It is sourced AFTER cli_parse, so re-defaulting
# here would wipe the --pull value, and defaulting it from the environment would
# resurrect the inherited FS_PULL=1 this design exists to refuse.
#
# WHAT THIS REPLACES
# ------------------
# The deleted prototype auto-pulled itself silently, on the theory that a
# bootstrap tool should always be current. That is how a machine ends up running
# code it never agreed to run, mid-module, with a half-applied profile. Here the
# pull is a SEPARATE, EXPLICIT act: `update` reports, and only `update --pull`
# moves the working tree. No code path pulls without that flag having been given
# on the command line.
# FS_PULL is deliberately NOT an env seam -- cli_parse resets it unconditionally
# like FS_MANIFEST, because an inherited FS_PULL=1 in the environment would
# reintroduce exactly the silent auto-pull this file exists to remove. It is the
# same rule, same reason: an inherited value must never be able to move a
# working tree.
#
# THE REPORTED STATES
# -------------------
# A clean tree with a remote is in exactly one of four states, and all four are
# reported explicitly rather than collapsed into "up to date":
#   up-to-date  HEAD == upstream
#   behind      upstream is ahead, HEAD is an ancestor  -> fast-forward possible
#   ahead       HEAD is ahead, upstream is an ancestor  -> nothing to pull
#   diverged    both moved                              -> NOT fast-forwardable
# Diverged is why every merge here is --ff-only: this tool must never be the
# thing that creates a merge commit in someone's checkout, and must never
# "resolve" a divergence by rewriting local history. Divergence is the user's to
# resolve, and the refusal says so.
#
# TWO further cases sit outside this table because neither has a branch to
# compare: a detached HEAD, and a branch with no upstream configured. Both are
# reported in their own words -- they are NOT "diverged" and NOT "up to date",
# and the advice differs, since `git branch --set-upstream-to` is impossible
# while detached.
#
# CLEANLINESS, and why it is checked FIRST
# ----------------------------------------
# A pull rewrites files. Uncommitted work in the tree is the user's, and a
# fast-forward over it is data loss git will not even warn about cleanly, so the
# tree must be clean before ANYTHING happens -- including the fetch. UNTRACKED
# files count as unclean -- but that check is NOT sufficient on its own, and the
# gap was measured rather than assumed. For an incoming file at a path the user
# already has untracked:
#   untracked, NOT ignored  -> `status --porcelain` reports it (so the tree is
#                              already refused) AND git refuses the merge itself
#   untracked, IGNORED      -> `status --porcelain` reports NOTHING and the
#                              merge SUCCEEDS, replacing the local content
# The second row is silent data loss, and --ff-only does not help: the fast-
# forward is legitimate, so the only guard is a pre-merge collision check. That
# check is deliberately NOT expressed with `status --ignored` (it would refuse
# on this repo's own artifacts -- downloads/, assets/*, .state/ -- forever) and
# NOT with `check-ignore` on incoming paths (it would refuse an incoming file at
# an ignored path even when nothing local is in the way). It is expressed as the
# property that actually matters: refuse when the fast-forward would ADD a path
# that already exists on disk and is untracked right now.
#
# THREE details of that test are load-bearing. Each was a measured hole, closed
# here and pinned by its own cell, and the first two fail SILENTLY -- rc 0, the
# postcondition satisfied, and the user's file replaced:
#   1. "exists on disk" is `-e` OR `-L`. A DANGLING SYMLINK -- a target on an
#      unmounted drive, or one not created yet -- is FALSE to `-e`, and those are
#      exactly the paths under assets/wallpaper/ and downloads/ that users hold.
#   2. "is untracked" must be asked with `--literal-pathspecs` as a git GLOBAL
#      option (before the subcommand; after it, git rejects it with rc 129).
#      Omitted, the path is a GLOB pathspec: an incoming `pkg1?2.deb` is answered
#      by a tracked `pkg1x2.deb`, and the guard concludes there is nothing to
#      lose.
#   3. the on-disk test is evaluated FIRST, so `ls-files` runs only for paths
#      that exist locally -- normally none, which keeps the guard off the
#      spawn-sensitive path of a large first pull.
#
# `$head` and `$up` are interpolated into rev arguments, and they are safe by
# PROVENANCE rather than by any ref-name rule: both come from `rev-parse` as a
# single full-width object id (40 hex under sha1, 64 under sha256), which cannot
# carry `..`, `~`, `^` or any other rev syntax, so no ref-name rule is needed.
# `$up` is a resolved object id, not a branch name.
# --diff-filter carries `C` even though the tool passes no copy flag at all. Copy
# detection at that strength only considers sources modified in the same diff, so
# a copy's destination classifies as `A` and `AMR` already inspects it; `C` can
# therefore only ever refuse an existing UNTRACKED copy destination, which is a
# real collision, so it costs nothing and closes a config-dependent hole. (No cell
# covers `C` specifically, since it is unreachable with the invocation used here,
# so that half is covered by inspection.)
#
# Known limit, left standing deliberately: incoming paths are read with
# `diff --name-only`, which is newline-delimited, so a path containing a newline
# is not inspected. Closing that needs -z, which cannot survive the $(...) these
# paths are read through.
# The refusal names the offending paths so the decision stays the user's. This is
# also the only place `update` can be destructive at all, and it is why --pull is
# gated on it rather than on a confirmation prompt.
#
# SCOPE OF "DOES NOTHING YET": clean-tree-and-fetch is NOT read-only. A report
# fetches, so it writes objects, FETCH_HEAD and the remote-tracking refs, and
# `git status --porcelain` refreshes .git/index (bytes unchanged, mtime touched)
# even on the refusal path. Nothing here writes the WORKING TREE or any ref the
# pull would move except under --pull, and "a refusal never half-happens" means
# the fast-forward specifically -- not that .git was untouched.
#
# DRY RUN PROBES NOTHING
# ----------------------
# Per AGENTS section 9 a dry run executes nothing, probes nothing and writes
# nothing -- so it CANNOT compare against the remote, because the comparison
# needs a fetch. `update --dry-run` therefore reports the version (static), and
# renders the steps a real run would perform (the fetch, and the merge when
# --pull was given), then says plainly that the comparison was not performed.
# It does NOT guess from the last-fetched ref: a stale @{u} would let a dry run
# print "already current" about a machine that is three commits behind, which is
# the exact class of confident-wrong output this project keeps rejecting. The
# chrome module (P7.6) established the same precedent for a seam a dry run
# cannot reach, and its rule is followed here: the rendered merge carries a
# literal RESOLVED-AT-RUN-TIME marker instead of a plausible-looking '@{u}',
# because the real merge targets the resolved 40-hex sha and a rendered line that
# merely LOOKS runnable invites someone to paste it and get different behaviour.
# "nothing was written" below means the working tree and every ref; see the
# SCOPE OF "DOES NOTHING YET" note above, since a real fetch is not inert.
#
# EXIT CODES (the contract)
# -------------------------
#   0  up-to-date, ahead, or behind-and-reported (updates available is not an
#      error; `update` without --pull is a report)
#   0  --pull with nothing to do
#   0  --dry-run (renders the plan; performs no check at all)
#   0  no upstream tracking branch, or detached HEAD, without --pull (warned;
#      there is nothing to compare, and `set-upstream-to` is not advised while
#      detached)
#   1  unclean tree / not a git working tree / no git binary
#   1  --pull with no upstream tracking branch, or on a detached HEAD
#   1  --pull when diverged (fast-forward impossible)
#   1  --pull when the merge did not land (postcondition below)
#   1  any git step failed
#
# rc IS NOT TRUSTED ALONE
# -----------------------
# run_cmd's default policy is keep-going-and-return-0, so it is called here with
# --stop to get a propagating rc, and the merge is additionally checked against
# its POSTCONDITION: after --ff-only, HEAD must equal the upstream sha we
# compared against. A merge that exits 0 without moving HEAD (a no-op wrapper, a
# git that decided there was nothing to do) is a failed update reported as a
# successful one otherwise, and the tool would then report a version it is not
# running. The check is on state, not on rc.
#
# ALWAYS -C "$root"
# -----------------
# Every git invocation carries -C "$root", the directory holding `setup`. The
# caller's working directory is never trusted: `./setup update` run from inside
# some other checkout must inspect THIS tool's repository, not that one. This is
# the single easiest way to get this command wrong, so there is no code path
# that runs git without it.

_UPDATE_OUT=""
_UPDATE_DIRTY_MAX=10

# _update_query runs a git plumbing read and captures stdout only. Its callers
# already know WHICH read failed, and run_cmd (used for the fetch, where git's
# own stderr is the interesting part) streams stderr through untouched. Plumbing
# reads are only reached after rev-parse --is-inside-work-tree succeeded, so a
# failure here means corruption rather than a diagnosable condition, and adding a
# mktemp-backed side channel to forward it would add a failure mode to the one
# helper every state check depends on.
# _update_query is a git plumbing READ, and dry-run mode must not reach one at
# all: update_run returns from its dry-run branch before any query is issued, so
# this function carries no dry-run guard of its own. The invariant is the
# caller's to hold, and an unreachable check would only read as protection.
_update_query() {
    _UPDATE_OUT=""
    local out=""
    out="$("$@" 2>/dev/null)" || return $?
    _UPDATE_OUT="$out"
    return 0
}

_update_report_dirty() {
    local n=0 shown=0 line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        n=$(( n + 1 ))
        if (( shown < _UPDATE_DIRTY_MAX )); then
            io_info "update:   ${line}"
            shown=$(( shown + 1 ))
        fi
    done <<<"$_UPDATE_OUT"
    if (( n > _UPDATE_DIRTY_MAX )); then
        io_info "update:   ... and $(( n - _UPDATE_DIRTY_MAX )) more"
    fi
    io_error "update: working tree is not clean ($n change(s)); commit, stash or remove them, then re-run"
}

_UPDATE_DETACHED=0

_update_identity() {
    local root="$1"
    if ! _update_query git -C "$root" rev-parse --short HEAD; then
        io_error "update: cannot resolve HEAD in $root"
        return 1
    fi
    io_info "update: commit ${_UPDATE_OUT:-unknown}"
    if _update_query git -C "$root" symbolic-ref --short -q HEAD; then
        _UPDATE_DETACHED=0
        io_info "update: branch ${_UPDATE_OUT:-unknown}"
    else
        _UPDATE_DETACHED=1
        io_info "update: on a detached HEAD"
    fi
    return 0
}

update_run() {
    local root="${1:-}" behind="" ahead="" up="" head=""
    _UPDATE_OUT=""
    if [[ -z "$root" ]]; then
        io_error "update requires the repository root"
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        io_error "update: git not found in PATH; cannot check for updates"
        return 1
    fi
    io_info "update: fedora-setup ${FS_VERSION:-unknown}"

    if (( FS_DRY_RUN == 1 )); then
        run_cmd "update: fetch remote" -- git -C "$root" fetch
        if [[ "$FS_PULL" == "1" ]]; then
            io_alert "update: --pull rewrites tracked files in $root after a fast-forward"
            run_cmd "update: fast-forward to upstream" -- git -C "$root" merge --ff-only "RESOLVED-AT-RUN-TIME"
            io_info "update: dry run: the fast-forward target is the upstream commit, resolved by the fetch above"
        fi
        io_info "update: dry run: cleanliness and the remote comparison were NOT performed (they need a fetch); nothing was written"
        return 0
    fi

    if ! _update_query git -C "$root" rev-parse --is-inside-work-tree; then
        io_error "update: $root is not a git working tree; there is no remote to compare against"
        return 1
    fi
    if [[ "$_UPDATE_OUT" != "true" ]]; then
        io_error "update: $root is not a git working tree (git reported '$_UPDATE_OUT')"
        return 1
    fi

    if ! _update_query git -C "$root" status --porcelain; then
        io_error "update: cannot read the status of $root"
        return 1
    fi
    if [[ -n "$_UPDATE_OUT" ]]; then
        _update_report_dirty
        return 1
    fi
    io_info "update: working tree is clean"

    _update_identity "$root" || return 1

    if ! _update_query git -C "$root" rev-parse --verify --quiet '@{u}'; then
        if (( _UPDATE_DETACHED == 1 )); then
            io_warn "update: HEAD is detached, so there is no branch to compare against"
            if [[ "$FS_PULL" == "1" ]]; then
                io_error "update: --pull needs a branch; check out a branch first (a detached HEAD has nothing to fast-forward)"
                return 1
            fi
            return 0
        fi
        io_warn "update: no upstream tracking branch is configured; nothing to compare against"
        if [[ "$FS_PULL" == "1" ]]; then
            io_error "update: --pull needs an upstream tracking branch (set one with 'git branch --set-upstream-to')"
            return 1
        fi
        return 0
    fi
    up="$_UPDATE_OUT"

    if ! run_cmd "update: fetch remote" --stop -- git -C "$root" fetch; then
        io_error "update: fetch failed; cannot compare against the remote"
        return 1
    fi
    if ! _update_query git -C "$root" rev-parse --verify --quiet '@{u}'; then
        io_error "update: the upstream ref vanished after the fetch"
        return 1
    fi
    up="$_UPDATE_OUT"

    if ! _update_query git -C "$root" rev-parse HEAD; then
        io_error "update: cannot resolve HEAD"
        return 1
    fi
    head="$_UPDATE_OUT"

    if ! _update_query git -C "$root" rev-list --count "HEAD..$up"; then
        io_error "update: cannot count the commits behind the remote"
        return 1
    fi
    behind="${_UPDATE_OUT:-0}"
    if ! _update_query git -C "$root" rev-list --count "$up..HEAD"; then
        io_error "update: cannot count the commits ahead of the remote"
        return 1
    fi
    ahead="${_UPDATE_OUT:-0}"
    if [[ ! "$behind" =~ ^[0-9]+$ || ! "$ahead" =~ ^[0-9]+$ ]]; then
        io_error "update: git returned a non-numeric commit count (behind='$behind' ahead='$ahead')"
        return 1
    fi
    behind=$(( 10#$behind ))
    ahead=$(( 10#$ahead ))

    if (( ahead == 0 && behind == 0 )); then
        io_info "update: already current with the remote"
        if [[ "$FS_PULL" == "1" ]]; then
            io_info "update: nothing to pull"
        fi
        return 0
    fi
    if (( behind == 0 )); then
        io_info "update: already current, and $ahead commit(s) ahead of the remote"
        return 0
    fi
    if (( ahead > 0 )); then
        io_info "update: diverged - $behind commit(s) behind and $ahead commit(s) ahead of the remote"
        if [[ "$FS_PULL" == "1" ]]; then
            io_error "update: --pull only fast-forwards, and a diverged branch cannot be fast-forwarded; resolve it yourself"
            return 1
        fi
        io_info "update: resolve the divergence (rebase or merge) before updating"
        return 0
    fi

    io_info "update: $behind commit(s) behind the remote"
    if [[ "$FS_PULL" != "1" ]]; then
        io_info "update: re-run with --pull to fast-forward to the remote"
        return 0
    fi

    if ! _update_query git -C "$root" diff --name-only --diff-filter=AMRC "$head" "$up"; then
        io_error "update: cannot list the paths the fast-forward would add"
        return 1
    fi
    local -a incoming=()
    local path="" collide=0
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        incoming+=("$path")
    done <<<"$_UPDATE_OUT"
    for path in "${incoming[@]+"${incoming[@]}"}"; do
        if [[ ! -e "$root/$path" && ! -L "$root/$path" ]]; then
            continue
        fi
        if _update_query git -C "$root" --literal-pathspecs ls-files --error-unmatch -- "$path"; then
            continue
        fi
        collide=1
        io_error "update: the fast-forward would overwrite your untracked file: $path"
    done
    if (( collide == 1 )); then
        io_error "update: refusing to overwrite it; move, commit or delete the file(s) above, then re-run"
        return 1
    fi

    io_alert "update: fast-forwarding $root by $behind commit(s)"
    if ! run_cmd "update: fast-forward to upstream" --stop -- git -C "$root" merge --ff-only "$up"; then
        io_error "update: the fast-forward did not complete; the working tree was left as it was"
        return 1
    fi
    if ! _update_query git -C "$root" rev-parse HEAD; then
        io_error "update: cannot resolve HEAD after the fast-forward"
        return 1
    fi
    if [[ "$_UPDATE_OUT" != "$up" ]]; then
        io_error "update: fast-forward reported success but HEAD is '$_UPDATE_OUT', not the upstream commit '$up'"
        return 1
    fi
    io_info "update: updated to ${up}"
    return 0
}