#!/bin/bash
# Configure the terminal: default shell and Starship initialization
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: ensure Bash is the default shell (chsh) and configure Starship init lines for Bash, Zsh, and Fish"
    exit 0
fi

# Check for required commands
if ! command -v bash >/dev/null 2>&1; then
    echo "Error: bash is required. Please install bash and try again." >&2
    exit 1
fi

# Always set Bash as the default shell
if [ "$SHELL" != "/bin/bash" ] && [ "$SHELL" != "/usr/bin/bash" ]; then
    echo "Setting Bash as the default shell..."
    run chsh -s "$(command -v bash)"
    echo "Default shell changed to Bash."
else
    echo "Bash is already the default shell."
fi

# Starship is installed by the packages layer (official installer only);
# this module only configures shell initialization.
if ! command -v starship >/dev/null 2>&1; then
    echo "Error: starship not found. Run './setup packages' first (Starship is installed there via the official installer)." >&2
    exit 1
fi

append_init() {
    local file="$1"
    local line="$2"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        printf '%s\n' "$line" >> "$file"
        echo "Added Starship init to $file."
    fi
}

append_init "$HOME/.bashrc" 'eval "$(starship init bash)"'

if command -v zsh >/dev/null 2>&1 || [ -f "$HOME/.zshrc" ]; then
    append_init "$HOME/.zshrc" 'eval "$(starship init zsh)"'
fi

if command -v fish >/dev/null 2>&1 || [ -f "$HOME/.config/fish/config.fish" ]; then
    mkdir -p "$HOME/.config/fish"
    append_init "$HOME/.config/fish/config.fish" 'starship init fish | source'
fi

echo "Starship initialization configured."
