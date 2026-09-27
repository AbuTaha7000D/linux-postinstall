#!/usr/bin/env bash
# modules/fonts/module.sh - metadata for the fonts module.
# Two halves: (1) distro font packages per family (packages.<family>.list -
# conservative curated names; real-host presence is a P5.4/P5.7 curation
# checkpoint, fixture validates the merge not the repo contents) and
# (2) Nerd Fonts via hooks.sh: config/nerdfonts.list entries (label:asset:
# version) are fetched as pinned GitHub release zips, sha256-verified,
# extracted into ~/.local/share/fonts, and a per-asset marker makes later
# runs skip already-installed sets (no 250MB re-copy). A local
# assets/fonts/ dir (or FS_NERDFONT_SRC_DIR) is honored for offline use and
# hermetic tests. fc-cache runs incrementally only when something changed.
MODULE_ID=fonts
MODULE_TITLE=Fonts
MODULE_DESCRIPTION=Distro font packages plus pinned Nerd Fonts with sha256 verification
MODULE_RISK=low
MODULE_DEFAULT=on