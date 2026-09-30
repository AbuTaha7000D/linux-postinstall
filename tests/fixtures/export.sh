#!/usr/bin/env bash
# tests/fixtures/export.sh - P9.3 fixture for `./setup export` and the
# `install --manifest` re-import.
#
# Drives the real launcher and the REAL repo modules/ + profiles/, so the
# manifests reflect shipped content. The system's managed files are faked in
# FX_TMP (never the real $HOME): export's whole job is reading the managed
# blocks, so the fixture supplies one and then asserts the exported block equals
# what was between the markers.
#
# The font marker is DERIVED from the module's own builder (`_font_marker`),
# not spelled by hand, because the exporter reproduces a filename the installer
# computed -- a hand-written spelling would be a second, drifting source of
# truth for the same name. The git and terminal blocks are content-agnostic:
# the exporter copies whatever is between the markers and never interprets it,
# so the fixture's marker spelling matching `fs_managed_block`'s writer is the
# whole contract between them.
#
# The two halves of the task are pinned from both directions:
#   * the export tree is self-contained -- `install --manifest` dry-runs
#     IDENTICALLY to `install --profile` (the ROADMAP criterion), and
#   * the export is authoritative -- a package added to the LIVE module list
#     after the export changes a profile install and does NOT change a
#     manifest install. Without that second cell the first is nearly
#     tautological, and a re-import that silently re-read the live tree would
#     pass it.
#
# Secret exclusion is structural, so it is pinned structurally: the exporter is
# an allowlist, so the fixture plants a distinct secret token in every place a
# secret could plausibly reach an export (the state root's logs/notes/
# backups/registry, a tool-owned keyring, and OUTSIDE the managed markers in
# the dotfiles) and asserts no token appears anywhere in the tree -- while
# asserting the managed block DOES appear, so the cell cannot pass vacuously.
#
# Usage: bash tests/fixtures/export.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
# Snapshot the repo's modules/ and profiles/ state so the end-of-run self-check
# can tell "the fixture left a change" from "the developer had uncommitted
# changes before the fixture ran". Without this, a dirty tree fails the check.
GIT_STATUS_BEFORE="$(git -C "$ROOT" status --porcelain -- modules profiles 2>/dev/null || :)"
SETUP="$ROOT/setup"
printf 'P9.3 export manifest\n'

GH="$FX_TMP/home"
GITCFG="$GH/.gitconfig"
BASHRC="$GH/.bashrc"
ALIASES="$GH/.local/share/fedora-setup/aliases"
FONTS="$FX_TMP/fonts"
NERDCFG="$FX_TMP/nerd.list"
TREE="$FX_TMP/tree"
# The drift cell has to change a LIVE module list after the export. That is
# done on a private copy of modules/ (FS_MODULES_DIR), never on the repo: a
# fixture that appends to a repo file and restores it in a later step is one
# edit away from leaving a stray file in the tree, which is how an earlier
# probe of mine planted modules/git/packages.list. MODS is the pristine
# reference the copy is remade from.
MODS="$FX_TMP/modules"
rm -rf -- "$MODS"
cp -R -- "$ROOT/modules" "$MODS"

# ---------------------------------------------------------------- helpers

# strip_ts erases the timestamp io_* prefixes and the scratch path, so two runs
# can be compared byte-for-byte instead of by eyeball.
strip_ts() {
    sed -E 's/\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] //; s|'"$FX_TMP"'|<T>|g'
}

# run_setup <label> <expected-rc> <env-assignments...> -- <args...>
# FS_BLOCK_RC carries the process status; stdout/stderr land in FX_OUT/FX_ERR.
run_setup() {
    local label="${1:-}" want="${2:-}"
    shift 2
    local -a envs=() args=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        envs+=("$1")
        shift
    done
    shift || :
    args=("$@")
    (   set -uo pipefail
        set +e
        env -i PATH="/usr/bin:/bin" HOME="$GH" \
            FS_MODULES_DIR="$MODS" FS_PROFILES_DIR="$ROOT/profiles" \
            FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm \
            FS_GIT_CONFIG="$GITCFG" FS_BASHRC="$BASHRC" \
            FS_TERM_ALIASES="$ALIASES" FS_FONTS_DIR="$FONTS" \
            FS_NERDFONT_CONFIG="$NERDCFG" \
            "${envs[@]+"${envs[@]}"}" "$SETUP" "${args[@]+"${args[@]}"}"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    if [[ -n "${FX_DEBUG_CELL:-}" && "$label" == "$FX_DEBUG_CELL" ]]; then
        { echo "=== $label rc=$FX_BLOCK_RC"; echo "--- stdout"; cat "$FX_OUT"; echo "--- stderr"; cat "$FX_ERR"; } >&2
    fi
    if [[ -n "$label" ]]; then
        fx_block_rc "$label rc" "$want"
    fi
    return 0
}

# mkhome creates the fake dotfiles the exporter reads, with a secret OUTSIDE
# the managed markers and a real managed block from the installer's own writer.
# SECRET_DOTFILE_TOKEN below is a secret a user keeps in their own dotfile,
# outside our markers: the exporter must never read or copy it.
mkhome() {
    rm -rf -- "$GH" "$FONTS"
    mkdir -p "$GH" "$FONTS" "$(dirname -- "$ALIASES")"
    printf 'export SECRET_DOTFILE_TOKEN=hunter2\n' >"$BASHRC"
    printf '# BEGIN fedora-setup terminal\n# terminal block body\n# END fedora-setup terminal\n' >>"$BASHRC"
    printf '# a user line the exporter must not touch\nexport SECRET_GITCONFIG_TOKEN=swordfish\n' >"$GITCFG"
    printf '# BEGIN fedora-setup git\n[init]\n\tdefaultBranch = main\n# END fedora-setup git\n' >>"$GITCFG"
    printf '# BEGIN fedora-setup aliases\nalias la=\x27ls -A\x27\n# END fedora-setup aliases\n' >"$ALIASES"
    printf '# one entry, and the marker is built by the installer itself\n' >"$NERDCFG"
    printf 'FiraCode Nerd Font:FiraCode:v3.3.0\n' >>"$NERDCFG"
    mkdir -p "$FONTS"
    local marker=""
    marker="$(
        set +e
        source "$ROOT/modules/fonts/hooks.sh" >/dev/null 2>&1
        _font_marker FiraCode v3.3.0
    )" || marker=""
    : >"$FONTS/$marker"
}

# plant_secrets fills the state root and a keyring with tokens the exporter has
# no reason to read. The layout is built with mkdir -p rather than state_init --
# state_init is never called in this fixture, and claiming otherwise would make a
# reader believe the exporter has been exercised against a state root this
# process actually registered. The paths are written out literally because they
# are the assertion: a change to lib/state.sh's layout must break these cells.
plant_secrets() {
    local sr="$FX_TMP/state/.local/state/fedora-setup"
    rm -rf -- "$FX_TMP/state"
    mkdir -p "$sr/logs" "$sr/notes" "$sr/modules" "$sr/backups/registry/20260101-000000-1"
    printf 'SECRET_LOG_TOKEN\n' >"$sr/logs/run.log"
    printf 'name|prior|SECRET_NOTE_TOKEN\n' >"$sr/notes/dns"
    printf 'SECRET_BACKUP_TOKEN\n' >"$sr/backups/registry/20260101-000000-1/.bashrc"
    printf 'SECRET_REGISTRY_TOKEN\n' >"$sr/modules/core"
    printf 'SECRET_KEYRING_TOKEN\n' >"$FX_TMP/tool.gpg"
}

no_secret_in_tree() {
    local label="$1" tok found=""
    for tok in SECRET_LOG_TOKEN SECRET_NOTE_TOKEN SECRET_BACKUP_TOKEN \
              SECRET_REGISTRY_TOKEN SECRET_KEYRING_TOKEN SECRET_DOTFILE_TOKEN \
              SECRET_GITCONFIG_TOKEN; do
        if grep -rqF -- "$tok" "$TREE" 2>/dev/null; then
            found="$found $tok"
        fi
    done
    if [[ -n "$found" ]]; then
        fx_bad "secret(s) reached the export tree:$found"
    else
        fx_ok
    fi
}

# ------------------------------------------------- 1. tree shape + contents

mkhome
plant_secrets
rm -rf -- "$TREE"
run_setup "export desktop" 0 FS_HOME="$FX_TMP/state" -- export "$TREE" --profile desktop

# EVERY file the format promises, for EVERY module in the profile, derived from
# the module ids themselves rather than a hand-copied list. An earlier version
# of this cell had an unanchored `case fonts.list` skip arm that silently
# dropped the fonts entries and a second loop that re-asserted four files the
# first had already checked -- so three shape asserts were never running and
# four were duplicates. The count now equals the number of paths.
# every module in the profile contributes exactly two manifests; the managed
# BLOCKS are a different, independent set (they are named by files/index, not by
# module id -- only the modules with a run() hook have one), so both are derived
# from the tree itself and the counts are asserted, so a shrunken list cannot
# quietly pass.
TREE_FILES="export.meta desktop.conf files/index"
n_mod=0
while IFS= read -r mid; do
    [[ -n "$mid" ]] || continue
    n_mod=$(( n_mod + 1 ))
    TREE_FILES="$TREE_FILES manifests/$mid.list manifests/$mid.flatpaks.list"
done < <(sed -n 's/^modules=//p' "$TREE/export.meta" 2>/dev/null | tr ',' '\n')
TREE_FILES="$TREE_FILES state/gsettings.list state/extensions.list state/fonts.list"
n_tree=0
for f in $TREE_FILES; do
    if [[ -f "$TREE/$f" ]]; then fx_ok; else fx_bad "missing from the tree: $f"; fi
    n_tree=$(( n_tree + 1 ))
done
if (( n_mod == 5 )); then fx_ok; else fx_bad "expected 5 modules in export.meta, got $n_mod"; fi
n_block=0
while IFS=$'\t' read -r bname _; do
    [[ -n "$bname" ]] || continue
    n_block=$(( n_block + 1 ))
    if [[ -f "$TREE/files/$bname" ]]; then fx_ok; else fx_bad "missing block: files/$bname"; fi
done <"$TREE/files/index"
if (( n_block == 3 )); then fx_ok; else fx_bad "expected 3 managed blocks, got $n_block"; fi

fx_out "export: 5 module(s) for profile 'desktop'"
for kv in format=1 family=rpm profile=desktop; do
    if grep -qxF "$kv" "$TREE/export.meta"; then fx_ok; else fx_bad "export.meta lacks $kv"; fi
done
if grep -q '^fs_version=' "$TREE/export.meta"; then fx_ok; else fx_bad "export.meta lacks fs_version="; fi
# no timestamp anywhere in the artifact
if grep -rqE '[0-9]{2}:[0-9]{2}:[0-9]{2}' "$TREE" 2>/dev/null; then
    fx_bad "the export tree contains a timestamp"
else
    fx_ok
fi

# --------------------------------------- 2. secrets are structurally excluded

no_secret_in_tree "secrets excluded"
# and the cell is not vacuous: the managed block content IS there
if [[ -f "$TREE/files/git" ]] && grep -q 'defaultBranch = main' "$TREE/files/git"; then
    fx_ok
else
    fx_bad "the managed block was not exported (secret cell could pass vacuously)"
fi
fx_err_not 'SECRET'

# the exporter's own paths are $HOME-relative
fx_out_not "^$GH"
if grep -qF "$GH" "$TREE/files/index" 2>/dev/null; then
    fx_bad "files/index leaks the home directory"
else
    fx_ok
fi
if grep -qF '~/.gitconfig' "$TREE/files/index"; then fx_ok; else fx_bad "files/index lacks the ~-relative path"; fi

# -------------------------------- 3. only the managed block, never the whole file

if grep -qF 'SECRET_DOTFILE_TOKEN' "$TREE/files/terminal" 2>/dev/null; then
    fx_bad "files/terminal copied content outside the managed block"
else
    fx_ok
fi
if grep -q 'terminal block body' "$TREE/files/terminal" 2>/dev/null; then
    fx_ok
else
    fx_bad "files/terminal is missing the managed block body"
fi

# ------------------------------------------ 4. fonts marker is the real one

# a font set that is NOT installed must not be listed
printf 'Ghost Nerd Font:Ghost:v9.9.9\n' >>"$NERDCFG"
rm -rf -- "$TREE"
run_setup "export with uninstalled font" 0 FS_HOME="$FX_TMP/state" -- export "$TREE" --profile desktop
fx_out_not 'Ghost'
python3 - "$NERDCFG" <<'PY'
import sys
p=sys.argv[1]
lines=[l for l in open(p) if not l.startswith('Ghost')]
open(p,'w').writelines(lines)
PY

# -------------------------------------------- 5. determinism (no timestamp)

rm -rf -- "$TREE" "$FX_TMP/out2"
run_setup "export determinism 1" 0 FS_HOME="$FX_TMP/state" -- export "$TREE" --profile desktop
if diff -r "$TREE" "$TREE" >/dev/null 2>&1; then fx_ok; else fx_bad "diff -r self"; fi
( cd "$TREE" && find . -type f | LC_ALL=C sort | xargs md5sum ) >"$FX_TMP/h1"
rm -rf -- "$FX_TMP/out2"
run_setup "export determinism 2" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/out2" --profile desktop
( cd "$FX_TMP/out2" && find . -type f | LC_ALL=C sort | xargs md5sum ) >"$FX_TMP/h2"
if cmp -s "$FX_TMP/h1" "$FX_TMP/h2"; then
    fx_ok
else
    fx_bad "two exports of the same state are not byte-identical"
fi

# -------------------------------------- 6. the snapshot's CONTENT, on a GNOME host
#
# Every cell so far runs on the "not a GNOME session" skip arm, so the gsettings
# and extensions snapshots are only existence-checked. Without this cell a
# regression that snapshotted ALL of org.gnome.desktop.* -- the exact thing
# that keeps the exporter off the user's unrelated desktop -- would stay green.
mkdir -p "$FX_TMP/fakebin"
cat >"$FX_TMP/fakebin/gsettings" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
    get)
        key="$2/$3"
        while IFS='' read -r line || [[ -n "$line" ]]; do
            k="${line%%|*}"
            [[ "$k" == "$key" ]] && { printf '%s\n' "${line#*|}"; exit 0; }
        done <"${FAKE_KEY_FILE:-/dev/null}"
        printf '%s\n' "${FAKE_GET:-@as []}"
        exit 0
        ;;
    *) exit 0 ;;
esac
FAKE
cat >"$FX_TMP/fakebin/gnome-extensions" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
    list)
        if [[ "${2:-}" == --enabled ]]; then
            cat "${FAKE_EXT_ENABLED:-/dev/null}"
        else
            cat "${FAKE_EXT_LIST:-/dev/null}"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac
FAKE
chmod +x "$FX_TMP/fakebin/gsettings" "$FX_TMP/fakebin/gnome-extensions"
# an ALLOWLISTED key with a real value, a key the exporter must NOT touch, and a
# tab-bearing value that must be skipped rather than corrupt the TSV
printf 'org.gnome.desktop.interface/gtk-theme|%s\n' "'Yaru-dark'" >"$FX_TMP/keys"
printf 'org.gnome.shell/favorite-apps|[%s]\n' "'org.gnome.Nautilus.desktop'" >>"$FX_TMP/keys"
printf 'org.gnome.desktop.background/picture-uri|file://%%s/T.png\n' "$GH" >>"$FX_TMP/keys"
printf 'org.gnome.desktop.interface/color-scheme|%s\n' "'prefer-dark'" >>"$FX_TMP/keys"
printf 'org.gnome.desktop.screensaver/lock-enabled|true\n' >>"$FX_TMP/keys"
printf 'demo@ext\nother@ext\n' >"$FX_TMP/ext-enabled"
printf 'demo@ext\nother@ext\ndisabled@ext\n' >"$FX_TMP/ext-all"
rm -rf -- "$FX_TMP/gnome-tree"
run_setup "export on a GNOME host" 0 FS_HOME="$FX_TMP/state" \
    PATH="$FX_TMP/fakebin:$PATH" FAKE_KEY_FILE="$FX_TMP/keys" \
    FAKE_EXT_ENABLED="$FX_TMP/ext-enabled" FAKE_EXT_LIST="$FX_TMP/ext-all" \
    FS_GNOME_FORCE=1 XDG_CURRENT_DESKTOP=GNOME -- export "$FX_TMP/gnome-tree" --profile desktop
# allowlisted keys are captured
for k in 'org.gnome.desktop.interface	gtk-theme' 'org.gnome.shell	favorite-apps' \
         'org.gnome.desktop.background	picture-uri'; do
    if grep -qF "$k" "$FX_TMP/gnome-tree/state/gsettings.list"; then fx_ok; else fx_bad "gsettings.list lacks $k"; fi
done
if grep -qF "'Yaru-dark'" "$FX_TMP/gnome-tree/state/gsettings.list"; then fx_ok; else fx_bad "gsettings.list lacks the value"; fi
# a NON-allowlisted key must be absent even though gsettings answers it
fx_out_not 'color-scheme'
fx_out_not 'screensaver'
if grep -qF 'color-scheme' "$FX_TMP/gnome-tree/state/gsettings.list"; then
    fx_bad "the exporter snapshotted a key outside its allowlist"
else
    fx_ok
fi
# only ENABLED extensions, not the full list
if grep -qx 'demo@ext' "$FX_TMP/gnome-tree/state/extensions.list"; then fx_ok; else fx_bad "enabled extension missing"; fi
if grep -qx 'other@ext' "$FX_TMP/gnome-tree/state/extensions.list"; then fx_ok; else fx_bad "enabled extension missing"; fi
if grep -qF 'disabled@ext' "$FX_TMP/gnome-tree/state/extensions.list"; then
    fx_bad "a DISABLED extension was exported"
else
    fx_ok
fi

# a tab inside a value must be skipped, not written into the TSV and corrupt it.
# The \t must live in the FORMAT string: printf does not interpret escapes
# inside a %s argument, and a literal backslash-t would not be a tab at all --
# the cell would then pass while proving nothing.
printf "org.gnome.desktop.interface/cursor-theme|'has\ttab'\n" >"$FX_TMP/keys2"
printf "org.gnome.desktop.interface/gtk-theme|'keepme'\n" >>"$FX_TMP/keys2"
if grep -qP '\t' "$FX_TMP/keys2"; then fx_ok; else fx_bad "keys2 has no real tab (printf escape mistake)"; fi
rm -rf -- "$FX_TMP/tab-tree"
run_setup "export with a tab in a gsettings value" 0 FS_HOME="$FX_TMP/state" \
    PATH="$FX_TMP/fakebin:$PATH" FAKE_KEY_FILE="$FX_TMP/keys2" \
    FAKE_EXT_ENABLED="$FX_TMP/ext-enabled" FS_GNOME_FORCE=1 XDG_CURRENT_DESKTOP=GNOME \
    -- export "$FX_TMP/tab-tree" --profile desktop
fx_err 'contains a tab, skipped'
if grep -qF 'has' "$FX_TMP/tab-tree/state/gsettings.list"; then
    fx_bad "a tab-bearing value reached the TSV"
else
    fx_ok
fi
# the other rows must still be there: skipping one key is not skipping the file
if grep -qF 'keepme' "$FX_TMP/tab-tree/state/gsettings.list"; then fx_ok; else fx_bad "a tab in one value dropped every row"; fi

# -------------------------------------- 7. the round trip (criterion)

run_setup "install --profile dry" 0 FS_HOME="$FX_TMP/state" -- install --dry-run --yes --profile desktop
strip_ts <"$FX_OUT" >"$FX_TMP/plan-profile.txt"
run_setup "install --manifest dry" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE"
strip_ts <"$FX_OUT" | grep -v 're-importing the exported tree' >"$FX_TMP/plan-manifest.txt"
if cmp -s "$FX_TMP/plan-profile.txt" "$FX_TMP/plan-manifest.txt"; then
    fx_ok
else
    fx_bad "the manifest re-import does not dry-run identically to the profile"
fi
fx_out "re-importing the exported tree"

# the plan is not empty, so the comparison above is not trivially true
if [[ -s "$FX_TMP/plan-profile.txt" ]] && grep -q 'would run' "$FX_TMP/plan-profile.txt"; then
    fx_ok
else
    fx_bad "the baseline plan is empty; the round-trip cell proves nothing"
fi

# ------------------------- 7. the manifest is AUTHORITATIVE (drift detection)

printf '\nDRIFT-PROBE-PKG\n' >>"$MODS/core/packages.list"
run_setup "profile install after drift" 0 FS_HOME="$FX_TMP/state" -- install --dry-run --yes --profile desktop
fx_out 'DRIFT-PROBE-PKG'
run_setup "manifest install after drift" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE"
fx_out_not 'DRIFT-PROBE-PKG'
# undo the mutation, and prove the cell was not a no-op while it was in place
if grep -qF 'DRIFT-PROBE-PKG' "$MODS/core/packages.list"; then
    fx_ok
else
    fx_bad "the drift mutation was not actually present (cell would pass vacuously)"
fi
rm -rf -- "$MODS"
cp -R -- "$ROOT/modules" "$MODS"

# ---------------------------- 8. a module absent from the manifest contributes
#      nothing -- it must NOT silently fall back to the live list
printf 'core\n' >"$TREE/exported.conf"
cp --remove-destination -- "$TREE/manifests/core.list" "$FX_TMP/core.manifest.bak"
rm -f -- "$TREE/manifests/core.list"
run_setup "manifest missing a module list" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE" --profile exported
fx_out_not 'gnupg2'
cp --remove-destination -- "$FX_TMP/core.manifest.bak" "$TREE/manifests/core.list"
if [[ -f "$TREE/manifests/core.list" ]]; then fx_ok; else fx_bad "could not restore the manifest"; fi

# The twin cell in the OTHER namespace. `core` ships no flatpaks.list, so the
# cell above cannot see a regression in list_flatpaks' manifest branch: reverting
# that branch alone leaves the system-namespace assertions green while the
# flatpak namespace silently falls back to the live tree. Both namespaces must
# be pinned, or the rule is pinned for half of what it protects.
cp --remove-destination -- "$TREE/manifests/flatpak.flatpaks.list" "$FX_TMP/flatpak.manifest.bak"
rm -f -- "$TREE/manifests/flatpak.flatpaks.list"
run_setup "manifest missing a module flatpak list" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE"
fx_out_not 'com.bitwarden.desktop'
fx_out_not 'net.nokyan.Resources'
cp --remove-destination -- "$FX_TMP/flatpak.manifest.bak" "$TREE/manifests/flatpak.flatpaks.list"
if [[ -f "$TREE/manifests/flatpak.flatpaks.list" ]]; then fx_ok; else fx_bad "could not restore the flatpak manifest"; fi

# and the flatpak namespace's own drift cell, mirroring the system one
printf '\nDRIFT-FLATPAK-PROBE\n' >>"$MODS/flatpak/flatpaks.list"
run_setup "flatpak profile install after drift" 0 FS_HOME="$FX_TMP/state" -- install --dry-run --yes --profile desktop
fx_out 'DRIFT-FLATPAK-PROBE'
run_setup "flatpak manifest install after drift" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE"
fx_out_not 'DRIFT-FLATPAK-PROBE'
fx_out 'com.bitwarden.desktop'
if grep -qF 'DRIFT-FLATPAK-PROBE' "$MODS/flatpak/flatpaks.list"; then
    fx_ok
else
    fx_bad "the flatpak drift mutation was not present (cell would pass vacuously)"
fi
rm -rf -- "$MODS"
cp -R -- "$ROOT/modules" "$MODS"

# B2: module_validate's family gate requires a live list file usable on the
# family, and it runs BEFORE list_packages reaches the manifest branch -- so a
# re-import could refuse a module whose ids the manifest already carries. The
# gate is only reachable for a module whose live lists are ALL for other
# families, which no shipped module is (every shipped one either has a common
# list, has a list for this family, or has no list at all), so this needs a
# synthetic module to reach. `debfamily` ships only packages.deb.list: the
# export runs on deb (where the live gate legitimately passes), and the
# re-import runs on rpm, where the live gate would fire even though the manifest
# carries the ids the export recorded. That is the real shape of the bug -- a
# deb tree replayed onto an rpm host.
rm -rf -- "$FX_TMP/syn-modules" "$FX_TMP/syn-profiles"
mkdir -p "$FX_TMP/syn-modules/debfamily" "$FX_TMP/syn-profiles"
cat >"$FX_TMP/syn-modules/debfamily/module.sh" <<'MOD'
MODULE_ID=debfamily
MODULE_TITLE="Deb-family-only lists"
MODULE_DESCRIPTION="Synthetic: live lists exist only for deb"
MODULE_DEFAULT=off
MODULE_RISK=low
MOD
printf 'some-deb-only-pkg\n' >"$FX_TMP/syn-modules/debfamily/packages.deb.list"
printf '# a one-module profile\ndebfamily\n' >"$FX_TMP/syn-profiles/syn.conf"
rm -rf -- "$FX_TMP/syn-tree"
run_setup "export the deb-family-only module" 0 FS_HOME="$FX_TMP/state" \
    FS_MODULES_DIR="$FX_TMP/syn-modules" FS_PROFILES_DIR="$FX_TMP/syn-profiles" \
    FS_DISTRO_FAMILY=deb -- export "$FX_TMP/syn-tree" --profile syn
if grep -qx 'some-deb-only-pkg' "$FX_TMP/syn-tree/manifests/debfamily.list" 2>/dev/null; then
    fx_ok
else
    fx_bad "the synthetic manifest does not carry the exported id"
fi
run_setup "re-import the deb tree on rpm" 0 FS_HOME="$FX_TMP/state" \
    FS_MODULES_DIR="$FX_TMP/syn-modules" FS_PROFILES_DIR="$FX_TMP/syn-profiles" \
    FS_DISTRO_FAMILY=rpm -- install --dry-run --yes --manifest "$FX_TMP/syn-tree"
fx_out 'some-deb-only-pkg'
fx_out_not 'no package list usable'
# and the same module on a LIVE rpm install must still be refused, or the fix
# has gutted the gate it was meant to relax
run_setup "live rpm install of the deb-family-only module" 1 FS_HOME="$FX_TMP/state" \
    FS_MODULES_DIR="$FX_TMP/syn-modules" FS_PROFILES_DIR="$FX_TMP/syn-profiles" \
    FS_DISTRO_FAMILY=rpm -- install --dry-run --yes --profile syn
fx_err 'no package list usable'

# ------------------------------------------------- 9. refusals and validation

rm -rf -- "$FX_TMP/notempty"
mkdir -p "$FX_TMP/notempty"
printf 'user data\n' >"$FX_TMP/notempty/important.txt"
run_setup "refuse a non-empty foreign dir" 1 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/notempty" --profile desktop
fx_err 'refusing to write into a non-empty directory'
if [[ -f "$FX_TMP/notempty/important.txt" ]]; then fx_ok; else fx_bad "clobbered a user file"; fi
if [[ -e "$FX_TMP/notempty/export.meta" ]]; then fx_bad "wrote into a refused dir"; else fx_ok; fi

printf 'x\n' >"$FX_TMP/isafile"
run_setup "refuse a file as output" 1 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/isafile" --profile desktop
fx_err 'exists and is not a directory'

mkdir -p "$FX_TMP/realdir"
ln -sf -- "$FX_TMP/realdir" "$FX_TMP/linkdir"
run_setup "refuse a symlinked output" 1 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/linkdir" --profile desktop
fx_err 'symlink'

run_setup "export with no outdir" 1 -- export
fx_err 'requires an output directory'
run_setup "export with two outdirs" 1 -- export a b
fx_err 'exactly one output directory'

run_setup "manifest dir missing" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/nope"
fx_err 'manifest directory not found'
mkdir -p "$FX_TMP/plain"
run_setup "manifest not an export tree" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/plain"
fx_err 'not an export tree'
run_setup "manifest profile absent" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$TREE" --profile nosuchprofile
fx_err "no profile 'nosuchprofile'"
ln -sf -- "$TREE" "$FX_TMP/treelink"
run_setup "manifest is a symlink" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/treelink"
fx_err 'symlink'

# ------------------------------------------ 10. the profile the export records

rm -rf -- "$FX_TMP/mintree"
mkdir -p "$FX_TMP/mintree"
printf 'format=1\nprofile=minimal\n' >"$FX_TMP/mintree/export.meta"
printf 'core\n' >"$FX_TMP/mintree/minimal.conf"
run_setup "re-import takes the profile from export.meta" 0 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/mintree"
fx_out "re-importing the exported tree .* (profile 'minimal')"
printf 'format=1\n' >"$FX_TMP/mintree/export.meta"
run_setup "export.meta with no profile" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/mintree"
fx_err 'records no profile'
printf 'format=1\nprofile=\n' >"$FX_TMP/mintree/export.meta"
run_setup "export.meta empty profile" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/mintree"
fx_err 'empty profile'

# ------------------------------------------------------- 11. dry-run purity

rm -rf -- "$FX_TMP/drytree"
run_setup "export dry-run" 0 FS_HOME="$FX_TMP/state" -- export --dry-run "$FX_TMP/drytree" --profile desktop
if [[ -e "$FX_TMP/drytree" ]]; then
    fx_bad "a dry run created the output tree"
else
    fx_ok
fi
fx_out "export (dry run)"
fx_out 'nothing was written'
fx_out 'would write: .*export\.meta'
fx_out 'would write: .*/desktop\.conf'
# a dry run must PROBE nothing: gsettings is unavailable in this farm, so a
# probe would have errored, and the gate skip is what we see instead.
# the gate line must be ABSENT in a dry run: proving the exporter probes
# nothing is the stronger assertion, since a real run always emits one of the
# two skip reasons and a probe would have to be made to learn that.
fx_out_not 'not GNOME'

# --------------------------------------- 12. read-only: no state, no marking

rm -rf -- "$FX_TMP/ro-state"
run_setup "export creates no state root" 0 FS_HOME="$FX_TMP/ro-state" \
    -- export "$FX_TMP/ro-out" --profile desktop
if [[ -e "$FX_TMP/ro-state" ]]; then
    fx_bad "export created a state root"
else
    fx_ok
fi
fx_out_not 'sudo'

# --------------------------------------- 13. an empty profile is not an error

rm -rf -- "$FX_TMP/emptyprof" "$FX_TMP/empty-out"
mkdir -p "$FX_TMP/emptyprof"
printf '# nothing here yet\n' >"$FX_TMP/emptyprof/emptyprof.conf"
run_setup "export an empty profile" 0 FS_HOME="$FX_TMP/state" \
    FS_PROFILES_DIR="$FX_TMP/emptyprof" -- export "$FX_TMP/empty-out" --profile emptyprof
fx_out "export: 0 module(s) for profile 'emptyprof'"
if [[ -f "$FX_TMP/empty-out/emptyprof.conf" ]]; then fx_ok; else fx_bad "no conf for an empty profile"; fi
if [[ -z "$(cat "$FX_TMP/empty-out/emptyprof.conf")" ]]; then fx_ok; else fx_bad "empty profile conf is not empty"; fi

# ------------------------------------- 14. a symlinked managed file is skipped

rm -rf -- "$FX_TMP/linktree"
printf 'SECRET_LINK_TARGET_TOKEN\n' >"$FX_TMP/secret-target"
ln -sf -- "$FX_TMP/secret-target" "$FX_TMP/gitlink"
run_setup "export skips a symlinked managed file" 0 FS_HOME="$FX_TMP/state" \
    FS_GIT_CONFIG="$FX_TMP/gitlink" -- export "$FX_TMP/linktree" --profile desktop
fx_err 'skipping symlinked managed file'
if [[ -f "$FX_TMP/linktree/files/git" ]]; then
    fx_bad "export followed a symlinked managed file"
else
    fx_ok
fi
if grep -rqF 'SECRET_LINK_TARGET_TOKEN' "$FX_TMP/linktree" 2>/dev/null; then
    fx_bad "export dereferenced a symlink and copied its target"
else
    fx_ok
fi

# -------------------------------------------- 15. unreadable font config fails

printf 'x\n' >"$FX_TMP/noread.list"
chmod 000 "$FX_TMP/noread.list"
if [[ -r "$FX_TMP/noread.list" ]]; then
    fx_bad "cannot make the font config unreadable as this user"
else
    run_setup "export with an unreadable font config" 1 FS_HOME="$FX_TMP/state" \
        FS_NERDFONT_CONFIG="$FX_TMP/noread.list" -- export "$FX_TMP/nr-out" --profile desktop
    fx_err 'font config'
    # B1: a FAILED export must not leave a tree a re-import accepts. The
    # manifests are already on disk at this point, so the only thing standing
    # between the user and a silently half-empty snapshot is the ordering of
    # the last write. Assert the artifact, not just the rc.
    if [[ -e "$FX_TMP/nr-out/export.meta" ]]; then
        fx_bad "the failed export left an export.meta, so the tree looks valid"
    else
        fx_ok
    fi
    if [[ -f "$FX_TMP/nr-out/manifests/core.list" ]]; then
        fx_ok
    else
        fx_bad "the partial export wrote no manifest at all (the failure cell is not exercising the partial state)"
    fi
    run_setup "re-import of the failed export" 1 FS_HOME="$FX_TMP/state" \
        -- install --dry-run --yes --manifest "$FX_TMP/nr-out"
    fx_err 'not an export tree'
fi
chmod 644 "$FX_TMP/noread.list" 2>/dev/null || :

# ------------------------------- 15b. an ABSENT block is not an unterminated one

# A file that simply has no managed block is the normal case for a fresh
# machine, and must be silent. Confusing "no BEGIN at all" with "BEGIN without
# an END" makes every unconfigured file emit a scary warning next to the
# contradictory "no managed block" line, which trains the reader to ignore both.
rm -f "$GH/.gitconfig" "$GH/.bashrc"
printf '[user]\n\tname = Someone\n' >"$GH/.gitconfig"
printf '# nothing managed here\n' >"$GH/.bashrc"
run_setup "export with no managed block anywhere" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/noblk" --profile desktop
if grep -q 'unterminated' "$FX_ERR"; then
    fx_bad "an absent managed block was reported as unterminated"
else
    fx_ok
fi
if [[ -f "$FX_TMP/noblk/files/git" ]]; then
    fx_bad "a file with no block produced a files/git artifact"
else
    fx_ok
fi

# The other direction: a stray BEGIN with no END must be refused, not treated as
# "open until end of file" -- that range would export everything after the
# marker, which is exactly the surrounding user content the allowlist promises
# is never read.
printf '# BEGIN fedora-setup git\n[git]\n\tuser.name = X\nSECRET_AFTER_STRAY=leak\n' >"$GH/.gitconfig"
run_setup "export with a stray unterminated BEGIN" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/stray" --profile desktop
# the wording is lib/fs.sh's, not lib/export.sh's: the exporter defers to the
# writer's own validator, so this asserts the shared relation rather than a
# private parser. Do not add an "unterminated" check to export.sh to satisfy it.
fx_err 'unterminated managed block'
if grep -rqF 'SECRET_AFTER_STRAY' "$FX_TMP/stray" 2>/dev/null; then
    fx_bad "a stray BEGIN exported the user content below it"
else
    fx_ok
fi
# and the cell must really be reading that file
if [[ ! -f "$FX_TMP/stray/files/git" ]]; then
    fx_ok
else
    fx_bad "the unterminated block was written to the tree anyway"
fi

# ------------------- 15b2. blocks the WRITER itself refuses are refused here too

# fs_managed_block demands exactly one BEGIN and one END (via _fs_locate_ok) and
# rejects two same-name blocks. The exporter used to concatenate both bodies,
# which is the auditor drifting from its writer: the tree then records a
# "managed block" the tool would refuse to manage. All four shapes the writer
# refuses must be refused identically here, silently producing no artifact.
printf '# BEGIN fedora-setup git\nbody\n# END fedora-setup git\n# BEGIN fedora-setup git\nbody2\n# END fedora-setup git\n' >"$GH/.gitconfig"
run_setup "export with two same-name blocks" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/dup" --profile desktop
fx_err 'malformed managed block'
if [[ -f "$FX_TMP/dup/files/git" ]]; then fx_bad "a duplicated block was exported"; else fx_ok; fi

printf '# END fedora-setup git\n' >"$GH/.gitconfig"
run_setup "export with an orphan END" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/orphan" --profile desktop
if grep -q 'malformed managed block\|orphan' "$FX_ERR"; then fx_ok; else fx_bad "an orphan END was not reported"; fi
if [[ -f "$FX_TMP/orphan/files/git" ]]; then fx_bad "an orphan END produced files/git"; else fx_ok; fi

# nested: a BEGIN inside an open block is rejected by _fs_validate_markers
printf '# BEGIN fedora-setup git\n# BEGIN fedora-setup other\nx\n# END fedora-setup other\n# END fedora-setup git\n' >"$GH/.gitconfig"
run_setup "export with a nested block" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/nest" --profile desktop
fx_err 'malformed managed block markers'
if [[ -f "$FX_TMP/nest/files/git" ]]; then fx_bad "a nested block was exported"; else fx_ok; fi

# and the shared locator must still read a WELL-FORMED block, or every cell
# above would pass on a reader that exports nothing at all
printf '# BEGIN fedora-setup git\n\tuser.name = Kept\n# END fedora-setup git\n' >"$GH/.gitconfig"
run_setup "export with one well-formed block" 0 FS_HOME="$FX_TMP/state" -- export "$FX_TMP/good" --profile desktop
if grep -qF 'user.name = Kept' "$FX_TMP/good/files/git" 2>/dev/null; then fx_ok; else fx_bad "the well-formed block was not exported"; fi

# --------------------------------- 15c. a failed RE-export invalidates the old tree

# Re-export over a good tree is allowed, so "export.meta is written last" alone
# is not enough: the previous run's marker is still on disk when the refresh
# fails part way, describing the PREVIOUS profile next to the new manifests.
# The re-import then replays the old profile with no error anywhere. The marker
# has to be dropped before the first write, not merely re-added at the end.
run_setup "first export into a tree that will be refreshed" 0 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/refresh" --profile desktop
if [[ -f "$FX_TMP/refresh/export.meta" ]]; then fx_ok; else fx_bad "the first export wrote no export.meta"; fi
printf 'x\n' >"$FX_TMP/noread2.list"
chmod 000 "$FX_TMP/noread2.list"
run_setup "a failed re-export over a valid tree" 1 FS_HOME="$FX_TMP/state" \
    FS_NERDFONT_CONFIG="$FX_TMP/noread2.list" -- export "$FX_TMP/refresh" --profile minimal
if [[ -e "$FX_TMP/refresh/export.meta" ]]; then
    fx_bad "the failed re-export left the previous export.meta in place"
else
    fx_ok
fi
# the partial refresh really did overwrite the tree, so the marker is the only
# thing refusing it -- without this the previous assert could pass vacuously
if [[ -f "$FX_TMP/refresh/minimal.conf" ]]; then fx_ok; else fx_bad "the failed re-export wrote no profile conf (cell is not exercising the refresh)"; fi
run_setup "re-import of the half-refreshed tree" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/refresh"
fx_err 'not an export tree'
chmod 644 "$FX_TMP/noread2.list" 2>/dev/null || :

# -------------------- 15d. a failure INSIDE the manifest loop invalidates too

# Cell 15c fails in _export_fonts, which runs AFTER the marker drop, so it
# cannot catch a drop placed in the wrong spot. The manifest loop is the first
# writer, so that is where a failure has to be injected: module 2 of a PRIVATE
# module copy gets an invalid MODULE_DEFAULT, which module_validate rejects
# after module 1's manifests have already been rewritten. If the marker were
# dropped after the loop -- the obvious place, next to the other setup -- the
# old marker would survive and the re-import would replay the OLD profile over
# the NEW ids.
rm -rf "$FX_TMP/loopy"; cp -a "$MODS" "$FX_TMP/loopy" || fx_bad "could not copy the module tree"
run_setup "good export before the in-loop failure" 0 FS_HOME="$FX_TMP/state" \
    FS_MODULES_DIR="$FX_TMP/loopy" -- export "$FX_TMP/loop" --profile desktop
printf 'DRIFTED-CORE-PKG\n' >>"$FX_TMP/loopy/core/packages.rpm.list"
sed -i 's/^MODULE_DEFAULT=.*/MODULE_DEFAULT=bogus/' "$FX_TMP/loopy/flatpak/module.sh"
run_setup "a re-export that fails inside the manifest loop" 1 FS_HOME="$FX_TMP/state" \
    FS_MODULES_DIR="$FX_TMP/loopy" -- export "$FX_TMP/loop" --profile minimal
fx_err 'MODULE_DEFAULT'
if [[ -e "$FX_TMP/loop/export.meta" ]]; then
    fx_bad "the in-loop failure left the previous export.meta in place"
else
    fx_ok
fi
# the loop must really have started and rewritten module 1, else the cell above
# passes on a run that never got as far as writing anything
if grep -qF 'DRIFTED-CORE-PKG' "$FX_TMP/loop/manifests/core.list" 2>/dev/null; then
    fx_ok
else
    fx_bad "the failed loop wrote nothing (cell is not exercising the window)"
fi
run_setup "re-import of the tree with an in-loop failure" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/loop"
fx_err 'not an export tree'

# ------------------- 15e. a failure in the LAST stage still invalidates

# 15c injects its failure in _export_fonts and 15d inside the manifest loop.
# The one stage left that can fail after both is _export_files, immediately
# before the marker is written -- so moving the final marker write up next to
# _export_fonts would pass the whole suite while breaking the contract that a
# tree carrying a marker had every stage succeed. An unwritable files/ on a
# refresh is the cheapest way to fail exactly there.
run_setup "good export before the last-stage failure" 0 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/tail" --profile desktop
if [[ -f "$FX_TMP/tail/export.meta" ]]; then fx_ok; else fx_bad "the export wrote no export.meta"; fi
chmod 500 "$FX_TMP/tail/files"
run_setup "a re-export that fails in the last stage" 1 FS_HOME="$FX_TMP/state" \
    -- export "$FX_TMP/tail" --profile minimal
chmod 700 "$FX_TMP/tail/files"
if [[ -e "$FX_TMP/tail/export.meta" ]]; then
    fx_bad "the last-stage failure left a marker behind"
else
    fx_ok
fi
run_setup "re-import of the tree with a last-stage failure" 1 FS_HOME="$FX_TMP/state" \
    -- install --dry-run --yes --manifest "$FX_TMP/tail"
fx_err 'not an export tree'

# ---------------------------------------- 16. the flag itself, not just the tree

run_setup "--manifest with no value" 1 -- install --manifest
fx_err "flag '--manifest' requires a directory"
run_setup "export --manifest with no value" 1 -- export --manifest
fx_err "flag '--manifest' requires a directory"
run_setup "--manifest is not reset between parses" 0 -- install --dry-run --yes --profile desktop
fx_out_not 're-importing'

# the private module copy must match the repo exactly at the end of the run
if diff -r "$ROOT/modules" "$MODS" >/dev/null 2>&1; then
    fx_ok
else
    fx_bad "the fixture left the private module copy modified"
fi
# The repo's modules/ and profiles/ must be no dirtier than they were BEFORE
# the fixture ran (see GIT_STATUS_BEFORE). A pre-existing dirty tree is the
# developer's state, not something the fixture left behind.
GIT_STATUS_AFTER="$(git -C "$ROOT" status --porcelain -- modules profiles 2>/dev/null || :)"
if [[ "$GIT_STATUS_AFTER" == "$GIT_STATUS_BEFORE" ]]; then
    fx_ok
else
    fx_bad "the fixture left a change in the repo modules/ or profiles/"
fi

fx_summary
