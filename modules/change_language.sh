#!/bin/bash
set -e

# Dry-run: no prompt, no verification, and no system changes
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: set system language (English default) and write the system locale file (with backup)"
    exit 0
fi

# Check every external command before using one or creating any backup.
for tool in dirname locale tee cp readlink grep sed sudo; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Error: Required tool '$tool' not found. Please install it and re-run." >&2
        exit 1
    }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Interactive selection with a 5-second timeout; non-TTY input
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
    echo "You have 5 seconds to choose."
    read -t 5 -r -p "> " input || input=""
    case "$input" in
        2) choice=2 ;;
        *) choice=1 ;;
    esac
fi

if [ "$choice" -eq 2 ]; then
    selected_locale="ar_EG.UTF-8"
    lang_name="Arabic"
else
    selected_locale="en_US.UTF-8"
    lang_name="English"
fi
base_locale="${selected_locale%%.*}"

family="$(distribution)"
case "$family" in
    redhat|arch) LOCALE_PATH="/etc/locale.conf" ;;
    debian) LOCALE_PATH="/etc/default/locale" ;;
    *)
        echo "Error: Unsupported distribution family '$family'; cannot select a system locale file." >&2
        exit 1
        ;;
esac

# Symlinks are resolved so backup and write always target the real file.
if [ ! -f "$LOCALE_PATH" ]; then
    echo "Error: Expected locale file '$LOCALE_PATH' does not exist or is not a regular file." >&2
    exit 1
fi
LOCALE_FILE="$(readlink -f "$LOCALE_PATH")"

if [ ! -f "$LOCALE_FILE" ]; then
    echo "Error: Locale file '$LOCALE_FILE' does not exist or is not a regular file." >&2
    exit 1
fi

# Verify the selected locale is available before modifying anything, so an
# unavailable locale fails cleanly with no partial state.
available=$(locale -a 2>/dev/null || true)
if ! grep -qE "^${base_locale}([._].*)?$" <<< "$available"; then
    echo "Error: Locale '$selected_locale' is not available on this system (not listed by locale -a)." >&2
    echo "Install the '$base_locale' locale first (e.g. glibc-langpack on Fedora, locales/locale-gen on Debian/Ubuntu, locale.gen on Arch) and re-run." >&2
    exit 1
fi

if [ ! -r "$LOCALE_FILE" ]; then
    echo "Error: Locale file '$LOCALE_FILE' is not readable; refusing to replace its contents." >&2
    exit 1
fi

new_content=$(sed -E "s/^(LANG|LC_ALL)=.*/\1=$selected_locale/" "$LOCALE_FILE")
if ! grep -q '^LANG=' <<< "$new_content"; then
    new_content=$(printf '%s\n%s\n' "$new_content" "LANG=$selected_locale")
fi

# Preserve the first backup. A previous backup is never overwritten.
if [ -L "$LOCALE_FILE.bak" ] || { [ -e "$LOCALE_FILE.bak" ] && [ ! -f "$LOCALE_FILE.bak" ]; }; then
    echo "Error: Backup path '$LOCALE_FILE.bak' exists but is not a regular file; refusing to modify the locale file." >&2
    exit 1
fi
if [ ! -e "$LOCALE_FILE.bak" ]; then
    if ! run_root cp -p --no-clobber "$LOCALE_FILE" "$LOCALE_FILE.bak"; then
        echo "Error: Failed to back up $LOCALE_FILE before modifying it." >&2
        exit 1
    fi
    echo "Backup of $LOCALE_FILE created."
fi

if ! printf '%s\n' "$new_content" | run_root tee "$LOCALE_FILE" > /dev/null; then
    echo "Error: Failed to write $LOCALE_FILE. A backup remains at $LOCALE_FILE.bak." >&2
    exit 1
fi
if command -v update-locale >/dev/null 2>&1; then
    if ! run_root update-locale; then
        echo "Warning: update-locale failed; the locale file was written, but the helper did not complete." >&2
    fi
fi

# Reload into the current shell if readable
if [ -r "$LOCALE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$LOCALE_FILE" 2>/dev/null || true
fi
locale || true

echo "System language set to $lang_name."
