#!/usr/bin/env bash
# modules/dns/module.sh - metadata for the high-risk DNS module (P8.1).
# Sets DNS servers on the active NetworkManager connection (the
# nmcli-native way) and records the prior connection properties so the
# change is revertible. MODULE_RISK=destructive: the P4.7 selection layer
# flags the row as high-risk, requires the explicit opt-in prompt, and the
# runner's destructive-failure policy stops the whole run if the hook fails.
# MODULE_DEFAULT=off and the module is deliberately wired into NO profile:
# it is opt-in only, run explicitly with `./setup install --yes dns`.
# Hooks-only module (no package/flatpak lists): the P4.2 family gate passes
# on the absence of all three list kinds (P7.6 chrome precedent).
MODULE_ID=dns
MODULE_TITLE="DNS servers (NetworkManager)"
MODULE_DESCRIPTION="Set NetworkManager DNS on the active connection (opt-in)"
MODULE_RISK=destructive
MODULE_DEFAULT=off