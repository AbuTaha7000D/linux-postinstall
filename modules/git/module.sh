#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/git/module.sh - metadata for the git configuration module.
# Configures git through a managed block (lib/fs.sh marker covenant, P2.5)
# appended to ~/.gitconfig: init.defaultBranch, merge/diff/color settings and
# (optionally, via FS_GIT_USER_NAME+FS_GIT_USER_EMAIL) a [user] identity.
# Never replaces the file: existing sections (user keys, core, aliases...) are
# preserved byte-for-byte and the block is replaced in place on later runs
# (fs_managed_block is a no-op when the desired block already matches). No
# interactive prompt by design (dry-run runs headless; identity is supplied by
# the operator or env). Hooks-only module: the git binary ships in core (P5.1).
MODULE_ID=git
MODULE_TITLE="Git configuration"
MODULE_DESCRIPTION="Managed .gitconfig merge with optional user identity"
MODULE_RISK=low
MODULE_DEFAULT=on
