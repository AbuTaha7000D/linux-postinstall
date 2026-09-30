#!/usr/bin/env bash
# lib/ui.sh - interactive prompts and selection UI (P4.7).
# Depends on lib/io.sh for io_error/io_warn (source io.sh first). Reads
# from stdin, writes prompts/checklists to stdout, uses Bash builtins plus
# dirname/mktemp/mv/rm/grep -c -- no external TUI tool, no ncurses/dialog/
# whiptail; Bash >= 4.3 floor: no
# namerefs, no associative-array iteration, guarded empty-array
# expansions). Two interaction modes, chosen per call via ui_tty_mode:
#
#   tty mode  (stdin AND stdout are terminals): a single-character raw-key
#              loop (`read -rsn1`). The checklist is redrawn in place with
#              ANSI cursor-up + erase after every key. Keys: 1..N toggle
#              that row, `a` selects all non-high-risk rows, `n` clears the
#              selection, `q` aborts (rc1, no write), Enter accepts. Colors
#              only when stdout is a TTY and FS_NO_COLOR is 0 (numeric --
#              lib/io.sh normalizes it, so a `-z` test would be false for
#              the string "0" and the red flag would never render; that was
#              a real P8.3 bug, see lib/io.sh's header).
#   line mode (anything else; pipes, scripts, CI): one prompt per line, and
#              each accepted line re-renders the whole checklist (the
#              scripted-fixture path, fully deterministic). Replies:
#              space/comma-separated row NUMBERS toggle those rows, `a` all
#              non-high-risk, `n` none, `q` abort (rc1, no write), Enter
#              accepts. EOF on stdin aborts rc1 -- the UI never silently
#              proceeds.
# High-risk rows (risk=high|destructive) are never toggleable by a row
# number or `a`; the opt-in prompt after acceptance is their only
# checklist route. A high-risk id pre-seeded in the selection file stays
# checked and is the caller's responsibility; bootstrap never pre-seeds a
# high-risk id except as an explicit CLI module. The final selection is
# written to <sel_file> atomically (same-dir temp + rename), in
# entries-file order, one id per line. rc0 accepts, rc1 aborts.
# ui_confirm is line-based in BOTH modes and returns 0 without prompting
# when FS_YES=1 (controllers unset it first to force a real prompt).
# Prompts are plain printf to stdout (not io_* lines)
# so the conversation reads naturally on a terminal; errors/warnings still
# go through io_*.

ui_tty_mode() {
    [[ -t 0 && -t 1 ]]
}

_ui_color_red() {
    if ((${FS_NO_COLOR:-0} == 0)) && [[ -t 1 ]]; then
        printf '\033[31m'
    fi
    return 0
}

_ui_color_reset() {
    if ((${FS_NO_COLOR:-0} == 0)) && [[ -t 1 ]]; then
        printf '\033[0m'
    fi
    return 0
}

_ui_emit_list() {
    local title="$1" entries="$2" lvls="$3" high_s="$4"
    local -a cv=() hh=()
    if [[ -n "$lvls" ]]; then
        IFS=' ' read -ra cv <<<"$lvls"
    fi
    if [[ -n "$high_s" ]]; then
        IFS=' ' read -ra hh <<<"$high_s"
    fi
    local line="" id="" ttl="" rk="" i=0 c="" mark="" ishr=""
    printf '%s\n' "$title"
    if [[ -f "$entries" ]]; then
        while IFS= read -r line; do
            IFS=$'\t' read -r id ttl rk <<<"$line"
            [[ -n "$id" ]] || continue
            mark=" "
            ishr=""
            for c in ${hh[@]+"${hh[@]}"}; do
                if ((c == i)); then
                    ishr=1
                fi
            done
            if ((i < ${#cv[@]})) && ((cv[i] == 1)); then
                mark="x"
            fi
            if [[ -n "$ishr" ]]; then
                _ui_color_red
            fi
            printf '[%s] %s - %s' "$mark" "$id" "$ttl"
            if [[ -n "$ishr" ]]; then
                printf '  [high-risk]'
                _ui_color_reset
            fi
            printf '\n'
            i=$((i + 1))
        done <"$entries"
    fi
}

_ui_rows() {
    local entries="$1" n=0
    if [[ -f "$entries" ]]; then
        n="$(grep -c . "$entries" 2>/dev/null || true)"
        n="${n:-0}"
    fi
    printf '%s' "$((n + 2))"
}

_ui_write_sel() {
    local sel="$1"
    shift
    local dir="" tmp="" id=""
    dir="$(dirname -- "$sel")"
    if [[ ! -d "$dir" ]]; then
        io_error "selection directory missing: $dir"
        return 1
    fi
    tmp="$(mktemp "${dir}/.fs-ui.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create selection temp file in: $dir"
        return 1
    }
    if (($# > 0)); then
        for id; do
            printf '%s\n' "$id"
        done >"$tmp" || {
            io_error "cannot write selection temp file"
            rm -f -- "$tmp"
            return 1
        }
    else
        : >"$tmp"
    fi
    mv -fT -- "$tmp" "$sel" || {
        io_error "cannot commit selection file: $sel"
        rm -f -- "$tmp"
        return 1
    }
    return 0
}

ui_confirm() {
    local prompt="${1:-}" default="${2:-n}"
    local answer="" suff="" rc=1
    if ((${FS_YES:-0} == 1)); then
        return 0
    fi
    case "$default" in
    y | Y | yes | YES)
        suff="[Y/n]"
        rc=0
        ;;
    *)
        suff="[y/N]"
        ;;
    esac
    while :; do
        printf '%s %s ' "$prompt" "$suff"
        IFS= read -r answer || return "$rc"
        answer="${answer,,}"
        case "$answer" in
        "")
            return "$rc"
            ;;
        y | yes)
            return 0
            ;;
        n | no)
            return 1
            ;;
        *)
            printf 'please answer y or n\n'
            ;;
        esac
    done
}

ui_multiselect() {
    local title="${1:-}" entries="${2:-}" sel="${3:-}"
    if [[ -z "$title" || -z "$entries" || -z "$sel" ]]; then
        io_error "ui_multiselect requires a title, an entries file, and a selection file"
        return 1
    fi
    local -a rows=() eid=() etitle=() erisk=() checked=() high=()
    local -a toks=() selids=()
    local line="" id="" ttl="" rk="" i=0 key="" lvls="" his="" nrows=0 t="" j=""
    local opt="" found=""
    if [[ ! -r "$entries" ]]; then
        io_error "cannot read entries: $entries"
        return 1
    fi
    mapfile -t rows <"$entries"
    for line in ${rows[@]+"${rows[@]}"}; do
        IFS=$'\t' read -r id ttl rk <<<"$line"
        [[ -n "$id" ]] || continue
        eid+=("$id")
        etitle+=("$ttl")
        erisk+=("${rk:-none}")
        checked+=(0)
        case "${rk:-none}" in
        high | destructive) high+=("$((${#eid[@]} - 1))") ;;
        esac
    done
    if ((${#eid[@]} == 0)); then
        _ui_write_sel "$sel"
        return $?
    fi
    if [[ -f "$sel" ]]; then
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            for ((i = 0; i < ${#eid[@]}; i++)); do
                if [[ "${eid[i]}" == "$id" ]]; then
                    checked[i]=1
                fi
            done
        done <"$sel"
    fi
    while :; do
        lvls=""
        his=""
        for ((i = 0; i < ${#eid[@]}; i++)); do
            lvls="$lvls$((checked[i])) "
        done
        for j in ${high[@]+"${high[@]}"}; do
            his="$his$j "
        done
        nrows="$(_ui_rows "$entries")"
        if ui_tty_mode; then
            printf '\033[%dA\033[J' "$nrows"
            _ui_emit_list "$title" "$entries" "${lvls% }" "${his% }"
            printf '(digits: toggle | a: all | n: none | q: quit | Enter: accept)\n'
            IFS= read -rsn1 key || return 1
            case "$key" in
            [0-9])
                if ((key >= 1 && key <= ${#eid[@]})); then
                    i=$((key - 1))
                    case "${erisk[i]}" in
                    high | destructive) : ;;
                    *)
                        if ((checked[i] == 1)); then
                            checked[i]=0
                        else
                            checked[i]=1
                        fi
                        ;;
                    esac
                fi
                ;;
            a | A)
                for ((i = 0; i < ${#eid[@]}; i++)); do
                    case "${erisk[i]}" in
                    high | destructive) : ;;
                    *) checked[i]=1 ;;
                    esac
                done
                ;;
            n | N)
                for ((i = 0; i < ${#eid[@]}; i++)); do
                    checked[i]=0
                done
                ;;
            q | Q)
                return 1
                ;;
            $'\n' | $'\r')
                break
                ;;
            *) : ;;
            esac
        else
            _ui_emit_list "$title" "$entries" "${lvls% }" "${his% }"
            printf "toggle (ids, 'a', 'n'; 'q' quit; Enter accept): "
            IFS= read -r line || return 1
            case "$line" in
            "")
                break
                ;;
            q | Q)
                return 1
                ;;
            a | A)
                for ((i = 0; i < ${#eid[@]}; i++)); do
                    case "${erisk[i]}" in
                    high | destructive) : ;;
                    *) checked[i]=1 ;;
                    esac
                done
                ;;
            n | N)
                for ((i = 0; i < ${#eid[@]}; i++)); do
                    checked[i]=0
                done
                ;;
            *)
                IFS=' ,' read -ra toks <<<"$line"
                for t in ${toks[@]+"${toks[@]}"}; do
                    case "$t" in
                    '' | *[!0-9]*)
                        io_warn "ignoring non-numeric toggle: '$t'"
                        ;;
                    *)
                        if ((10#$t >= 1 && 10#$t <= ${#eid[@]})); then
                            case "${erisk[10#$t - 1]}" in
                            high | destructive)
                                io_warn "high-risk module ${eid[10#$t - 1]} cannot be toggled here (use the opt-in prompt)"
                                ;;
                            *)
                                i=$((10#$t - 1))
                                if ((checked[i] == 1)); then
                                    checked[i]=0
                                else
                                    checked[i]=1
                                fi
                                ;;
                            esac
                        else
                            io_warn "no such row: $t"
                        fi
                        ;;
                    esac
                done
                ;;
            esac
        fi
    done
    if ((${#high[@]} > 0)); then
        printf 'Enable high-risk modules (ids, space/comma separated; Enter to skip): '
        IFS= read -r line || return 1
        if [[ -n "$line" ]]; then
            IFS=' ,' read -ra toks <<<"$line"
            for opt in ${toks[@]+"${toks[@]}"}; do
                found=0
                for j in ${high[@]+"${high[@]}"}; do
                    if [[ "${eid[j]}" == "$opt" ]]; then
                        checked[j]=1
                        found=1
                    fi
                done
                if ((found == 0)); then
                    io_warn "not a high-risk module: $opt"
                fi
            done
        fi
    fi
    for ((i = 0; i < ${#eid[@]}; i++)); do
        if ((checked[i] == 1)); then
            selids+=("${eid[i]}")
        fi
    done
    _ui_write_sel "$sel" ${selids[@]+"${selids[@]}"}
    return $?
}
