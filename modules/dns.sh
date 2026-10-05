#!/usr/bin/env bash
# modules/dns.sh - DNS servers on a NetworkManager connection.
#
# Destructive: it changes system-wide name resolution. Not in
# config/modules.txt; run it on purpose with ./setup install dns.
#
#   FS_DNS_CONNECTION   connection to change (default: the active one)
#   FS_DNS_SERVERS      space-separated servers, default 8.8.8.8 8.8.4.4
#   FS_DNS_REVERT=1     put the previously recorded servers back
#
# The previous value is written to .dns-backup next to the module on the first
# run, so the revert needs no state from this script.

install_dns() {
    have nmcli || {
        log_warn "nmcli not found (not a NetworkManager host); skipping"
        return 0
    }
    local backup="$FS_ROOT/.dns-backup"
    local name="${FS_DNS_CONNECTION:-}"
    local want="${FS_DNS_SERVERS:-8.8.8.8 8.8.4.4}"
    local current csv

    if [[ -z "$name" ]]; then
        name="$(_dns_active)"
        [[ -n "$name" ]] || {
            log_error "no active NetworkManager connection; set FS_DNS_CONNECTION"
            return 1
        }
    fi

    if (( ${FS_DNS_REVERT:-0} )); then
        [[ -f "$backup" ]] || {
            log_error "no $backup to revert from"
            return 1
        }
        read -r name want <"$backup"
        log_info "reverting $name to $want"
    else
        current="$(_dns_servers "$name")"
        log_info "$name current DNS: ${current:-none}"
        if [[ ! -f "$backup" ]]; then
            printf '%s %s\n' "$name" "$current" >"$backup" || {
                log_error "cannot write $backup"
                return 1
            }
        fi
    fi

    [[ "$(_dns_servers "$name")" == "$want" ]] && {
        log_info "unchanged: $name already resolves via $want"
        return 0
    }

    csv="${want// /,}"
    run_root "set DNS on $name" nmcli connection modify "$name" \
        ipv4.dns "$csv" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
    run_root "reapply $name" nmcli connection up "$name"

    if [[ "$(_dns_servers "$name")" != "$want" ]]; then
        log_error "nmcli reported success but $name still resolves via $(_dns_servers "$name")"
        return 1
    fi
    log_info "DNS set to $want (previous value in $backup)"
}

_dns_active() {
    local line
    while IFS= read -r line; do
        case "$line" in
        *"NAME="*)
            line="${line#*NAME=}"
            printf '%s' "${line%%|*}"
            return 0
            ;;
        esac
    done < <(nmcli -t -f NAME connection show --active 2>/dev/null)
    return 0
}

_dns_servers() {
    nmcli -t -f ipv4.dns connection show "$1" 2>/dev/null | head -1 |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/,/ /g; s/[[:space:]][[:space:]]*/ /g'
}
