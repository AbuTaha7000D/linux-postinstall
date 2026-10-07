#!/bin/bash
# Install and configure Atuin shell history manager
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: install Atuin if missing (official installer) and add the Atuin init line to the current shell's rc file"
    exit 0
fi

CURRENT_SHELL=$(basename "$SHELL")
CONFIG_FILE=""
INIT_CMD=""

case $CURRENT_SHELL in
    bash)
        CONFIG_FILE="$HOME/.bashrc"
        INIT_CMD="atuin init bash"
        ;;
    fish)
        CONFIG_FILE="$HOME/.config/fish/config.fish"
        INIT_CMD="atuin init fish | source"
        ;;
    zsh)
        CONFIG_FILE="$HOME/.zshrc"
        INIT_CMD="atuin init zsh"
        ;;
    *)
        echo "Unsupported shell: $CURRENT_SHELL"
        exit 1
        ;;
esac

# Ensure config file exists
run touch "$CONFIG_FILE"

# Install Atuin if not present
if ! command -v atuin &>/dev/null; then
    bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh) || { echo "Atuin install failed!"; exit 1; }
fi

# Add init command if not present
if ! grep -q "atuin init" "$CONFIG_FILE"; then
    echo "$INIT_CMD" >> "$CONFIG_FILE"
    # Immediate activation for Bash/Zsh
    if [[ $CURRENT_SHELL == bash || $CURRENT_SHELL == zsh ]]; then
        eval "$INIT_CMD"
    fi
fi

echo "Atuin installed and configured for $CURRENT_SHELL."
