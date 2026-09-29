#!/usr/bin/env bash
# modules/chrome/module.sh - metadata for the Google Chrome module (P7.6).
# Text-parsed by lib/modules.sh, never sourced, so it carries no
# `set -euo pipefail` -- symmetric with every other module.sh.
#
# THE NATIVE PATH IS A BUNDLE, NOT A PACKAGE LIST. Google ships Chrome as a
# standalone .deb/.rpm that the distro package manager installs from a local
# file (dnf install -y <file> / apt install -y <file>); there is no
# packages.list / packages.<family>.list entry for it, and none is wanted --
# the bundle name and version are resolved at run time, so a static list
# would go stale the moment Chrome ships a release. That also makes this a
# hooks-only module (module_validate's family-loadability gate is satisfied
# by the absence of all three list kinds), so NO list file is shipped.
#
# WHY A RUN-TIME RESOLVED (URL, DIGEST) PAIR, and what it does NOT claim.
# The task text asks for a "pinned arch URL". Measured 2026-09-29 against
# dl.google.com (see the URL table below), the vendor serves:
#   deb  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#        https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb
#   rpm  .../current.x86_64.rpm  ->  404. There is NO rolling rpm name at
#        all; only versioned files exist:
#        https://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome-stable-154.0.8037.57-1.x86_64.rpm
#        https://dl.google.com/linux/chrome/rpm/stable/aarch64/google-chrome-stable-154.0.8037.57-1.aarch64.rpm
# So "pinned arch URL" is achievable for deb but not for rpm, and hardcoding
# a version for either family would make this module permanently install a
# STALE browser: the pinned URL 404s a few releases later and the tool would
# never move again. Instead the module resolves the pair at run time from the
# vendor's own repository index, so the URL is architecture-pinned and the
# artifact is digest-pinned, while the version floats to current stable:
#   deb  .../chrome/deb/dists/stable/main/binary-<amd64|arm64>/Packages
#        -> the `google-chrome-stable` stanza's Filename + SHA256
#   rpm  .../chrome/rpm/stable/<x86_64|aarch64>/repodata/primary.xml.gz
#        -> the <package> whose <name> is google-chrome-stable: its
#           <checksum type="sha256"> and <location href="...">
# Both fields come from the SAME stanza, so the (URL, SHA-256) pair always
# describes the same exact artifact; the digest is not an independent
# second lookup that could disagree with the URL.
#
# TRUST BOUNDARY -- read this before "improving" it. The SHA-256 check makes
# the download verifiable against tampering or corruption in transit and
# pins the exact bytes that metadata described. It is NOT a GPG trust
# anchor: the index itself is trusted purely over HTTPS to dl.google.com,
# and unlike P7.5 (config/vscode-gpg.fingerprint) nothing here verifies a
# vendor signature or a pinned key. P7.5 could pin a key because a repository
# key rotates rarely and deliberately; Chrome's stable channel is expected
# to change every few weeks, so pinning its signing key into this repo would
# mean shipping a key we would have to re-pin constantly. Because the index
# and the bundle arrive over the SAME TLS channel to dl.google.com, the
# digest does not compensate for that channel either: it buys corruption
# detection and a divergent mirror/CDN edge, and nothing against a
# compromised vendor host or a CA. Do not describe
# this as "signature verification", and do not "upgrade" it to a vendored
# key without an owner decision.
#
# FAMILY SUPPORT: rpm and deb install the native bundle. arch has NO
# official Arch package (`google-chrome` in the AUR needs an AUR helper and
# a manual build), exactly like P7.5's vscode, so arch warns and is a no-op
# rather than shelling out to an AUR helper this tool does not manage.
#
# FLATPAK ALTERNATIVE: the P7.5 pair, reused unchanged. With
# FS_CHROME_FLATPAK truthy the alternative id goes to the FLATPAK namespace
# and the module contributes NOTHING to the SYSTEM namespace, so the native
# bundle and the flatpak can never install side by side in one run. The hook
# reaches the same verdict through the same module_flatpak_alt call, so the
# hook and the batch cannot disagree.
#
# No verify() note: verify() lives in hooks.sh and checks the installed
# .desktop, read-only, per the P7.1 apps precedent (setup verify itself is
# still "not implemented yet", rc1, P9.2).
#
# The install itself is confirmed by POSTCONDITION, not by the seam's rc:
# pkg_install_local cannot report failure (see hooks.sh for the P3
# run_sudo/--stop reason), so hooks.sh requires
# pkg_query_installed google-chrome-stable to be rc0 before the module is
# allowed to latch as done.
#
# Seams: FS_CHROME_FLATPAK (exclusive alternative), FS_CHROME_ARCH (host
# arch override), FS_CHROME_DESKTOP_DIR (verify() target directory).
MODULE_ID=chrome
MODULE_TITLE=Google Chrome
MODULE_DESCRIPTION=Distro-native Chrome bundle with a digest check, or the flatpak build
MODULE_RISK=medium
MODULE_DEFAULT=on
MODULE_FLATPAK_ALT_ID=com.google.Chrome
MODULE_FLATPAK_ALT_SEAM=FS_CHROME_FLATPAK
