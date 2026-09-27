#!/usr/bin/env bash
# lib/profiles.sh - declarative profile loader (P4.5).
# Depends on lib/io.sh and lib/lists.sh (source io.sh then lists.sh first);
# profile_resolve additionally needs lib/modules.sh and lib/depgraph.sh.
# Bash >= 4.3 safe (loop bounds from $#, every empty-array expansion
# guarded, no namerefs). Effect-free: reads profile/module metadata only,
# never executes module code, no writes, no sudo, never touches /etc/sudoers.
#
# profiles/*.conf = one module id per line using the list-file grammar
# (see lib/lists.sh: blank and '#' lines ignored, entries trimmed, first-seen
# dedupe, CRLF and missing-final-newline tolerant, and entries are WHOLE
# LINES -- an inline trailing comment is not stripped and becomes part of
# the id, resolving to "module directory not found"). A profile's file
# order is its load order; resolution re-orders the union deps-first. The
# shipped profiles (profiles/{minimal,desktop,developer,full}.conf): as of
# P5.7 `minimal` = core+flatpak and `desktop` = minimal+git+fonts+terminal,
# while `developer`/`full` are still comment-only — a comment-only profile
# is a valid empty profile today. The base profiles carry real module sets
# before the package/flatpak routing split (flatpaks currently batch through
# the family package backend — an owner-pending split, see profiles/minimal.conf).
# Ids printed are MODULE_ID values (the P4.2 identity invariant MODULE_ID ==
# dir basename is enforced upstream by module_validate), so a resolver maps
# each printed id back to <modules_dir>/<id>. Where the task speaks of "conflicts", the P4.1
# contract has no exclusion key -- conflicts here mean a dependency cycle
# or an unresolvable MODULE_DEPENDS reference (dep_toposort).
#
# _profile_id_ok <id>     locale-stable token predicate shared by name and
#                       content validation (case glob, not a collation-
#                       sensitive regex): non-empty, no '/', no leading
#                       '.'/'-', charset [A-Za-z0-9._-]. rc 0 iff <id> is a
#                       usable module-id token.
# profile_validate <dir> <name>
#                       rc0 iff <name> is a valid profile name token per
#                       _profile_id_ok; else io_error + rc1. <dir> is not
#                       consulted (the name gate is path-shape only);
#                       existence/layout of the file itself is profile_load's
#                       concern.
# profile_load <dir> <name>
#                       print the profile's module ids in file order,
#                       deduped (first-seen wins), rc0; produces nothing
#                       for an empty profile. Missing / non-regular /
#                       unreadable file -> list_parse io_error + rc1.
# profile_resolve <modules_dir> <profiles_dir> <name> [module...]
#                       fold the profile plus any CLI-specified module ids
#                       into one ordered module set: the union (profile
#                       order first, CLI ids appended, duplicates against
#                       the profile and each other collapsed, written out
#                       first-seen in the merge loop, then re-collapsed by
#                       the BFS visited set) is closed over MODULE_DEPENDS
#                       (BFS over module metadata; every profile-content
#                       and CLI id is token-validated before use, and every
#                       MODULE_DEPENDS id is token-validated as it is
#                       discovered, then verified against the module tree
#                       by module_load) and topologically sorted via
#                       dep_toposort (P4.4), so stdout is deps-first,
#                       deterministic, and immune to argument order.
#                       Errors before any output (io_error + rc1, nothing
#                       printed): invalid name; invalid id anywhere in the
#                       set (profile/CLI id -> 'invalid module id in set:
#                       <id>', MODULE_DEPENDS reference -> 'invalid module
#                       id in module '<id>': <dep>'); missing profile file;
#                       any referenced module missing or unloadable; and
#                       dependency cycles. rc0 iff the whole
#                       set resolves; an empty profile with no CLI ids
#                       resolves to nothing. Each referenced module's
#                       metadata is parsed twice (closure BFS + dep_toposort)
#                       -- harmless at P4 scale. <modules_dir> and
#                       <profiles_dir> are supplied by the caller
#                       (bootstrap default: repo modules/ and the profiles/
#                       tree; the FS_PROFILES_DIR seam is consumed by that
#                       caller-level wiring in P4.6/P4.7, see AGENTS.md
#                       section 3).

_profile_id_ok() {
    case "${1:-}" in
        "" | "." | ".." | [.-]* | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

profile_validate() {
    local name="${2:-}"
    if ! _profile_id_ok "$name"; then
        io_error "invalid profile name: $name"
        return 1
    fi
    return 0
}

profile_load() {
    local dir="${1:-}" name="${2:-}"
    if [[ -z "$dir" || -z "$name" ]]; then
        io_error "profile_load requires a directory and a name"
        return 1
    fi
    profile_validate "$dir" "$name" || return 1
    list_parse "$dir/$name.conf"
}

profile_resolve() {
    local modules_dir="${1:-}" profiles_dir="${2:-}" name="${3:-}"
    shift 3 2>/dev/null || {
        io_error "profile_resolve requires a modules dir, a profiles dir, and a name"
        return 1
    }
    if [[ -z "$modules_dir" || -z "$profiles_dir" || -z "$name" ]]; then
        io_error "profile_resolve requires a modules dir, a profiles dir, and a name"
        return 1
    fi
    local profile_out=""
    profile_out="$(profile_load "$profiles_dir" "$name")" || return 1
    local -a ids=()
    if [[ -n "$profile_out" ]]; then
        local id=""
        while IFS= read -r id; do
            ids+=("$id")
        done <<<"$profile_out"
    fi
    local cli=""
    for cli in "$@"; do
        ids+=("$cli")
    done
    local -a cand=()
    local -A seen=()
    local cand_id=""
    for cand_id in ${ids[@]+"${ids[@]}"}; do
        if ! _profile_id_ok "$cand_id"; then
            io_error "invalid module id in set: $cand_id"
            return 1
        fi
        if [[ -z "${seen[$cand_id]:-}" ]]; then
            seen[$cand_id]=1
            cand+=("$cand_id")
        fi
    done
    local -a dirs=()
    local -A visited=()
    local -a candds=()
    local cid="" dep=""
    while ((${#cand[@]} > 0)); do
        cid="${cand[0]}"
        if ((${#cand[@]} > 1)); then
            cand=("${cand[@]:1}")
        else
            cand=()
        fi
        if [[ -n "${visited[$cid]:-}" ]]; then
            continue
        fi
        visited[$cid]=1
        dirs+=("$modules_dir/$cid")
        module_load "$modules_dir/$cid" || return 1
        IFS=$' \t\n' read -ra candds <<<"$MODULE_DEPENDS"
        for dep in ${candds[@]+"${candds[@]}"}; do
            if ! _profile_id_ok "$dep"; then
                io_error "invalid module id in module '$cid': $dep"
                return 1
            fi
            cand+=("$dep")
        done
    done
    if ((${#dirs[@]} > 0)); then
        dep_toposort "${dirs[@]}" || return 1
    fi
    return 0
}