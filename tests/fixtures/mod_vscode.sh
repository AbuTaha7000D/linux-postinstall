#!/usr/bin/env bash
# tests/fixtures/mod_vscode.sh - P7.5 fixture for the `vscode` module and
# the pre-batch prerepo stage it is the first user of.
# Drives the REAL repo modules/ + config/ through `./setup install` and
# through direct prerepo() calls with hermetic stand-ins for the external
# binaries (curl/gpg/rpm/dnf5/apt-get/flatpak). Covers:
#   1. metadata + contract: exact MODULE_ID/RISK/DEFAULT/alt-pair, the
#      no-hooks.sh decision pin, and the `setup list` row;
#   2. module_flatpak_alt truthiness (1/true/yes/on, case-insensitive) plus
#      the two fail-closed halves of the pair and the stale-global guard
#      (a module that omits the optional keys must not inherit them from a
#      previously loaded module);
#   3. family lists: `code` on rpm+deb, NOTHING on arch (comment-only
#      packages.arch.list), the P4.2 gate on arch, and the gate failing
#      when the arch list is removed;
#   4. dry-run per family: exact rendered lines AND their order (key fetch
#      -> key import -> repo add -> metadata refresh -> the single `code`
#      install), no flatpak namespace, nothing executed, no repo file
#      written, no state dir;
#   5. the FS_VSCODE_FLATPAK=1 swap on rpm: the flatpak namespace carries
#      com.visualstudio.code and the system namespace is empty, so the two
#      paths can never install side by side;
#   6. real mode against fake binaries: fingerprint MISMATCH refuses
#      everything (no import, no repo file, rc1), a matching fingerprint
#      imports the key and writes the repo file with the right content per
#      family (rpm: gpgcheck=1, no gpgkey=; deb: signed-by= with a
#      tool-owned keyring that really exists), a second run is a no-op for
#      the repo file (--if-not-exists) and the fetch is not, a missing or
#      malformed pin and a missing gpg all fail closed, the arch and
#      flatpak paths are no-ops, and a direct call without
#      FS_MODULE_FAMILY refuses instead of guessing.
# Nothing outside FX_TMP + the real repo modules/config is touched.
# Usage: bash tests/fixtures/mod_vscode.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
# fx_init does not neutralize the ambient seam variables (known gap, same on
# mod_apps/mod_media), and a stray value would silently pick a different
# path than the cell is asserting: FS_VSCODE_FLATPAK would take the flatpak
# branch in the native cells, FS_VSCODE_KEY_FILE/KEYRING would move the pin
# and the keyring, FS_MODULE_FAMILY/FS_DISTRO_FAMILY/FS_PKG_BACKEND would
# re-route the backend, and an inherited FS_DRY_RUN would render instead of
# executing. Every cell sets what it needs, so the baseline is empty.
unset FS_DRY_RUN FS_YES FS_PROFILE FS_VERBOSE FS_DEBUG
unset FS_DISTRO_FILE FS_DISTRO_FAMILY FS_PKG_BACKEND FS_MODULE_FAMILY
unset FS_VSCODE_FLATPAK FS_VSCODE_KEY_FILE FS_VSCODE_KEYRING
unset FS_MOCK_LOG FS_MOCK_INSTALLED FS_FAKE_INSTALLED FS_FAKE_LOG FS_FAKE_FPR
unset FS_FAKE_CURL_RC FS_FAKE_GPG_NOOUT FS_FAKE_GPG_BUNDLE FS_FAKE_GPG_SUBKEY FS_FAKE_FPR2 FS_FAKE_FPR_SUBKEY FS_OPS FS_EUID FS_RUNNING_AS_ROOT
unset FS_SUDO_AVAILABLE FS_REPOS_DIR FS_SOURCES_DIR FS_LOG_FILE
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/repos" "$FX_TMP/sources" "$FX_TMP/keys" "$FX_TMP/scratch"

printf 'P7.5 vscode module\n'

SETUP="$ROOT/setup"
VSDIR="$ROOT/modules/vscode"
PINFILE="$ROOT/config/vscode-gpg.fingerprint"
PIN="BC528686B50D79E339D3721CEB3E94ADBE1229CF"
OPS="$FX_TMP/ops.log"
STUBLOG="$FX_TMP/stub.log"
FAKEST="$FX_TMP/flatpak.inst"

# --- stand-in binaries -----------------------------------------------------
# Every external binary the hook or the pkg layer can reach is a script that
# appends to $OPS, so ordering AND absence of execution are both provable.
# $FS_FAKE_FPR lets a cell report a different primary-key fingerprint.
cat >"$FX_TMP/fakebin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${FS_OPS:?}"
out=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-o" ]]; then out="$a"; fi
    prev="$a"
done
[[ -n "${FS_FAKE_CURL_RC:-}" ]] && exit "${FS_FAKE_CURL_RC}"
[[ -n "$out" ]] && printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\nFAKE\n-----END PGP PUBLIC KEY BLOCK-----\n' >"$out"
exit 0
EOF
cat >"$FX_TMP/fakebin/gpg" <<'EOF'
#!/usr/bin/env bash
printf 'gpg %s\n' "$*" >>"${FS_OPS:?}"
out=""
prev=""
show=0
for a in "$@"; do
    if [[ "$prev" == "--output" ]]; then out="$a"; fi
    if [[ "$a" == "--show-keys" ]]; then show=1; fi
    prev="$a"
done
if (( show == 1 )); then
    printf 'pub:-:2048:1:EB3E94ADBE1229CF:1446074508:::-:::scSC::::::23::0:\n'
    printf 'fpr:::::::::%s:\n' "${FS_FAKE_FPR:-BC528686B50D79E339D3721CEB3E94ADBE1229CF}"
    printf 'uid:-::::1446074508::8994540C1CFC63CED708309E14AD7C334A57793D::Microsoft (Release signing)::::::::::0:\n'
    if [[ -n "${FS_FAKE_GPG_SUBKEY:-}" ]]; then
        printf 'sub:-:2048:1:DEADBEEFDEADBEEF:1446074509:::-:::e::23::0:\n'
        printf 'fpr:::::::::%s:\n' "${FS_FAKE_FPR_SUBKEY:-0000000000000000000000000000000000000002}"
    fi
    if [[ -n "${FS_FAKE_GPG_BUNDLE:-}" ]]; then
        printf 'pub:-:2048:1:0000000000000000:1446074509:::-:::scSC::::::23::0:\n'
        printf 'fpr:::::::::%s:\n' "${FS_FAKE_FPR2:-0000000000000000000000000000000000000001}"
    fi
    exit 0
fi
[[ -n "${FS_FAKE_GPG_NOOUT:-}" ]] && exit 0
if [[ -n "$out" ]]; then printf 'FAKE KEYRING\n' >"$out"; fi
exit 0
EOF
for t in rpm dnf5 dnf apt-get; do
    printf '#!/usr/bin/env bash\nprintf '"'"'%s %%s\\n'"'"' "$*" >>"${FS_OPS:?}"\nexit 0\n' "$t" >"$FX_TMP/fakebin/$t"
done
cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'dpkg-query %s\n' "$*" >>"${FS_OPS:?}"
exit 1
EOF
cat >"$FX_TMP/fakebin/flatpak" <<'EOF'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >>"${FS_OPS:?}"
case "${1:-}" in
    info)
        grep -qxF -- "${3:-}" "${FS_FAKE_INSTALLED:?}" 2>/dev/null
        exit $?
        ;;
    install)
        shift
        for a in "$@"; do
            case "$a" in --*) continue ;; esac
            printf '%s\n' "$a" >>"${FS_FAKE_INSTALLED:?}"
        done
        exit 0
        ;;
esac
exit 0
EOF
chmod +x "$FX_TMP/fakebin"/*
# vs_mkbin builds a COMPLETE, minimal PATH: the coreutils the libs may exec
# (io.sh stamps timestamps, the hook uses mktemp/rm/mkdir, pkg.sh installs
# files) plus the named stubs, and nothing else. That is what makes the two
# "external tool missing" cells honest without inventing a seam: nogpg has
# every stub but gpg, nocurl every stub but curl, and neither inherits the
# host /usr/bin, so `command -v` inside the hook really comes up empty.
COREUTILS="bash env date mkdir mktemp rm install cat grep sed tr head cut cp
mv ls dirname chmod basename uname tty stty id sort wc uniq tee readlink sleep touch"
vs_mkbin() {
    local dir="$1" t p
    shift
    mkdir -p "$dir"
    for t in $COREUTILS; do
        if p="$(type -P "$t")"; then ln -sf "$p" "$dir/$t"; fi
    done
    for t in "$@"; do ln -sf "$FX_TMP/fakebin/$t" "$dir/$t"; done
}
vs_mkbin "$FX_TMP/full" curl gpg rpm dnf5 dnf apt-get dpkg-query flatpak
vs_mkbin "$FX_TMP/nogpg" curl rpm dnf5 dnf apt-get dpkg-query flatpak
vs_mkbin "$FX_TMP/nocurl" gpg rpm dnf5 dnf apt-get dpkg-query flatpak

mkdir -p "$FX_TMP/M2/vscode" "$FX_TMP/M2/zz" "$FX_TMP/P2"
cp "$VSDIR/module.sh" "$FX_TMP/M2/vscode/module.sh"
cp "$VSDIR/packages.rpm.list" "$FX_TMP/M2/vscode/packages.rpm.list"
cp "$VSDIR/prerepo.sh" "$FX_TMP/M2/vscode/prerepo.sh"
printf 'MODULE_ID=zz\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$FX_TMP/M2/zz/module.sh"
printf 'zzp' >"$FX_TMP/M2/zz/packages.list"
printf 'vscode\nzz\n' >"$FX_TMP/P2/pair.conf"

VSRC='source "$ROOT/lib/io.sh"; source "$ROOT/lib/run.sh"; source "$ROOT/lib/sudo.sh"; source "$ROOT/lib/pkg.sh"; source "$ROOT/lib/planner.sh"; source "$ROOT/lib/state.sh"; source "$ROOT/lib/lists.sh"; source "$ROOT/lib/modules.sh"; source "$ROOT/lib/depgraph.sh"; source "$ROOT/lib/profiles.sh"; source "$ROOT/lib/runner.sh"; source "$ROOT/lib/summary.sh"'

# --- 1. metadata + decision pins ------------------------------------------
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$VSRC"
    module_validate "$VSDIR" rpm
    printf 'id=%s\nrisk=%s\ndefault=%s\naltid=%s\nseam=%s\ntitle=%s\n' \
        "$MODULE_ID" "$MODULE_RISK" "$MODULE_DEFAULT" \
        "$MODULE_FLATPAK_ALT_ID" "$MODULE_FLATPAK_ALT_SEAM" "$MODULE_TITLE"
    module_has_hooks "$VSDIR" && printf 'hooks=yes\n' || printf 'hooks=no\n'
    module_has_prerepo "$VSDIR" && printf 'prerepo=yes\n' || printf 'prerepo=no\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode validate rc" 0
fx_out '^id=vscode$'
fx_out '^risk=medium$'
fx_out '^default=on$'
fx_out '^altid=com\.visualstudio\.code$'
fx_out '^seam=FS_VSCODE_FLATPAK$'
fx_out '^title=Visual Studio Code$'
fx_out '^hooks=no$'
fx_out '^prerepo=yes$'

(
    set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^vscode[[:space:]]Visual Studio Code[[:space:]]medium[[:space:]]on[[:space:]]-$' "$FX_OUT"; then
    fx_ok
else
    fx_bad "vscode list row malformed"
fi

# --- 2. the flatpak-alternative resolver -----------------------------------
vs_alt_cell() {
    local seam="$1" want="$2" label="$3"
    (
        set -euo pipefail
        export FS_NO_COLOR=1
        eval "$VSRC"
        module_load "$VSDIR" strict
        if [[ -n "$seam" ]]; then export FS_VSCODE_FLATPAK="$seam"; fi
        module_flatpak_alt
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    if [[ "$(cat "$FX_OUT")" == "$want" ]]; then fx_ok; else fx_bad "$label (got [$(cat "$FX_OUT")], want [$want])"; fi
}
vs_alt_cell "" "" "alt seam unset"
vs_alt_cell "0" "" "alt seam 0"
vs_alt_cell "false" "" "alt seam false"
vs_alt_cell "maybe" "" "alt seam garbage"
vs_alt_cell "1" "com.visualstudio.code" "alt seam 1"
vs_alt_cell "true" "com.visualstudio.code" "alt seam true"
vs_alt_cell "YES" "com.visualstudio.code" "alt seam YES"
vs_alt_cell "On" "com.visualstudio.code" "alt seam On"

# the reset guard: a module WITHOUT the optional keys must not inherit them
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_VSCODE_FLATPAK=1
    eval "$VSRC"
    mkdir -p "$FX_TMP/scratch/plain"
    printf 'MODULE_ID=plain\n' >"$FX_TMP/scratch/plain/module.sh"
    module_load "$VSDIR" strict
    module_load "$FX_TMP/scratch/plain" strict
    module_flatpak_alt
    printf 'end\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "alt seam stale-global guard rc" 0
if [[ "$(cat "$FX_OUT")" == "end" ]]; then fx_ok; else fx_bad "alt id leaked across module_load"; fi

vs_bad_pair() {
    local label="$1" idline="$2" seamline="$3"
    mkdir -p "$FX_TMP/scratch/bad"
    {
        printf 'MODULE_ID=bad\n'
        printf '%s\n' "$idline"
        [[ -n "$seamline" ]] && printf '%s\n' "$seamline"
    } >"$FX_TMP/scratch/bad/module.sh"
    (
        set -euo pipefail
        export FS_NO_COLOR=1
        eval "$VSRC"
        module_validate "$FX_TMP/scratch/bad" rpm
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 1
}
vs_bad_pair "alt pair id-only rc" 'MODULE_FLATPAK_ALT_ID=com.example.App' ""
vs_bad_pair "alt pair seam-only rc" "" 'MODULE_FLATPAK_ALT_SEAM=FS_EXAMPLE'
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$VSRC"
    mkdir -p "$FX_TMP/scratch/badseam"
    printf 'MODULE_ID=badseam\nMODULE_FLATPAK_ALT_ID=com.example.App\nMODULE_FLATPAK_ALT_SEAM=not-an-env-name\n' \
        >"$FX_TMP/scratch/badseam/module.sh"
    module_validate "$FX_TMP/scratch/badseam" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "alt seam bad name rc" 1
fx_err 'invalid MODULE_FLATPAK_ALT_SEAM'
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$VSRC"
    mkdir -p "$FX_TMP/scratch/badid"
    printf 'MODULE_ID=badid\nMODULE_FLATPAK_ALT_ID=com.example.App extra\nMODULE_FLATPAK_ALT_SEAM=FS_EXAMPLE\n' \
        >"$FX_TMP/scratch/badid/module.sh"
    module_validate "$FX_TMP/scratch/badid" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "alt id with space rc" 1
fx_err 'invalid MODULE_FLATPAK_ALT_ID'

# --- 3. family lists + the P4.2 gate --------------------------------------
vs_map_cell() {
    local family="$1" want="$2" label="$3"
    (
        set -euo pipefail
        export FS_NO_COLOR=1
        eval "$VSRC"
        list_packages "$VSDIR" "$family"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    local got
    got="$(tr '\n' ' ' <"$FX_OUT")"
    got="${got% }"
    if [[ "$got" == "$want" ]]; then fx_ok; else fx_bad "$label (got [$got], want [$want])"; fi
}
vs_map_cell rpm "code" "vscode list_packages rpm"
vs_map_cell deb "code" "vscode list_packages deb"
vs_map_cell arch "" "vscode list_packages arch"
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$VSRC"
    module_validate "$VSDIR" arch
    printf 'arch-gate-ok\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode arch gate rc" 0
fx_out '^arch-gate-ok$'
mkdir -p "$FX_TMP/scratch/nogate/vscode"
cp "$VSDIR/module.sh" "$FX_TMP/scratch/nogate/vscode/module.sh"
cp "$VSDIR/packages.rpm.list" "$FX_TMP/scratch/nogate/vscode/packages.rpm.list"
cp "$VSDIR/packages.deb.list" "$FX_TMP/scratch/nogate/vscode/packages.deb.list"
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$VSRC"
    module_validate "$FX_TMP/scratch/nogate/vscode" arch
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode arch gate without arch list rc" 1
fx_err "no package list usable on family 'arch'"

# --- 4. dry-run per family -------------------------------------------------
vs_dry_cell() {
    local family="$1" backend="$2" label="$3" want_repo="$4" want_import="$5" want_refresh="$6" want_install="$7"
    : >"$OPS"
    rm -rf "$FX_TMP/repos" "$FX_TMP/sources"
    mkdir -p "$FX_TMP/repos" "$FX_TMP/sources"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/hdry"
        export FS_PKG_BACKEND="$backend" FS_DISTRO_FAMILY="$family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_OPS="$OPS" FS_REPOS_DIR="$FX_TMP/repos" FS_SOURCES_DIR="$FX_TMP/sources"
        export FS_VSCODE_KEYRING="$FX_TMP/keys/fedora-setup-vscode.gpg"
        export TMPDIR="$FX_TMP" FS_FAKE_FPR="$PIN"
        export PATH="$FX_TMP/fakebin:$PATH"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_VSCODE_FLATPAK 2>/dev/null || :
        "$SETUP" install --yes vscode
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out 'module: vscode (medium)'
    fx_out "$want_repo"
    fx_out "$want_import"
    fx_out "$want_refresh"
    fx_out "$want_install"
    fx_out_not '^# would run: flatpak '
    if grep -q 'repodata/repomd.xml.key' "$FX_OUT"; then fx_ok; else fx_bad "$label key url missing"; fi
    if grep -q 'packages.microsoft.com' "$FX_OUT"; then fx_ok; else fx_bad "$label repo url missing"; fi
    local r i
    r="$(grep -n 'fedora-setup-repo-vscode\.dry ' "$FX_OUT" | head -1 | cut -d: -f1)"
    i="$(grep -n 'install -y code' "$FX_OUT" | head -1 | cut -d: -f1)"
    if [[ -n "$r" && -n "$i" ]] && (( r < i )); then fx_ok; else fx_bad "$label repo add must precede the install (repo line $r, install line $i)"; fi
    fx_empty "$label dry executed nothing" "$OPS"
    if [[ -z "$(ls -A "$FX_TMP/repos")" && -z "$(ls -A "$FX_TMP/sources")" ]]; then fx_ok; else fx_bad "$label dry wrote a repo file"; fi
    if [[ -e "$FX_TMP/hdry/.local/state/fedora-setup" ]]; then fx_bad "$label dry created state dir"; else fx_ok; fi
}
vs_dry_cell rpm rpm "vscode dry rpm" \
    '^# would run: sudo -- install -m 0644 .*fedora-setup-repo-vscode\.dry .*/repos/vscode\.repo$' \
    '^# would run: sudo -- rpm --import .*fedora-setup-vscode-key\.dry$' \
    '^# would run: sudo -- dnf5 makecache$' \
    '^# would run: sudo -- dnf5 install -y code$'
vs_dry_cell deb deb "vscode dry deb" \
    '^# would run: sudo -- install -m 0644 .*fedora-setup-repo-vscode\.dry .*/sources/vscode\.list$' \
    '^# would run: sudo -- gpg --batch --yes --dearmor --output .*fedora-setup-vscode\.gpg .*fedora-setup-vscode-key\.dry$' \
    '^# would run: sudo -- apt-get update$' \
    '^# would run: sudo -- apt-get install -y code$'

# arch: no repository, no install, explicit warning, module still done
: >"$OPS"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/harch"
    export FS_PKG_BACKEND=arch FS_DISTRO_FAMILY=arch FS_DRY_RUN=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_REPOS_DIR="$FX_TMP/repos" FS_SOURCES_DIR="$FX_TMP/sources"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_VSCODE_FLATPAK 2>/dev/null || :
    "$SETUP" install --yes vscode
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode dry arch rc" 0
fx_err 'no official Arch package'
fx_out_not '^# would run:'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
fx_empty "vscode dry arch executed nothing" "$OPS"

# --- 5. the flatpak swap ---------------------------------------------------
: >"$OPS"
: >"$FAKEST"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/hswap"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1 FS_VSCODE_FLATPAK=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_FAKE_INSTALLED="$FAKEST" FS_FAKE_LOG="$FX_TMP/fake.log"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes vscode
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode flatpak swap dry rc" 0
fx_out '^# would run: flatpak install --user --noninteractive --assumeyes com\.visualstudio\.code$'
fx_out_not 'dnf5 install'
fx_out_not 'apt-get install'
fx_out_not 'vscode.repo'
fx_out_not 'vscode.list'
fx_out_not 'repodata/repomd.xml.key'
fx_out_not 'install -y code'
fx_empty "vscode flatpak swap touched nothing" "$OPS"

# The stale-metadata regression: `zz` sorts AFTER `vscode` in C order, so a
# PREREQ subshell that did not load its own module would answer
# `module_flatpak_alt` with `zz`'s (empty) alt pair and do the native repo
# work anyway -- both paths side by side. Selected through a two-module
# profile so the resolved order is vscode, zz.
: >"$OPS"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/hswap2"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1 FS_VSCODE_FLATPAK=1
    export FS_MODULES_DIR="$FX_TMP/M2" FS_PROFILES_DIR="$FX_TMP/P2"
    export FS_OPS="$OPS" FS_FAKE_INSTALLED="$FAKEST" FS_FAKE_LOG="$FX_TMP/fake.log"
    export FS_REPOS_DIR="$FX_TMP/repos" FS_SOURCES_DIR="$FX_TMP/sources"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --profile pair --yes
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode flatpak swap after a later module rc" 0
fx_out '^# would run: flatpak install --user --noninteractive --assumeyes com\.visualstudio\.code$'
fx_out_not 'repodata/repomd.xml.key'
fx_out_not 'rpm --import'
fx_out_not 'dnf5 install -y code'
fx_out_not 'install -m 0644'
fx_out_not 'dnf5 makecache'
fx_empty "vscode flatpak swap after a later module touched nothing" "$OPS"

# mirror cell: the same selection with the seam unset must still add the
# repository, so the cell above is not green because prerepo stopped running
: >"$OPS"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/hnative2"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$FX_TMP/M2" FS_PROFILES_DIR="$FX_TMP/P2"
    export FS_OPS="$OPS" FS_FAKE_INSTALLED="$FAKEST" FS_FAKE_LOG="$FX_TMP/fake.log"
    export FS_REPOS_DIR="$FX_TMP/repos" FS_SOURCES_DIR="$FX_TMP/sources"
    export FS_VSCODE_KEYRING="$FX_TMP/keys/fedora-setup-vscode.gpg"
    export TMPDIR="$FX_TMP" FS_FAKE_FPR="$PIN"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_VSCODE_FLATPAK 2>/dev/null || :
    "$SETUP" install --profile pair --yes
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode native path after a later module rc" 0
fx_out 'repodata/repomd.xml.key'
fx_out 'install -m 0644 .*fedora-setup-repo-vscode\.dry .*/repos/vscode\.repo$'
fx_out '^# would run: sudo -- dnf5 install -y code zzp$'
fx_empty "vscode native path after a later module executed nothing" "$OPS"

# --- 6. real mode against the stand-ins ------------------------------------
# vs_hook <label> <want-rc> <family> [KEY=VAL ...] -- sources the REAL libs
# and the REAL prerepo.sh in a subshell and calls prerepo() once, with the
# stand-in binaries first on PATH and every repo/sources/key path inside
# FX_TMP. FS_EUID=0 is a documented run.sh seam: run_sudo then
# runs the command directly instead of demanding sudo, so the real P3
# primitives really write their files.
vs_hook() {
    local label="$1" want="$2" family="$3"
    shift 3
    : >"$OPS"
    rm -rf "$FX_TMP/repos" "$FX_TMP/sources" "$FX_TMP/keys"
    mkdir -p "$FX_TMP/repos" "$FX_TMP/sources" "$FX_TMP/keys"
    (
        set -euo pipefail
        export FS_NO_COLOR=1 FS_DRY_RUN=0
        export FS_PKG_BACKEND="$family" FS_MODULE_FAMILY="$family" FS_EUID=0
        export FS_REPOS_DIR="$FX_TMP/repos" FS_SOURCES_DIR="$FX_TMP/sources"
        export FS_VSCODE_KEYRING="$FX_TMP/keys/fedora-setup-vscode.gpg"
        export FS_OPS="$OPS" TMPDIR="$FX_TMP"
        export FS_FAKE_FPR="$PIN"
        for kv in "$@"; do export "${kv?}"; done
        export PATH="${VS_BIN:-$FX_TMP/full}"
        eval "$VSRC"
        module_load "$VSDIR" strict
        source "$VSDIR/prerepo.sh"
        prerepo
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

# 6a. fingerprint mismatch: nothing is imported, nothing is written
vs_hook "vscode real rpm mismatch" 1 rpm FS_FAKE_FPR=0000000000000000000000000000000000000000
fx_err 'repository key fingerprint mismatch'
fx_err 'refusing to trust the key'
if [[ -s "$FX_TMP/repos/vscode.repo" ]]; then fx_bad "mismatch wrote a repo file"; else fx_ok; fi
if grep -q '^rpm --import' "$OPS"; then fx_bad "mismatch imported the key"; else fx_ok; fi

# A key that carries a signing SUBKEY must be judged on its PRIMARY
# fingerprint. gpg --with-colons emits pub, fpr, uid, sub, fpr, so a
# naive "last fpr wins" read pins the SUBKEY -- a strictly weaker trust
# anchor than the primary -- and the documented re-pin remedy would make
# a maintainer pin it for real.
vs_hook "vscode primary fpr wins over a subkey" 0 rpm FS_FAKE_GPG_SUBKEY=1
if grep -q '^rpm --import' "$OPS"; then fx_ok; else fx_bad "a key with a subkey was not imported"; fi
if [[ -s "$FX_TMP/repos/vscode.repo" ]]; then fx_ok; else fx_bad "a key with a subkey added no repository"; fi

# ... and the same key with a WRONG primary is still refused, even though
# its subkey fingerprint would have been accepted by the naive read
vs_hook "vscode wrong primary refused despite matching subkey" 1 rpm \
    FS_FAKE_GPG_SUBKEY=1 FS_FAKE_FPR=0000000000000000000000000000000000000009 \
    FS_FAKE_FPR_SUBKEY=BC528686B50D79E339D3721CEB3E94ADBE1229CF
fx_err 'fingerprint mismatch'
if grep -q '^rpm --import' "$OPS"; then fx_bad "a key whose SUBKEY matched the pin was imported"; else fx_ok; fi
if [[ -s "$FX_TMP/repos/vscode.repo" ]]; then fx_bad "a key whose SUBKEY matched the pin still added the repository"; else fx_ok; fi

# a key file whose FIRST key is the pinned one but which also carries a
# second key must be refused: the single-fingerprint check must not be
# satisfiable by a bundle
vs_hook "vscode real rpm key bundle" 1 rpm FS_FAKE_GPG_BUNDLE=1
fx_err 'expected exactly 1'
if grep -q '^rpm --import' "$OPS"; then fx_bad "a key bundle was imported"; else fx_ok; fi
if [[ -s "$FX_TMP/repos/vscode.repo" ]]; then fx_bad "a key bundle still added the repository"; else fx_ok; fi
vs_hook "vscode real deb key bundle" 1 deb FS_FAKE_GPG_BUNDLE=1
fx_err 'expected exactly 1'
if [[ -e "$FX_TMP/keys/fedora-setup-vscode.gpg" ]]; then fx_bad "a key bundle was dearmored into the keyring"; else fx_ok; fi

# 6b. matching fingerprint on rpm: import + repo file + refresh, no keyring
vs_hook "vscode real rpm match" 0 rpm
if grep -q '^rpm --import' "$OPS"; then fx_ok; else fx_bad "rpm key not imported"; fi
REPO="$FX_TMP/repos/vscode.repo"
if [[ -s "$REPO" ]]; then fx_ok; else fx_bad "rpm repo file missing"; fi
if grep -qx 'dnf5 makecache' "$OPS"; then fx_ok; else fx_bad "rpm metadata not refreshed"; fi
if grep -q '^rpm --import ' "$OPS"; then fx_ok; else fx_bad "rpm import op not recorded"; fi
if [[ -e "$FX_TMP/keys/fedora-setup-vscode.gpg" ]]; then fx_bad "rpm path wrote a deb keyring"; else fx_ok; fi
if grep -qx 'gpgcheck=1' "$REPO"; then fx_ok; else fx_bad "rpm repo gpgcheck!=1"; fi
if grep -qx 'baseurl=https://packages.microsoft.com/yumrepos/vscode/' "$REPO"; then fx_ok; else fx_bad "rpm repo baseurl wrong"; fi
if grep -q '^gpgkey=' "$REPO"; then fx_bad "rpm repo should rely on the imported key, not gpgkey="; else fx_ok; fi
if compgen -G "$FX_TMP/fedora-setup-vscode-key.*" >/dev/null; then fx_bad "temporary key file left behind"; else fx_ok; fi

# 6c. matching fingerprint on deb: keyring + signed-by sources entry
vs_hook "vscode real deb match" 0 deb
if [[ -s "$FX_TMP/keys/fedora-setup-vscode.gpg" ]]; then fx_ok; else fx_bad "deb keyring missing"; fi
if grep -q '^gpg --batch --yes --dearmor' "$OPS"; then fx_ok; else fx_bad "deb key not dearmored"; fi
if grep -qxF "deb [signed-by=$FX_TMP/keys/fedora-setup-vscode.gpg] https://packages.microsoft.com/repos/code stable main" \
    "$FX_TMP/sources/vscode.list"; then
    fx_ok
else
    fx_bad "deb sources entry wrong"
    cat "$FX_TMP/sources/vscode.list" >&2 || :
fi
if grep -qx 'apt-get update' "$OPS"; then fx_ok; else fx_bad "deb metadata not refreshed"; fi
if [[ -e "$FX_TMP/repos/vscode.repo" ]]; then fx_bad "deb path wrote an rpm repo file"; else fx_ok; fi

# 6d. re-run: --if-not-exists leaves the repo file byte-identical, and the
# fingerprint is still re-verified (the check is not part of the skip)
vs_hook "vscode real rpm pre-rerun" 0 rpm
cp "$REPO" "$FX_TMP/repo.first"
: >"$OPS"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=0
    export FS_PKG_BACKEND=rpm FS_MODULE_FAMILY=rpm FS_EUID=0
    export FS_REPOS_DIR="$FX_TMP/repos" FS_OPS="$OPS" TMPDIR="$FX_TMP"
    export PATH="$FX_TMP/fakebin:$PATH" FS_FAKE_FPR="$PIN"
    eval "$VSRC"
    module_load "$VSDIR" strict
    source "$VSDIR/prerepo.sh"
    prerepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode real rpm rerun rc" 0
if cmp -s "$REPO" "$FX_TMP/repo.first"; then fx_ok; else fx_bad "repo file changed on re-run"; fi
if grep -q 'repodata/repomd.xml.key' "$OPS"; then fx_ok; else fx_bad "re-run skipped the fingerprint verification"; fi
if grep -q '^install -m 0644 ' "$OPS"; then fx_bad "re-run rewrote the repo file"; else fx_ok; fi

# 6e. fail-closed inputs
vs_hook "vscode absent pin file" 1 rpm FS_VSCODE_KEY_FILE="$FX_TMP/scratch/absent.fp"
fx_err 'pinned fingerprint file missing or unreadable'
printf 'not-a-fingerprint\n' >"$FX_TMP/scratch/bad.fp"
vs_hook "vscode malformed pin" 1 rpm FS_VSCODE_KEY_FILE="$FX_TMP/scratch/bad.fp"
fx_err 'no 40-hex fingerprint'
vs_hook "vscode no gpg" 1 rpm VS_BIN="$FX_TMP/nogpg"
fx_err 'gpg not found on PATH'
vs_hook "vscode no curl" 1 rpm VS_BIN="$FX_TMP/nocurl"
fx_err 'curl not found on PATH'
# a dearmor that exits 0 but writes nothing must still fail: the hook does
# not trust the tool's rc, it checks the postcondition
vs_hook "vscode keyring not written" 1 deb FS_FAKE_GPG_NOOUT=1
fx_err 'vscode: keyring was not written'
if [[ -s "$FX_TMP/sources/vscode.list" ]]; then fx_bad "added a sources entry without a keyring"; else fx_ok; fi
# a failed fetch must stop the hook on the spot (run_cmd --stop): no key
# verification, no import, no repository
vs_hook "vscode fetch fails" 1 rpm FS_FAKE_CURL_RC=22
fx_err 'vscode: fetch repository key'
if grep -q '^rpm --import' "$OPS"; then fx_bad "a failed fetch still imported the key"; else fx_ok; fi
if [[ -s "$FX_TMP/repos/vscode.repo" ]]; then fx_bad "a failed fetch still added the repository"; else fx_ok; fi

# 6f. arch and flatpak are no-ops; a direct call without the seam refuses
vs_hook "vscode real arch" 0 arch
fx_err 'no official Arch package'
fx_empty "vscode real arch touched nothing" "$OPS"
vs_hook "vscode real flatpak no-op" 0 rpm FS_VSCODE_FLATPAK=1
fx_empty "vscode real flatpak touched nothing" "$OPS"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=0
    export FS_PKG_BACKEND=rpm FS_EUID=0
    export FS_OPS="$OPS" TMPDIR="$FX_TMP" PATH="$FX_TMP/full"
    eval "$VSRC"
    module_load "$VSDIR" strict
    source "$VSDIR/prerepo.sh"
    unset FS_MODULE_FAMILY FS_DISTRO_FAMILY
    prerepo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "vscode no family rc" 1
fx_err 'FS_MODULE_FAMILY is not set'

fx_summary
