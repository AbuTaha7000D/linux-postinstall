#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Dry-run: no prompt, no verification, and no system changes
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: set system language (English default) and write the system locale file (with backup)"
    exit 0
fi

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

# Resolve the system locale file by family; unknown distributions fail nonzero.
# Symlinks are resolved so backup and write always target the real file.
for tool in locale tee cp readlink; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Error: Required tool '$tool' not found. Please install it and re-run." >&2
        exit 1
    }
done

if [ -f "/etc/locale.conf" ]; then
    LOCALE_FILE=$(readlink -f /etc/locale.conf)
elif [ -f "/etc/default/locale" ]; then
    LOCALE_FILE=$(readlink -f /etc/default/locale)
else
    echo "Warning: Unknown distro. No /etc/locale.conf or /etc/default/locale found." >&2
    exit 1
fi

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

# Apply: recoverable backup, then rewrite only the LANG/LC_ALL values so that
# unrelated LC_* settings in the file are preserved. Every privileged step's
# exit status is checked; failures leave the backup intact and fail the step.
if ! run_root cp -p "$LOCALE_FILE" "$LOCALE_FILE.bak"; then
    echo "Error: Failed to back up $LOCALE_FILE before modifying it." >&2
    exit 1
fi
echo "Backup of $LOCALE_FILE created."

if [ -r "$LOCALE_FILE" ]; then
    new_content=$(sed -E "s/^(LANG|LC_ALL)=.*/\1=$selected_locale/" "$LOCALE_FILE")
    if ! grep -q '^LANG=' <<< "$new_content"; then
        new_content=$(printf '%s\n%s\n' "$new_content" "LANG=$selected_locale")
    fi
else
    new_content="LANG=$selected_locale"
fi

if ! printf '%s\n' "$new_content" | run_root tee "$LOCALE_FILE" > /dev/null; then
    echo "Error: Failed to write $LOCALE_FILE. A backup remains at $LOCALE_FILE.bak." >&2
    exit 1
fi
if command -v update-locale >/dev/null 2>&1; then
    run_root update-locale || true
fi

# Reload into the current shell if readable
if [ -r "$LOCALE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$LOCALE_FILE" 2>/dev/null || true
fi
locale || true

echo "System language set to $lang_name."