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
#
# P9.3 MANIFEST SOURCE. When FS_MANIFEST names an exported tree, both
# readers resolve from that tree instead of the module directory, keyed by the
# module id (the P4.2 invariant MODULE_ID == dir basename, so the id is
# available from the path alone). The exported list is ALREADY family-resolved
# and already deduped, so no family override logic runs and the re-import
# consumes exactly the ids that were exported -- which is what lets the round
# trip detect upstream drift instead of assuming it. This is the ONLY
# integration point for a re-import: the runner's PLAN stage already calls
# these two functions, so a manifest install exercises the identical batching
# and rendering path as a profile install.
# A module ABSENT from the manifest contributes nothing rather than falling
# back to the live tree: silently mixing an exported set with a live one would
# produce a plan that is neither the export nor the profile, and the user would
# have no way to tell which ids came from where. The seam is opt-in and
# explicit (--manifest), and cli_parse resets it, so a run without the flag
# reads the module tree exactly as before.
#
# The ABSENT case is therefore a THREE-state distinction, not a two-state one,
# and the distinction is load-bearing. _list_manifest_file answers 0 with a
# path (use it), 1 for absent (contribute nothing), 2 for a symlinked list
# (refused: an export tree is untrusted input, and a symlink here would let a
# crafted artifact pull an arbitrary file's lines into a package batch, which
# then render into the user's plan). _list_manifest_read collapses the first
# two into "read it, or emit nothing" and propagates a read error, and both
# readers call it ONLY when FS_MANIFEST is set -- that is the guard which keeps
# the absent case from degrading into a live-tree fallback. Returning 1 for
# both "no manifest" and "not in the manifest" was the bug that made the
# re-import silently consult the live tree.

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

_list_manifest_file() {
    local dir="${1:-}" kind="${2:-}" id="" path=""
    if [[ -z "${FS_MANIFEST:-}" ]]; then
        return 1
    fi
    if [[ -z "$dir" || -z "$kind" ]]; then
        return 1
    fi
    id="${dir##*/}"
    case "$id" in
        ''|.|..|*/*) return 1 ;;
    esac
    path="$FS_MANIFEST/manifests/$id.$kind"
    if [[ -L "$path" ]]; then
        io_error "manifest list is a symlink, refusing to read through it: $path"
        return 2
    fi
    if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    return 1
}

_list_manifest_read() {
    local dir="${1:-}" kind="${2:-}" mfile="" rc=0
    if [[ -z "${FS_MANIFEST:-}" ]]; then
        return 1
    fi
    mfile="$(_list_manifest_file "$dir" "$kind")" || rc=$?
    if (( rc == 2 )); then
        return 1
    fi
    if [[ -z "$mfile" ]]; then
        return 0
    fi
    list_parse "$mfile" || return 1
    return 0
}

list_packages() {
    local dir="${1:-}" family="${2:-}" id=""
    if [[ -z "$dir" ]]; then
        io_error "list_packages requires a module directory"
        return 1
    fi
    if [[ -n "${FS_MANIFEST:-}" ]]; then
        _list_manifest_read "$dir" "list" || return 1
        return 0
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
    if [[ -n "${FS_MANIFEST:-}" ]]; then
        _list_manifest_read "$dir" "flatpaks.list" || return 1
        return 0
    fi
    if [[ -f "$dir/flatpaks.list" ]]; then
        list_parse "$dir/flatpaks.list" || return 1
    fi
    return 0
}