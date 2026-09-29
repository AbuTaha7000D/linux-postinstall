#!/usr/bin/env bash
# tests/fixtures/mod_chrome.sh - P7.6 fixture for the `chrome` module.
# Drives the REAL repo modules/chrome/ through direct run()/verify() calls
# and through `./setup install`, with hermetic stand-ins for every external
# binary (wget/gzip/sha256sum/dnf5/apt-get/flatpak). No network, no
# package is ever installed, nothing outside FX_TMP + the real repo module
# is touched. Covers:
#   1. metadata + contract: exact MODULE_ID/RISK/DEFAULT/alt-pair, hooks
#      yes / prerepo no, the `setup list` row, and the P4.2 family gate on
#      all three families -- this module is HOOKS-ONLY and ships no list
#      file at all, so the gate must pass precisely because none exists;
#   2. arch mapping and the index URL table (deb/rpm x x86_64/aarch64),
#      plus unsupported-host refusal;
#   3. the deb index parser: the google-chrome-stable stanza is selected
#      out of five decoy stanzas (google-chrome-repo/-beta/-canary/
#      -unstable come first and carry their own digests, so a parser that
#      grabbed the first Filename/SHA256 in the file would be caught), and
#      a missing stanza / Filename / SHA256, an absolute path, a `..`
#      segment, an embedded space, a non-sha256 digest and a malformed file
#      all fail closed;
#   4. the rpm primary.xml.gz parser: same decoy structure, and the
#      resolved URL MUST carry the per-arch repo directory (the
#      <location href> is repo-relative, so a base without the arch yields
#      a 404 -- a real bug found while building this task and pinned here);
#   5. run() real mode: index fetch, digest verify, install through the
#      REAL pkg seam (mock backend records the call, rpm/deb backends
#      render `install -y <file>`), and every fail-closed branch --
#      flatpak alternative selected, arch no-op, unknown family,
#      unsupported arch, missing wget, missing sha256sum, missing gzip,
#      index fetch failure, unparseable index, digest mismatch (nothing
#      installed), bundle download failure, install failure -- each with the
#      staging directory proven to be removed afterwards;
#   6. dry-run: the exact rendered lines AND their order, the
#      RESOLVED-AT-RUN-TIME marker, no network, no staging dir, no install;
#   7. verify(): canonical google-chrome.desktop, the com.google.Chrome
#      compatibility name, a missing desktop file, the dry-run no-probe
#      rule, and the flatpak/arch no-op rules;
#   8. the FS_CHROME_FLATPAK=1 exclusivity through the real runner: the
#      flatpak namespace carries com.google.Chrome and the SYSTEM
#      namespace is empty, so native and flatpak never run side by side.
# Usage: bash tests/fixtures/mod_chrome.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
unset FS_DRY_RUN FS_YES FS_PROFILE FS_VERBOSE FS_DEBUG
unset FS_DISTRO_FILE FS_DISTRO_FAMILY FS_PKG_BACKEND FS_MODULE_FAMILY
unset FS_CHROME_FLATPAK FS_CHROME_ARCH FS_CHROME_DESKTOP_DIR
unset FS_MOCK_LOG FS_MOCK_INSTALLED FS_OPS FS_EUID FS_RUNNING_AS_ROOT
unset FS_SUDO_AVAILABLE FS_LOG_FILE
unset FS_FAKE_WGET_INDEX FS_FAKE_WGET_BUNDLE FS_FAKE_WGET_RC_INDEX FS_FAKE_WGET_RC_BUNDLE
unset CH_DEFAULT_INDEX CH_DEFAULT_BUNDLE CH_FAKE_INSTALLED CH_FAKE_INSTALL_RC
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/apps"

printf 'P7.6 chrome module\n'

SETUP="$ROOT/setup"
CHDIR="$ROOT/modules/chrome"
OPS="$FX_TMP/ops.log"
BUNDLE="$FX_TMP/fakebundle.deb"
printf 'FAKE CHROME BUNDLE PAYLOAD\n' >"$BUNDLE"
SUM="$(sha256sum -- "$BUNDLE")"
DIGEST="${SUM%% *}"
BADSUM="$(printf 'other\n' >"$FX_TMP/other"; sha256sum -- "$FX_TMP/other")"
BADSUM="${BADSUM%% *}"

# --- fixture vendor indexes ------------------------------------------------
# The deb index is shaped like the real one: five stanzas, the target NOT
# first, each decoy carrying a distinct (valid-looking) Filename+SHA256.
mk_deb_index() {
    local dest="$1" digest="$2" drop="${3:-}" arch="${4:-amd64}"
    {
        printf 'Package: google-chrome-repo\n'
        printf 'Version: 1.0\nArchitecture: amd64\n'
        printf 'Filename: pool/main/g/google-chrome-repo/google-chrome-repo_1.0_all.deb\n'
        printf 'SHA256: %s\n\n' "1111111111111111111111111111111111111111111111111111111111111111"
        printf 'Package: google-chrome-beta\n'
        printf 'Version: 155.0.8059.12-1\nArchitecture: amd64\n'
        printf 'Filename: pool/main/g/google-chrome-beta/google-chrome-beta_155.0.8059.12-1_amd64.deb\n'
        printf 'SHA256: %s\n\n' "2222222222222222222222222222222222222222222222222222222222222222"
        printf 'Package: google-chrome-canary\n'
        printf 'Version: 156.0.8078.0-1\nArchitecture: amd64\n'
        printf 'Filename: pool/main/g/google-chrome-canary/google-chrome-canary_156.0.8078.0-1_amd64.deb\n'
        printf 'SHA256: %s\n\n' "3333333333333333333333333333333333333333333333333333333333333333"
        printf 'Package: google-chrome-stable\n'
        printf 'Version: 154.0.8037.57-1\nArchitecture: %s\n' "$arch"
        if [[ "$drop" != filename ]]; then
            printf 'Filename: pool/main/g/google-chrome-stable/google-chrome-stable_154.0.8037.57-1_%s.deb\n' "$arch"
        fi
        if [[ "$drop" != sha ]]; then
            printf 'SHA256: %s\n' "$digest"
        fi
        printf 'Size: 27\n\n'
        printf 'Package: google-chrome-unstable\n'
        printf 'Version: 156.0.8072.0-1\nArchitecture: amd64\n'
        printf 'Filename: pool/main/g/google-chrome-unstable/google-chrome-unstable_156.0.8072.0-1_amd64.deb\n'
        printf 'SHA256: %s\n\n' "4444444444444444444444444444444444444444444444444444444444444444"
    } >"$dest"
}
mk_rpm_index() {
    local dest="$1" arch="$2" digest="$3" drop="${4:-}"
    local chk="      <checksum type=\"sha256\" pkgid=\"YES\">$digest</checksum>"
    [[ "$drop" == checksum ]] && chk=""
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<metadata packages="4">\n'
        printf '<package type="rpm">\n  <name>google-chrome-beta</name>\n  <arch>%s</arch>\n' "$arch"
        printf '  <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>\n'
        printf '  <location href="google-chrome-beta-155.0.8059.12-1.%s.rpm"/>\n</package>\n' "$arch"
        printf '<package type="rpm">\n  <name>google-chrome-canary</name>\n  <arch>%s</arch>\n' "$arch"
        printf '  <checksum type="sha256" pkgid="YES">bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</checksum>\n'
        printf '  <location href="google-chrome-canary-156.0.8078.0-1.%s.rpm"/>\n</package>\n' "$arch"
        if [[ "$drop" != nopkg ]]; then
            printf '<package type="rpm">\n  <name>google-chrome-stable</name>\n  <arch>%s</arch>\n' "$arch"
            printf '  <version epoch="0" ver="154.0.8037.57" rel="1"/>\n'
            printf '%s\n' "$chk"
            printf '  <location href="google-chrome-stable-154.0.8037.57-1.%s.rpm"/>\n</package>\n' "$arch"
        fi
        printf '<package type="rpm">\n  <name>google-chrome-unstable</name>\n  <arch>%s</arch>\n' "$arch"
        printf '  <checksum type="sha256" pkgid="YES">cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc</checksum>\n'
        printf '  <location href="google-chrome-unstable-156.0.8072.0-1.%s.rpm"/>\n</package>\n' "$arch"
        printf '</metadata>\n'
    } | gzip -c >"$dest"
}
DEB_OK="$FX_TMP/Packages"
RPM_OK="$FX_TMP/primary.xml.gz"
RPM_A64="$FX_TMP/primary.aarch64.xml.gz"
DEB_A64="$FX_TMP/Packages.arm64"
mk_deb_index "$DEB_OK" "$DIGEST"
mk_rpm_index "$RPM_OK" x86_64 "$DIGEST"
mk_rpm_index "$RPM_A64" aarch64 "$DIGEST"
mk_deb_index "$DEB_A64" "$DIGEST" "" arm64

# --- stand-in binaries -----------------------------------------------------
# wget is the only binary with real logic: it serves the index from
# FS_FAKE_WGET_INDEX and the bundle from FS_FAKE_WGET_BUNDLE, and each
# phase can be forced to fail or to serve nothing at all.
cat >"$FX_TMP/fakebin/wget" <<'EOF'
#!/usr/bin/env bash
printf 'wget %s\n' "$*" >>"${FS_OPS:?}"
out=""
url=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-O" ]]; then out="$a"; fi
    if [[ "$prev" == "-o" ]]; then out="$a"; fi
    case "$a" in http*://*) url="$a" ;; esac
    prev="$a"
done
if [[ "$url" == *"/repodata/"* || "$url" == *"/Packages" ]]; then
    [[ -n "${FS_FAKE_WGET_RC_INDEX:-}" ]] && exit "${FS_FAKE_WGET_RC_INDEX}"
    src="${FS_FAKE_WGET_INDEX:-$CH_DEFAULT_INDEX}"
    [[ -n "$src" ]] || exit 1
    cat -- "$src" >"$out" || exit 1
    exit 0
fi
[[ -n "${FS_FAKE_WGET_RC_BUNDLE:-}" ]] && exit "${FS_FAKE_WGET_RC_BUNDLE}"
src="${FS_FAKE_WGET_BUNDLE:-$CH_DEFAULT_BUNDLE}"
[[ -n "$src" ]] || exit 1
cat -- "$src" >"$out" || exit 1
exit 0
EOF
# The package-manager stand-ins are COUPLED to the query stand-ins: an
# `install` only records the package when it succeeds, and rpm -q /
# dpkg-query answer from that same file. That coupling is what makes the
# postcondition cell real -- a package manager that refuses the install
# leaves nothing behind for the query to find, exactly as on a real host.
# CH_FAKE_INSTALL_RC forces the install to fail.
for t in dnf5 dnf apt-get; do
    cat >"$FX_TMP/fakebin/$t" <<EOF
#!/usr/bin/env bash
printf '$t %s\n' "\$*" >>"\${FS_OPS:?}"
if [[ "\${1:-}" == "install" ]]; then
    [[ -n "\${CH_FAKE_INSTALL_RC:-}" ]] && exit "\${CH_FAKE_INSTALL_RC}"
    printf 'google-chrome-stable\n' >>"\${CH_FAKE_INSTALLED:?}"
fi
exit 0
EOF
done
printf '#!/usr/bin/env bash\nexit 0\n' >"$FX_TMP/fakebin/flatpak"
# Queries deliberately write nothing to FS_OPS: FS_OPS means "mutating
# vendor command", and a query must not look like one.
cat >"$FX_TMP/fakebin/rpm" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-q" ]]; then
    [[ -n "${2:-}" ]] || exit 1
    grep -qxF -- "$2" "${CH_FAKE_INSTALLED:-/nonexistent}" 2>/dev/null || exit 1
    exit 0
fi
exit 0
EOF
cat >"$FX_TMP/fakebin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
pkg=""
for a in "$@"; do
    case "$a" in -*) ;; *) pkg="$a" ;; esac
done
if [[ -n "$pkg" ]] && grep -qxF -- "$pkg" "${CH_FAKE_INSTALLED:-/nonexistent}" 2>/dev/null; then
    printf 'installed'
    exit 0
fi
exit 1
EOF

# A bin dir is a COMPLETE, hermetic PATH: every real executable reachable
# from the ambient PATH is symlinked in (so ./setup and the libs find all
# the coreutils they shell out to), then the fakes shadow the vendor
# binaries. A "missing tool" cell is then a genuine PATH gap -- the tool
# is simply not linked -- rather than a stub that pretends to be absent.
ch_mkbin() {
    local dir="$1"
    mkdir -p "$dir"
    local d f
    IFS=':' read -r -a CH_PATH_DIRS <<<"$PATH"
    for d in "${CH_PATH_DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            [[ -f "$f" && -x "$f" ]] || continue
            ln -sf "$f" "$dir/${f##*/}" 2>/dev/null || :
        done
    done
    for t in wget dnf5 dnf apt-get flatpak rpm dpkg-query; do
        ln -sf "$FX_TMP/fakebin/$t" "$dir/$t"
    done
}
ch_mkbin "$FX_TMP/bin_full"
ch_mkbin "$FX_TMP/bin_nowget"
rm -f "$FX_TMP/bin_nowget/wget"
ch_mkbin "$FX_TMP/bin_nosha"
rm -f "$FX_TMP/bin_nosha/sha256sum"
ch_mkbin "$FX_TMP/bin_nogzip"
rm -f "$FX_TMP/bin_nogzip/gzip"
chmod +x "$FX_TMP/fakebin"/* 2>/dev/null || :

CH_SRC='source "$ROOT/lib/io.sh"; source "$ROOT/lib/run.sh"; source "$ROOT/lib/sudo.sh"; source "$ROOT/lib/pkg.sh"; source "$ROOT/lib/planner.sh"; source "$ROOT/lib/state.sh"; source "$ROOT/lib/lists.sh"; source "$ROOT/lib/modules.sh"'
CH_FAKE_INSTALLED="$FX_TMP/installed"
: >"$CH_FAKE_INSTALLED"

# --- helpers ---------------------------------------------------------------
# ch_hook <label> <want-rc> <family> <bin> [VAR=VAL ...] : run() in a hook
# subshell shaped exactly like lib/runner.sh builds it.
ch_hook() {
    local label="$1" want="$2" family="$3" bin="$4" backend="$family"
    shift 4
    case "$family" in
        rpm | deb) backend="$family" ;;
        *) backend=mock ;;
    esac
    : >"$OPS"
    : >"$FX_TMP/mock.log"
    : >"$CH_FAKE_INSTALLED"
    if [[ -n "${CH_SEED_INSTALLED:-}" ]]; then
        printf 'google-chrome-stable\n' >>"$CH_FAKE_INSTALLED"
    fi
    (
        set -euo pipefail
        export FS_NO_COLOR=1 FS_DRY_RUN=0 FS_VERBOSE=0
        export FS_MODULE_FAMILY="$family" FS_PKG_BACKEND="$backend" FS_EUID=0
        export FS_MOCK_LOG="$FX_TMP/mock.log"
        export CH_FAKE_INSTALLED="$CH_FAKE_INSTALLED"
        export FS_OPS="$OPS" TMPDIR="$FX_TMP"
        export CH_DEFAULT_INDEX="$DEB_OK" CH_DEFAULT_BUNDLE="$BUNDLE"
        export PATH="$bin"
        local kv
        for kv in "$@"; do export "${kv?}"; done
        eval "$CH_SRC"
        module_load "$CHDIR" strict
        source "$CHDIR/hooks.sh"
        sudo_detect
        run
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}
ch_noinstall() {
    local what="$1"
    if grep -q 'install-local' "$FX_TMP/mock.log" 2>/dev/null; then
        fx_bad "$what: pkg_install_local was called anyway"
    elif grep -qxF 'google-chrome-stable' "$CH_FAKE_INSTALLED" 2>/dev/null; then
        fx_bad "$what: google-chrome-stable ended up installed anyway"
    else
        fx_ok
    fi
}
# Proves the install really took effect: the package is in the installed
# set (so the postcondition query could only have passed if the vendor
# install had succeeded) and the vendor command carried the verified file.
ch_installed() {
    local what="$1" ext="$2"
    if ! grep -qxF 'google-chrome-stable' "$CH_FAKE_INSTALLED" 2>/dev/null; then
        fx_bad "$what: google-chrome-stable is not installed, so the postcondition never held"
    elif ! grep -q "install -y .*google-chrome-stable\.$ext\$" "$OPS" 2>/dev/null; then
        fx_bad "$what: no vendor install command for the verified google-chrome-stable.$ext"
        sed 's/^/    /' "$OPS" >&2 2>/dev/null
    else
        fx_ok
    fi
}
ch_no_staging() {
    local what="$1"
    if compgen -G "$FX_TMP/fedora-setup-chrome.*" >/dev/null 2>&1; then
        fx_bad "$what: staging directory left behind"
    else
        fx_ok
    fi
}

# --- 1. metadata + contract pins ------------------------------------------
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    for fam in rpm deb arch; do module_validate "$CHDIR" "$fam"; done
    printf 'id=%s\nrisk=%s\ndefault=%s\naltid=%s\nseam=%s\ntitle=%s\n' \
        "$MODULE_ID" "$MODULE_RISK" "$MODULE_DEFAULT" \
        "$MODULE_FLATPAK_ALT_ID" "$MODULE_FLATPAK_ALT_SEAM" "$MODULE_TITLE"
    module_has_hooks "$CHDIR" && printf 'hooks=yes\n' || printf 'hooks=no\n'
    module_has_prerepo "$CHDIR" && printf 'prerepo=yes\n' || printf 'prerepo=no\n'
    printf 'listfiles=%s\n' "$(ls "$CHDIR" | tr '\n' ' ')"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome validate all families rc" 0
fx_out '^id=chrome$'
fx_out '^risk=medium$'
fx_out '^default=on$'
fx_out '^altid=com\.google\.Chrome$'
fx_out '^seam=FS_CHROME_FLATPAK$'
fx_out '^hooks=yes$'
fx_out '^prerepo=no$'
fx_out '^listfiles=hooks\.sh module\.sh $'
if grep -q 'list' <<<"$(ls "$CHDIR")"; then fx_bad "chrome ships a list file"; else fx_ok; fi

# A hooks-only module must satisfy the P4.2 family gate BECAUSE no list
# file exists; adding a native list file back would break the alt exclusivity
# guarantee, so the absence is itself a decision worth pinning.
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    for fam in rpm deb arch; do
        if module_validate "$CHDIR" "$fam" 2>/dev/null; then
            printf 'gate-%s=ok\n' "$fam"
        else
            printf 'gate-%s=FAIL\n' "$fam"
        fi
    done
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome family gate rc" 0
fx_out '^gate-rpm=ok$'
fx_out '^gate-deb=ok$'
fx_out '^gate-arch=ok$'

(
    set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^chrome[[:space:]]Google Chrome[[:space:]]medium[[:space:]]on[[:space:]]-$' "$FX_OUT"; then
    fx_ok
else
    fx_bad "setup list has no chrome row"
    sed 's/^/    /' "$FX_OUT" >&2
fi

# --- 2. arch mapping + index URL table -------------------------------------
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=0
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    for h in x86_64 aarch64; do
        FS_CHROME_ARCH="$h"
        export FS_CHROME_ARCH
        printf '%s -> host=%s deb=%s rpm=%s\n' "$h" "$(_chrome_host_arch)" \
            "$(_chrome_deb_arch "$(_chrome_host_arch)")" \
            "$(_chrome_rpm_arch "$(_chrome_host_arch)")"
    done
    printf 'deb-x86=%s\n' "$(_chrome_index_url deb amd64)"
    printf 'deb-a64=%s\n' "$(_chrome_index_url deb arm64)"
    printf 'rpm-x86=%s\n' "$(_chrome_index_url rpm x86_64)"
    printf 'rpm-a64=%s\n' "$(_chrome_index_url rpm aarch64)"
    for bad in riscv64 i686 ppc64le; do
        if FS_CHROME_ARCH="$bad" _chrome_host_arch >/dev/null 2>&1; then
            printf 'UNEXPECTED-OK %s\n' "$bad"
        else
            printf 'refused %s\n' "$bad"
        fi
    done
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "arch mapping rc" 0
fx_out '^x86_64 -> host=x86_64 deb=amd64 rpm=x86_64$'
fx_out '^aarch64 -> host=aarch64 deb=arm64 rpm=aarch64$'
fx_out '^deb-x86=https://dl\.google\.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages$'
fx_out '^deb-a64=https://dl\.google\.com/linux/chrome/deb/dists/stable/main/binary-arm64/Packages$'
fx_out '^rpm-x86=https://dl\.google\.com/linux/chrome/rpm/stable/x86_64/repodata/primary\.xml\.gz$'
fx_out '^rpm-a64=https://dl\.google\.com/linux/chrome/rpm/stable/aarch64/repodata/primary\.xml\.gz$'
fx_out '^refused riscv64$'
fx_out '^refused i686$'
fx_out '^refused ppc64le$'
fx_out_not 'UNEXPECTED-OK'

# uname -m is the real host arch when the seam is unset
(
    set -euo pipefail
    export FS_NO_COLOR=1
    unset FS_CHROME_ARCH
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    printf 'detected=%s\n' "$(_chrome_host_arch)"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "host arch detection rc" 0
fx_out "^detected=$(uname -m | sed 's/^amd64$/x86_64/;s/^arm64$/aarch64/')$"

# --- 3. deb index parser ---------------------------------------------------
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_deb "$DEB_OK"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "deb parse ok rc" 0
fx_out "^https://dl\.google\.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_154\.0\.8037\.57-1_amd64\.deb $DIGEST\$"
fx_out_not 'google-chrome-repo'
fx_out_not 'google-chrome-beta'
fx_out_not '1111111111'

ch_deb_bad() {
    local label="$1" want="$2" pat="$3"
    shift 3
    (
        set -euo pipefail
        export FS_NO_COLOR=1
        eval "$CH_SRC"
        source "$CHDIR/hooks.sh"
        _chrome_parse_deb "$1"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
    [[ -n "$pat" ]] && fx_err "$pat"
}
mk_deb_index "$FX_TMP/idx_nostanza" "$DIGEST"
printf 'Package: google-chrome-beta\nFilename: pool/b.deb\nSHA256: %s\n' "$DIGEST" >"$FX_TMP/idx_nostanza"
ch_deb_bad "deb parse no stanza" 1 'no google-chrome-stable stanza' "$FX_TMP/idx_nostanza"
mk_deb_index "$FX_TMP/idx_nosha" "$DIGEST" sha
ch_deb_bad "deb parse no SHA256" 1 'has no SHA256' "$FX_TMP/idx_nosha"
mk_deb_index "$FX_TMP/idx_nofn" "$DIGEST" filename
ch_deb_bad "deb parse no Filename" 1 'has no Filename' "$FX_TMP/idx_nofn"
mk_deb_index "$FX_TMP/idx_badsum" 'not-a-digest'
ch_deb_bad "deb parse bad digest" 1 'non-sha256 digest' "$FX_TMP/idx_badsum"
: >"$FX_TMP/idx_empty"
ch_deb_bad "deb parse empty file" 1 'no google-chrome-stable stanza' "$FX_TMP/idx_empty"

# A hostile index must not be able to steer the download off the vendor
# host or up the tree: the resolved path is validated before use.
for variant in abs dotdot space dot; do
    case "$variant" in
        abs) f="/etc/passwd" ;;
        dotdot) f="../../../../etc/passwd" ;;
        space) f="pool/main/g/g/x y.deb" ;;
        dot) f="./pool/x.deb" ;;
    esac
    {
        printf 'Package: google-chrome-repo\nFilename: pool/repo.deb\nSHA256: %s\n\n' "$DIGEST"
        printf 'Package: google-chrome-stable\nFilename: %s\nSHA256: %s\n' "$f" "$DIGEST"
    } >"$FX_TMP/idx_hostile"
    ch_deb_bad "deb parse hostile path ($variant)" 1 'refusing unsafe Filename' "$FX_TMP/idx_hostile"
done

# --- 4. rpm index parser ---------------------------------------------------
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_rpm "$RPM_OK" x86_64
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm parse ok rc" 0
# The arch directory MUST be in the URL: <location href> is repo-relative,
# so .../rpm/stable/<file>.rpm is a 404. Pinned because it was a real bug.
fx_out "^https://dl\.google\.com/linux/chrome/rpm/stable/x86_64/google-chrome-stable-154\.0\.8037\.57-1\.x86_64\.rpm $DIGEST\$"
fx_out_not '^https://dl\.google\.com/linux/chrome/rpm/stable/google-chrome-stable'
fx_out_not 'aaaaaaaaaaaaaaaa'

# a different arch must yield a different, arch-correct URL
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_rpm "$RPM_A64" aarch64
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm parse aarch64 rc" 0
fx_out '^https://dl\.google\.com/linux/chrome/rpm/stable/aarch64/google-chrome-stable-154\.0\.8037\.57-1\.aarch64\.rpm '

ch_rpm_bad() {
    local label="$1" want="$2" pat="$3" file="$4"
    (
        set -euo pipefail
        export FS_NO_COLOR=1
        eval "$CH_SRC"
        source "$CHDIR/hooks.sh"
        _chrome_parse_rpm "$file" x86_64
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
    [[ -n "$pat" ]] && fx_err "$pat"
}
mk_rpm_index "$FX_TMP/rpm_nopkg" x86_64 "$DIGEST" nopkg
ch_rpm_bad "rpm parse no stable package" 1 'no google-chrome-stable location' "$FX_TMP/rpm_nopkg"
mk_rpm_index "$FX_TMP/rpm_nochk" x86_64 "$DIGEST" checksum
ch_rpm_bad "rpm parse no checksum" 1 'no sha256 checksum' "$FX_TMP/rpm_nochk"
mk_rpm_index "$FX_TMP/rpm_bad" x86_64 'not-a-digest'
ch_rpm_bad "rpm parse bad checksum" 1 'non-sha256 checksum' "$FX_TMP/rpm_bad"
# A hex string of the WRONG LENGTH is a different rejection from a non-hex
# one. Both existing bad-digest cells use 'not-a-digest', which fails on
# charset alone, so the {64} quantifier itself was never load-bearing.
mk_rpm_index "$FX_TMP/rpm_shortsum" x86_64 'deadbeef'
ch_rpm_bad "rpm parse short digest" 1 'non-sha256 checksum' "$FX_TMP/rpm_shortsum"
mk_deb_index "$FX_TMP/idx_shortsum" 'deadbeef'
ch_deb_bad "deb parse short digest" 1 'non-sha256 digest' "$FX_TMP/idx_shortsum"

# N5: the same hostile-path rule the deb parser applies must also hold for
# the rpm <location href>, which is an independent extraction path.
for variant in abs dotdot space dot; do
    case "$variant" in
        abs) h="/etc/shadow" ;;
        dotdot) h="../../../../etc/shadow" ;;
        space) h="google chrome stable.rpm" ;;
        dot) h="./google-chrome-stable.rpm" ;;
    esac
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<metadata packages="1">\n'
        printf '<package type="rpm">\n  <name>google-chrome-stable</name>\n  <arch>x86_64</arch>\n'
        printf '  <checksum type="sha256" pkgid="YES">%s</checksum>\n' "$DIGEST"
        printf '  <location href="%s"/>\n</package>\n</metadata>\n' "$h"
    } | gzip -c >"$FX_TMP/rpm_hostile"
    ch_rpm_bad "rpm parse hostile href ($variant)" 1 'refusing unsafe location' "$FX_TMP/rpm_hostile"
done

# N7: an index whose LAST meaningful line is unterminated. `while read`
# returns non-zero on a final unterminated line and discards it, so this is
# only survivable because of the `|| [[ -n "$line" ]]` guard. Ending the
# stream on a structural line instead would pass either way, so the line the
# parser actually needs has to be the unterminated one.
{
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<metadata packages="1">\n'
    printf '<package type="rpm">\n  <name>google-chrome-stable</name>\n  <arch>x86_64</arch>\n'
    printf '  <checksum type="sha256" pkgid="YES">%s</checksum>\n' "$DIGEST"
    printf '  <location href="google-chrome-stable-154.0.8037.57-1.x86_64.rpm"/>'
} | gzip -c >"$FX_TMP/rpm_nonl"
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_rpm "$FX_TMP/rpm_nonl" x86_64
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm parse unterminated location line rc" 0
fx_out "^https://dl\.google\.com/linux/chrome/rpm/stable/x86_64/google-chrome-stable-154\.0\.8037\.57-1\.x86_64\.rpm $DIGEST\$"
{
    printf 'Package: google-chrome-repo\nFilename: pool/repo.deb\nSHA256: %s\n\n' "$DIGEST"
    printf 'Package: google-chrome-stable\nFilename: pool/main/g/google-chrome-stable/google-chrome-stable_154.0.8037.57-1_amd64.deb\nSHA256: %s' "$DIGEST"
} >"$FX_TMP/idx_nonl"
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_deb "$FX_TMP/idx_nonl"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "deb parse unterminated digest line rc" 0
fx_out "^https://dl\.google\.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_154\.0\.8037\.57-1_amd64\.deb $DIGEST\$"

# N11: pin SUBSTRING semantics, not indentation. The main index indents
# every element two spaces, so a full-string compare written against that
# indentation would still pass. Here the target <name> is indented four
# spaces and the decoy two, so no full-string pattern can match and only a
# substring search can find the stable stanza.
{
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<metadata packages="2">\n'
    printf '<package type="rpm">\n  <name>google-chrome-beta</name>\n  <arch>x86_64</arch>\n'
    printf '  <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>\n'
    printf '  <location href="google-chrome-beta-155.0.8059.12-1.x86_64.rpm"/>\n</package>\n'
    printf '<package type="rpm">\n    <name>google-chrome-stable</name>\n    <arch>x86_64</arch>\n'
    printf '    <checksum type="sha256" pkgid="YES">%s</checksum>\n' "$DIGEST"
    printf '    <location href="google-chrome-stable-154.0.8037.57-1.x86_64.rpm"/>\n</package>\n'
    printf '</metadata>\n'
} | gzip -c >"$FX_TMP/rpm_deepindent"
(
    set -euo pipefail
    export FS_NO_COLOR=1
    eval "$CH_SRC"
    source "$CHDIR/hooks.sh"
    _chrome_parse_rpm "$FX_TMP/rpm_deepindent" x86_64
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "rpm parse substring semantics rc" 0
fx_out "^https://dl\.google\.com/linux/chrome/rpm/stable/x86_64/google-chrome-stable-154\.0\.8037\.57-1\.x86_64\.rpm $DIGEST\$"
fx_out_not 'google-chrome-beta'
printf 'not gzip at all\n' >"$FX_TMP/rpm_notgz"
ch_rpm_bad "rpm parse not gzip" 1 'no google-chrome-stable location' "$FX_TMP/rpm_notgz"
: >"$FX_TMP/rpm_empty"
ch_rpm_bad "rpm parse empty" 1 'no google-chrome-stable location' "$FX_TMP/rpm_empty"

# --- 5. run() real mode ----------------------------------------------------
: >"$FX_TMP/mock.log"

ch_hook "chrome real deb ok" 0 deb "$FX_TMP/bin_full"
ch_installed "chrome real deb ok" deb
fx_err_not 'digest mismatch'
ch_no_staging "chrome real deb ok"
if grep -q '^wget .*binary-amd64/Packages' "$OPS"; then fx_ok; else fx_bad "index was not fetched from the vendor index URL"; fi
if grep -q 'wget .*google-chrome-stable_154\.0\.8037\.57-1_amd64\.deb' "$OPS"; then fx_ok; else fx_bad "bundle was not fetched from the resolved pool URL"; fi
# ordering: index before bundle before install
if [[ "$(grep -c . "$OPS")" -ge 2 ]] && \
    [[ "$(grep -n 'Packages' "$OPS" | head -1 | cut -d: -f1)" -lt "$(grep -n 'google-chrome-stable_' "$OPS" | head -1 | cut -d: -f1)" ]]; then
    fx_ok
else
    fx_bad "index was not fetched before the bundle"
fi

ch_hook "chrome real rpm ok" 0 rpm "$FX_TMP/bin_full" CH_DEFAULT_INDEX="$RPM_OK"
ch_installed "chrome real rpm ok" rpm
if grep -q 'wget .*repodata/primary\.xml\.gz' "$OPS"; then fx_ok; else fx_bad "rpm index was not fetched"; fi
if grep -q 'wget .*rpm/stable/x86_64/google-chrome-stable-154' "$OPS"; then fx_ok; else fx_bad "rpm bundle URL lost the arch directory"; fi
ch_no_staging "chrome real rpm ok"

# the REAL rpm/deb seams must accept the staging file, not just the mock
: >"$OPS"
: >"$CH_FAKE_INSTALLED"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=0 FS_VERBOSE=0
    export FS_MODULE_FAMILY=rpm FS_PKG_BACKEND=rpm FS_EUID=0
    export FS_OPS="$OPS" TMPDIR="$FX_TMP" PATH="$FX_TMP/bin_full"
    export CH_DEFAULT_INDEX="$RPM_OK" CH_DEFAULT_BUNDLE="$BUNDLE"
    export CH_FAKE_INSTALLED="$CH_FAKE_INSTALLED"
    eval "$CH_SRC"
    module_load "$CHDIR" strict
    source "$CHDIR/hooks.sh"
    sudo_detect
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome real rpm backend rc" 0
if grep -qE '^dnf5? install -y .*google-chrome-stable\.rpm' "$OPS"; then fx_ok; else fx_bad "rpm backend did not install the local bundle"; fi
ch_no_staging "chrome real rpm backend"

# An aarch64 host must reach the arm64/aarch64 vendor paths end to end. These
# cells are what stop an "assume x86_64" regression from shipping: the arch
# helpers can be right while run() still hardcodes an architecture.
ch_hook "chrome real deb aarch64" 0 deb "$FX_TMP/bin_full" \
    FS_CHROME_ARCH=aarch64 FS_FAKE_WGET_INDEX="$DEB_A64"
ch_installed "chrome real deb aarch64" deb
if grep -q '^wget .*binary-arm64/Packages' "$OPS"; then fx_ok; else fx_bad "deb arm64 host did not fetch the arm64 index"; fi
if grep -q 'wget .*google-chrome-stable_154\.0\.8037\.57-1_arm64\.deb' "$OPS"; then fx_ok; else fx_bad "deb arm64 host did not download the arm64 bundle"; fi
fx_out_not 'binary-amd64'
ch_no_staging "chrome real deb aarch64"

ch_hook "chrome real rpm aarch64" 0 rpm "$FX_TMP/bin_full" \
    FS_CHROME_ARCH=aarch64 FS_FAKE_WGET_INDEX="$RPM_A64"
ch_installed "chrome real rpm aarch64" rpm
if grep -q '^wget .*rpm/stable/aarch64/repodata/primary\.xml\.gz' "$OPS"; then fx_ok; else fx_bad "rpm aarch64 host did not fetch the aarch64 index"; fi
if grep -q 'wget .*rpm/stable/aarch64/google-chrome-stable-154.*aarch64\.rpm' "$OPS"; then fx_ok; else fx_bad "rpm aarch64 host did not download the aarch64 bundle"; fi
fx_out_not 'rpm/stable/x86_64'
ch_no_staging "chrome real rpm aarch64"

# a seam that claims aarch64 while the host is x86_64 must be honoured --
# the seam is a test override, not a hint.
ch_hook "chrome aarch64 seam on an x86_64 host" 0 rpm "$FX_TMP/bin_full" \
    FS_CHROME_ARCH=arm64 FS_FAKE_WGET_INDEX="$RPM_A64"
if grep -q '^wget .*rpm/stable/aarch64/repodata' "$OPS"; then fx_ok; else fx_bad "FS_CHROME_ARCH=arm64 was not honoured"; fi

ch_hook "chrome flatpak alt is a no-op" 0 rpm "$FX_TMP/bin_full" FS_CHROME_FLATPAK=1
ch_noinstall "chrome flatpak alt"
ch_no_staging "chrome flatpak alt"
if [[ ! -s "$OPS" ]]; then fx_ok; else fx_bad "the flatpak alternative still touched the network"; fi
fx_out_not 'wget'

ch_hook "chrome alt truthy variants" 0 deb "$FX_TMP/bin_full" FS_CHROME_FLATPAK=on
ch_noinstall "chrome alt on"
ch_hook "chrome arch is a no-op" 0 arch "$FX_TMP/bin_full"
ch_noinstall "chrome arch"
fx_err 'no native Arch package'
if [[ ! -s "$OPS" ]]; then fx_ok; else fx_bad "arch path touched the network"; fi

ch_hook "chrome unknown family" 1 bsd "$FX_TMP/bin_full"
fx_err "no native bundle path for family 'bsd'"
ch_noinstall "chrome unknown family"
ch_no_staging "chrome unknown family"

ch_hook "chrome unsupported arch" 1 deb "$FX_TMP/bin_full" FS_CHROME_ARCH=riscv64
fx_err 'unsupported host architecture'
ch_noinstall "chrome unsupported arch"
ch_no_staging "chrome unsupported arch"

ch_hook "chrome missing wget" 1 deb "$FX_TMP/bin_nowget"
fx_err 'wget not found'
ch_noinstall "chrome missing wget"
ch_no_staging "chrome missing wget"

ch_hook "chrome missing sha256sum" 1 deb "$FX_TMP/bin_nosha"
fx_err 'sha256sum not found'
ch_noinstall "chrome missing sha256sum"
ch_no_staging "chrome missing sha256sum"

ch_hook "chrome missing gzip (rpm)" 1 rpm "$FX_TMP/bin_nogzip" CH_DEFAULT_INDEX="$RPM_OK"
fx_err 'gzip is required'
ch_noinstall "chrome missing gzip"
ch_no_staging "chrome missing gzip"

ch_hook "chrome index fetch fails" 1 deb "$FX_TMP/bin_full" FS_FAKE_WGET_RC_INDEX=1
fx_err 'command failed.*fetch chrome metadata'
ch_noinstall "chrome index fetch fails"
ch_no_staging "chrome index fetch fails"

ch_hook "chrome index empty" 1 deb "$FX_TMP/bin_full" FS_FAKE_WGET_INDEX="$FX_TMP/idx_empty"
fx_err 'no google-chrome-stable stanza'
ch_noinstall "chrome index empty"
ch_no_staging "chrome index empty"

# A bundle whose bytes do not match the index digest is the case that
# matters most: the file must never reach the package manager.
ch_hook "chrome digest mismatch" 1 deb "$FX_TMP/bin_full" FS_FAKE_WGET_BUNDLE="$FX_TMP/other"
fx_err 'digest mismatch'
fx_err 'refusing to install'
ch_noinstall "chrome digest mismatch"
ch_no_staging "chrome digest mismatch"

ch_hook "chrome bundle download fails" 1 deb "$FX_TMP/bin_full" FS_FAKE_WGET_RC_BUNDLE=1
fx_err 'command failed.*download chrome bundle'
ch_noinstall "chrome bundle download fails"
ch_no_staging "chrome bundle download fails"

# B1: the P3 local-install seam cannot report failure (rpm/deb call
# run_sudo with no --stop, so run_cmd returns 0), so the module gates on
# the postcondition instead. This is the cell that would have caught it: a
# package manager that REFUSES the install, driven through the real runner.
# The assertions that matter: rc1, the module reported failed, and NO
# registry mark (a mark would make every later run skip chrome forever).
: >"$OPS"
: >"$CH_FAKE_INSTALLED"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=0 FS_YES=1 FS_EUID=0
    export FS_HOME="$FX_TMP/state-fail" FS_DISTRO_FAMILY=deb FS_PKG_BACKEND=deb
    export FS_MODULE_FAMILY=deb FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export CH_DEFAULT_INDEX="$DEB_OK" CH_DEFAULT_BUNDLE="$BUNDLE"
    export CH_FAKE_INSTALLED="$CH_FAKE_INSTALLED" CH_FAKE_INSTALL_RC=1
    export FS_OPS="$OPS" TMPDIR="$FX_TMP" PATH="$FX_TMP/bin_full"
    : >"$FX_TMP/fail.log"
    export FS_LOG_FILE="$FX_TMP/fail.log"
    unset FS_PROFILE FS_CHROME_FLATPAK 2>/dev/null || :
    "$SETUP" install --yes chrome
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install --yes chrome (install refused) rc" 1
fx_err 'module failed: chrome'
fx_err 'is still not installed'
if grep -qE '^apt-get install -y .*google-chrome-stable\.deb$' "$OPS"; then fx_ok; else fx_bad "the refused install never reached apt-get"; fi
ch_noinstall "install refused"
ch_no_staging "install refused"
# The state tree must EXIST (state_init ran) yet carry no chrome mark: an
# empty registry is the proof the module did not latch itself as done.
CH_FAIL_STATE="$FX_TMP/state-fail/.local/state/fedora-setup/modules"
if [[ -d "$CH_FAIL_STATE" ]]; then
    if [[ -f "$CH_FAIL_STATE/chrome" ]]; then
        fx_bad "chrome was marked done after a failed install"
    else
        fx_ok
    fi
else
    fx_bad "no state tree at all, so the registry check would pass vacuously"
fi
# the error must be the postcondition message, not a bare rc passthrough
fx_err_not 'install-local.*rc'

# What the postcondition actually asserts, stated honestly: "is it
# installed", not "did my command succeed". A host that ALREADY has Chrome
# satisfies it even when this run's install failed -- which is the intended
# reading (the user does have the browser), and the one case a
# postcondition cannot distinguish. Pinned so nobody later "strengthens" it
# into a claim it cannot deliver.
CH_SEED_INSTALLED=1
ch_hook "chrome install refused but already installed" 0 deb "$FX_TMP/bin_full" \
    CH_FAKE_INSTALL_RC=1
unset CH_SEED_INSTALLED
fx_err_not 'is still not installed'
if grep -qE '^apt-get install -y .*google-chrome-stable\.deb' "$OPS"; then fx_ok; else fx_bad "a pre-existing install skipped the install attempt"; fi

# --- 6. dry-run ------------------------------------------------------------
: >"$OPS"
# ch_noinstall below reads the installed set, so it must start from a clean
# one: the preceding cell deliberately left a seeded package behind.
: >"$CH_FAKE_INSTALLED"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=1 FS_VERBOSE=0
    export FS_MODULE_FAMILY=deb FS_PKG_BACKEND=mock FS_EUID=0
    export FS_MOCK_LOG="$FX_TMP/mock.log" FS_OPS="$OPS" TMPDIR="$FX_TMP"
    export PATH="$FX_TMP/bin_full"
    eval "$CH_SRC"
    module_load "$CHDIR" strict
    source "$CHDIR/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome dry-run rc" 0
fx_out '^# would run: wget -q --timeout=300 --tries=2 -O [^ ]*/index https://dl\.google\.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages$'
fx_out '^# would run: wget -q --timeout=300 --tries=2 -O [^ ]*/google-chrome-stable\.deb RESOLVED-AT-RUN-TIME$'
# the rendered plan must be ordered: index, then bundle
if [[ "$(grep -n 'index https' "$FX_OUT" | head -1 | cut -d: -f1)" -lt \
      "$(grep -n 'RESOLVED-AT-RUN-TIME' "$FX_OUT" | head -1 | cut -d: -f1)" ]]; then
    fx_ok
else
    fx_bad "dry-run rendered the bundle fetch before the index fetch"
fi
fx_out 'pkg_install_local'
if [[ ! -s "$OPS" ]]; then fx_ok; else fx_bad "dry-run executed a command"; fi
if compgen -G "$FX_TMP/fedora-setup-chrome.*" >/dev/null 2>&1; then
    fx_bad "dry-run created a staging directory"
else
    fx_ok
fi
ch_noinstall "dry-run"

# dry-run on rpm renders the rpm index URL and a .rpm bundle
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=1
    export FS_MODULE_FAMILY=rpm FS_PKG_BACKEND=mock FS_EUID=0
    export FS_MOCK_LOG="$FX_TMP/mock.log" FS_OPS="$OPS" TMPDIR="$FX_TMP"
    export PATH="$FX_TMP/bin_full"
    eval "$CH_SRC"
    module_load "$CHDIR" strict
    source "$CHDIR/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome dry-run rpm rc" 0
fx_out '^# would run: wget -q --timeout=300 --tries=2 -O [^ ]*/index https://dl\.google\.com/linux/chrome/rpm/stable/x86_64/repodata/primary\.xml\.gz$'
fx_out '^# would run: wget -q --timeout=300 --tries=2 -O [^ ]*/google-chrome-stable\.rpm RESOLVED-AT-RUN-TIME$'

# The same dry run on a REAL backend. The mock backend makes dry-run
# harmless by accident (mock_install_local only renders), so only a real
# backend can show that dry-run does not reach the seam at all -- which is
# the whole point of the documented limitation, because the real seam opens
# with a file-existence test a zero-write dry run can never satisfy.
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=1 FS_EUID=0
    export FS_MODULE_FAMILY=deb FS_PKG_BACKEND=deb
    export FS_OPS="$OPS" TMPDIR="$FX_TMP" PATH="$FX_TMP/bin_full"
    : >"$OPS"
    eval "$CH_SRC"
    module_load "$CHDIR" strict
    source "$CHDIR/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "chrome dry-run on the real deb backend rc" 0
fx_out 'RESOLVED-AT-RUN-TIME'
fx_out 'pkg_install_local'
fx_out_not 'apt-get install'
if [[ ! -s "$OPS" ]]; then fx_ok; else fx_bad "dry-run on a real backend executed a command"; sed 's/^/    /' "$OPS" >&2; fi
fx_err_not 'local package file not found'

# --- 7. verify() -----------------------------------------------------------
ch_verify() {
    local label="$1" want="$2" family="$3"
    shift 3
    (
        set -euo pipefail
        export FS_NO_COLOR=1 FS_DRY_RUN=0
        export FS_MODULE_FAMILY="$family" FS_PKG_BACKEND=mock FS_EUID=0
        export FS_OPS="$OPS" TMPDIR="$FX_TMP" PATH="$FX_TMP/bin_full"
        export FS_CHROME_DESKTOP_DIR="$FX_TMP/apps"
        local kv
        for kv in "$@"; do export "${kv?}"; done
        eval "$CH_SRC"
        module_load "$CHDIR" strict
        source "$CHDIR/hooks.sh"
        verify
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}
rm -f "$FX_TMP/apps/"*
ch_verify "verify missing desktop file" 1 deb
fx_err 'verify FAILED'
: >"$FX_TMP/apps/google-chrome.desktop"
ch_verify "verify finds google-chrome.desktop" 0 deb
fx_out 'verify ok.*google-chrome\.desktop'
rm -f "$FX_TMP/apps/google-chrome.desktop"
: >"$FX_TMP/apps/com.google.Chrome.desktop"
ch_verify "verify finds compatibility name" 0 deb
fx_out 'verify ok.*com\.google\.Chrome\.desktop'
rm -f "$FX_TMP/apps/com.google.Chrome.desktop"
ch_verify "verify flatpak alt no-op" 0 deb FS_CHROME_FLATPAK=1
fx_out 'desktop-entry check covers the native bundle only'
ch_verify "verify arch no-op" 0 arch
fx_out 'nothing to verify'
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=1
    export FS_MODULE_FAMILY=deb FS_PKG_BACKEND=mock FS_EUID=0
    export FS_CHROME_DESKTOP_DIR="$FX_TMP/apps" PATH="$FX_TMP/bin_full"
    export FS_OPS="$OPS"
    : >"$OPS"
    eval "$CH_SRC"
    module_load "$CHDIR" strict
    source "$CHDIR/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry-run rc" 0
fx_out 'verify is read-only'
fx_out_not 'verify FAILED'
if [[ ! -s "$OPS" ]]; then fx_ok; else fx_bad "verify probed the system in dry-run"; fi

# --- 8. flatpak exclusivity through the real runner ------------------------
for family in rpm deb arch; do
    : >"$OPS"
    (
        set -euo pipefail
        export FS_NO_COLOR=1 FS_DRY_RUN=1 FS_YES=1
        export FS_HOME="$FX_TMP/state" FS_DISTRO_FAMILY="$family"
        export FS_PKG_BACKEND="$family" FS_CHROME_FLATPAK=1
        export FS_MODULE_FAMILY="$family"
        export PATH="$FX_TMP/bin_full:$PATH"
        unset FS_PROFILE 2>/dev/null || :
        "$SETUP" install --yes chrome
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "install --yes chrome (alt, $family) rc" 0
    fx_out '^# would run: flatpak install --user --noninteractive --assumeyes com\.google\.Chrome$'
    fx_out_not 'dnf5 install'
    fx_out_not 'dnf install'
    fx_out_not 'apt-get install'
    fx_out_not 'install -y'
    fx_out_not 'wget'
    fx_empty "alt swap ($family) touched nothing" "$OPS"
done

# native path through the runner: the SYSTEM namespace carries no package
# and the flatpak namespace carries nothing, so the bundle is reached only
# through the hook.
: >"$FX_TMP/mock.log"
(
    set -euo pipefail
    export FS_NO_COLOR=1 FS_DRY_RUN=1 FS_YES=1
    export FS_HOME="$FX_TMP/state" FS_DISTRO_FAMILY=deb
    export FS_PKG_BACKEND=mock FS_MOCK_LOG="$FX_TMP/mock.log"
    export FS_CHROME_ARCH=x86_64
    export PATH="$FX_TMP/bin_full:$PATH"
    unset FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes chrome
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "install --yes chrome (native) rc" 0
if [[ ! -s "$FX_TMP/mock.log" ]]; then fx_ok; else fx_bad "the native run reached a package backend in dry-run"; fi
fx_out_not 'flatpak install'
fx_out 'wget .*binary-amd64/Packages'
fx_out 'wget .*RESOLVED-AT-RUN-TIME'
fx_out_not 'com\.google\.Chrome'

fx_summary
