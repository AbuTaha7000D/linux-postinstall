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

# Select the Fedora package that provides the unversioned node/npm commands.
# Fedora 44 split these links into versioned binary subpackages.
fedora_node_npm_package(){
    local file="${OS_RELEASE_FILE:-/etc/os-release}" line version_id=""
    if [ -r "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in VERSION_ID=*) version_id="${line#VERSION_ID=}" ;; esac
        done < "$file"
    fi
    version_id="${version_id#\"}"
    version_id="${version_id%\"}"
    version_id="${version_id#\'}"
    version_id="${version_id%\'}"
    if [[ "$version_id" =~ ^([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -ge 44 ]; then
        printf '%s\n' nodejs24-npm-bin
    else
        printf '%s\n' nodejs-npm
    fi
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

# Ensure sudo credentials before a privileged operation. Lazy: only called
# from run_root, so authentication happens exactly when a privileged command
# is about to run. Uses native credential caching: a non-interactive probe
# first (also refreshes a still-valid timestamp), then a single interactive
# sudo -v if the probe fails. If sudo is not installed at all, that missing
# prerequisite is reported clearly instead of as an authentication failure.
# Sudo timestamps are shared state, so setup does
# not try to clear them with sudo -k; sudo expires them according to its policy.
# Dry-run never touches credentials. Failure prints once and returns nonzero;
# no retry loop, so a cancelled prompt cannot hang the run.
ensure_sudo(){
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        return 0
    fi
    if [ "${SUDO_AUTH_FAILED:-0}" = "1" ]; then
        return 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        SUDO_AUTH_FAILED=1
        echo "Error: sudo is required for privileged operations but is not installed." >&2
        return 1
    fi
    if sudo -n -v >/dev/null 2>&1; then
        return 0
    fi
    if sudo -v; then
        return 0
    fi
    SUDO_AUTH_FAILED=1
    echo "Error: sudo authentication failed." >&2
    return 1
}

# Run a command with sudo, or print it when SETUP_DRY_RUN=1. The single path
# for privileged operations: authenticate lazily, then run through sudo.
run_root(){
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        printf 'would run: sudo'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    ensure_sudo || return 1
    sudo "$@"
}

# Make the yay AUR helper available on Arch, bootstrapping it from the AUR only
# when it is missing. Returns 0 when yay is already installed or is built
# successfully, and nonzero on any failure so the caller decides how to report
# it. Shared by modules/install_apps.sh and modules/dev.sh. The privileged
# base-devel and git install goes through run_root; the clone and makepkg build
# run unprivileged. git is provided before the clone because the AUR yay package
# depends on it and the clone itself cannot run without it. The build directory
# is removed before returning, so this helper installs no EXIT trap of its own
# and cannot disturb a caller's cleanup.
ensure_yay(){
    if command -v yay >/dev/null 2>&1; then
        return 0
    fi

    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        # run_root prints the privileged line; the unprivileged build steps are
        # printed explicitly so the plan output stays stable.
        run_root pacman -S --needed --noconfirm base-devel git
        echo "would run: git clone --depth 1 https://aur.archlinux.org/yay.git"
        echo "would run: makepkg -si --noconfirm"
        return 0
    fi

    if ! run_root pacman -S --needed --noconfirm base-devel git; then
        echo "Error: failed to install base-devel and git for yay bootstrap." >&2
        return 1
    fi
    if ! command -v makepkg >/dev/null 2>&1; then
        echo "Error: makepkg is still unavailable after installing base-devel." >&2
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is still unavailable after installing it for the yay bootstrap." >&2
        return 1
    fi

    local yay_tmp yay_rc=0
    if ! yay_tmp=$(mktemp -d); then
        echo "Error: failed to create a temporary directory for yay." >&2
        return 1
    fi

    if ! run git clone --depth 1 https://aur.archlinux.org/yay.git "$yay_tmp/yay"; then
        echo "Error: failed to clone yay from AUR." >&2
        yay_rc=1
    elif ! (cd "$yay_tmp/yay" && run makepkg -si --noconfirm); then
        echo "Error: failed to build and install yay." >&2
        yay_rc=1
    elif ! command -v yay >/dev/null 2>&1; then
        echo "Error: yay build failed." >&2
        yay_rc=1
    fi

    if ! rm -rf "$yay_tmp"; then
        echo "Error: failed to remove the yay temporary directory: $yay_tmp" >&2
        yay_rc=1
    fi
    return "$yay_rc"
}
