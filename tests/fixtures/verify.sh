#!/usr/bin/env bash
# tests/fixtures/verify.sh - P9.2 fixture for `./setup verify` (audit).
#
# Drives the real launcher. Two module trees are used deliberately:
#   * the REAL repo modules/ for the cells that must reflect shipped content
#     (family list selection, the alt pair, the real verify() hooks), and
#   * a SYNTHETIC tree for the protocol cells, so hook-rc and
#     no-verify()-defined cases are reachable without inventing a repo
#     module that has no business existing.
#
# "Half-installed" is the task's own fixture shape and is the centerpiece: a
# module whose declared packages are only partly present must yield one FAIL
# row naming exactly the absent ones. Packages are driven by the mock backend
# + FS_MOCK_INSTALLED (a file IS the installed set), and flatpaks by a fake
# `flatpak` that answers only `info`/`remotes`.
#
# `guard_fake` is the P8.1 lesson applied preemptively: a farm built from
# symlinks once leaked the real binary into a non-dry cell and mutated this
# machine. A leaked real `flatpak` here would silently answer from the real
# store and turn a FAIL cell into a PASS, so every non-dry cell asserts the
# fake is a regular file that differs from the real binary, and the guard has
# a self-test proving it still rejects a leaky farm.
#
# `agree` re-derives the exit-code rule independently of the implementation on
# every cell, so the table and the process status can never drift apart
# without a FAIL here.
# Usage: bash tests/fixtures/verify.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
SETUP="$ROOT/setup"
printf 'P9.2 verify audit\n'

REAL_MODULES="$ROOT/modules"
SYNTH="$FX_TMP/synth"
FARM="$FX_TMP/farm"
REAL_SNAP="$FX_TMP/real"
FAKE_LOG="$FX_TMP/flatpak.calls"
INSTALLED="$FX_TMP/mock-installed"
FP_STATE="$FX_TMP/flatpak-state"

FX_BLOCK_RC=0

WHITELIST="bash sh dash awk gawk mktemp rm mv cp cat ls readlink dirname basename uname df id tr sed grep sort head wc cut chmod touch mkdir env sleep date expr"

mkfarm() {
    local name dest
    rm -rf -- "$FARM"
    mkdir -p "$FARM" "$REAL_SNAP"
    for name in $WHITELIST; do
        dest="$(command -v "$name" 2>/dev/null)" || continue
        [[ -n "$dest" ]] || continue
        dest="$(readlink -f "$dest" 2>/dev/null)" || continue
        [[ -f "$dest" && ! -L "$dest" ]] || continue
        cp --remove-destination -- "$dest" "$FARM/$name" 2>/dev/null || continue
        [[ -f "$FARM/$name" && ! -L "$FARM/$name" ]] || continue
        cp --remove-destination -- "$dest" "$REAL_SNAP/$name" 2>/dev/null || :
    done
}

setfake() {
    local name="$1"
    shift
    rm -f -- "$FARM/$name"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$*"
    } >"$FARM/$name"
    chmod +x "$FARM/$name"
}

guard_fake() {
    local name="$1" label="$2" want_bad="${3:-0}"
    local f="$FARM/$name" real="$REAL_SNAP/$name" bad=0
    if [[ -e "$f" ]]; then
        if [[ ! -f "$f" ]] || [[ -L "$f" ]]; then
            bad=1
        fi
        if [[ -f "$real" ]]; then
            if cmp -s -- "$f" "$real"; then
                bad=1
            fi
        fi
    fi
    if (( bad == want_bad )); then
        fx_ok
    else
        fx_bad "guard_fake: $name in the $label farm leaked (want_bad=$want_bad, bad=$bad)"
    fi
    return 0
}

# A fake flatpak that answers ONLY read-only queries. `info --user|--system
# <app>` succeeds for an app in $FP_STATE; `remotes --columns=name` prints
# $FP_REMOTES. Anything else exits 97, so a mutation slipping into verify is
# caught by the verb allowlist rather than silently succeeding.
farm_flatpak() {
    local remotes="${1-__DEFAULT__}"
    if [[ "$remotes" == "__DEFAULT__" ]]; then
        remotes="flathub"
    fi
    : >"$FAKE_LOG"
    setfake flatpak "case \"\$1 \$2\" in
  'info --user'|'info --system')
    printf '%s\\n' \"info \$*\" >>'$FAKE_LOG'
    grep -qxF -- \"\$3\" '$FP_STATE' && exit 0
    exit 1
    ;;
  'remotes --columns=name')
    printf '%s\\n' \"remotes \$*\" >>'$FAKE_LOG'
    for r in $remotes; do printf '%s\\n' \"\$r\"; done
    exit 0
    ;;
esac
printf '%s\\n' \"\$*\" >>'$FAKE_LOG'
exit 97"
}

only_readonly_verbs() {
    local label="$1" line bad=0
    if [[ ! -s "$FAKE_LOG" ]]; then
        fx_ok
        return 0
    fi
    while IFS= read -r line; do
        case "$line" in
            info\ * | remotes\ *) ;;
            *) bad=1 ;;
        esac
    done <"$FAKE_LOG"
    if (( bad == 0 )); then
        fx_ok
    else
        fx_bad "$label: fake flatpak saw a non-read-only invocation:"
        sed 's/^/    /' "$FAKE_LOG" >&2
    fi
    return 0
}

# seed <pkg>... writes the mock backend's installed set.
seed() {
    : >"$INSTALLED"
    local p
    for p in "$@"; do
        printf '%s\n' "$p" >>"$INSTALLED"
    done
}

app() {
    local a
    for a in "$@"; do
        printf '%s\n' "$a" >>"$FP_STATE"
    done
}

FX_BLOCK_RC=0
run_verify() {
    local want="$1" label="$2"
    shift 2
    : >"$FAKE_LOG"
    (   set -uo pipefail
        set +e
        env -i PATH="$FARM" "$@"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

agree() {
    local want="$1" label="$2"
    if grep -q '^  - FAIL ' "$FX_OUT" 2>/dev/null; then
        if (( want == 1 )) && grep -q '^  - verify FAILED' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: FAIL row present but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    elif grep -q '^  - WARN ' "$FX_OUT" 2>/dev/null; then
        if (( want == 0 )) && grep -q '^  - verify OK with warnings' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: WARN rows present but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    elif grep -q '^  - SKIP ' "$FX_OUT" 2>/dev/null; then
        local skips
        skips="$(grep -c '^  - SKIP ' "$FX_OUT")"
        if (( want == 0 )) && grep -qx "  - verify OK with $skips check(s) skipped" "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: SKIP rows present but verdict/rc disagree (want $want, got $FX_BLOCK_RC, skips=$skips)"
        fi
    else
        if (( want == 0 )) && grep -qx '  - verify OK' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: all-PASS but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    fi
    return 0
}

# ── synthetic module tree, for the hook-protocol cells ────────────────────
mkm() {
    local id="$1" risk="${2:-none}"
    mkdir -p "$SYNTH/$id"
    {
        printf 'MODULE_ID=%s\n' "$id"
        printf 'MODULE_TITLE=%s\n' "$id"
        printf 'MODULE_RISK=%s\n' "$risk"
        printf 'MODULE_DEFAULT=off\n'
    } >"$SYNTH/$id/module.sh"
}

# --- 1. half-installed module: the task's own verification shape ----------

mkfarm
farm_flatpak
seed wget vim
: >"$FP_STATE"
app org.libreoffice.LibreOffice
mkm m1
printf 'wget\nvim\ncurl\n' >"$SYNTH/m1/packages.list"
run_verify 1 "half-installed" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
guard_fake flatpak "half-installed"
fx_out 'FAIL m1:packages: missing: curl'
fx_out_not 'missing: wget'
fx_out_not 'missing: vim'
fx_out 'SKIP m1:hook: module has no verify() hook'
agree 1 "half-installed"

# --- 2. fully present -> PASS, and an all-PASS table -> "verify OK" ------

seed wget vim curl
cat >"$SYNTH/m1/hooks.sh" <<'EOS'
run() { :; }
verify() { return 0; }
EOS
run_verify 0 "all present" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'PASS m1:packages: all 3 present'
fx_out 'PASS m1:hook: verify() passed'
fx_out 'PASS repo:flathub: remote present'
fx_out_not '^  - WARN '
fx_out_not '^  - FAIL '
agree 0 "all present"

# --- 3. empty package list -> no packages row at all --------------------

rm -f -- "$SYNTH/m1/packages.list" "$SYNTH/m1/hooks.sh"
run_verify 0 "no lists" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out_not 'm1:packages'
fx_out_not 'm1:flatpaks'
fx_out 'SKIP m1: nothing to verify (no list files, no verify() hook)'
fx_out_not 'm1:hook'
agree 0 "no lists"

# --- 4. flatpaks: mixed present/missing --------------------------------

rm -f -- "$SYNTH/m1/packages.list"
printf 'org.a.A\norg.b.B\n' >"$SYNTH/m1/flatpaks.list"
app org.a.A
run_verify 1 "flatpak half" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
guard_fake flatpak "flatpak half"
fx_out 'FAIL m1:flatpaks: not installed: org.b.B'
fx_out_not 'not installed: org.a.A'
only_readonly_verbs "flatpak half"
agree 1 "flatpak half"

# --- 5. flatpaks all present -> PASS ------------------------------------

app org.a.A org.b.B
run_verify 0 "flatpak all" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'PASS m1:flatpaks: all 2 present'
only_readonly_verbs "flatpak all"
agree 0 "flatpak all"

# --- 6. no flatpak CLI -> SKIP (cannot check), not FAIL -----------------
#
# The repo row is asserted POSITIVELY as a skip: before A2 this check returned
# NO row at all when the flatpak CLI was missing, which is the defect F5 names
# -- an audit that could not run rendered an incomplete table indistinguishable
# from a complete one. `fx_out_not 'repo:flathub'` was the pin for that silence,
# so it is now the pin for its replacement.
rm -f -- "$FARM/flatpak"
run_verify 0 "no flatpak cli" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'SKIP m1:flatpaks: cannot check 2 app(s): flatpak CLI not in PATH'
fx_out 'SKIP repo:flathub: cannot check the flathub remote: flatpak CLI not in PATH'
fx_out_not '^  - FAIL '
agree 0 "no flatpak cli"

# --- 7. flathub remote missing -> WARN, and it is the only repo row ------

farm_flatpak someotherremote
run_verify 0 "no flathub" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'WARN repo:flathub: remote flathub is not configured'
fx_out_not '^  - FAIL '
agree 0 "no flathub"
only_readonly_verbs "no flathub"

# --- 8. hook rc1 -> FAIL, rc0 -> PASS ----------------------------------

farm_flatpak
cat >"$SYNTH/m1/hooks.sh" <<'EOS'
run() { :; }
verify() {
    io_info "m1: hook ran"
    return 1
}
EOS
run_verify 1 "hook rc1" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'FAIL m1:hook: verify() reported problems (rc 1)'
fx_out 'm1: hook ran'
agree 1 "hook rc1"

cat >"$SYNTH/m1/hooks.sh" <<'EOS'
run() { :; }
verify() {
    io_info "m1: hook ran"
    return 0
}
EOS
run_verify 0 "hook rc0" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'PASS m1:hook: verify() passed'
agree 0 "hook rc0"

# --- 9. hooks.sh with no verify() -> WARN, not PASS ---------------------

cat >"$SYNTH/m1/hooks.sh" <<'EOS'
run() { :; }
EOS
run_verify 0 "no verify fn" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'SKIP m1:hook: hooks.sh defines no verify()'
fx_out_not 'PASS m1:hook'
agree 0 "no verify fn"

# --- 10. the hook sees its OWN metadata, not the last-loaded module -----

cat >"$SYNTH/m1/hooks.sh" <<'EOS'
run() { :; }
verify() {
    io_info "m1: sees id=$MODULE_ID family=${FS_MODULE_FAMILY:-unset}"
    return 0
}
EOS
run_verify 0 "own metadata" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'm1: sees id=m1 family=rpm'
agree 0 "own metadata"

# --- 11. a hook with nothing to verify must NOT render as a PASS row ----
#
# Every shipped hook returns 0 when it declines to check (locale with no
# localectl, chrome on arch, the gnome hooks behind gnome_require_capable).
# In a DRY RUN every hook returns 0 unconditionally, so a PASS row there
# would be a claim verify never made. This cell is the guard for that.
run_verify 0 "dry run hook" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    FS_DRY_RUN=1 HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'SKIP m1:hook: skipped (dry run; the hook refuses to probe)'
fx_out_not 'PASS m1:hook'
agree 0 "dry run hook"

# --- 12. generic layer still runs in dry mode (read-only queries) -------

printf 'wget\n' >"$SYNTH/m1/packages.list"
rm -f -- "$SYNTH/m1/hooks.sh"
seed wget
run_verify 0 "dry run generic" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    FS_DRY_RUN=1 HOME="$FX_TMP/h" "$SETUP" verify m1
fx_out 'PASS m1:packages: all 1 present'
agree 0 "dry run generic"

# --- 13. flatpak-alt pair: a truthy seam must not read the SYSTEM list --

mkm alt
cat >"$SYNTH/alt/module.sh" <<'EOS'
MODULE_ID=alt
MODULE_TITLE=alt
MODULE_RISK=none
MODULE_DEFAULT=off
MODULE_FLATPAK_ALT_ID=com.alt.Alt
MODULE_FLATPAK_ALT_SEAM=FS_ALT_ON
EOS
printf 'stale-native-pkg\n' >"$SYNTH/alt/packages.rpm.list"
printf 'com.alt.Alt\n' >"$SYNTH/alt/flatpaks.list"
seed
app com.alt.Alt
run_verify 0 "alt seam on" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    FS_ALT_ON=1 HOME="$FX_TMP/h" "$SETUP" verify alt
guard_fake flatpak "alt seam on"
fx_out_not 'alt:packages'
fx_out_not 'stale-native-pkg'
fx_out 'PASS alt:flatpaks: all 1 present'
fx_out_not 'all 2 present'
agree 0 "alt seam on"

run_verify 1 "alt seam off" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify alt
fx_out 'FAIL alt:packages: missing: stale-native-pkg'
fx_out 'PASS alt:flatpaks: all 1 present'
agree 1 "alt seam off"

# --- 14. family list selection: the deb list is used on deb ------------

mkm fam
printf 'common-pkg\n' >"$SYNTH/fam/packages.list"
printf 'rpm-only\n' >"$SYNTH/fam/packages.rpm.list"
printf 'deb-only\n' >"$SYNTH/fam/packages.deb.list"
seed common-pkg rpm-only
run_verify 0 "rpm family" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify fam
fx_out 'PASS fam:packages: all 2 present'
run_verify 1 "deb family" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" FS_DISTRO_FAMILY=deb "$SETUP" verify fam
fx_out 'FAIL fam:packages: missing: deb-only'
fx_out_not 'rpm-only'
agree 1 "deb family"

# --- 15. selection: explicit ids only ----------------------------------

mkm m2
printf 'wget\n' >"$SYNTH/m2/packages.list"
seed wget
run_verify 0 "explicit ids" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m2
fx_out 'm2:packages'
fx_out_not 'm1:'
fx_out 'SKIP m2:hook: module has no verify() hook'
agree 0 "explicit ids"

# --- 16. selection: the P4.6 registry gates the default ----------------

ST="$FX_TMP/h2/.local/state/fedora-setup"
mkdir -p "$ST/modules"
printf 'done 2026-01-01T00:00:00\n' >"$ST/modules/m2"
run_verify 0 "registry default" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h2" "$SETUP" verify
fx_out 'm2:packages'
fx_out_not 'm1:'
agree 0 "registry default"

# --- 17. selection: an empty registry falls back to every module -------

run_verify 1 "empty registry" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h3" "$SETUP" verify
fx_out 'm1:'
fx_out 'm2:'
fx_out 'alt:'
fx_out 'fam:'
fx_out_not 'no modules to verify'
agree 1 "empty registry"

# --- 18. selection: a profile closure is deps-closed -------------------

PDIR="$FX_TMP/profiles"
mkdir -p "$PDIR"
printf 'm2\n' >"$PDIR/audited.conf"
run_verify 0 "profile closure" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PROFILES_DIR="$PDIR" FS_PKG_BACKEND=mock \
    FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h4" "$SETUP" verify --profile audited
fx_out 'm2:packages'
fx_out_not 'm1:'
agree 0 "profile closure"

# --- 19. bad selections fail closed ------------------------------------

run_verify 1 "invalid id" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm HOME="$FX_TMP/h" \
    "$SETUP" verify 'bad id!'
fx_err 'invalid module id'
run_verify 1 "unknown module" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm HOME="$FX_TMP/h" \
    "$SETUP" verify nosuch
fx_err 'module not found: nosuch'
run_verify 1 "empty modules dir" PATH="$FARM" FS_MODULES_DIR="$FX_TMP/nope" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm HOME="$FX_TMP/h" "$SETUP" verify
fx_err 'modules directory not found'
run_verify 1 "unsupported family" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=plan9 HOME="$FX_TMP/h" \
    "$SETUP" verify m1
fx_err 'unsupported family: plan9'
run_verify 1 "empty synth tree" PATH="$FARM" FS_MODULES_DIR="$FX_TMP/emptytree" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm HOME="$FX_TMP/h" "$SETUP" verify
mkdir -p "$FX_TMP/emptytree"
run_verify 1 "empty synth tree" PATH="$FARM" FS_MODULES_DIR="$FX_TMP/emptytree" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm HOME="$FX_TMP/h" "$SETUP" verify
fx_err 'no modules to verify'

# --- 20. READ-ONLY: no state root is created for a fresh HOME ----------

rm -rf -- "$FX_TMP/h5"
# No explicit ids: selection falls through to the recorded registry, and THAT is
# the only path that reads state and could therefore create a state root. An
# earlier revision of this cell passed an explicit id, which bypasses the
# registry entirely and so tested nothing about the read-only contract.
FRESH_MODS="$FX_TMP/fresh-modules"
mkdir -p "$FRESH_MODS/onlymod"
{
    printf 'MODULE_ID=onlymod\n'
    printf 'MODULE_TITLE=onlymod\n'
    printf 'MODULE_RISK=none\n'
    printf 'MODULE_DEFAULT=off\n'
} >"$FRESH_MODS/onlymod/module.sh"
printf 'run() { :; }\nverify() { return 0; }\n' >"$FRESH_MODS/onlymod/hooks.sh"
run_verify 0 "read-only fresh home" PATH="$FARM" FS_MODULES_DIR="$FRESH_MODS" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h5" "$SETUP" verify
if [[ -e "$FX_TMP/h5/.local/state/fedora-setup" ]]; then
    fx_bad "verify created a state root on a host that had none"
else
    fx_ok
fi

# --- 21. READ-ONLY: the flatpak fake never saw a mutation -------------

farm_flatpak
app org.a.A org.b.B
run_verify 0 "flatpak read-only" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify m1
guard_fake flatpak "flatpak read-only"
only_readonly_verbs "flatpak read-only"

# --- 22. the REAL shipped modules, real hooks, real content ------------

# The point of the generic layer is that it covers shipped modules with no
# hooks of their own, so the audit is checked against the real tree: `dev`
# ships no hooks.sh at all, and its rows must still come from its list files.
seed python3-pip nodejs gcc make cmake clang jupyter-notebook
run_verify 0 "real dev module" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify dev
guard_fake flatpak "real dev module"
fx_out 'PASS dev:packages: all 7 present'
fx_out 'SKIP dev:hook: module has no verify() hook'
only_readonly_verbs "real dev module"
agree 0 "real dev module"

# half the real dev set absent
seed nodejs gcc
run_verify 1 "real dev half" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify dev
fx_out 'FAIL dev:packages: missing: python3-pip make cmake clang jupyter-notebook'
fx_out_not 'missing: nodejs'
agree 1 "real dev half"

# --- 23. vscode: a prerepo module with no hooks still gets package rows

seed code
run_verify 0 "real vscode" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify vscode
guard_fake flatpak "real vscode"
fx_out 'PASS vscode:packages: all 1 present'
agree 0 "real vscode"

# --- 24. the flatpak-alternative pair on the REAL vscode module ---------

seed
app com.visualstudio.code
run_verify 0 "real vscode flatpak" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    FS_VSCODE_FLATPAK=1 HOME="$FX_TMP/h" "$SETUP" verify vscode
fx_out_not 'vscode:packages'
fx_out_not 'missing: code'
fx_out 'PASS vscode:flatpaks: all 1 present'
only_readonly_verbs "real vscode flatpak"
agree 0 "real vscode flatpak"

# mkblock.sh <file> <block-name> <body-file> - write a managed block exactly
# the way lib/fs.sh's fs_managed_block does, so the fixture never hardcodes a
# rendering that the real installer would not produce.
cat >"$FX_TMP/mkblock.sh" <<MKBLOCK
#!/usr/bin/env bash
set -euo pipefail
export FS_HOME="$FX_TMP/state"
source "$ROOT/lib/io.sh"
source "$ROOT/lib/state.sh"
source "$ROOT/lib/fs.sh"
state_init >/dev/null
fs_managed_block "\$1" "\$2" "\$(cat "\$3")" >/dev/null
MKBLOCK
chmod +x "$FX_TMP/mkblock.sh"

# fs_managed_block with an empty body leaves the MARKERS in place, so
# "the user deleted our block" must go through the real removal path.
cat >"$FX_TMP/rmblock.sh" <<MKBLOCK
#!/usr/bin/env bash
set -euo pipefail
export FS_HOME="$FX_TMP/state"
source "$ROOT/lib/io.sh"
source "$ROOT/lib/state.sh"
source "$ROOT/lib/fs.sh"
state_init >/dev/null
fs_managed_block_remove "\$1" "\$2" >/dev/null
MKBLOCK
chmod +x "$FX_TMP/rmblock.sh"

# Bodies are produced by the hooks' OWN helpers (_git_body, _term_block,
# _term_aliases_body, _font_marker) and written through the real
# fs_managed_block, so the known-good state is by construction what run()
# installs. An earlier revision of this section hand-wrote the bodies, which is
# why three false-PASS defects were invisible to a fully green suite: the
# oracle was authored from the same reading of the module as the verifier, so
# the two shared an assumption and could never disagree. Deriving the bodies
# makes a divergence in either direction turn this suite red.
cat >"$FX_TMP/mkstate.sh" <<MKSTATE
#!/usr/bin/env bash
set -euo pipefail
export FS_HOME="$FX_TMP/state"
export FS_GIT_USER_NAME="\${FS_GIT_USER_NAME:-Ada}"
export FS_GIT_USER_EMAIL="\${FS_GIT_USER_EMAIL:-ada@example.org}"
export FS_FONTS_DIR="$FX_TMP/fonts"
export FS_BASHRC="$FX_TMP/gh/.bashrc"
export FS_TERM_ALIASES="$FX_TMP/gh/aliases"
export FS_OMP_BIN="$FX_TMP/posh"
export FS_OMP_THEME="$FX_TMP/theme.json"
export FS_ATUIN_BIN="$FX_TMP/atuin"
mkdir -p "$FX_TMP/fonts" "$FX_TMP/gh"
source "$ROOT/lib/io.sh"
source "$ROOT/lib/state.sh"
source "$ROOT/lib/fs.sh"
state_init >/dev/null
source "$ROOT/modules/git/hooks.sh"
_git_body
fs_managed_block "\$FS_GIT_CONFIG" git "\$GIT_BODY" >/dev/null
printf '%s' "\$GIT_BODY" >"$FX_TMP/gitbody"
source "$ROOT/modules/terminal/hooks.sh"
_term_aliases_body
fs_managed_block "\$FS_TERM_ALIASES" aliases "\$TERM_ALIASES_BODY" >/dev/null
printf '%s' "\$TERM_ALIASES_BODY" >"$FX_TMP/aliasbody"
_term_block "\$FS_TERM_ALIASES" "\$FS_OMP_BIN" "\$FS_OMP_THEME" "\$FS_ATUIN_BIN"
fs_managed_block "\$FS_BASHRC" terminal "\$TERM_BLOCK_BODY" >/dev/null
printf '{"version":2}\n' >"\$FS_OMP_THEME"
source "$ROOT/modules/fonts/hooks.sh"
while IFS= read -r _e; do
    case "\$_e" in \#*|"") continue ;; esac
    _a="\${_e#*:}"; _a="\${_a%%:*}"
    _v="\${_e##*:}"
    : >"\$FS_FONTS_DIR/\$(_font_marker "\$_a" "\$_v")"
done <"$ROOT/config/nerdfonts.list"
MKSTATE
chmod +x "$FX_TMP/mkstate.sh"

# --- 24b. a hook's rc is a VERDICT, never a protocol signal --------------
#
# The blocking finding of the P9.2 review: an earlier revision reused rc 2/3 as
# the "no hook" / "no verify() defined" signals, so a verify() that returned 2
# to mean FAILURE was reported as WARN "module has no verify() hook" and the
# process exited 0 -- a broken install audited as clean. rc 2 and rc 3 must
# therefore both be ordinary failures. The reserved signals are 90/91.

printf 'wget\n' >"$SYNTH/m1/packages.list"
seed wget

for _rc in 2 3; do
    mkm "h$_rc"
    printf 'wget\n' >"$SYNTH/h$_rc/packages.list"
    printf 'run() { :; }\nverify() { return %s; }\n' "$_rc" >"$SYNTH/h$_rc/hooks.sh"
    run_verify 1 "hook rc $_rc is a failure" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
        HOME="$FX_TMP/h" "$SETUP" verify "h$_rc"
    fx_out "FAIL h$_rc:hook: verify() reported problems (rc $_rc)"
    fx_out_not "WARN h$_rc:hook: module has no verify() hook"
    fx_out_not "no verify() hook"
    agree 1 "hook rc $_rc is a failure"
done

# 90/91 are the reserved "not applicable" signals. A module with no hooks.sh
# yields 90 LEGITIMATELY, so that case is a SKIP (A2). A hook that RETURNS 90
# collides with it, and that collision must stay LOUD rather than being absorbed
# into the new SKIP: _verify_hook remaps a sentinel that came back FROM verify()
# to its own reserved values (90+100 / 91+100), so the row is reported as a WARN
# naming the signal the hook actually returned instead of quietly becoming a
# skip. Asserted POSITIVELY, because asserting only negatives would stay green if
# the row were any other WARN or absent entirely -- and `fx_out_not SKIP` is the
# load-bearing half, since a SKIP here is exactly the regression this cell exists
# to catch.
for _rc in 90 91; do
    mkm "h$_rc"
    printf 'wget\n' >"$SYNTH/h$_rc/packages.list"
    printf 'run() { :; }\nverify() { return %s; }\n' "$_rc" >"$SYNTH/h$_rc/hooks.sh"
    run_verify 0 "hook returning reserved $_rc" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
        HOME="$FX_TMP/h" "$SETUP" verify "h$_rc"
    fx_out "WARN h$_rc:hook: verify() returned the reserved audit signal $_rc; reported, not treated as absent"
    fx_out_not "SKIP h$_rc:hook"
    fx_out_not "PASS h$_rc:hook"
    fx_out_not 'verify() passed'
    fx_out_not "no verify() hook"
    agree 0 "hook returning reserved $_rc"
done

# The same two signals, but reaching the harness as `exit` instead of `return`.
# The hook protocol is written with `return`, but nothing enforces it, and the
# two spellings are NOT equivalent inside the harness: a `return` comes back
# through the remap and a `exit` used to terminate the hook subshell before the
# remap could run, at which point its 90/91 is indistinguishable from the
# harness's own sentinels and renders as the SKIP "module has no verify() hook"
# -- a false statement about a hook that demonstrably ran and answered. Pinned
# here because the fix is an extra subshell level, which is exactly the kind of
# "one extra brace" a future refactor removes without noticing why it is there.
for _rc in 90 91; do
    mkm "hx$_rc"
    printf 'wget\n' >"$SYNTH/hx$_rc/packages.list"
    printf 'run() { :; }\nverify() { exit %s; }\n' "$_rc" >"$SYNTH/hx$_rc/hooks.sh"
    run_verify 0 "hook exiting reserved $_rc" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
        HOME="$FX_TMP/h" "$SETUP" verify "hx$_rc"
    fx_out "WARN hx$_rc:hook: verify() returned the reserved audit signal $_rc; reported, not treated as absent"
    fx_out_not "SKIP hx$_rc:hook"
    fx_out_not "no verify() hook"
    agree 0 "hook exiting reserved $_rc"
done

# And a hook that adopts the harness's own internal remap values must not be
# able to impersonate it: 190/191 are the audit's private codes, so a hook that
# returns one is just a hook returning an uninterpretable verdict, and the
# `*` arm FAILs it. This is the "can the remap be spoofed" direction, and it is
# why the remap carries the original rc instead of collapsing both signals onto
# one shared sentinel (a single shared value would have been adoptable).
for _rc in 190 191; do
    mkm "hz$_rc"
    printf 'wget\n' >"$SYNTH/hz$_rc/packages.list"
    printf 'run() { :; }\nverify() { return %s; }\n' "$_rc" >"$SYNTH/hz$_rc/hooks.sh"
    run_verify 1 "hook returning harness-internal $_rc" PATH="$FARM" \
        FS_MODULES_DIR="$SYNTH" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
        HOME="$FX_TMP/h" "$SETUP" verify "hz$_rc"
    fx_out "FAIL hz$_rc:hook: verify() reported problems (rc $_rc)"
    fx_out_not "reserved audit signal"
    agree 1 "hook returning harness-internal $_rc"
done

# and the no-hooks.sh case is the same sentinel reached legitimately
mkm hnohook
printf 'wget\n' >"$SYNTH/hnohook/packages.list"
run_verify 0 "no hooks.sh at all" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify hnohook
fx_out 'SKIP hnohook:hook: module has no verify() hook'
agree 0 "no hooks.sh at all"

# --- 24c. a stale registry entry FAILs but never hides the rest ---------
#
# Selection via the recorded registry must not abort on the first stale id: a
# removed module would otherwise make the whole audit unreachable, which is the
# opposite of useful. Every stale entry is reported, and the remaining recorded
# modules are still audited.

STALE_ROOT="$FX_TMP/stale-home"
# The registry is one file per module id under $root/modules, which is what
# state_module_mark writes, so the fixture writes it the same way.
SR_STATE="$STALE_ROOT/.local/state/fedora-setup/modules"
mkdir -p "$SR_STATE"
printf 'done 2026-09-30T00:00:00Z\n' >"$SR_STATE/core"
printf 'done 2026-09-30T00:00:00Z\n' >"$SR_STATE/ghost-one"
printf 'done 2026-09-30T00:00:00Z\n' >"$SR_STATE/ghost-two"
mkm core
printf 'wget\n' >"$SYNTH/core/packages.list"
printf 'run() { :; }\nverify() { return 0; }\n' >"$SYNTH/core/hooks.sh"
seed wget
run_verify 1 "stale registry entries" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$STALE_ROOT" "$SETUP" verify
guard_fake flatpak "stale registry entries"
fx_out 'FAIL ghost-one: recorded as installed, but the module directory is gone'
fx_out 'FAIL ghost-two: recorded as installed, but the module directory is gone'
fx_out 'PASS core:packages: all 1 present'
fx_out 'PASS core:hook: verify() passed'
only_readonly_verbs "stale registry entries"
agree 1 "stale registry entries"

# --- 25. REAL git/fonts/terminal hooks: the P9.2 category coverage -------
#
# ROADMAP P9.2 names "fonts" and "managed files" as audited categories, and
# these are the only shipped modules that own managed files / a font dir, so
# the coverage is checked against the real hooks rather than a synthetic
# module. State is built with the same seams run() uses, so the audit and the
# installer are pointed at one place.

GH="$FX_TMP/gh"
mkdir -p "$GH" "$FX_TMP/fonts"
printf 'google-noto-sans-fonts\nfira-code-fonts\njetbrains-mono-fonts\n' >"$INSTALLED"

# The known-good install is built by the hooks' own helpers, so the audit is
# checked against what run() would actually produce. The posh and atuin BINARIES
# are intentionally never created: run() guards both behind `[ -x ] &&`, so
# their absence is a reportable state, not a broken install.
TB_BIN="$FX_TMP/posh"
TB_THEME="$FX_TMP/theme.json"
TB_ATUIN="$FX_TMP/atuin"
TB_ALIAS="$GH/aliases"
FS_GIT_CONFIG="$GH/.gitconfig" bash "$FX_TMP/mkstate.sh"

SEAMS=(FS_GIT_USER_NAME=Ada FS_GIT_USER_EMAIL=ada@example.org
    FS_FONTS_DIR="$FX_TMP/fonts" FS_BASHRC="$GH/.bashrc"
    FS_TERM_ALIASES="$TB_ALIAS" FS_OMP_BIN="$TB_BIN"
    FS_OMP_THEME="$TB_THEME" FS_ATUIN_BIN="$TB_ATUIN")
run_real() {
    local want="$1" label="$2"; shift 2
    : >"$FAKE_LOG"
    (   set -uo pipefail
        set +e
        env -i PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
            FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" \
            FS_DISTRO_FAMILY=rpm HOME="$GH" "${SEAMS[@]}" \
            "$SETUP" verify "$@"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
    agree "$want" "$label"
    only_readonly_verbs "$label"
}

# all three present -> PASS. Note the posh/atuin BINARIES are deliberately
# absent here: the managed block references them behind `[ -x ] &&` guards,
# so a missing binary is a reportable state, not a broken install.
run_real 0 "real git+fonts+terminal" git fonts terminal
fx_out 'PASS git:hook: verify() passed'
fx_out 'PASS fonts:hook: verify() passed'
fx_out 'PASS terminal:hook: verify() passed'
fx_out 'verify OK'

# Pristine copies are taken HERE, while the state is known-good, so no cell can
# inherit a previous cell's mutation through its own "restore".
cp "$GH/.gitconfig" "$FX_TMP/gitconfig.pristine"
cp "$GH/.bashrc" "$FX_TMP/bashrc.pristine"
cp "$GH/aliases" "$FX_TMP/aliases.pristine"

# git: every VALUE present, every section HEADER gone. git reads a setting
# outside any section as inert, so this block configures nothing at all, and an
# audit that checked only the values reported it clean. The mutation is derived
# from the real body by deleting the header lines, so it cannot drift from what
# run() writes.
grep -v '^\[' "$FX_TMP/gitbody" >"$FX_TMP/gitbody-noheaders"
bash "$FX_TMP/mkblock.sh" "$GH/.gitconfig" git "$FX_TMP/gitbody-noheaders"
run_real 1 "git headers stripped" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: managed block is missing: \[init\]'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# git: the block exists but is half-written -> FAIL (the drift an audit is for).
# Drops the [diff] header AND its value, so the two failure shapes stay distinct.
grep -v '^\[diff\]' "$FX_TMP/gitbody" | grep -v 'colorMoved' >"$FX_TMP/gitbody-short"
bash "$FX_TMP/mkblock.sh" "$GH/.gitconfig" git "$FX_TMP/gitbody-short"
run_real 1 "git half-written block" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: managed block is missing: colorMoved = zebra'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# git: block gone entirely (the user deleted it) -> FAIL
bash "$FX_TMP/rmblock.sh" "$GH/.gitconfig" git
run_real 1 "git no block" git
fx_err 'git: managed block missing in'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# git: identity configured but the block predates it -> FAIL. With the identity
# UNSET the same block must pass, because run() omits [user] in that case, so
# this cell also pins that the check is not unconditional.
grep -v '^\[user\]' "$FX_TMP/gitbody" | grep -v 'name = \|email = ' >"$FX_TMP/gitbody-nouser"
bash "$FX_TMP/mkblock.sh" "$GH/.gitconfig" git "$FX_TMP/gitbody-nouser"
run_real 1 "git identity missing" git
fx_err 'git: managed block is missing: name = Ada'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# fonts: one marker gone -> FAIL naming that set
mv "$FX_TMP/fonts/.fedora-setup-nerd-JetBrainsMono-v3.3.0" "$FX_TMP/marker.bak"
run_real 1 "fonts one set missing" fonts
fx_err 'fonts: JetBrainsMono Nerd Font (v3.3.0) is not installed'
mv "$FX_TMP/marker.bak" "$FX_TMP/fonts/.fedora-setup-nerd-JetBrainsMono-v3.3.0"

# fonts: the config is unreadable. run() fails closed on this; an audit that
# dropped list_parse's rc saw zero entries, never entered its loop, and reported
# "passed (0 nerd font sets installed)" -- the installer and the auditor
# returning opposite verdicts on identical state.
printf 'FiraCode Nerd Font:FiraCode:v3.3.0\n' >"$FX_TMP/unreadable.list"
chmod 000 "$FX_TMP/unreadable.list"
: >"$FAKE_LOG"
(   set -uo pipefail
    set +e
    env -i PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" \
        FS_DISTRO_FAMILY=rpm HOME="$GH" "${SEAMS[@]}" \
        FS_NERDFONT_CONFIG="$FX_TMP/unreadable.list" \
        "$SETUP" verify fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts unreadable config rc" 1
fx_out 'FAIL fonts:hook: verify() reported problems (rc 1)'
fx_err 'fonts: cannot read the nerd font config'
only_readonly_verbs "fonts unreadable config"
chmod 644 "$FX_TMP/unreadable.list"

# fonts: a comment-only (empty) config is a SUCCESSFUL NO-OP for run(), so the
# auditor must not call it broken. Making verify() fail here was the inverse of
# the B3 disagreement, and would have left a user who trims the config with a
# clean install that `setup verify` reports as a failure and no way out. A WARN
# is the agreed verdict, and it still surfaces the "0 sets" fact.
printf '# only a comment, no entries\n' >"$FX_TMP/empty-fonts.list"
: >"$FAKE_LOG"
(   set -uo pipefail
    set +e
    env -i PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" \
        FS_DISTRO_FAMILY=rpm HOME="$GH" "${SEAMS[@]}" \
        FS_NERDFONT_CONFIG="$FX_TMP/empty-fonts.list" \
        "$SETUP" verify fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts empty config rc" 0
fx_out 'PASS fonts:packages: all 3 present'
# The ROW is PASS, because a hook's return code is a verdict and 0 is the only
# "clean" one it may return -- 90/91 are the framework's reserved "not
# applicable" signals and a hook must never emit them (see AGENTS s12). The
# nuance is carried by the hook's own io_warn, which this cell pins so a
# "0 sets installed" PASS can never again be silent.
fx_out 'PASS fonts:hook: verify() passed'
fx_err 'fonts: no nerd fonts configured in'
fx_out_not 'FAIL '
only_readonly_verbs "fonts empty config"
agree 0 "fonts empty config"

# fonts: target dir gone -> FAIL
mv "$FX_TMP/fonts" "$FX_TMP/fonts.bak"
run_real 1 "fonts dir missing" fonts
fx_err 'fonts: target dir not found'
mv "$FX_TMP/fonts.bak" "$FX_TMP/fonts"

# terminal: bashrc block removed but the user's own lines survive -> FAIL
bash "$FX_TMP/rmblock.sh" "$GH/.bashrc" terminal
printf '# my own line\n' >>"$GH/.bashrc"
run_real 1 "terminal bashrc block gone" terminal
fx_err 'terminal: managed block missing in'
cp "$FX_TMP/bashrc.pristine" "$GH/.bashrc"

# terminal: aliases block removed -> FAIL
bash "$FX_TMP/rmblock.sh" "$GH/aliases" aliases
printf '# my own alias\n' >>"$GH/aliases"
run_real 1 "terminal aliases block gone" terminal
fx_err 'terminal: managed block missing in'
cp "$FX_TMP/aliases.pristine" "$GH/aliases"

# terminal: the aliases block keeps only the FIRST alias and drops the other
# four. An audit that asserted a single alias passed this. The mutation is
# derived from the real five, so it cannot drift from run().
grep -c '' "$FX_TMP/aliasbody" >/dev/null
grep "alias ll=" "$FX_TMP/aliasbody" >"$FX_TMP/aliasbody-short"
bash "$FX_TMP/mkblock.sh" "$GH/aliases" aliases "$FX_TMP/aliasbody-short"
run_real 1 "terminal aliases partial" terminal
fx_err "terminal: aliases block is missing: alias la='ls -A'"
fx_err "terminal: aliases block is missing: alias grep='grep --color=auto'"
fx_err "terminal: aliases block is missing: alias egrep='egrep --color=auto'"
fx_err "terminal: aliases block is missing: alias less='less -R'"
cp "$FX_TMP/aliases.pristine" "$GH/aliases"

# git: a REORDERED block. Every header and every value is present and the SET
# of lines is identical to what run() writes -- but git is section-scoped, so a
# swapped pair moves each value into the wrong section and git reads none of
# them. A set-based comparison called this clean; fs_managed_block, which
# WRITES the block, calls the same state drift. This is the cell that was
# missing when B4 was found, so it is derived from the real body: swap the two
# lines of [diff] and [color] while keeping everything else exactly as run()
# writes it.
sed -e 's/^	colorMoved = zebra$/\tSWAP_A/' \
    -e 's/^	ui = auto$/\tSWAP_B/' \
    -e 's/^\tSWAP_A$/\tui = auto/' \
    -e 's/^\tSWAP_B$/\tcolorMoved = zebra/' \
    "$FX_TMP/gitbody" >"$FX_TMP/gitbody-swapped"
if cmp -s "$FX_TMP/gitbody-swapped" "$FX_TMP/gitbody"; then
    fx_bad "the reorder mutation is a no-op: it did not change the body"
else
    fx_ok
fi
bash "$FX_TMP/mkblock.sh" "$GH/.gitconfig" git "$FX_TMP/gitbody-swapped"
run_real 1 "git reordered block" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: managed block differs from what run() writes at line 6'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# git: a REPEATED line. The set of lines still matches (git is last-wins and
# the value is identical, so behaviour is unchanged) but the length does not,
# and run() would rewrite it -- so a set-only comparison would pass it.
{ cat "$FX_TMP/gitbody"; printf '\tui = auto\n'; } >"$FX_TMP/gitbody-dup"
bash "$FX_TMP/mkblock.sh" "$GH/.gitconfig" git "$FX_TMP/gitbody-dup"
run_real 1 "git duplicated line" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: managed block has'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# git: two complete managed blocks in one file. fs_managed_block refuses to
# create this, so it is hand-edit-only; it must still fail with a message that
# says what is wrong instead of blaming the marker line.
# BOTH shapes are covered. Two ADJACENT well-formed blocks are the realistic
# one (a duplicated merge) and the more likely to lose coverage by accident, so
# they get their own cell; an OVERLAPPING pair (a second BEGIN before the first
# END) is the malformed one. Both are caught by the same check, so neither is
# treated as out of scope.
{ printf '# BEGIN fedora-setup git\n'; cat "$FX_TMP/gitbody"; printf '\n'
  printf '# END fedora-setup git\n'
  printf '# BEGIN fedora-setup git\n'; cat "$FX_TMP/gitbody"; printf '\n'
  printf '# END fedora-setup git\n'; } >"$GH/.gitconfig"
run_real 1 "git two adjacent managed blocks" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: more than one managed block in'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

{ printf '# BEGIN fedora-setup git\n'; cat "$FX_TMP/gitbody"; printf '\n'
  printf '# BEGIN fedora-setup git\n'; cat "$FX_TMP/gitbody"; printf '\n'
  printf '# END fedora-setup git\n'; } >"$GH/.gitconfig"
run_real 1 "git two overlapping managed blocks" git
fx_out 'FAIL git:hook: verify() reported problems (rc 1)'
fx_err 'git: more than one managed block in'
cp "$FX_TMP/gitconfig.pristine" "$GH/.gitconfig"

# terminal: an EXTRA line run() would never write is drift too
{ cat "$FX_TMP/aliasbody"; printf '\n'; printf "alias rm='rm -i'\n"; } >"$FX_TMP/aliasbody-extra"
bash "$FX_TMP/mkblock.sh" "$GH/aliases" aliases "$FX_TMP/aliasbody-extra"
run_real 1 "terminal aliases extra line" terminal
fx_err "terminal: aliases block has an unexpected line: alias rm='rm -i'"
cp "$FX_TMP/aliases.pristine" "$GH/aliases"

# terminal: the posh THEME is referenced with no `[ -x ]` guard, so a missing
# theme breaks the prompt and is a FAIL (unlike the binaries).
mv "$FX_TMP/theme.json" "$FX_TMP/theme.bak"
run_real 1 "terminal theme missing" terminal
fx_err 'terminal: oh-my-posh theme not found'
mv "$FX_TMP/theme.bak" "$FX_TMP/theme.json"

# terminal: a REORDERED aliases block must FAIL *and* say why. An earlier
# version failed correctly but printed no diagnostic at all, because the verdict
# came from a strict comparison while the reporting was set-based, so a pure
# reorder produced silence.
{ head -2 "$FX_TMP/aliasbody"; printf '%s\n%s\n' \
    "alias egrep='egrep --color=auto'" "alias grep='grep --color=auto'"
  tail -1 "$FX_TMP/aliasbody"; } >"$FX_TMP/aliasbody-swapped"
bash "$FX_TMP/mkblock.sh" "$GH/aliases" aliases "$FX_TMP/aliasbody-swapped"
run_real 1 "terminal aliases reordered" terminal
fx_out 'FAIL terminal:hook: verify() reported problems (rc 1)'
fx_err 'terminal: aliases block differs from what run() writes at line'
cp "$FX_TMP/aliases.pristine" "$GH/aliases"

# The severity split, pinned rather than merely true today: the posh/atuin
# BINARIES stay absent throughout this section, yet terminal audits PASS. The
# .bashrc block guards both behind `[ -x ... ] &&`, so a missing binary
# degrades the prompt gracefully and is only reported; the THEME, which the
# block passes unguarded, is a FAIL. That asymmetry is a deliberate contract
# with run(), and this cell turns it red if it ever inverts.
run_real 0 "terminal binaries absent is not a failure" terminal
fx_out 'PASS terminal:hook: verify() passed'
fx_out_not 'FAIL terminal:hook'
fx_out 'terminal: oh-my-posh binary absent'
fx_out 'terminal: atuin binary absent'

run_real 0 "real git+fonts+terminal restored" git fonts terminal
fx_out 'verify OK'

# --- 26. dry-run: the three hooks refuse, and probe nothing -------------

: >"$FAKE_LOG"
(   set -uo pipefail
    set +e
    env -i PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
        FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" \
        FS_DISTRO_FAMILY=rpm HOME="$GH" FS_DRY_RUN=1 "${SEAMS[@]}" \
        "$SETUP" --dry-run verify git fonts terminal
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry-run hooks rc" 0
fx_out 'SKIP git:hook: skipped (dry run; the hook refuses to probe)'
fx_out 'SKIP fonts:hook: skipped (dry run; the hook refuses to probe)'
fx_out 'SKIP terminal:hook: skipped (dry run; the hook refuses to probe)'
fx_out_not 'FAIL '
only_readonly_verbs "dry-run hooks"

# --- 25. guard_fake is not vacuous -------------------------------------

LEAKY="$FX_TMP/leaky"
mkdir -p "$LEAKY"
ln -sf "$(readlink -f "$(command -v flatpak)")" "$LEAKY/flatpak" 2>/dev/null || :
if [[ -L "$LEAKY/flatpak" ]]; then
    FARM="$LEAKY"
    guard_fake flatpak "leaky" 1
else
    printf 'SKIP guard_fake self-test (could not create a symlink farm)\n' >&2
fi
FARM="$FX_TMP/farm"
guard_fake flatpak "real" 0

# --- 27. one cell per SKIPPED cause, on the REAL shipped modules ---------
#
# Each cause is a different arm of lib/gnome.sh's gnome_require_capable, so
# pinning only one of them would leave the other two untested: the gate has four
# reasons plus an override, and every one of them used to arrive at the audit as
# PASS. `gnome-base` is used because it ships NO list files at all, so the table
# is one hook row and the SKIP is the only thing in it -- a mixed table would let
# a wrong rc hide inside PASS rows. The gate refuses BEFORE any probe, so the
# fake gsettings is never invoked in cells b/c (asserted below), and no gsettings
# exists at all in cell a.
#
# The farm has no gsettings unless one is added, which is why cell a is the
# missing-tool case with no extra work: the whitelist deliberately omits it.
farm_flatpak
run_verify 0 "skip cause: missing gsettings" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=0 XDG_CURRENT_DESKTOP=GNOME \
    HOME="$FX_TMP/h" "$SETUP" verify gnome-base
fx_out 'SKIP gnome-base:hook: verify() reported not applicable on this host (reserved rc 93)'
fx_out_not 'PASS gnome-base:hook'
fx_out_not '^  - FAIL '
fx_out 'gnome-base: skipped (not GNOME) (gsettings not found)'
agree 0 "skip cause: missing gsettings"

setfake gsettings "printf '%s\\n' \"\$*\" >>'$FX_TMP/gs.calls'
exit 0"
: >"$FX_TMP/gs.calls"
run_verify 0 "skip cause: non-GNOME session" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=0 XDG_CURRENT_DESKTOP=KDE \
    HOME="$FX_TMP/h" "$SETUP" verify gnome-base
fx_out 'SKIP gnome-base:hook: verify() reported not applicable on this host (reserved rc 93)'
fx_out_not 'PASS gnome-base:hook'
fx_out_not '^  - FAIL '
fx_out "gnome-base: skipped (not GNOME) (not a GNOME session (XDG_CURRENT_DESKTOP='KDE'))"
[[ -s "$FX_TMP/gs.calls" ]] && fx_bad "non-GNOME cell invoked gsettings" || fx_ok
agree 0 "skip cause: non-GNOME session"

: >"$FX_TMP/gs.calls"
run_verify 0 "skip cause: headless SSH session" PATH="$FARM" FS_MODULES_DIR="$REAL_MODULES" \
    FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=0 XDG_CURRENT_DESKTOP=GNOME \
    SSH_CONNECTION='10.0.0.1 51000 10.0.0.2 22' \
    HOME="$FX_TMP/h" "$SETUP" verify gnome-base
fx_out 'SKIP gnome-base:hook: verify() reported not applicable on this host (reserved rc 93)'
fx_out_not 'PASS gnome-base:hook'
fx_out_not '^  - FAIL '
fx_out 'gnome-base: skipped (not GNOME) (SSH session)'
[[ -s "$FX_TMP/gs.calls" ]] && fx_bad "headless cell invoked gsettings" || fx_ok
agree 0 "skip cause: headless SSH session"
rm -f -- "$FARM/gsettings"

# --- 27b. no package backend -> SKIP (cannot check), not FAIL -------------
#
# The flatpak twin of cell 6, and it needed its own cell: every other cell in
# this suite passes FS_PKG_BACKEND=mock, so the no-backend arm was reachable
# from no test at all and mutation M07 (the row reverted to WARN) escaped.
# A backend name lib/pkg.sh does not implement is the hermetic way in: it makes
# pkg_supported fail exactly the way an unimplemented or absent backend does,
# without depending on what this machine happens to have installed.
mkm nobackend
printf 'wget\n' >"$SYNTH/nobackend/packages.list"
seed wget
run_verify 0 "no package backend" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=nosuchbackend FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify nobackend
fx_out 'SKIP nobackend:packages: cannot check 1 package(s): no package backend available'
fx_out_not 'PASS nobackend:packages'
fx_out_not 'FAIL nobackend:packages'
agree 0 "no package backend"

# --- 28. the exit code is one derivation over PASS + SKIP + WARN + FAIL ----
#
# Three shapes, because "SKIP is non-blocking" and "SKIP is non-blocking" are
# one fact with three different ways to be wrong: a skip-only table that exited
# 1, a mixed table where the skip masked a PASS-driven rc, and a skip that
# downgraded a genuine failure. The third is the one that would matter to a user:
# a half-installed module plus an unauditable hook must still fail the run.
mkm bare
run_verify 0 "skip only" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify bare
fx_out 'PASS repo:flathub: remote present'
fx_out 'SKIP bare: nothing to verify (no list files, no verify() hook)'
# Exact per-level counts rather than negatives. `grep -c '^  - '` would also
# count the verdict line, which is indented the same way; the row pattern is
# anchored on the label instead. A negative pin alone would pass on a table that
# had lost its skip row entirely, which is the failure this cell exists for.
if [[ "$(grep -c '^  - PASS ' "$FX_OUT")" == 1 ]] &&
    [[ "$(grep -c '^  - SKIP ' "$FX_OUT")" == 1 ]] &&
    [[ "$(grep -c '^  - WARN ' "$FX_OUT")" == 0 ]] &&
    [[ "$(grep -c '^  - FAIL ' "$FX_OUT")" == 0 ]]; then
    fx_ok
else
    fx_bad "skip only: expected 1 PASS + 1 SKIP + 0 WARN + 0 FAIL rows, got PASS=$(grep -c '^  - PASS ' "$FX_OUT") SKIP=$(grep -c '^  - SKIP ' "$FX_OUT") WARN=$(grep -c '^  - WARN ' "$FX_OUT") FAIL=$(grep -c '^  - FAIL ' "$FX_OUT")"
fi
agree 0 "skip only"

mkm mixed
printf 'wget\n' >"$SYNTH/mixed/packages.list"
seed wget
run_verify 0 "PASS and SKIP together" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify mixed
fx_out 'PASS mixed:packages: all 1 present'
fx_out 'SKIP mixed:hook: module has no verify() hook'
agree 0 "PASS and SKIP together"

seed
run_verify 1 "FAIL and SKIP together" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify mixed
fx_out 'FAIL mixed:packages: missing: wget'
fx_out 'SKIP mixed:hook: module has no verify() hook'
fx_out 'verify FAILED'
fx_out_not 'verify OK'
agree 1 "FAIL and SKIP together"

# The fourth combination, and the one no single-level table can reach: a WARN
# row AND a SKIP row together. It needed its own cell because the two verdicts
# are reached through two different arms of lib/status.sh's status_verdict, and
# with only PASS+SKIP, SKIP-only and FAIL+SKIP covered, SWAPPING those two arms
# was invisible to the whole battery (measured: swapping them left verify 322/0,
# check 131/0 and smoke 169/0 byte-for-byte). The decided policy is that the
# verdict names the WORST level only -- so a table that warns says nothing about
# the skips in its verdict sentence, and the skip rows carry that fact. Pinned
# here so the policy is a recorded decision rather than an accident of arm
# order, and so `_status_skip_count`'s "the skip count is named" claim stays
# scoped to the SKIP-worst case exactly as lib/status.sh's header states.
farm_flatpak "" # a flatpak CLI that answers, but reports no remotes -> WARN
mkm warnskip
run_verify 0 "WARN and SKIP together" PATH="$FARM" FS_MODULES_DIR="$SYNTH" \
    FS_PKG_BACKEND=mock FS_MOCK_INSTALLED="$INSTALLED" FS_DISTRO_FAMILY=rpm \
    HOME="$FX_TMP/h" "$SETUP" verify warnskip
farm_flatpak
fx_out 'WARN repo:flathub: remote flathub is not configured; every flatpak install will fail'
fx_out 'SKIP warnskip: nothing to verify (no list files, no verify() hook)'
if [[ "$(grep -c '^  - WARN ' "$FX_OUT")" == 1 ]] &&
    [[ "$(grep -c '^  - SKIP ' "$FX_OUT")" == 1 ]] &&
    [[ "$(grep -c '^  - FAIL ' "$FX_OUT")" == 0 ]]; then
    fx_ok
else
    fx_bad "WARN+SKIP: expected 1 WARN + 1 SKIP + 0 FAIL rows, got WARN=$(grep -c '^  - WARN ' "$FX_OUT") SKIP=$(grep -c '^  - SKIP ' "$FX_OUT") FAIL=$(grep -c '^  - FAIL ' "$FX_OUT")"
fi
if grep -qx '  - verify OK with warnings' "$FX_OUT"; then
    fx_ok
else
    fx_bad "WARN+SKIP: verdict is not exactly 'verify OK with warnings' (the worst level is the WARN, not the skip)"
fi
fx_out_not 'check(s) skipped'
agree 0 "WARN and SKIP together"

# --- 29. the reserved status codes stay distinct -------------------------
#
# _VERIFY_HOOK_SKIP=93 is only unambiguous while it is neither 90 nor 91 nor 92.
# 92 belongs to lib/modules.sh's run() protocol (MODULE_HOOK_SKIP), so reusing it
# here would make "the hook had nothing to do" mean two different things in two
# different consumers of the same rc, and _VERIFY_HOOK_RESERVED_NONE /
# _VERIFY_HOOK_RESERVED_UNDEFINED are the audit's own private remap values (the
# protocol codes plus 110), which no hook may adopt -- a cell above pins what
# happens when one does. Pinned as literals AND as distinctness, because a
# distinctness-only check would still pass if all of them moved together into a
# colliding block, and a literals-only check would not name the property.
(
    set -uo pipefail
    . "$ROOT/lib/modules.sh"
    . "$ROOT/lib/verify.sh"
    printf '%s %s %s %s %s %s\n' "$_VERIFY_HOOK_NONE" "$_VERIFY_HOOK_UNDEFINED" \
        "$_VERIFY_HOOK_SKIP" "$_VERIFY_HOOK_RESERVED_NONE" \
        "$_VERIFY_HOOK_RESERVED_UNDEFINED" "$MODULE_HOOK_SKIP"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_out '90 91 93 200 201 92'
if [[ "$(tr ' ' '\n' <"$FX_OUT" | grep -c .)" == 6 ]] &&
    [[ "$(tr ' ' '\n' <"$FX_OUT" | sort -u | grep -c .)" == 6 ]]; then
    fx_ok
else
    fx_bad "reserved status codes are not six distinct values: $(cat "$FX_OUT")"
fi
# The remap must also stay OUT of every exit-code-representable range a hook
# could plausibly return as a verdict, and stay above the protocol band, so it
# can never be mistaken for one of the signals it is remapping. Only the remap
# codes (200/201) are checked here; the protocol codes (90/91/93/92) are
# intentionally in the low range.
for _v in 200 201; do
    if ((_v <= 100)); then
        fx_bad "a remap status code is inside the verdict range: $_v"
        break
    fi
done
# and none of them may collide with the small verdicts, or a hook returning 1
# would be read as "no verify() hook" again
small=0
for _v in $(cat "$FX_OUT"); do
    ((_v <= 9)) && small=1
done
if ((small == 0)); then
    fx_ok
else
    fx_bad "a reserved status code collides with a small verdict rc: $(cat "$FX_OUT")"
fi

fx_summary
