#!/usr/bin/env bash
# modules/locale.sh - system locale.
#
# Destructive: it changes the whole system's language. Not in
# config/modules.txt; run it on purpose with ./setup install locale.
#
#   FS_LOCALE           target locale, default en_US.UTF-8
#   FS_LOCALE_REVERT=1  put the previously recorded locale back
#
# The previous value is written to .locale-backup next to the module on the
# first run, so the revert needs no state from this script.

install_locale() {
    have localectl || {
        log_warn "localectl not found (not a systemd host); skipping"
        return 0
    }
    local backup="$FS_ROOT/.locale-backup"
    local want="${FS_LOCALE:-en_US.UTF-8}"
    local current

    if (( ${FS_LOCALE_REVERT:-0} )); then
        [[ -f "$backup" ]] || {
            log_error "no $backup to revert from"
            return 1
        }
        want="$(<"$backup")"
        log_info "reverting locale to $want"
    else
        current="$(_locale_current)"
        log_info "current locale: ${current:-none}"
        if [[ ! -f "$backup" ]]; then
            printf '%s\n' "$current" >"$backup" || {
                log_error "cannot write $backup"
                return 1
            }
        fi
    fi

    [[ "$(_locale_current)" == "$want" ]] && {
        log_info "unchanged: locale is already $want"
        return 0
    }

    run_root "set locale" localectl set-locale "LANG=$want"

    if [[ "$(_locale_current)" != "$want" ]]; then
        log_error "localectl reported success but the locale is still ${current:-unknown}"
        return 1
    fi
    log_info "locale set to $want (previous value in $backup)"
}

_locale_current() {
    local line
    while IFS= read -r line; do
        case "$line" in
        *"System Locale:"*)
            line="${line#*System Locale:}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line#LANG=}"
            line="${line#\"}"
            line="${line%\"}"
            printf '%s' "$line"
            return 0
            ;;
        esac
    done < <(localectl status 2>/dev/null)
    return 0
}
