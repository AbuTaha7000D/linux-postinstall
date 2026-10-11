#!/bin/bash
# Terminal stack: select the default shell, install and verify the selected
# shell (falling back to Bash when it cannot be verified), install Atuin and
# Starship when missing, configure the selected shell, then chsh to it.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DRY=0
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    DRY=1
fi

ATUIN_INSTALL_CMD="curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh | ATUIN_NO_MODIFY_PATH=1 sh"
STARSHIP_INSTALL_CMD='curl -sS https://starship.rs/install.sh | sh -s -- -y'
STARSHIP_CONFIG_SOURCE="$SCRIPT_DIR/config/starship.toml"
STARSHIP_CONFIG_TARGET="$HOME/.config/starship.toml"
STARSHIP_CONFIG_BACKUP="$STARSHIP_CONFIG_TARGET.linux-postinstall.bak"

if [ ! -r "$STARSHIP_CONFIG_SOURCE" ]; then
    echo "Error: Starship configuration source is missing or unreadable: $STARSHIP_CONFIG_SOURCE" >&2
    exit 1
fi

# Both official installers require curl. Keep terminal standalone by ensuring
# it first, using the same family package-manager and privilege helpers as the
# selected-shell install below.
ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        echo "curl is already installed."
        return 0
    fi

    local dtype
    dtype=$(distribution)
    if [ "$DRY" -eq 0 ]; then
        echo "Installing required curl..."
    else
        echo "curl is missing; planning its installation."
    fi

    case "$dtype" in
        redhat)
            run_root dnf install -y curl || { echo "Error: failed to install required curl with dnf." >&2; return 1; }
            ;;
        debian)
            run_root apt-get update || { echo "Error: failed to refresh the apt package index for curl." >&2; return 1; }
            run_root apt-get install -y curl || { echo "Error: failed to install required curl with apt-get." >&2; return 1; }
            ;;
        arch)
            run_root pacman -S --noconfirm curl || { echo "Error: failed to install required curl with pacman." >&2; return 1; }
            ;;
        *)
            echo "Error: cannot install required curl on unsupported distribution ($dtype)." >&2
            return 1
            ;;
    esac

    if [ "$DRY" -eq 0 ] && ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl installation completed but the curl command is still unavailable." >&2
        return 1
    fi
}

ensure_curl || exit 1

# Stage 1: shell selection. Interactive with a 5-second default; non-TTY
# input skips the menu and uses Bash without blocking.
shell_key="bash"
if [ -t 0 ]; then
    echo "Choose your default shell:"
    echo
    echo "  1) Bash"
    echo "  2) Zsh"
    echo "  3) Fish"
    echo
    echo "Default: Bash"
    echo
    echo "You have 5 seconds to choose:"
    input=""
    read -t 5 -r input || input=""
    case "$input" in
        2) shell_key="zsh" ;;
        3) shell_key="fish" ;;
        *) shell_key="bash" ;;
    esac
fi

# Map shell_key to the shell name, binary, rc file, and init lines. Called
# once after selection and again if the selected shell falls back to Bash.
apply_shell_selection() {
    case "$shell_key" in
        zsh)
            shell_name="Zsh"
            shell_bin="zsh"
            rc_file="$HOME/.zshrc"
            atuin_init='eval "$(atuin init zsh)"'
            atuin_path_init='case ":$PATH:" in *":$HOME/.atuin/bin:"*) ;; *) export PATH="$HOME/.atuin/bin:$PATH" ;; esac'
            starship_init='eval "$(starship init zsh)"'
            ;;
        fish)
            shell_name="Fish"
            shell_bin="fish"
            rc_file="$HOME/.config/fish/config.fish"
            atuin_init='atuin init fish | source'
            atuin_path_init='if not contains -- "$HOME/.atuin/bin" $PATH; set -gx PATH "$HOME/.atuin/bin" $PATH; end'
            starship_init='starship init fish | source'
            ;;
        *)
            shell_name="Bash"
            shell_bin="bash"
            rc_file="$HOME/.bashrc"
            atuin_init='eval "$(atuin init bash)"'
            atuin_path_init='case ":$PATH:" in *":$HOME/.atuin/bin:"*) ;; *) export PATH="$HOME/.atuin/bin:$PATH" ;; esac'
            starship_init='eval "$(starship init bash)"'
            ;;
    esac
}
apply_shell_selection
echo "Selected shell: $shell_name."

# Stage 2: ensure the selected shell is installed (family package manager),
# then verify it really exists. A package-manager failure or a successful
# install that leaves the shell missing is recovered by falling back to Bash
# before any configuration or chsh. Dry-run only prints would-run lines and
# never verifies or falls back on simulated results.
install_shell_package() {
    local pkg="$1" dtype
    dtype=$(distribution)
    case "$dtype" in
        redhat)
            run_root dnf install -y "$pkg" || { echo "Warning: failed to install $pkg (dnf)." >&2; return 1; }
            ;;
        debian)
            run_root apt-get update || { echo "Warning: failed to refresh the apt package index." >&2; return 1; }
            run_root apt-get install -y "$pkg" || { echo "Warning: failed to install $pkg (apt-get)." >&2; return 1; }
            ;;
        arch)
            run_root pacman -S --noconfirm "$pkg" || { echo "Warning: failed to install $pkg (pacman)." >&2; return 1; }
            ;;
        *)
            echo "Warning: cannot install $pkg: unsupported distribution ($dtype)." >&2
            return 1
            ;;
    esac
}

if [ "$shell_key" = "bash" ]; then
    echo "$shell_name is already installed."
elif command -v "$shell_bin" >/dev/null 2>&1; then
    echo "$shell_name is already installed."
elif [ "$DRY" -eq 1 ]; then
    install_shell_package "$shell_bin"
else
    echo "Installing $shell_name..."
    install_shell_package "$shell_bin" || true
    if ! command -v "$shell_bin" >/dev/null 2>&1; then
        echo "Warning: $shell_name installation could not be verified." >&2
        echo "Falling back to Bash."
        shell_key="bash"
        apply_shell_selection
        echo "Selected shell: $shell_name."
        if ! command -v "$shell_bin" >/dev/null 2>&1; then
            echo "Error: bash not found after falling back." >&2
            exit 1
        fi
    fi
fi

# Stage 3: install Atuin's official binary installer directly. Unlike the
# setup.atuin.sh wrapper, this does not edit shell or agent configuration and
# has no import/account prompts. Disable cargo-dist PATH editing; this module
# adds the Atuin binary directory only to the selected shell's rc file below.
atuin_present() {
    command -v atuin >/dev/null 2>&1 || [ -x "$HOME/.atuin/bin/atuin" ]
}

if atuin_present; then
    echo "Atuin is already installed."
elif [ "$DRY" -eq 1 ]; then
    echo "would run: $ATUIN_INSTALL_CMD"
else
    echo "Installing Atuin (official binary installer)..."
    sh -c "$ATUIN_INSTALL_CMD" || { echo "Error: Atuin installation failed." >&2; exit 1; }
    if ! atuin_present; then
        echo "Error: Atuin installation failed (atuin not found after running the installer)." >&2
        exit 1
    fi
fi

atuin_path_needed=0
if ! command -v atuin >/dev/null 2>&1 && { [ -x "$HOME/.atuin/bin/atuin" ] || [ "$DRY" -eq 1 ]; }; then
    atuin_path_needed=1
fi

# Stage 4: ensure Starship is installed (official installer only).
starship_present() {
    command -v starship >/dev/null 2>&1
}

if starship_present; then
    echo "Starship is already installed."
elif [ "$DRY" -eq 1 ]; then
    echo "would run: $STARSHIP_INSTALL_CMD"
else
    echo "Installing Starship (official installer)..."
    # The installer self-elevates for /usr/local/bin; authenticate first so
    # the only password prompt happens at a clean point, never mid-pipeline.
    ensure_sudo || exit 1
    if ! sh -c "$STARSHIP_INSTALL_CMD"; then
        echo "Error: Starship installation failed (official installer)." >&2
        exit 1
    fi
    if ! starship_present; then
        echo "Error: Starship installation failed (starship not found after running the installer)." >&2
        exit 1
    fi
fi

# Stages 5 and 6: configure Atuin and Starship in the selected shell's file
# only. Exact-line guards; user content outside the appended lines is kept.
ensure_init_line() { # $1=file, $2=line, $3=label, $4=optional broader detection substring
    local found=0
    if [ -n "${4:-}" ]; then
        if grep -qF "$4" "$1" 2>/dev/null; then found=1; fi
    else
        if grep -qxF "$2" "$1" 2>/dev/null; then found=1; fi
    fi
    if [ "$found" -eq 1 ]; then
        echo "$3 init already present in $1."
    elif [ "$DRY" -eq 1 ]; then
        echo "would run: add '$2' to $1"
    else
        printf '%s\n' "$2" >> "$1"
        echo "Added $3 init to $1."
    fi
}

# Install the project Starship config, preserving an existing user config once.
configure_starship() {
    if [ -L "$STARSHIP_CONFIG_TARGET" ] || { [ -e "$STARSHIP_CONFIG_TARGET" ] && [ ! -f "$STARSHIP_CONFIG_TARGET" ]; }; then
        echo "Error: refusing to replace non-regular Starship config: $STARSHIP_CONFIG_TARGET" >&2
        return 1
    fi
    if [ -f "$STARSHIP_CONFIG_TARGET" ] && { [ -L "$STARSHIP_CONFIG_BACKUP" ] || { [ -e "$STARSHIP_CONFIG_BACKUP" ] && [ ! -f "$STARSHIP_CONFIG_BACKUP" ]; }; }; then
        echo "Error: existing Starship config backup is not a regular file: $STARSHIP_CONFIG_BACKUP" >&2
        return 1
    fi

    run mkdir -p "$HOME/.config" || {
        echo "Error: failed to create Starship config directory: $HOME/.config" >&2
        return 1
    }

    if [ -f "$STARSHIP_CONFIG_TARGET" ] && [ ! -e "$STARSHIP_CONFIG_BACKUP" ]; then
        run cp -p -- "$STARSHIP_CONFIG_TARGET" "$STARSHIP_CONFIG_BACKUP" || {
            echo "Error: failed to back up existing Starship config to $STARSHIP_CONFIG_BACKUP" >&2
            return 1
        }
    fi

    run cp -p -- "$STARSHIP_CONFIG_SOURCE" "$STARSHIP_CONFIG_TARGET" || {
        echo "Error: failed to install Starship config at $STARSHIP_CONFIG_TARGET" >&2
        return 1
    }
}

configure_starship || exit 1

if [ "$shell_key" = "fish" ] && [ "$DRY" -eq 0 ]; then
    mkdir -p "$HOME/.config/fish"
fi

# A prior Atuin wrapper run may have written a guarded Fish block (`if status
# is-interactive` ... `atuin init fish | source` ... `end`). Detect the broader
# substring so an existing config does not receive a second Atuin init.
atuin_detect=""
if [ "$shell_key" = "fish" ]; then
    atuin_detect="atuin init fish"
fi
if [ "$atuin_path_needed" -eq 1 ]; then
    ensure_init_line "$rc_file" "$atuin_path_init" "Atuin PATH"
fi
ensure_init_line "$rc_file" "$atuin_init" "Atuin" "$atuin_detect"
ensure_init_line "$rc_file" "$starship_init" "Starship"

# Stage 7: make the selected shell the default, after all configuration
# succeeded. The actual login shell comes from getent, with $SHELL as fallback.
pw_entry=$(getent passwd "$(id -un)" 2>/dev/null) || pw_entry=""
login_shell="${pw_entry##*:}"
if [ -z "$login_shell" ]; then
    login_shell="${SHELL:-}"
fi
login_base="${login_shell##*/}"

if [ "$login_base" = "$shell_bin" ]; then
    echo "$shell_name is already the default shell."
else
    shell_path=$(command -v "$shell_bin" 2>/dev/null) || shell_path="$shell_bin"
    if [ "$DRY" -eq 1 ]; then
        run_root chsh -s "$shell_path" "$(id -un)"
    else
        echo "Setting $shell_name as the default shell..."
        # Root plus an explicit username keeps chsh non-interactive.
        if ! run_root chsh -s "$shell_path" "$(id -un)"; then
            echo "Error: failed to change the default shell to $shell_name." >&2
            exit 1
        fi
        echo "Default shell changed to $shell_name."
    fi
fi
