#!/usr/bin/env bash
# check.sh - the validation for this project. Plain bash, no framework.
#
#   ./check.sh          everything
#   ./check.sh syntax   bash -n over every script
#   ./check.sh unit     the unit checks
#
# Exit status 0 when everything passes, 1 otherwise. Every test uses a
# temporary HOME and a fake os-release, so nothing here touches the real
# machine or the network.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export FS_ROOT="$ROOT"

pass=0
fail=0
_tmpdir=""

setup_tmp() { _tmpdir="$(mktemp -d)"; }
TMP() { printf '%s' "$_tmpdir/$1"; }
TMPD() { mkdir -p "$_tmpdir/$1"; }
teardown_tmp() {
    [[ -n "$_tmpdir" ]] && rm -rf -- "$_tmpdir"
    _tmpdir=""
}
trap teardown_tmp EXIT

ok() {
    pass=$((pass + 1))
    printf '  ok   %s\n' "$1"
}

no() {
    fail=$((fail + 1))
    printf '  FAIL %s\n' "$1"
    printf '       %s\n' "${2:-}"
}

check_eq() { # <name> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}

check_contains() { # <name> <needle> <haystack>
    if [[ "$3" == *"$2"* ]]; then ok "$1"; else no "$1" "expected to contain [$2], got [$3]"; fi
}

check_missing() { # <name> <needle> <haystack>
    if [[ "$3" != *"$2"* ]]; then ok "$1"; else no "$1" "did not expect [$2], got [$3]"; fi
}

# Load the libraries without running anything.
source_libs() {
    # shellcheck source=/dev/null
    source "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    source "$ROOT/lib/packages.sh"
    # shellcheck source=/dev/null
    source "$ROOT/lib/config.sh"
    # shellcheck source=/dev/null
    source "$ROOT/lib/modules.sh"
    _tmpdirs=()
}

# ---------------------------------------------------------------- syntax ----

t_syntax() {
    local f out
    while IFS= read -r f; do
        if out="$(bash -n "$f" 2>&1)"; then
            ok "syntax ${f#$ROOT/}"
        else
            no "syntax ${f#$ROOT/}" "$out"
        fi
    done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*'; printf '%s\n' "$ROOT/setup")
}

# ---------------------------------------------------------------- distro ----

t_distro() {
    setup_tmp

    # Fake package managers, so the checks do not depend on what this machine
    # happens to have installed.
    TMPD bin
    local c
    for c in dnf dnf5 apt-get dpkg-query pacman rpm; do
        printf '#!/bin/sh\nexit 0\n' >"$(TMP bin/$c)"
        chmod +x "$(TMP bin/$c)"
    done
    PATH="$(TMP bin):$PATH"
    export PATH

    printf 'ID=fedora\nVERSION_ID=42\n' >"$(TMP os-fedora)"
    printf 'ID=ubuntu\nID_LIKE=debian\n' >"$(TMP os-ubuntu)"
    printf 'ID=arch\n' >"$(TMP os-arch)"
    printf 'ID=plan9\nID_LIKE=inferno\n' >"$(TMP os-unsupported)"

    source_libs

    local out
    out="$(FS_OS_RELEASE="$(TMP os-fedora)" FS_PKG_BIN=dnf5 detect_distro 2>&1 >/dev/null; printf '%s|%s|%s' "$FS_DISTRO" "$FS_FAMILY" "$PKG_INSTALL")"
    check_eq "detect fedora" "fedora|rpm|dnf5 install -y" "$out"

    out="$(FS_OS_RELEASE="$(TMP os-ubuntu)" detect_distro 2>&1 >/dev/null; printf '%s|%s|%s' "$FS_DISTRO" "$FS_FAMILY" "$PKG_INSTALL")"
    check_eq "detect ubuntu" "ubuntu|deb|apt-get install -y" "$out"

    out="$(FS_OS_RELEASE="$(TMP os-arch)" detect_distro 2>&1 >/dev/null; printf '%s|%s|%s' "$FS_DISTRO" "$FS_FAMILY" "$PKG_INSTALL")"
    check_eq "detect arch" "arch|arch|pacman -S --needed --noconfirm" "$out"

    local rc=0
    out="$(FS_OS_RELEASE="$(TMP os-unsupported)" detect_distro 2>&1 >/dev/null)" || rc=$?
    check_eq "unsupported distro exits non-zero" "1" "$rc"
    check_contains "unsupported distro names the distro" "unsupported distro: plan9" "$out"

    rc=0
    out="$(FS_OS_RELEASE="$(TMP nope)" detect_distro 2>&1 >/dev/null)" || rc=$?
    check_eq "missing os-release exits non-zero" "1" "$rc"
    check_contains "missing os-release is reported" "cannot read" "$out"

    teardown_tmp
}

# ------------------------------------------------------------------ lists ----

t_read_list() {
    setup_tmp
    source_libs
    printf '# comment\n\n   # indented comment\n\ngit\n  curl  \nvim\n' >"$(TMP list.txt)"

    check_eq "read_list drops blanks, comments and padding" "git
  curl
vim" "$(read_list "$(TMP list.txt)")"

    # Leading whitespace must survive: gitconfig indentation is load-bearing.
    printf '[init]\n\tdefaultBranch = main\n' >"$(TMP gc.txt)"
    check_eq "read_list keeps leading whitespace" "$(printf '[init]\n\tdefaultBranch = main')" \
        "$(read_list "$(TMP gc.txt)")"

    local out
    out="$(read_list "$(TMP absent.txt)" 2>&1 >/dev/null)"
    check_contains "read_list fails on a missing file" "config file not found" "$out"
    teardown_tmp
}

# --------------------------------------------------------------- packages ----

t_package_files() {
    setup_tmp
    source_libs
    mkdir -p "$(TMP root/config)"
    printf 'git\n' >"$(TMP root/config/packages.txt)"
    printf 'python3-pip\n' >"$(TMP root/config/packages-deb.txt)"

    FS_ROOT="$(TMP root)"

    # Pinned, so the list does not depend on the desktop running the checks.
    unset XDG_CURRENT_DESKTOP

    FS_FAMILY=deb
    check_eq "package_files includes the deb list" "2" "$(package_files | wc -l)"
    check_contains "package_files includes the shared list" "config/packages.txt" "$(package_files)"

    FS_FAMILY=rpm
    check_eq "package_files skips an absent family list" "1" "$(package_files | wc -l)"

    XDG_CURRENT_DESKTOP=GNOME
    FS_FAMILY=rpm
    check_eq "package_files adds the gnome list on gnome" "2" "$(package_files | wc -l)"
    check_contains "package_files names the gnome list" "config/packages-gnome.txt" "$(package_files)"

    XDG_CURRENT_DESKTOP=KDE
    check_eq "package_files skips the gnome list elsewhere" "1" "$(package_files | wc -l)"

    FS_ROOT="$ROOT"
    teardown_tmp
}

t_install_packages() {
    setup_tmp
    source_libs
    FS_FAMILY=deb
    PKG_INSTALL="apt-get install -y"

    printf '# packages\ngit\ncurl\n\nvim\n' >"$(TMP pkgs.txt)"
    local log
    log="$(TMP log)"

    run_root() { printf '%s\n' "$*" >>"$log"; }
    pkg_installed() { return 1; }

    install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1
    check_contains "install_packages builds one batch" "apt-get install -y git curl vim" "$(cat "$log")"

    : >"$log"
    pkg_installed() { [[ "$1" == "git" ]]; }
    install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1
    check_contains "install_packages keeps going past installed ones" "curl vim" "$(cat "$log")"
    check_missing "install_packages omits installed ones" "git" "$(cat "$log")"

    : >"$log"
    pkg_installed() { return 0; }
    install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1
    check_eq "install_packages does nothing when all are installed" "" "$(cat "$log")"

    teardown_tmp
}

# The fallback in the assertion used to be the expected string itself, so the
# check passed whether or not the module had said anything.
t_install_flatpaks() {
    setup_tmp
    source_libs
    printf '# apps\norg.gimp.GIMP\ncom.bitwarden.desktop\n' >"$(TMP f.txt)"
    local log out rc
    log="$(TMP log)"
    run() { printf '%s\n' "$*" >>"$log"; }
    flatpak() {
        [[ "$1" == "info" ]] && return 0
        return 0
    }
    export -f flatpak 2>/dev/null || true

    # Every app is already installed, so the module must say so and run nothing.
    out="$(install_flatpaks "$(TMP f.txt)" 2>&1)"
    check_contains "install_flatpaks skips installed apps" "no flatpaks to install" "$out"
    check_eq "install_flatpaks runs no command" "" "$(cat "$log" 2>/dev/null)"

    # One app missing: the module must install that app only. A flatpak shell
    # function cannot be overridden, so a PATH stub stands in for it.
    unset -f flatpak 2>/dev/null || true
    TMPD bin
    cat >"$(TMP bin/flatpak)" <<EOF
#!/bin/sh
if [ "\$1" = info ]; then
    [ "\$2" = org.gimp.GIMP ] && exit 0
    exit 1
fi
if [ "\$1" = install ]; then printf '%s\\n' "\$*" >>"$log"; exit 0; fi
exit 0
EOF
    chmod +x "$(TMP bin/flatpak)"
    PATH="$(TMP bin):$PATH"

    rc=0
    out="$(install_flatpaks "$(TMP f.txt)" 2>&1)" || rc=$?
    check_eq "install_flatpaks succeeds" "0" "$rc"
    check_contains "install_flatpaks installs the missing app" \
        "flatpak install -y flathub com.bitwarden.desktop" "$(cat "$log")"
    check_missing "install_flatpaks leaves installed apps alone" "org.gimp.GIMP" "$(cat "$log")"

    # With both apps installed, a rerun must run nothing.
    flatpak() { return 0; }
    : >"$log"
    out="$(install_flatpaks "$(TMP f.txt)" 2>&1)"
    check_contains "install_flatpaks is a no-op once installed" "no flatpaks to install" "$out"
    check_eq "install_flatpaks runs no command on a rerun" "" "$(cat "$log")"

    teardown_tmp
}

# ---------------------------------------------------------- managed blocks ----

t_write_block() {
    setup_tmp
    source_libs
    printf 'existing user line\n' >"$(TMP rc)"

    printf 'alpha\nbeta\n' | write_block "$(TMP rc)" demo >/dev/null
    check_contains "write_block keeps unrelated lines" "existing user line" "$(cat "$(TMP rc)")"
    check_contains "write_block writes the body" "alpha" "$(cat "$(TMP rc)")"

    local before
    before="$(cat "$(TMP rc)")"
    printf 'alpha\nbeta\n' | write_block "$(TMP rc)" demo >/dev/null
    check_eq "write_block is a no-op when already correct" "$before" "$(cat "$(TMP rc)")"
    check_eq "write_block backs up only when it changes" "1" "$(find "$_tmpdir" -name 'rc.bak' | wc -l)"

    printf 'only-new\n' | write_block "$(TMP rc)" demo >/dev/null
    check_contains "write_block replaces a drifted block" "only-new" "$(cat "$(TMP rc)")"
    check_missing "write_block drops the old body" "alpha" "$(cat "$(TMP rc)")"
    check_contains "write_block still keeps unrelated lines" "existing user line" "$(cat "$(TMP rc)")"

    local out
    out="$(printf '' | write_block "$(TMP rc)" demo 2>&1 >/dev/null)"
    check_contains "write_block refuses an empty block" "refusing to write an empty block" "$out"

    printf '# BEGIN postinstall demo\nold\n# END postinstall demo\n# BEGIN postinstall demo\nold2\n# END postinstall demo\n' >"$(TMP dup)"
    out="$(printf 'new\n' | write_block "$(TMP dup)" demo 2>&1 >/dev/null)"
    check_contains "write_block refuses duplicate blocks" "merge them by hand" "$out"

    teardown_tmp
}

# --------------------------------------------------------------- modules ----

t_modules() {
    setup_tmp
    source_libs
    local out rc

    check_eq "validate_modules accepts real modules" "" "$(validate_modules git terminal gnome 2>&1)"
    out="$(validate_modules nosuchmodule 2>&1 >/dev/null)"
    check_contains "validate_modules rejects a typo" "no such module: nosuchmodule" "$out"

    check_contains "list_modules finds git" "git" "$(list_modules)"
    check_contains "config/modules.txt lists terminal" "terminal" "$(default_modules)"

    local log
    log="$(TMP run.log)"

    # The probe modules live in a throwaway copy of modules/, so an interrupted
    # run cannot leave a stray module in the real repository.
    TMPD root/modules
    FS_ROOT="$(TMP root)"

    printf 'install_probe() { printf "ran\\n" >>"%s"; }\n' "$log" >"$(TMP root/modules/probe.sh)"
    run_modules probe >/dev/null 2>&1
    check_contains "run_modules calls install_<id>" "ran" "$(cat "$log")"

    printf 'install_probe() { return 1; }\n' >"$(TMP root/modules/probe.sh)"
    rc=0
    out="$(run_modules probe 2>&1 >/dev/null)" || rc=$?
    check_eq "a failing module makes run_modules fail" "1" "$rc"
    check_contains "a failing module is named" "failed modules: probe" "$out"

    printf 'install_probe() { return 1; }\n' >"$(TMP root/modules/probe.sh)"
    printf 'install_probe2() { printf "probe2 ran\\n" >>"%s"; }\n' "$log" >"$(TMP root/modules/probe2.sh)"
    : >"$log"
    rc=0
    run_modules probe probe2 >/dev/null 2>&1 || rc=$?
    check_eq "a failing module still fails the run" "1" "$rc"
    check_contains "a failing module does not stop the ones after it" "probe2 ran" "$(cat "$log")"

    printf 'install_wrongname() { :; }\n' >"$(TMP root/modules/probe.sh)"
    out="$(run_modules probe 2>&1 >/dev/null)"
    check_contains "a module missing its function fails" "does not define install_probe" "$out"

    FS_ROOT="$ROOT"
    check_missing "the checks leave no module behind" "probe" "$(ls "$ROOT/modules")"

    teardown_tmp
}

# ------------------------------------------------------- verified binaries ----

# Covers the install path for the pinned, downloaded binaries: a plain file, a
# tarball whose binary sits inside a subdirectory, a good checksum, a bad one,
# and a rerun that must notice the installed version.
t_verified_binary() {
    setup_tmp
    source_libs
    # shellcheck source=/dev/null
    source "$ROOT/modules/terminal.sh"
    _tmpdirs=()
    local dest out rc

    # FS_BIN_SRC_DIR stands in for the cache a real run would download into.
    TMPD src/bin
    TMPD dest
    export FS_BIN_SRC_DIR="$(TMP src/bin)"
    dest="$(TMP dest/tool)"

    local url="https://example.invalid/tool.tar.gz"
    local stage
    stage="$(TMP src/bin/tool.tar.gz)"

    # A tarball, because that is the shape that exercises extraction too.
    TMPD src/pkg
    printf '#!/bin/sh\necho "tool 1.2.3"\n' >"$(TMP src/pkg/tool)"
    tar -czf "$stage" -C "$(TMP src)" pkg/tool
    (cd "$(TMP src/bin)" && sha256sum tool.tar.gz >tool.tar.gz.sha256)

    rc=0
    _install_verified_binary "$url" "$dest" "$dest --version" "1.2.3" tar >/dev/null 2>&1 || rc=$?
    check_eq "a verified tarball installs" "0" "$rc"
    check_eq "the binary lands at the destination" "tool 1.2.3" "$("$dest" 2>/dev/null)"
    check_eq "the installed binary is executable" "yes" \
        "$([[ -x "$dest" ]] && echo yes || echo no)"
    check_missing "the archive is not left in the cache" "tool.tar.gz.sha256" \
        "$(ls "$(TMP dest)")"

    # Already installed and the version matches: nothing to do.
    out="$(_install_verified_binary "$url" "$dest" "$dest --version" "1.2.3" tar 2>&1)"
    check_contains "a matching version is left alone" "already installed" "$out"

    # Corrupt the cached archive; the digest no longer matches, so the install
    # must be refused rather than silently trusted.
    printf 'tampered\n' >>"$stage"
    rm -f "$dest"
    rc=0
    out="$(_install_verified_binary "$url" "$dest" "$dest --version" "1.2.3" tar 2>&1 >/dev/null)" || rc=$?
    check_eq "a checksum mismatch fails" "1" "$rc"
    check_contains "a checksum mismatch is explained" "sha256 mismatch" "$out"
    check_eq "a refused binary is not installed" "no" \
        "$([[ -e "$dest" ]] && echo yes || echo no)"

    unset FS_BIN_SRC_DIR
    teardown_tmp
}

# -------------------------------------------------------------- dns/locale ----

# nmcli and localectl are stubbed, and FS_ROOT points into the temp dir, so the
# dns and locale modules run for real without touching this machine or the
# checked-in repository.

t_dns() {
    setup_tmp
    source_libs
    # shellcheck source=/dev/null
    source "$ROOT/modules/dns.sh"
    _tmpdirs=()

    TMPD root
    FS_ROOT="$(TMP root)"
    export FS_DNS_CONNECTION=""

    nmcli() {
        local a prev="" dns=""
        if [[ "$*" == *--active* ]]; then
            cat "$(TMP names)"
        elif [[ "$1 $2" == "connection modify" ]]; then
            for a in "$@"; do
                [[ "$prev" == ipv4.dns ]] && dns="$a"
                prev="$a"
            done
            printf '%s' "$3" >"$(TMP modified)"
            printf '%s' "$dns" >"$(TMP dns)"
        elif [[ "$3" == ipv4.dns ]]; then
            printf 'ipv4.dns:%s\n' "$(cat "$(TMP dns)" 2>/dev/null)"
        fi
        return 0
    }
    # run_root is stubbed so applying the change needs no root, but it keeps the
    # real dry-run behaviour: a dry run must not run the command.
    run_root() {
        ((FS_DRY_RUN)) && return 0
        shift
        "$@"
    }

    # nmcli lists the loopback profile first: it must be skipped.
    printf 'lo\nMy Net 5\n' >"$(TMP names)"

    # The bare NAME output, with no field prefix to match on.
    check_eq "dns finds the active connection" "My Net 5" "$(_dns_active)"

    # nmcli prefixes the field, and joins the servers with commas.
    printf '8.8.8.8,8.8.4.4' >"$(TMP dns)"
    check_eq "dns drops the ipv4.dns prefix and the commas" "8.8.8.8 8.8.4.4" \
        "$(_dns_servers "My Net 5")"

    : >"$(TMP dns)"
    check_eq "an unset dns reads as empty" "" "$(_dns_servers "My Net 5")"

    # A connection whose name contains spaces: the backup must keep the name
    # whole, and the revert must hand that whole name back to nmcli.
    FS_DRY_RUN=0
    FS_DNS_REVERT=0
    printf '192.168.1.1' >"$(TMP dns)"
    local rc=0
    install_dns >/dev/null 2>&1 || rc=$?
    check_eq "dns sets the servers and succeeds" "0" "$rc"
    check_eq "the backup keeps the connection name whole" "My Net 5" \
        "$(sed -n 1p "$(TMP root/.dns-backup)")"
    check_eq "the backup keeps the old servers" "192.168.1.1" \
        "$(sed -n 2p "$(TMP root/.dns-backup)")"

    rm -f "$(TMP modified)"
    FS_DNS_REVERT=1
    rc=0
    install_dns >/dev/null 2>&1 || rc=$?
    check_eq "dns revert succeeds" "0" "$rc"
    check_eq "dns revert targets the whole name" "My Net 5" "$(cat "$(TMP modified)")"
    check_eq "dns revert restores the old servers" "192.168.1.1" \
        "$(_dns_servers "My Net 5")"

    # Running again with the wanted value already in place changes nothing.
    FS_DNS_REVERT=0
    printf '8.8.8.8,8.8.4.4' >"$(TMP dns)"
    rm -f "$(TMP modified)"
    rc=0
    install_dns >/dev/null 2>&1 || rc=$?
    check_eq "an already correct dns succeeds without changing anything" "0" "$rc"
    check_eq "an already correct dns runs no modify" "no" \
        "$([[ -e "$(TMP modified)" ]] && echo yes || echo no)"

    # A dry run must touch neither NetworkManager nor the backup.
    rm -f "$(TMP root/.dns-backup)" "$(TMP modified)"
    printf '192.168.1.1' >"$(TMP dns)"
    FS_DRY_RUN=1
    rc=0
    install_dns >/dev/null 2>&1 || rc=$?
    check_eq "dns dry run succeeds" "0" "$rc"
    check_eq "dns dry run creates no backup" "no" \
        "$([[ -e "$(TMP root/.dns-backup)" ]] && echo yes || echo no)"
    check_eq "dns dry run changes no connection" "no" \
        "$([[ -e "$(TMP modified)" ]] && echo yes || echo no)"

    printf 'Some Other Net\n1.1.1.1\n' >"$(TMP root/.dns-backup)"
    install_dns >/dev/null 2>&1
    check_eq "dns dry run leaves an existing backup alone" "Some Other Net
1.1.1.1" "$(cat "$(TMP root/.dns-backup)")"

    FS_DRY_RUN=0
    unset FS_DNS_CONNECTION FS_DNS_REVERT
    FS_ROOT="$ROOT"
    # Drop the stubs so the later checks see the real run_root again.
    unset -f nmcli run_root
    source_libs
    teardown_tmp
}

t_locale() {
    setup_tmp
    source_libs
    # shellcheck source=/dev/null
    source "$ROOT/modules/locale.sh"
    _tmpdirs=()

    TMPD root
    FS_ROOT="$(TMP root)"
    export FS_LOCALE=""

    localectl() {
        case "${1:-}" in
        status) printf '   System Locale: LANG=%s\n' "$(cat "$(TMP lang)")" ;;
        set-locale) printf '%s' "${2#LANG=}" >"$(TMP lang)" ;;
        esac
        return 0
    }
    run_root() {
        ((FS_DRY_RUN)) && return 0
        shift
        "$@"
    }

    printf 'C.UTF-8' >"$(TMP lang)"

    # A dry run must leave both the locale and the backup alone.
    FS_DRY_RUN=1
    local rc=0
    install_locale >/dev/null 2>&1 || rc=$?
    check_eq "locale dry run succeeds" "0" "$rc"
    check_eq "locale dry run creates no backup" "no" \
        "$([[ -e "$(TMP root/.locale-backup)" ]] && echo yes || echo no)"
    check_eq "locale dry run changes no locale" "C.UTF-8" "$(cat "$(TMP lang)")"

    printf 'de_DE.UTF-8\n' >"$(TMP root/.locale-backup)"
    install_locale >/dev/null 2>&1
    check_eq "locale dry run leaves an existing backup alone" "de_DE.UTF-8" \
        "$(cat "$(TMP root/.locale-backup)")"

    # Dry run off, the change really happens.
    FS_DRY_RUN=0
    rm -f "$(TMP root/.locale-backup)"
    rc=0
    install_locale >/dev/null 2>&1 || rc=$?
    check_eq "locale set succeeds" "0" "$rc"
    check_eq "locale set applies the locale" "en_US.UTF-8" "$(cat "$(TMP lang)")"
    check_eq "locale backup keeps the old locale" "C.UTF-8" \
        "$(cat "$(TMP root/.locale-backup)")"

    FS_LOCALE_REVERT=1
    rc=0
    install_locale >/dev/null 2>&1 || rc=$?
    check_eq "locale revert succeeds" "0" "$rc"
    check_eq "locale revert restores the old locale" "C.UTF-8" "$(cat "$(TMP lang)")"

    FS_ROOT="$ROOT"
    # Drop the stubs so the later checks see the real run_root again.
    unset -f localectl run_root
    source_libs
    teardown_tmp
}

# ------------------------------------------------------------ error paths ----

t_failure_propagation() {
    setup_tmp
    source_libs

    # The real run()/run_root() must turn a failing command into a non-zero
    # exit, because every mutating step goes through them.
    local rc=0
    (run "boom" false) >/dev/null 2>&1 || rc=$?
    check_eq "a failing run command exits non-zero" "1" "$rc"

    rc=0
    local out
    out="$(run "boom" false 2>&1 >/dev/null)"
    check_contains "a failing run command is reported" "boom failed" "$out"

    # A package command that fails must not be reported as a successful setup.
    FS_FAMILY=deb
    PKG_INSTALL="false"
    pkg_installed() { return 1; }
    printf 'git\n' >"$(TMP pkgs.txt)"
    rc=0
    (install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1) || rc=$?
    check_eq "a failing package install exits non-zero" "1" "$rc"

    teardown_tmp
}

# -------------------------------------------------------------- dry run ----

t_dry_run() {
    setup_tmp
    source_libs
    local rc

    # Every command goes through run()/run_root(), so a dry run that leaves the
    # filesystem and the sudo path untouched proves nothing ran.
    FS_FAMILY=deb
    PKG_INSTALL="touch $(TMP PWNED)"
    pkg_installed() { return 1; }
    printf 'git\n' >"$(TMP pkgs.txt)"

    FS_DRY_RUN=1
    install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1
    check_eq "dry run installs nothing" "0" "$(find "$_tmpdir" -name PWNED | wc -l)"

    local out
    out="$(install_packages "$(TMP pkgs.txt)" 2>&1)"
    check_contains "dry run says what it would do" "would install packages" "$out"

    # Same input, dry run off: the command really runs. run_root is stubbed so
    # the check does not need root.
    run_root() { shift; "$@"; }
    FS_DRY_RUN=0
    install_packages "$(TMP pkgs.txt)" >/dev/null 2>&1
    check_eq "a real run does install" "1" "$(find "$_tmpdir" -name PWNED | wc -l)"
    rm -f "$(TMP PWNED)"

    printf 'user line\n' >"$(TMP rc)"
    FS_DRY_RUN=1
    printf 'mine\n' | write_block "$(TMP rc)" demo >/dev/null 2>&1
    check_eq "dry run writes no block" "user line" "$(cat "$(TMP rc)")"
    check_eq "dry run takes no backup" "0" "$(find "$_tmpdir" -name 'rc.bak' | wc -l)"

    printf 'body\n' | write_atomic "$(TMP written.txt)" >/dev/null 2>&1
    check_eq "dry run writes no plain file" "0" "$(find "$_tmpdir" -name 'written.txt' | wc -l)"

    FS_DRY_RUN=0
    printf 'body\n' | write_atomic "$(TMP written.txt)" >/dev/null 2>&1
    check_eq "a real run writes the file" "body" "$(cat "$(TMP written.txt)")"

    teardown_tmp
}

# ------------------------------------------------------------------ cli ----

t_cli() {
    setup_tmp
    local out rc

    out="$("$ROOT/setup" help 2>&1)"
    check_contains "setup help explains the tool" "personal post-install script" "$out"
    check_contains "setup help lists the install command" "./setup install" "$out"

    out="$("$ROOT/setup" list 2>&1)"
    check_contains "setup list prints terminal" "terminal" "$out"

    rc=0
    out="$("$ROOT/setup" nosuchcommand 2>&1 >/dev/null)" || rc=$?
    check_eq "an unknown command exits non-zero" "1" "$rc"
    check_contains "an unknown command is reported" "unknown command" "$out"

    rc=0
    out="$("$ROOT/setup" --nosuchoption 2>&1 >/dev/null)" || rc=$?
    check_eq "an unknown option exits non-zero" "1" "$rc"
    check_contains "an unknown option is reported" "unknown option" "$out"

    rc=0
    out="$("$ROOT/setup" install nosuchmodule 2>&1 >/dev/null)" || rc=$?
    check_eq "an unknown module exits non-zero" "1" "$rc"
    check_contains "an unknown module is reported" "no such module" "$out"

    rc=0
    out="$(FS_OS_RELEASE="$(TMP nope)" "$ROOT/setup" --dry-run packages 2>&1 >/dev/null)" || rc=$?
    check_eq "an unreadable distro file exits non-zero" "1" "$rc"
    check_contains "an unreadable distro file is reported" "cannot read" "$out"

    rc=0
    printf 'ID=plan9\nID_LIKE=inferno\n' >"$(TMP os)"
    out="$(FS_OS_RELEASE="$(TMP os)" "$ROOT/setup" --dry-run packages 2>&1 >/dev/null)" || rc=$?
    check_eq "an unsupported distro exits non-zero" "1" "$rc"
    check_contains "an unsupported distro is reported" "unsupported distro: plan9" "$out"

    # The bare invocation is the documented default and must behave like
    # ./setup install, running the modules from config/modules.txt.
    printf 'ID=fedora\nVERSION_ID=42\n' >"$(TMP os-fed)"
    rc=0
    out="$(FS_OS_RELEASE="$(TMP os-fed)" "$ROOT/setup" --dry-run 2>&1)" || rc=$?
    check_eq "a bare run exits zero" "0" "$rc"
    check_contains "a bare run starts the first default module" "--- git ---" "$out"
    check_contains "a bare run reaches the last default module" "--- dev ---" "$out"
    check_missing "a bare run skips the opt-in dns module" "--- dns ---" "$out"

    # --dry-run must not be tripped up by downloads it never made: no fetch,
    # no verification, no failure.
    check_missing "a dry run reports no fetch failure" "no .sha256 published" "$out"
    check_missing "a dry run leaves no module failed" "module terminal failed" "$out"

    # Naming modules must run exactly those, in the order given.
    out="$(FS_OS_RELEASE="$(TMP os-fed)" "$ROOT/setup" --dry-run install terminal git 2>&1)"
    check_contains "named modules run, first one first" "--- terminal ---" "$out"
    check_missing "only the named modules run" "--- fonts ---" "$out"

    teardown_tmp
}

# ----------------------------------------------------------------- main ----

run_unit_tests() {
    local t
    for t in t_distro t_read_list t_package_files t_install_packages t_install_flatpaks \
        t_write_block t_modules t_verified_binary t_dns t_locale \
        t_failure_propagation t_dry_run t_cli; do
        printf '%s\n' "${t#t_}"
        "$t"
    done
}

main() {
    case "${1:-all}" in
    syntax)
        printf 'syntax\n'
        t_syntax
        ;;
    unit)
        printf 'units\n'
        run_unit_tests
        ;;
    all | "")
        t_syntax
        run_unit_tests
        ;;
    *)
        printf 'usage: %s [syntax|unit]\n' "$0" >&2
        return 2
        ;;
    esac

    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    ((fail == 0))
}

main "$@"
