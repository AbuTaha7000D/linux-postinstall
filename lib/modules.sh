#!/usr/bin/env bash
# lib/modules.sh - module discovery and execution.
#
# A module is one file in modules/ named <id>.sh that defines one function:
#
#   install_<id>() { ... }
#
# That is the whole contract. The runner sources the file, calls the function,
# and moves on; the function's exit status decides whether the module counts as
# done. No metadata file, no state directory, no risk classification, no
# dependency graph. To add a module: create the file, define the function.
#
# Order is the order of the ids given on the command line, or the order of
# config/modules.txt when none are given.
#
# Sourced by setup; not executable on its own.

module_path() {
    printf '%s/modules/%s.sh' "$FS_ROOT" "$1"
}

# list_modules -- print every available module id, one per line.
list_modules() {
    local f id
    for f in "$FS_ROOT"/modules/*.sh; do
        [[ -f "$f" ]] || continue
        id="$(basename -- "$f" .sh)"
        [[ "$id" == "_"* ]] && continue
        printf '%s\n' "$id"
    done
}

# default_modules -- print the ids from config/modules.txt.
default_modules() {
    local file="$FS_ROOT/config/modules.txt"
    [[ -f "$file" ]] || die "config/modules.txt not found in $FS_ROOT"
    read_list "$file"
}

# validate_modules <id>... -- die unless every id names a real module file.
validate_modules() {
    local id path
    for id in "$@"; do
        path="$(module_path "$id")"
        [[ -f "$path" ]] || die "no such module: $id (looked for $path)"
    done
}

# run_modules <id>... -- run each module, collecting failures.
# Returns 1 if any module failed, after every module has had its turn.
run_modules() {
    local id path fn rc=0 failed=""
    local -i total=0 done_n=0
    local -a failed_ids=()

    for id in "$@"; do
        path="$(module_path "$id")"
        fn="install_${id//-/_}"

        total+=1
        log_info "--- $id ---"

        (
            set -euo pipefail
            # shellcheck source=/dev/null
            source "$path"
            declare -F "$fn" >/dev/null || die "$path does not define $fn()"
            "$fn"
        ) || {
            log_error "module $id failed"
            failed_ids+=("$id")
            rc=1
        }
        done_n+=1
    done

    log_info "modules: $((total - ${#failed_ids[@]}))/$total ok"
    if ((${#failed_ids[@]} > 0)); then
        log_error "failed modules: ${failed_ids[*]}"
        return 1
    fi
    return 0
}
