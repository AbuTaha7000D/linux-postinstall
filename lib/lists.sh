#!/usr/bin/env bash
# lib/lists.sh - declarative list-file parsers for fedora-setup modules.
# Depends on lib/io.sh only (io_error); source io.sh first.
#
# A module may declare packages via packages.list, a family override via
# packages.<family>.list (family in rpm|deb|arch), and flatpaks via
# flatpaks.list. None are required; absent = the empty set. Parsing is
# line-oriented with a fixed grammar common to all three file kinds:
#   - blank lines and `#` comment lines (leading whitespace allowed) are
#     ignored;
#   - each remaining line is trimmed and is exactly one entry (whole line,
#     no field splitting, so an entry may not contain meaning inside it;
#     inline trailing comments are NOT supported -- `git # for dev` is a
#     single entry);
#   - duplicate entries are dropped, first-seen order retained;
#   - a final line without a trailing newline parses normally.
#
# list_parse <file>       parse one list FILE (any name). Missing or
#                         non-regular paths are io_error + rc 1; use the
#                         module-level helpers below for optional files,
#                         which skip absent paths and treat them as empty.
# list_packages <dir> <family>
#                         print the module's merged package set. Exact
#                         precedence: when <family> is non-empty and
#                         packages.<family>.list is a regular file, its
#                         entries are printed first (deduped first-seen),
#                         then packages.list entries whose name was NOT in
#                         the family file (common twins dropped). Net
#                         effect: the family file overrides same-named
#                         common entries and precedes them; without an
#                         override file only the common list survives.
#                         Absent files are empty; only list_parse errors on
#                         a non-regular or unreadable path -- list_packages
#                         gates on -f and silently treats a non-regular
#                         path as absent. A present but empty (comment-only)
#                         list contributes nothing and never emits a blank
#                         line.
# list_flatpaks <dir>     print the module's flatpaks.list entries
#                         (deduped first-seen) if the file is a regular
#                         path, else nothing. flatpaks are their own
#                         namespace and never mix with package entries.

list_parse() {
    local file="${1:-}" line=""
    if [[ -z "$file" ]]; then
        io_error "list_parse requires a file path"
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        io_error "list file missing or not a regular file: $file"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        io_error "list file not readable: $file"
        return 1
    fi
    local -A seen=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        case "$line" in
            "" | \#*) continue ;;
        esac
        if [[ -z "${seen[$line]:-}" ]]; then
            seen[$line]=1
            printf '%s\n' "$line"
        fi
    done <"$file"
    return 0
}

list_packages() {
    local dir="${1:-}" family="${2:-}" id=""
    if [[ -z "$dir" ]]; then
        io_error "list_packages requires a module directory"
        return 1
    fi
    local fam=""
    if [[ -n "$family" && -f "$dir/packages.$family.list" ]]; then
        fam="$(list_parse "$dir/packages.$family.list")" || return 1
        if [[ -n "$fam" ]]; then
            printf '%s\n' "$fam"
        fi
    fi
    if [[ -f "$dir/packages.list" ]]; then
        local common
        common="$(list_parse "$dir/packages.list")" || return 1
        if [[ -z "$fam" ]]; then
            if [[ -n "$common" ]]; then
                printf '%s\n' "$common"
            fi
        else
            while IFS= read -r id; do
                if [[ -n "$id" ]] && ! grep -qxF -- "$id" <<<"$fam"; then
                    printf '%s\n' "$id"
                fi
            done <<<"$common"
        fi
    fi
    return 0
}

list_flatpaks() {
    local dir="${1:-}"
    if [[ -z "$dir" ]]; then
        io_error "list_flatpaks requires a module directory"
        return 1
    fi
    if [[ -f "$dir/flatpaks.list" ]]; then
        list_parse "$dir/flatpaks.list" || return 1
    fi
    return 0
}