#!/usr/bin/env bash
# lib/modules.sh - module contract + loader for fedora-setup.
# Depends on lib/io.sh only (io_error/io_warn); source io.sh first.
#
# A module is a directory <root>/modules/<id>/. Only three file kinds are
# recognized; anything else is ignored:
#   module.sh   REQUIRED metadata file. Parsed textually, NEVER executed,
#               so `./setup list` never runs module code. Line-oriented
#               `KEY=VALUE` entries: blank lines and `#` comments ignored,
#               an optional matching pair of single/double quotes around
#               the value is stripped, values may not contain newlines,
#               inline comments are not supported. Known keys (P4.1):
#               MODULE_ID  (required, safe id)  MODULE_TITLE
#               MODULE_DESCRIPTION              MODULE_RISK  (default none)
#               MODULE_DEFAULT (default off)    MODULE_DEPENDS
#               (space-separated ids). A line naming an unknown key
#               triggers io_warn but does not fail the load; module_load
#               with the strict argument escalates it to io_error + rc 1
#               (validation uses strict).
#   hooks.sh    OPTIONAL file defining run() and/or verify(). Never
#               sourced at load time; the P4.6 runner sources it in a
#               subshell and calls run() for install, verify() for
#               `setup verify`. module_has_hooks only reports presence.
#   packages.list, packages.rpm.list, packages.deb.list,
#   packages.arch.list, flatpaks.list
#               OPTIONAL declarative lists. Precedence (P4.3, lib/lists.sh):
#               the family files override the common list (family entries
#               first, same-named common entries dropped). MODULE_LIST_NAMES
#               enumerates the fixed set
#               for parser/runner/validator reuse; module_list_files
#               reports which exist so consumers do not guess filenames.
#
# module_load <dir> [strict]
#                       reset the six contract globals, fill them from
#                       module.sh. rc 1 with io_error on: missing dir,
#                       missing module.sh, or absent/invalid MODULE_ID.
#                       Unknown keys io_warn and the load continues by
#                       default; with `strict` an unknown key is io_error
#                       and rc 1 (validation uses strict). Prints nothing.
#                       On failure the globals may be partially populated
#                       -- callers must honor rc. RISK/DEFAULT value
#                       vocabularies (levels, on/off) are validated by
#                       module_validate; the loader keeps raw values.
# module_validate <dir> <family>
#                       strict load + structural checks for a module dir:
#                       MODULE_ID must equal the directory basename
#                       (identity invariant -- enforced here, which makes
#                       duplicate ids structurally impossible for sets
#                       validated by module_validate), MODULE_RISK in
#                       none|low|medium|high|destructive, MODULE_DEFAULT
#                       in on|off. MODULE_TITLE/MODULE_DESCRIPTION must
#                       not contain control characters (TSV safety).
#                       When family is rpm|deb|arch and the
#                       dir carries any list file (packages.* or
#                       flatpaks.list), at least one of packages.list,
#                       packages.<family>.list, or flatpaks.list must
#                       exist (unsupported-family rejection); a module
#                       with no list files (hooks-only) always passes.
#                       Non-rpm/deb/arch family is treated as "skip the
#                       family check". rc 1 with io_error naming reason.
# module_validate_set <dir>...
#                       whole-set check: every dir must module_load, no
#                       MODULE_ID may repeat, and every MODULE_DEPENDS
#                       referral must resolve to an id in the set
#                       ("missing lists referenced"). The duplicate-id
#                       check guards callers that skip module_validate
#                       (which already enforces identity); rc 1 with
#                       io_error naming the offender.
# module_depends <dir>  print the module's DEPENDS ids one per line.
# module_list_files <dir> print existing declared list-file basenames,
#                         one per line, in MODULE_LIST_NAMES order.
# module_has_hooks <dir>  rc 0 when <dir>/hooks.sh is a regular file.
# module_valid_id <id>    rc 0 for a safe [A-Za-z0-9._-] id (no "", "." ,
#                         ".."); mirrors state.sh's _state_valid_name
#                         (kept separate so modules.sh depends only on
#                         io.sh -- change both in sync). P4.2 validation
#                         reuses it.
#
# Globals MODULE_ID/MODULE_TITLE/MODULE_DESCRIPTION/MODULE_RISK/
# MODULE_DEFAULT/MODULE_DEPENDS hold the most recent load; RISK/DEFAULT
# reset to the documented defaults none/off, the rest to "". Single-
# writer: callers load one module at a time and read the globals
# immediately. Effect-free: no writes, no sudo, no execution of module
# code. Bash >= 4.3 safe (no namerefs).

MODULE_LIST_NAMES=(packages.list packages.rpm.list packages.deb.list packages.arch.list flatpaks.list)
MODULE_ID=""
MODULE_TITLE=""
MODULE_DESCRIPTION=""
MODULE_RISK="none"
MODULE_DEFAULT="off"
MODULE_DEPENDS=""

module_valid_id() {
    case "${1:-}" in
        "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

_MODULE_RISK_LEVELS="none low medium high destructive"

module_load() {
    local dir="${1:-}" strict="${2:-}" key="" val="" line=""
    MODULE_ID=""
    MODULE_TITLE=""
    MODULE_DESCRIPTION=""
    MODULE_RISK="none"
    MODULE_DEFAULT="off"
    MODULE_DEPENDS=""
    if [[ -z "$dir" ]]; then
        io_error "module_load requires a directory"
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        io_error "module directory not found: $dir"
        return 1
    fi
    if [[ ! -f "$dir/module.sh" ]]; then
        io_error "module metadata missing: $dir/module.sh"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "" | \#*) continue ;;
        esac
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${line#*=}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        if (( ${#val} >= 2 )) && [[ "$val" == \"*\" ]]; then
            val="${val:1:$(( ${#val} - 2 ))}"
        elif (( ${#val} >= 2 )) && [[ "$val" == \'*\' ]]; then
            val="${val:1:$(( ${#val} - 2 ))}"
        fi
        case "$key" in
            MODULE_ID | MODULE_TITLE | MODULE_DESCRIPTION | \
                MODULE_RISK | MODULE_DEFAULT | MODULE_DEPENDS) ;;
            *)
                if [[ "$strict" == "strict" ]]; then
                    io_error "unknown metadata key '$key' in $dir/module.sh"
                    return 1
                fi
                io_warn "unknown metadata key '$key' in $dir/module.sh"
                continue
                ;;
        esac
        case "$key" in
            MODULE_ID) MODULE_ID="$val" ;;
            MODULE_TITLE) MODULE_TITLE="$val" ;;
            MODULE_DESCRIPTION) MODULE_DESCRIPTION="$val" ;;
            MODULE_RISK) MODULE_RISK="$val" ;;
            MODULE_DEFAULT) MODULE_DEFAULT="$val" ;;
            MODULE_DEPENDS) MODULE_DEPENDS="$val" ;;
        esac
    done <"$dir/module.sh"
    if [[ -z "$MODULE_ID" ]]; then
        io_error "module metadata missing MODULE_ID: $dir/module.sh"
        return 1
    fi
    if ! module_valid_id "$MODULE_ID"; then
        io_error "invalid MODULE_ID '$MODULE_ID' in $dir/module.sh"
        return 1
    fi
    return 0
}

module_list_files() {
    local dir="${1:-}" f
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        io_error "module_list_files requires a module directory"
        return 1
    fi
    for f in "${MODULE_LIST_NAMES[@]}"; do
        if [[ -f "$dir/$f" ]]; then
            printf '%s\n' "$f"
        fi
    done
    return 0
}

module_has_hooks() {
    local dir="${1:-}"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        io_error "module_has_hooks requires a module directory"
        return 1
    fi
    [[ -f "$dir/hooks.sh" ]]
}

module_validate() {
    local dir="${1:-}" family="${2:-}" name="" f="" has=0
    if [[ -z "$dir" ]]; then
        io_error "module_validate requires a directory"
        return 1
    fi
    module_load "$dir" strict || return 1
    name="${dir##*/}"
    if [[ "$MODULE_ID" != "$name" ]]; then
        io_error "MODULE_ID '$MODULE_ID' does not match directory name '$name'"
        return 1
    fi
    case "$MODULE_RISK" in
        none | low | medium | high | destructive) ;;
        *)
            io_error "invalid MODULE_RISK '$MODULE_RISK' in $dir/module.sh (allowed: $_MODULE_RISK_LEVELS)"
            return 1
            ;;
    esac
    case "$MODULE_DEFAULT" in
        on | off) ;;
        *)
            io_error "invalid MODULE_DEFAULT '$MODULE_DEFAULT' in $dir/module.sh (allowed: on off)"
            return 1
            ;;
    esac
    case "$MODULE_TITLE" in
        *$'\t'* | *$'\n'* | *$'\r'*)
            io_error "MODULE_TITLE must not contain control characters (module $MODULE_ID)"
            return 1
            ;;
    esac
    case "$MODULE_DESCRIPTION" in
        *$'\t'* | *$'\n'* | *$'\r'*)
            io_error "MODULE_DESCRIPTION must not contain control characters (module $MODULE_ID)"
            return 1
            ;;
    esac
    case "$family" in
        rpm | deb | arch) ;;
        *) return 0 ;;
    esac
    for f in "${MODULE_LIST_NAMES[@]}"; do
        if [[ -f "$dir/$f" ]]; then
            has=1
            break
        fi
    done
    if (( ! has )); then
        return 0
    fi
    if [[ -f "$dir/packages.list" || -f "$dir/packages.$family.list" || -f "$dir/flatpaks.list" ]]; then
        return 0
    fi
    io_error "$MODULE_ID has no package list usable on family '$family' (need packages.list, packages.$family.list, or flatpaks.list)"
    return 1
}

module_validate_set() {
    local dir="" id="" dep="" dups="" ids=""
    local -a all=()
    for dir in "$@"; do
        module_load "$dir" || return 1
        all+=("$MODULE_ID")
    done
    if ((${#all[@]} == 0)); then
        return 0
    fi
    ids="$(printf '%s\n' "${all[@]}" | sort -u)"
    dups="$(printf '%s\n' "${all[@]}" | sort | uniq -d)"
    if [[ -n "$dups" ]]; then
        while IFS= read -r id; do
            if [[ -n "$id" ]]; then
                io_error "duplicate module id '$id'"
            fi
        done <<<"$dups"
        return 1
    fi
    for dir in "$@"; do
        module_load "$dir" || return 1
        id="$MODULE_ID"
        for dep in $MODULE_DEPENDS; do
            if ! grep -qxF -- "$dep" <<<"$ids"; then
                io_error "$id depends on unknown module '$dep'"
                return 1
            fi
        done
    done
    return 0
}

module_depends() {
    local dir="${1:-}" dep=""
    if [[ -z "$dir" ]]; then
        io_error "module_depends requires a directory"
        return 1
    fi
    module_load "$dir" || return 1
    for dep in $MODULE_DEPENDS; do
        printf '%s\n' "$dep"
    done
    return 0
}