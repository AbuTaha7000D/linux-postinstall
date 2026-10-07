#!/bin/bash
# Manage the project's alias block in shell rc files (idempotent, non-destructive)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

BLOCK_BEGIN="# >>> linux-postinstall aliases >>>"
BLOCK_END="# <<< linux-postinstall aliases <<<"

# Dry-run: report targets, write nothing
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: write linux-postinstall alias block to $HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1; then
        echo "would run: write linux-postinstall alias block to $HOME/.zshrc"
    fi
    if [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1; then
        echo "would run: write linux-postinstall alias block to $HOME/.config/fish/config.fish"
    fi
    exit 0
fi

# Emit the managed block for one shell.
# Definitions are embedded here (migrated from additions/shell_conf, minus the
# removed remote-execution terminal-theme alias); family aliases are baked in.
emit_block() {
    local refresh_cmd="$1"
    printf '%s\n' "$BLOCK_BEGIN"
    cat <<'ALIASES'
# Common aliases
alias ls='eza -al --color=always --group-directories-first --icons'
alias grep='grep --color=auto'
alias pingo='ping 8.8.8.8'
alias ff='fastfetch'
alias efrc='nano $HOME/.config/fish/config.fish'
alias ebrc='nano $HOME/.bashrc'
alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
alias update-fonts='fc-cache -f -v'
alias finstall='sudo flatpak install'
ALIASES
    # Distro-specific aliases, baked for the detected family
    case "$(distribution)" in
        debian)
            cat <<'ALIASES'
alias supdate='sudo apt-get update -y && sudo apt-get upgrade -y && flatpak update -y && sudo apt-get autoremove -y'
alias install='sudo apt-get install'
alias remove='sudo apt-get remove'
ALIASES
            ;;
        redhat)
            cat <<'ALIASES'
alias supdate='sudo dnf update -y && sudo dnf upgrade -y && flatpak update -y && sudo dnf autoremove -y'
alias install='sudo dnf install'
alias remove='sudo dnf remove'
ALIASES
            ;;
        arch)
            cat <<'ALIASES'
alias supdate='sudo pacman -Syu --noconfirm && flatpak update -y && yay -Sua --noconfirm'
alias install='sudo pacman -S'
alias remove='sudo pacman -Rns'
ALIASES
            ;;
    esac
    printf '# Shell-specific aliases\n'
    printf "alias refresh='%s'\n" "$refresh_cmd"
    printf '%s\n' "$BLOCK_END"
}

# Strip any existing block, then append exactly one fresh block.
apply_block() {
    local rc_file="$1"
    local refresh_cmd="$2"

    if [ ! -f "$rc_file" ]; then
        mkdir -p "$(dirname "$rc_file")"
        : > "$rc_file"
    fi

    run sed -i "/^$(printf '%s' "$BLOCK_BEGIN")\$/,/^$(printf '%s' "$BLOCK_END")\$/d" "$rc_file"

    if [ -s "$rc_file" ] && [ -n "$(tail -n1 "$rc_file")" ]; then
        printf '\n' >> "$rc_file"
    fi
    {
        emit_block "$refresh_cmd"
    } >> "$rc_file"
    echo "Alias block written to $rc_file."
}

apply_block "$HOME/.bashrc" 'source $HOME/.bashrc'

if [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1; then
    apply_block "$HOME/.zshrc" 'source $HOME/.zshrc'
fi

if [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1; then
    apply_block "$HOME/.config/fish/config.fish" 'source $HOME/.config/fish/config.fish'
fi

echo "Aliases set successfully!"
