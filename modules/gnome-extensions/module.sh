#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/gnome-extensions/module.sh - metadata for the GNOME Shell
# extensions module (P6.3).
# Installs distro-packaged extensions where available (packages.<family>.list)
# through the package runner, then enables the curated set declared in
# extensions.list via `gnome-extensions enable <uuid>` (only uuids already
# installed; never auto-installs a user extension). GNOME Shell version and
# per-extension compatibility are reported against config/extensions.compat
# (or FS_GNOME_COMPAT_FILE). --browse (FS_GNOME_BROWSE=1) opens at most the
# first two browse.list URLs sequentially through run_cmd -- the old
# prototype forked xdg-open in a loop over 20 URLs; this module never opens
# more than two and never backgrounds them.
MODULE_ID=gnome-extensions
MODULE_TITLE="GNOME Shell extensions"
MODULE_DESCRIPTION="Packaged extensions, curated enables, compatibility notes"
MODULE_RISK=medium
MODULE_DEFAULT=on
