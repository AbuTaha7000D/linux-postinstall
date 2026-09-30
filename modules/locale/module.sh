#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/locale/module.sh - metadata for the high-risk locale module (P8.2).
# Sets the system locale on a systemd host through `localectl set-locale`
# (the supported path) and backs up /etc/locale.conf with a timestamped
# copy first, so the change is revertible. MODULE_RISK=destructive: the
# P4.7 selection layer flags the row as high-risk, requires the explicit
# opt-in prompt, and the runner's destructive-failure policy stops the
# whole run if the hook fails.
# MODULE_DEFAULT=off and the module is deliberately wired into NO profile:
# it is opt-in only, run explicitly with `./setup install --yes locale`.
# Hooks-only module (no package/flatpak lists): the P4.2 family gate passes
# on the absence of all three list kinds (P7.6 chrome, P8.1 dns precedent).
MODULE_ID=locale
MODULE_TITLE="System locale (systemd)"
MODULE_DESCRIPTION="Set the system language via localectl (opt-in)"
MODULE_RISK=destructive
MODULE_DEFAULT=off
