#!/usr/bin/env bash
# modules/terminal/module.sh - metadata for the terminal shell-setup module.
# Shell integration done via managed blocks (lib/fs.sh marker covenant, P2.5)
# in ~/.bashrc (aliases sourcing guard + oh-my-posh init line), never a
# whole-file rewrite: existing content is preserved byte-for-byte and the
# block is replaced in place on drift (no-op when already matching). The
# aliases themselves live in their own managed block file sourced at shell
# start. oh-my-posh (pinned v23.9.0, FS_OMP_VERSION) is installed to
# ~/.local/bin with a sha256-verified release binary for the host arch; a
# theme is placed under ~/.config/oh-my-posh/themes and referenced by the
# guarded init line. Hooks-only module: all functionality is in hooks.sh.
# The task's "Depends: P5.4" is sequencing/rationale (the theme uses Nerd
# Fonts glyphs), NOT a MODULE_DEPENDS: profile curation stays explicit
# (P5.2 NB-B philosophy) and P5.7 wires the desktop profile by hand.
MODULE_ID=terminal
MODULE_TITLE=Terminal setup
MODULE_DESCRIPTION=Managed shell aliases, pinned oh-my-posh prompt and theme
MODULE_RISK=low
MODULE_DEFAULT=on