#!/usr/bin/env bash
# lib/depgraph.sh - MODULE_DEPENDS topological ordering + cycle detection.
# Depends on lib/io.sh (io_error) and lib/modules.sh (module_load);
# source io.sh then modules.sh first. Bash >= 4.3 safe (empty-array
# expansions are guarded; no namerefs). Effect-free: parses module.sh
# metadata only, never executes module code, no writes, no sudo, never
# touches /etc/sudoers; reads no FS_* seams.
#
# dep_toposort <dir>...
#                       build the id->deps graph from the given module
#                       dirs (each loaded via module_load), then print the
#                       ids in a topological order -- every dependency
#                       precedes all of its dependents -- with ties broken
#                       by LC_ALL=C id sort so output is independent of
#                       argument order. Ids are taken from MODULE_ID (the
#                       P4.2 identity invariant MODULE_ID == dir basename
#                       is enforced upstream by module_validate/
#                       module_validate_set, not here). With no arguments
#                       nothing prints and rc is 0. Errors are io_error +
#                       rc 1, before any output:
#                         - any dir fails module_load (missing dir /
#                           module.sh);
#                         - a DEPENDS id has no dir in the set: "<id>
#                           depends on unknown module '<dep>'";
#                         - the graph has a cycle: "cycle: <id> -> ... ->
#                           <id>", a concrete dependence walk that
#                           witnesses the cycle -- it starts at the
#                           lexicographically smallest id left when the
#                           acyclic prefix is consumed, follows each
#                           module's declared DEPENDS order, and records
#                           the id that repeats to close the loop; for a
#                           self-dependency: "cycle: a -> a"; for a tail
#                           cycle reached via an acyclic prefix the report
#                           shows the walk (e.g. a -> b -> c -> b), with
#                           the cycle being b -> c -> b.
#                       Duplicate ids in the argument list collapse to one
#                       (first wins); duplicate DEPENDS entries within a
#                       module are counted once. On error nothing is
#                       printed to stdout; the caller must honor rc.

dep_toposort() {
    local IFS=$' \t\n'
    local dir="" id="" dep="" cur="" nxt="" p="" q="" path=""
    local -A node=()
    local -A deps=()
    local -A dependents=()
    local -A indeg=()
    local -a order=()
    local -a ready=()
    local -a ds=()
    local -a ps=()
    if (($# == 0)); then
        return 0
    fi
    for dir in "$@"; do
        module_load "$dir" || return 1
        id="$MODULE_ID"
        if [[ -n "${node[$id]:-}" ]]; then
            continue
        fi
        node[$id]=1
        local seen=""
        local deps_sorted=""
        IFS=$' \t\n' read -ra ds <<<"$MODULE_DEPENDS"
        for dep in ${ds[@]+"${ds[@]}"}; do
            case " $seen " in
                *" $dep "*) continue ;;
            esac
            seen="$seen $dep"
            deps_sorted="$deps_sorted $dep"
        done
        deps[$id]="${deps_sorted# }"
        order+=("$id")
    done
    for id in "${order[@]}"; do
        IFS=$' \t\n' read -ra ds <<<"${deps[$id]:-}"
        for dep in ${ds[@]+"${ds[@]}"}; do
            if [[ -z "${node[$dep]:-}" ]]; then
                io_error "$id depends on unknown module '$dep'"
                return 1
            fi
            local n="${indeg[$id]:-0}"
            indeg[$id]=$((n + 1))
            dependents[$dep]="${dependents[$dep]:-} $id"
        done
    done
    for id in "${order[@]}"; do
        if [[ -z "${indeg[$id]:-}" ]]; then
            ready+=("$id")
        fi
    done
    local -a emitted=()
    while ((${#ready[@]} > 0)); do
        local -a sorted=()
        while IFS= read -r cur; do
            sorted+=("$cur")
        done <<<"$(printf '%s\n' "${ready[@]}" | LC_ALL=C sort)"
        ready=("${sorted[@]}")
        cur="${ready[0]}"
        if ((${#ready[@]} > 1)); then
            ready=("${ready[@]:1}")
        else
            ready=()
        fi
        emitted+=("$cur")
        IFS=$' \t\n' read -ra ps <<<"${dependents[$cur]:-}"
        for p in ${ps[@]+"${ps[@]}"}; do
            q="${indeg[$p]}"
            indeg[$p]=$((q - 1))
            if ((indeg[$p] == 0)); then
                ready+=("$p")
            fi
        done
    done
    if ((${#emitted[@]} == ${#order[@]})); then
        if ((${#emitted[@]} > 0)); then
            printf '%s\n' "${emitted[@]}"
        fi
        return 0
    fi
    local -a remain=()
    for id in "${order[@]}"; do
        local hit=0
        local e
        for e in "${emitted[@]+"${emitted[@]}"}"; do
            if [[ "$e" == "$id" ]]; then
                hit=1
                break
            fi
        done
        if (( ! hit )); then
            remain+=("$id")
        fi
    done
    local sorted_remain
    sorted_remain="$(printf '%s\n' "${remain[@]}" | LC_ALL=C sort)"
    remain=()
    while IFS= read -r cur; do
        remain+=("$cur")
    done <<<"$sorted_remain"
    cur="${remain[0]:-}"
    path="$cur"
    local cur2="$cur"
    while :; do
        if [[ -z "${deps[$cur2]:-}" ]]; then
            break
        fi
        IFS=$' \t\n' read -ra ds <<<"${deps[$cur2]}"
        for dep in "${ds[@]}"; do
            nxt="$dep"
            break
        done
        if [[ "$nxt" == "$cur" ]]; then
            path="$path -> $nxt"
            break
        fi
        case " $path " in
            *" $nxt "*)
                path="$path -> $nxt"
                break
                ;;
        esac
        path="$path -> $nxt"
        cur2="$nxt"
    done
    io_error "cycle: $path"
    return 1
}