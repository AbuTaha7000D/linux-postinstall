#!/usr/bin/env bash
# lib/gnome.sh - GNOME gsettings layer for fedora-setup modules (P6.1).
# Depends on lib/io.sh (io_error/io_debug) and lib/run.sh (run_cmd);
# source io.sh first, then run.sh, then this file.
#
# Design:
#   - All writes go through run_cmd, so --dry-run renders an exact
#     `# would run: ...` line and executes nothing, and real writes are
#     audited by the run layer. Reads probe dconf, so a read is refused
#     while FS_DRY_RUN=1 (fail-closed: dry-run never probes).
#   - Idempotency: a real-mode set reads the current value first and skips
#     silently (rc0, no write) when it already equals the target. Real
#     `gsettings get` renders string scalars single-quoted ('file:///x'), so a
#     bare target must also match its single-quoted rendering; a target that
#     needs GVariant escapes (embedded quote, backslash) never matches and is
#     re-written -- fails safe (extra write, never a skipped needed write);
#     whether such a value is accepted by real `gsettings set` is left to the
#     run layer (a rejected value is audited and the run keeps going).
#   - GVariant string arrays are parsed, merged and rebuilt in memory; the
#     old prototype's stateful text rewriting of dconf output is never used
#     (P6.1 verification: malformed keys error safely, never via direct
#     rewriting of system files).
#   - Array elements are validated (non-empty, printable ASCII, no quotes,
#     no backslash, no whitespace): their sanitized values are app ids,
#     dconf paths and binding names, and the GVariant text format cannot
#     represent those bytes without escapes. Existing elements already
#     stored by gsettings are passed through parse->merge->build as-is; if
#     such an element violates the charset the merge fails closed loudly
#     rather than emitting an unrepresentable array.
#   - schema tokens are restricted to [A-Za-z0-9._-] (locale-stable case
#     globs, no [[ =~ ]] - see P4.5), optionally followed by `:` and an
#     absolute dconf path for a relocatable schema instantiation
#     (org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/
#     .../custom0/); path segments are [A-Za-z0-9._-] with no empty, `.` or
#     `..` segment and at most a single trailing slash. Keys are plain
#     [A-Za-z0-9._-] tokens. Both are validated before any read or write.
#   - Failure policy: malformed arguments fail loudly (io_error + rc1)
#     before anything runs; a failed real write is graceful (run_cmd
#     keep-going policy logs it and returns 0 so the runner continues).
#
# gnome_gsettings_available                rc0 iff `gsettings` is on PATH (no IO).
# gnome_extensions_available               rc0 iff `gnome-extensions` is on PATH.
# gnome_require_capable <context>          capability gate (P6.5): rc0 ONLY when
#         this machine is a safe place to touch GNOME settings, otherwise
#         io_info "<context>: skipped (not GNOME) (<reason>)" and rc1 --
#         callers return 0 (graceful skip, never a module failure). Order of
#         checks (first hit wins): FS_GNOME_FORCE=1 => capable, silent
#         (operator override); any of SSH_CONNECTION/SSH_CLIENT/SSH_TTY set
#         => "SSH session"; XDG_CURRENT_DESKTOP set but not matching *GNOME*
#         => "not a GNOME session (XDG_CURRENT_DESKTOP=...)"; unset AND
#         neither DISPLAY nor WAYLAND_DISPLAY set => "no graphical session";
#         gsettings missing from PATH => "gsettings not found". Pure env
#         check, no probing, so it is safe in dry-run.
# gnome_gsettings_get <schema> <key>
#         print the current value (real mode only). Refuses under
#         FS_DRY_RUN (no probing) and when gsettings is absent.
# gnome_gsettings_set <schema> <key> <gvariant>
#         idempotent (skip-if-already-set) write via run_cmd; dry-run
#         renders `# would run: gsettings set ...` and never probes.
#         <gvariant> must be non-empty printable ASCII without tab/
#         newline/CR (scalar values may contain spaces and quotes). A
#         failed pre-write read aborts the set with rc1 and no write.
#         Equality is textual against the current value OR its single-quoted
#         rendering, because real `gsettings get` quotes string scalars
#         ('file:///x'); a bare target therefore matches an applied bare or
#         quoted value and is a no-op.
# gnome_strv_parse <gvariant>
#         print one array element per line. Accepts ['a', 'b'], @as [],
#         [], bare numeric tokens and backslash escapes (decoded); empty
#         input is the empty array; control bytes inside quoted elements
#         and anything else malformed -> rc1.
# gnome_strv_build [element...]
#         print ['a', 'b'] (or @as [] when no elements) with validated
#         elements; invalid element -> rc1 io_error.
# gnome_strv_merge <current> [new...]
#         parse <current>, append each unseen <new> once in the order
#         given (first-seen dedupe, existing order preserved), print the
#         merged array. <current> may be empty. This is the
#         read->merge->write primitive.
# gnome_custom_keybindings_merge_add <dconf-path...>
#         read->merge->write for org.gnome.settings-daemon.plugins.media-keys
#         custom-keybindings (prototype bug #4 fix): the existing array is
#         preserved and the given paths are appended once, deduped, and the
#         result written back. Dry-run renders the write of the new-only
#         merge (the current value is not probeable). Thin wrapper over
#         gnome_strv_merge_set.
# gnome_strv_merge_set <schema> <key> <new...>
#         generic read->merge->write of a string-array key (the favorites
#         merge and dock/background defaults): the current value is preserved
#         and each unseen <new> is appended once in order, then written back.
#         <schema> must be plain or relocatable; <key> plain. Dry-run renders
#         the write of the new-only build (the current value is not
#         probeable) and never probes. A failed pre-write read aborts rc1.
# gnome_shell_version
#         print the numeric GNOME Shell version token probed from
#         `gnome-shell --version` (real mode only: refuses under
#         FS_DRY_RUN with no probing; rc1 when gnome-shell is absent, the
#         probe fails, or the token is not digits/dots without leading,
#         trailing, or doubled dots -- so `50.5`, `3.38.4` are accepted,
#         anything else rejected). Used by P6.3 to report extension
#         compatibility notes -- always a report, never a write.
# gnome_extensions_list [--enabled]
#         print `gnome-extensions list` (all installed) or `gnome-extensions
#         list --enabled` output verbatim, one entry per line. Real mode only
#         (refuses probing in dry-run); rc1 when gnome-extensions is absent,
#         the flag is unknown, or the probe fails. Callers must expect bare
#         uuid lines (`name` only, no state/number columns); lines carrying
#         extra columns that fail the bare-uuid filter are dropped by the
#         consumer (see modules/gnome-extensions/hooks.sh).

gnome_gsettings_available() {
    command -v gsettings >/dev/null 2>&1
}

gnome_extensions_available() {
    command -v gnome-extensions >/dev/null 2>&1
}

gnome_require_capable() {
    local ctx="${1:-gnome}" reason="" desktop=""
    if [[ "${FS_GNOME_FORCE:-0}" == 1 ]]; then
        return 0
    fi
    if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
        reason="SSH session"
    else
        desktop="${XDG_CURRENT_DESKTOP:-}"
        if [[ -n "$desktop" && "$desktop" != *GNOME* ]]; then
            reason="not a GNOME session (XDG_CURRENT_DESKTOP='$desktop')"
        elif [[ -z "$desktop" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
            reason="no graphical session"
        elif ! gnome_gsettings_available; then
            reason="gsettings not found"
        fi
    fi
    if [[ -n "$reason" ]]; then
        io_info "$ctx: skipped (not GNOME) ($reason)"
        return 1
    fi
    return 0
}

_gnome_ok_id() {
    local v="$1"
    case "$v" in
    *[!A-Za-z0-9._-]* | "") return 1 ;;
    esac
    return 0
}

_gnome_ok_schema() {
    local s="$1" head="" rest="" seg="" t=""
    head="${s%%:*}"
    if [[ "$s" == "$head" ]]; then
        _gnome_ok_id "$s"
        return $?
    fi
    _gnome_ok_id "$head" || return 1
    rest="${s#*:}"
    case "$rest" in
    /*) ;;
    *) return 1 ;;
    esac
    case "$rest" in
    *"//"*) return 1 ;;
    esac
    t="${rest#/}"
    t="${t%/}"
    if [[ -z "$t" ]]; then
        return 1
    fi
    while [[ -n "$t" ]]; do
        seg="${t%%/*}"
        case "$seg" in
        "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
        esac
        if [[ "$t" != */* ]]; then
            break
        fi
        t="${t#*/}"
    done
    return 0
}

_gnome_ok_ele() {
    local e="$1" LC_ALL=C tab=$'\t' nl=$'\n' cr=$'\r'
    case "$e" in
    "" | *[\'\\]* | *\"* | *" "* | *"$tab"* | *"$nl"* | *"$cr"* | *[![:print:]]*) return 1 ;;
    esac
    return 0
}

_gnome_ok_val() {
    local v="$1" LC_ALL=C tab=$'\t' nl=$'\n' cr=$'\r'
    case "$v" in
    "" | *"$tab"* | *"$nl"* | *"$cr"* | *[!" "-\~]*) return 1 ;;
    esac
    return 0
}

_gnome_isspace() {
    case "$1" in
    ' ' | $'\t' | $'\n' | $'\r') return 0 ;;
    esac
    return 1
}

_gnome_parse_fail() {
    io_error "gnome_strv_parse: malformed GVariant array: $1"
    return 1
}

gnome_strv_parse() {
    local value="${1:-}" LC_ALL=C
    local s="$value" i=0 n=0 c="" el="" seen=0
    n=${#s}
    if [[ -z "$s" ]]; then
        return 0
    fi
    if [[ "${s:i:1}" == "@" ]]; then
        i=1
        while ((i < n)); do
            c="${s:i:1}"
            case "$c" in
            '[' | ' ' | $'\t') break ;;
            *) i=$((i + 1)) ;;
            esac
        done
    fi
    while ((i < n)) && _gnome_isspace "${s:i:1}"; do
        i=$((i + 1))
    done
    if ((i >= n)) || [[ "${s:i:1}" != "[" ]]; then
        _gnome_parse_fail "$value"
        return 1
    fi
    i=$((i + 1))
    while ((i < n)); do
        while ((i < n)) && _gnome_isspace "${s:i:1}"; do
            i=$((i + 1))
        done
        if ((i >= n)); then
            _gnome_parse_fail "$value"
            return 1
        fi
        c="${s:i:1}"
        if [[ "$c" == "]" ]]; then
            i=$((i + 1))
            while ((i < n)) && _gnome_isspace "${s:i:1}"; do
                i=$((i + 1))
            done
            if ((i < n)); then
                _gnome_parse_fail "$value"
                return 1
            fi
            return 0
        fi
        el=""
        if [[ "$c" == "'" ]]; then
            i=$((i + 1))
            seen=0
            while ((i < n)); do
                c="${s:i:1}"
                if [[ "$c" == "'" ]]; then
                    i=$((i + 1))
                    seen=1
                    break
                fi
                if [[ "$c" == "\\" ]]; then
                    i=$((i + 1))
                    if ((i >= n)); then
                        _gnome_parse_fail "$value"
                        return 1
                    fi
                    el+="${s:i:1}"
                    i=$((i + 1))
                    continue
                fi
                case "$c" in
                $'\t' | $'\n' | $'\r')
                    _gnome_parse_fail "$value"
                    return 1
                    ;;
                *[!" "-\~]*)
                    _gnome_parse_fail "$value"
                    return 1
                    ;;
                esac
                el+="$c"
                i=$((i + 1))
            done
            if ((seen != 1)); then
                _gnome_parse_fail "$value"
                return 1
            fi
        else
            while ((i < n)); do
                c="${s:i:1}"
                case "$c" in
                ',' | ']' | ' ' | $'\t' | $'\n' | $'\r') break ;;
                *)
                    el+="$c"
                    i=$((i + 1))
                    ;;
                esac
            done
        fi
        if [[ -z "$el" ]]; then
            _gnome_parse_fail "$value"
            return 1
        fi
        printf '%s\n' "$el"
        while ((i < n)) && _gnome_isspace "${s:i:1}"; do
            i=$((i + 1))
        done
        if ((i >= n)); then
            _gnome_parse_fail "$value"
            return 1
        fi
        c="${s:i:1}"
        case "$c" in
        ',') i=$((i + 1)) ;;
        ']')
            i=$((i + 1))
            while ((i < n)) && _gnome_isspace "${s:i:1}"; do
                i=$((i + 1))
            done
            if ((i < n)); then
                _gnome_parse_fail "$value"
                return 1
            fi
            return 0
            ;;
        *)
            _gnome_parse_fail "$value"
            return 1
            ;;
        esac
    done
    _gnome_parse_fail "$value"
    return 1
}

gnome_strv_build() {
    local -a els=("$@")
    if ((${#els[@]} == 0)); then
        printf '@as []\n'
        return 0
    fi
    local el bad="" first=1 LC_ALL=C
    for el in "${els[@]}"; do
        if ! _gnome_ok_ele "$el"; then
            bad="$el"
            break
        fi
    done
    if [[ -n "$bad" ]]; then
        io_error "gnome_strv_build: invalid array element: $bad"
        return 1
    fi
    printf '['
    for el in "${els[@]}"; do
        if ((first == 1)); then
            first=0
        else
            printf ', '
        fi
        printf "'%s'" "$el"
    done
    printf ']\n'
    return 0
}

gnome_strv_merge() {
    local current="${1:-}" out="" rc=0 new="" el="" seen=0 j=0
    local -a merged=()
    if [[ -n "$current" ]]; then
        rc=0
        out="$(gnome_strv_parse "$current")" || rc=$?
        if ((rc != 0)); then
            return 1
        fi
        if [[ -n "$out" ]]; then
            local IFS=$'\n'
            # shellcheck disable=SC2206  # intentional: word-splits parsed output into an array
            merged=($out)
        fi
    fi
    shift || true
    for new in "$@"; do
        if ! _gnome_ok_ele "$new"; then
            io_error "gnome_strv_merge: invalid element: $new"
            return 1
        fi
        seen=0
        if ((${#merged[@]} > 0)); then
            for j in "${!merged[@]}"; do
                if [[ "${merged[$j]}" == "$new" ]]; then
                    seen=1
                    break
                fi
            done
        fi
        if ((seen == 0)); then
            merged+=("$new")
        fi
    done
    gnome_strv_build "${merged[@]+"${merged[@]}"}"
    return "$?"
}

gnome_gsettings_get() {
    local schema="${1:-}" key="${2:-}" bin="" out="" rc=0
    if ! _gnome_ok_schema "$schema"; then
        io_error "gnome_gsettings_get: invalid schema: ${schema:-<empty>}"
        return 1
    fi
    if ! _gnome_ok_id "$key"; then
        io_error "gnome_gsettings_get: invalid key: ${key:-<empty>}"
        return 1
    fi
    if ((FS_DRY_RUN == 1)); then
        io_error "gnome_gsettings_get: cannot probe gsettings in dry-run ($schema $key)"
        return 1
    fi
    if ! gnome_gsettings_available; then
        io_error "gnome_gsettings_get: gsettings not found on PATH"
        return 1
    fi
    bin="$(command -v gsettings)"
    rc=0
    out="$("$bin" get "$schema" "$key" 2>/dev/null)" || rc=$?
    if ((rc != 0)); then
        io_error "gnome_gsettings_get: gsettings get failed ($schema $key)"
        return 1
    fi
    printf '%s\n' "$out"
    return 0
}

gnome_gsettings_set() {
    local schema="${1:-}" key="${2:-}" value="${3:-}" cur="" rc=0
    if ! _gnome_ok_schema "$schema"; then
        io_error "gnome_gsettings_set: invalid schema: ${schema:-<empty>}"
        return 1
    fi
    if ! _gnome_ok_id "$key"; then
        io_error "gnome_gsettings_set: invalid key: ${key:-<empty>}"
        return 1
    fi
    if ! _gnome_ok_val "$value"; then
        io_error "gnome_gsettings_set: invalid value for $key"
        return 1
    fi
    if ((FS_DRY_RUN == 0)); then
        rc=0
        cur="$(gnome_gsettings_get "$schema" "$key")" || rc=$?
        if ((rc != 0)); then
            return 1
        fi
        if [[ "$cur" == "$value" || "$cur" == "'$value'" ]]; then
            io_debug "gsettings $schema/$key already at target; no-op"
            return 0
        fi
    fi
    rc=0
    run_cmd "gsettings set $schema/$key" --stop -- gsettings set "$schema" "$key" "$value" || rc=$?
    return "$rc"
}

gnome_strv_merge_set() {
    local schema="${1:-}" key="${2:-}" current="" result="" rc=0
    shift 2 || true
    if (($# == 0)); then
        io_error "gnome_strv_merge_set requires at least one new element"
        return 1
    fi
    if ((FS_DRY_RUN == 1)); then
        rc=0
        result="$(gnome_strv_build "$@")" || rc=$?
        if ((rc != 0)); then
            return 1
        fi
        rc=0
        gnome_gsettings_set "$schema" "$key" "$result" || rc=$?
        return "$rc"
    fi
    rc=0
    current="$(gnome_gsettings_get "$schema" "$key")" || rc=$?
    if ((rc != 0)); then
        return 1
    fi
    rc=0
    result="$(gnome_strv_merge "$current" "$@")" || rc=$?
    if ((rc != 0)); then
        return 1
    fi
    rc=0
    gnome_gsettings_set "$schema" "$key" "$result" || rc=$?
    return "$rc"
}

gnome_custom_keybindings_merge_add() {
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local key="custom-keybindings"
    if (($# == 0)); then
        io_error "gnome_custom_keybindings_merge_add requires at least one dconf path"
        return 1
    fi
    gnome_strv_merge_set "$schema" "$key" "$@"
}

gnome_shell_version() {
    local bin="" out="" rc=0 version=""
    if ((FS_DRY_RUN == 1)); then
        io_error "gnome_shell_version: cannot probe gnome-shell version in dry-run"
        return 1
    fi
    if ! command -v gnome-shell >/dev/null 2>&1; then
        io_error "gnome_shell_version: gnome-shell not found on PATH"
        return 1
    fi
    bin="$(command -v gnome-shell)"
    rc=0
    out="$("$bin" --version 2>/dev/null)" || rc=$?
    if ((rc != 0)); then
        io_error "gnome_shell_version: gnome-shell --version failed"
        return 1
    fi
    version="${out##* }"
    case "$version" in
    "" | *[!0-9.]* | *..* | .* | *.)
        io_error "gnome_shell_version: cannot parse version from: $out"
        return 1
        ;;
    esac
    printf '%s\n' "$version"
    return 0
}

gnome_extensions_list() {
    local flag="${1:-}" bin="" out="" rc=0
    if ((FS_DRY_RUN == 1)); then
        io_error "gnome_extensions_list: cannot probe gnome-extensions in dry-run"
        return 1
    fi
    if ! gnome_extensions_available; then
        io_error "gnome_extensions_list: gnome-extensions not found on PATH"
        return 1
    fi
    case "$flag" in
    --enabled) ;;
    "") ;;
    *)
        io_error "gnome_extensions_list: unknown flag: $flag"
        return 1
        ;;
    esac
    bin="$(command -v gnome-extensions)"
    local -a args=("$bin" list)
    if [[ -n "$flag" ]]; then
        args+=("$flag")
    fi
    rc=0
    out="$("${args[@]}" 2>/dev/null)" || rc=$?
    if ((rc != 0)); then
        io_error "gnome_extensions_list: gnome-extensions list failed"
        return 1
    fi
    if [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    fi
    return 0
}
