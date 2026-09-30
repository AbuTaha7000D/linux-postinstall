#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/core/module.sh - metadata for the core CLI-tools module.
# Curated essential command-line utilities (P5.1): present on every
# profile. Family overrides handle name differences (gnupg2 on rpm, gpg
# on deb/arch; fastfetch in-repo on rpm/arch only). Intentionally small:
# no sed/gpg/xdg-utils noise. flatpak is included so the flatpak module
# (P5.2) always finds the CLI.
MODULE_ID=core
MODULE_TITLE="Core CLI tools"
MODULE_DESCRIPTION="Curated essential command-line utilities for every profile"
MODULE_RISK=none
MODULE_DEFAULT=on
