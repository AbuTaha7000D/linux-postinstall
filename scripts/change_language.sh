#!/bin/bash
set -e

echo "Choose system language:"
echo "1) English (default)"
echo "2) Arabic"
read -t 5 -p "Enter choice [1-2] (auto-selects English after 5s): " choice
choice=${choice:-1}

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

LOCALE_FILE="/etc/locale.conf"

if [ -f "/etc/locale.conf" ]; then
	LOCALE_FILE="/etc/locale.conf"
elif [ -f "/etc/default/locale" ]; then
    LOCALE_FILE="/etc/default/locale"
else
    echo "Warning: Unknown distro. Only updated LANG in current shell."
    export LANG=$(echo "$LANG_CONTENT" | grep LANG | cut -d= -f2)
    locale
fi

sudo cp "$LOCALE_FILE" "$LOCALE_FILE.bak"
echo "Backup of $LOCALE_FILE created."

echo "$LANG_CONTENT" | sudo tee "$LOCALE_FILE" > /dev/null
if command -v update-locale &> /dev/null; then
	sudo update-locale
fi
source "$LOCALE_FILE"
locale

echo "System language set to $lang_name."

for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
