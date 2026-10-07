#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Dry-run: no prompt and no system changes
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: set system language (English default) and write the system locale file (with backup)"
    exit 0
fi

# Interactive selection with a 10-second timeout; non-TTY input
# (unattended runs) and timeout/invalid input default to English.
choice=1
if [ -t 0 ]; then
    echo "Choose your preferred language:"
    echo
    echo "  1) English"
    echo "  2) Arabic"
    echo
    echo "Default: English"
    echo
    echo "You have 10 seconds to choose."
    read -t 10 -r -p "> " input || input=""
    case "$input" in
        2) choice=2 ;;
        *) choice=1 ;;
    esac
fi

if [ "$choice" -eq 2 ]; then
    LANG_CONTENT="LANG=ar_EG.UTF-8
LC_CTYPE=ar_EG.UTF-8
LC_NUMERIC=ar_EG.UTF-8
LC_TIME=ar_EG.UTF-8
LC_COLLATE=ar_EG.UTF-8
LC_MONETARY=ar_EG.UTF-8
LC_MESSAGES=ar_EG.UTF-8
LC_PAPER=ar_EG.UTF-8
LC_NAME=ar_EG.UTF-8
LC_ADDRESS=ar_EG.UTF-8
LC_TELEPHONE=ar_EG.UTF-8
LC_MEASUREMENT=ar_EG.UTF-8
LC_IDENTIFICATION=ar_EG.UTF-8
LC_ALL=ar_EG.UTF-8"
    lang_name="Arabic"
else
    LANG_CONTENT="LANG=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_TIME=en_US.UTF-8
LC_COLLATE=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_ALL=en_US.UTF-8"
    lang_name="English"
fi

LOCALE_FILE=""

if [ -f "/etc/locale.conf" ]; then
    LOCALE_FILE="/etc/locale.conf"
elif [ -f "/etc/default/locale" ]; then
    LOCALE_FILE="/etc/default/locale"
else
    echo "Warning: Unknown distro. Only updated LANG in current shell." >&2
    LANG_VAL=$(echo "$LANG_CONTENT" | grep '^LANG=' | cut -d= -f2)
    export LANG="$LANG_VAL"
    locale || true
    exit 1
fi

run_root cp "$LOCALE_FILE" "$LOCALE_FILE.bak"
echo "Backup of $LOCALE_FILE created."

echo "$LANG_CONTENT" | sudo tee "$LOCALE_FILE" > /dev/null
if command -v update-locale &> /dev/null; then
    run_root update-locale || true
fi
# Source if present/readable
if [ -r "$LOCALE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$LOCALE_FILE" 2>/dev/null || true
fi
locale || true

echo "System language set to $lang_name."
