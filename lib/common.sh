#!/bin/bash
# Shared helpers for setup and modules

distribution(){
    local file="${OS_RELEASE_FILE:-/etc/os-release}"
    local line word dtype="unknown" id="" id_like=""
    local -a like_words=()

    if [ ! -r "$file" ]; then
        echo "$dtype"
        return 0
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ID_LIKE=*) id_like="${line#ID_LIKE=}" ;;
            ID=*) id="${line#ID=}" ;;
        esac
    done < "$file"

    id="${id#\"}"
    id="${id%\"}"
    id="${id#\'}"
    id="${id%\'}"
    id_like="${id_like#\"}"
    id_like="${id_like%\"}"
    id_like="${id_like#\'}"
    id_like="${id_like%\'}"

    case "$id" in
        fedora|rhel|centos) dtype="redhat" ;;
        ubuntu|debian) dtype="debian" ;;
        arch|cachyos) dtype="arch" ;;
        *)
            read -ra like_words <<< "$id_like"
            for word in "${like_words[@]}"; do
                case "$word" in
                    fedora|rhel|centos) dtype="redhat"; break ;;
                    ubuntu|debian) dtype="debian"; break ;;
                    arch|cachyos) dtype="arch"; break ;;
                esac
            done
            ;;
    esac

    echo "$dtype"
}

# Print the detected desktop environment as a lowercase token.
# Uses XDG_CURRENT_DESKTOP (colon-separated list) with DESKTOP_SESSION fallback.
desktop_environment(){
    local raw="${XDG_CURRENT_DESKTOP:-}" session="${DESKTOP_SESSION:-}"
    local entry lower

    local IFS=':'
    for entry in $raw; do
        lower=$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            gnome) echo "gnome"; return 0 ;;
            hyprland) echo "hyprland"; return 0 ;;
            kde) echo "kde"; return 0 ;;
            xfce) echo "xfce"; return 0 ;;
            sway) echo "sway"; return 0 ;;
        esac
    done

    lower=$(printf '%s' "$session" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *gnome*) echo "gnome" ;;
        *hypr*) echo "hyprland" ;;
        *kde*) echo "kde" ;;
        *) echo "unknown" ;;
    esac
}

# Run a command, or print it when SETUP_DRY_RUN=1.
run(){
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        printf 'would run:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

# Run a command with sudo, or print it when SETUP_DRY_RUN=1.
run_root(){
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        printf 'would run: sudo'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    sudo "$@"
}
