#!/usr/bin/env bash
# tests/fixtures/mod_dns.sh - P8.1 fixture for the high-risk `dns` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Mock strategy: a PATH-visible fake `nmcli` implements a stateful
# NetworkManager (an FS_NM_STATE file of `key=value` connection properties,
# mutated by `connection modify` and read back by `connection show -g`), a
# fake `ip` returns one default-route line, and a fake `getent` answers the
# name-resolution probe. Every fake invocation is appended to $FS_OPS, so a
# cell can assert both that the right commands ran and that nothing else
# did. FS_EUID=0 is the documented run.sh seam, so run_sudo executes
# directly without a password prompt.
# Covers: metadata + opt-in default; dry-run purity (exact plan lines, ZERO
# probes, no state dir, no record) with and without an explicit connection
# (RESOLVED-AT-RUN-TIME marker); every non-NetworkManager/ambiguous-host skip
# and fail-closed path; the real apply with default-route connection
# selection, prior-state record, postcondition, reactivation and resolution
# check; idempotent re-apply; the revert restoring the exact recorded values
# and removing the record; postcondition failure, resolution failure and
# resolution retry; getent-missing and reactivate-failure tolerance; invalid
# seams; the read-only verify() paths; and the "never touches resolv.conf or
# chattr" guarantee.
# Usage: bash tests/fixtures/mod_dns.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init

SETUP="$ROOT/setup"
OPS="$FX_TMP/ops"
NMSTATE="$FX_TMP/nm.state"
NMPRISTINE="$FX_TMP/nm.pristine"
GETENT_CALLS="$FX_TMP/getent.calls"
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools"

cat >"$FX_TMP/fakebin/nmcli" <<'NMCLI'
#!/usr/bin/env bash
printf 'nmcli %s\n' "$*" >>"${FS_OPS:-/dev/null}"
state="${FS_NM_STATE:-/dev/null}"
args=("$@")
i=0
field=""
terse=0
while (( i < $# )); do
    case "${args[i]}" in
        -t) terse=1; i=$(( i + 1 )); continue ;;
        -f | -g) field="${args[i+1]}"; terse=$(( terse == 1 ? 1 : 2 )); i=$(( i + 2 )); continue ;;
    esac
    break
done
verb="${args[i]:-}"
i=$(( i + 1 ))
if [[ "$verb" == general ]]; then
    printf '%s\n' "${FS_FAKE_NM_RUNNING:-running}"
    exit 0
fi
if [[ "$verb" != connection ]]; then
    exit 0
fi
sub="${args[i]:-}"
i=$(( i + 1 ))
obj="${args[i]:-}"
case "$sub" in
    show)
        if (( terse == 1 )); then
            printf '%s' "${FS_FAKE_NM_CONNS-Home:wlp0s20f3:activated
lo:lo:activated
}"
            exit 0
        fi
        if [[ "$obj" != "${FS_FAKE_NM_CONN:-Home}" ]]; then
            exit 1
        fi
        v="$(grep "^$field=" "$state" 2>/dev/null | head -1)"
        printf '%s\n' "${v#*=}"
        exit 0
        ;;
    up)
        [[ "${FS_FAKE_NM_UP_RC:-0}" == 0 ]] || exit 1
        exit 0
        ;;
    modify)
        [[ "${FS_FAKE_NM_MODIFY_NOOP:-0}" == 0 ]] || exit 0
        i=$(( i + 1 ))
        while (( i < $# )); do
            k="${args[i]}"
            v="${args[i+1]:-}"
            i=$(( i + 2 ))
            if grep -q "^$k=" "$state" 2>/dev/null; then
                sed -i "s|^$k=.*|$k=$v|" "$state"
            else
                printf '%s=%s\n' "$k" "$v" >>"$state"
            fi
        done
        exit 0
        ;;
esac
exit 0
NMCLI

cat >"$FX_TMP/fakebin/ip" <<'IPFAKE'
#!/usr/bin/env bash
printf 'ip %s\n' "$*" >>"${FS_OPS:-/dev/null}"
printf '%s\n' "${FS_FAKE_NM_ROUTE-default via 192.168.1.1 dev wlp0s20f3 proto dhcp src 192.168.1.39 metric 600 }"
IPFAKE

cat >"$FX_TMP/fakebin/getent" <<'GETENT'
#!/usr/bin/env bash
printf 'getent %s\n' "$*" >>"${FS_OPS:-/dev/null}"
n=0
if [[ -f "${FS_GETENT_CALLS:-/dev/null}" ]]; then
    n="$(cat -- "${FS_GETENT_CALLS}" 2>/dev/null || printf '0')"
fi
n=$(( n + 1 ))
printf '%s' "$n" >"${FS_GETENT_CALLS:-/dev/null}"
if [[ "${FS_FAKE_GETENT_RC:-0}" != 0 ]]; then
    exit 1
fi
if [[ "$n" -le ${FS_FAKE_GETENT_FAILS:-0} ]]; then
    exit 2
fi
printf '1.1.1.1 %s\n' "${2:-example.invalid}"
exit 0
GETENT

cat >"$FX_TMP/fakebin/chattr" <<'CHATTR'
#!/usr/bin/env bash
printf 'chattr %s\n' "$*" >>"${FS_OPS:-/dev/null}"
exit 0
CHATTR

chmod +x "$FX_TMP/fakebin/nmcli" "$FX_TMP/fakebin/ip" \
    "$FX_TMP/fakebin/getent" "$FX_TMP/fakebin/chattr"

printf 'P8.1 dns module\n'

fx_out_fixed() {
    local pat="$1"
    if grep -Fq -- "$pat" "$FX_OUT" 2>/dev/null; then
        fx_ok
    else
        fx_bad "stdout did not contain (literal): $pat"
        printf '  stdout:\n' >&2
        sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
    fi
}

# The one thing this fixture must never do is reach the REAL nmcli. The cells
# set FS_EUID=0 (the documented run.sh seam), so the sudo barrier is gone, and
# NetworkManager's polkit lets the session user rewrite their own live profile
# without root -- a leaked real nmcli would therefore silently reconfigure the
# machine running the tests. That is not hypothetical: an earlier revision of
# this file built its "no getent" PATH by symlinking every real binary, failed
# to overwrite the nmcli symlink, and a non-dry cell then applied 8.8.8.8 to
# the host's live Home profile. Every non-dry cell therefore asserts, from the
# same PATH the child will see, that nmcli is our fake regular file.
_nmcli_is_fake() {
    local dir="${1:-$FX_TMP/fakebin}" resolved
    [[ -n "$dir" ]] || return 1
    resolved="$(command -v nmcli 2>/dev/null || :)"
    [[ "$resolved" == "$dir/nmcli" && -f "$dir/nmcli" && ! -L "$dir/nmcli" ]] || return 1
    cmp -s -- "$dir/nmcli" "$FX_TMP/fakebin/nmcli"
}

guard_fake_nmcli() {
    if _nmcli_is_fake "${1:-$FX_TMP/fakebin}"; then
        fx_ok
    else
        fx_bad "nmcli on PATH is not the fake (resolved: $(command -v nmcli 2>/dev/null || printf none))"
    fi
}

nm_reset() {
    : >"$OPS"
    rm -f -- "$GETENT_CALLS" 2>/dev/null || :
    printf 'ipv4.dns=\nipv4.ignore-auto-dns=no\n' >"$NMSTATE"
    cp -- "$NMSTATE" "$NMPRISTINE"
}

# A PATH of symlinks to every real binary EXCEPT the named ones, so a cell can
# make a tool genuinely absent (command -v must fail) instead of pretending.
build_farm() {
    local dir="$1" skip=" $* " d f
    rm -rf -- "$dir"
    mkdir -p -- "$dir"
    for d in /usr/local/bin /usr/bin /bin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            [[ -x "$f" && -f "$f" ]] || continue
            case "$skip" in
                *" ${f##*/} "*) continue ;;
            esac
            ln -sf "$f" "$dir/${f##*/}" 2>/dev/null || :
        done
    done
}

# install_fake puts the NetworkManager/IP fakes into a farm, replacing any
# same-named symlink (cp must not follow it back to the real binary).
install_fake() {
    local dir="$1" name
    shift
    for name in "$@"; do
        rm -f -- "$dir/$name"
        cp --remove-destination "$FX_TMP/fakebin/$name" "$dir/$name" 2>/dev/null || :
        chmod +x "$dir/$name" 2>/dev/null || :
    done
}

dns_run() {
    local state_dir="$1" label="$2" want="$3" dry="${4:-0}"
    shift 4 || :
    local -a extra=("$@")
    PATH="$FX_TMP/fakebin:$PATH"
    export PATH
    guard_fake_nmcli "$FX_TMP/fakebin"
    : >"$OPS"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_OPS="$OPS" FS_NM_STATE="$NMSTATE" FS_GETENT_CALLS="$GETENT_CALLS"
        export FS_DNS_CHECK_HOST=flathub.org
        if [[ "$dry" == 1 ]]; then
            export FS_DRY_RUN=1
        fi
        if (( ${#extra[@]} > 0 )); then
            export "${extra[@]}"
        fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes dns
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

printf -- '--- cell: metadata + opt-in default\n'
line="$(FS_MODULES_DIR="$ROOT/modules" FS_DISTRO_FAMILY=rpm "$SETUP" list 2>/dev/null | grep -P '^dns\t' || :)"
[[ "$line" == "dns	DNS servers (NetworkManager)	destructive	off	-" ]] && fx_ok \
    || fx_bad "setup list row wrong: $line"
for p in minimal desktop developer full; do
    if grep -qx "dns" "$ROOT/profiles/$p.conf" 2>/dev/null; then
        fx_bad "profile $p includes dns"
    else
        fx_ok
    fi
done

printf -- '--- cell: dry-run, explicit connection: exact plan, zero probes\n'
nm_reset
rm -rf "$FX_TMP/h_dry"
dns_run h_dry "dry explicit" 0 1 'FS_DNS_CONNECTION=Home'
[[ $(grep -c '^# would run:' "$FX_OUT") == 2 ]] && fx_ok \
    || fx_bad "dry plan is 2 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out_fixed "# would run: sudo nmcli connection modify Home ipv4.dns 8.8.8.8\\,8.8.4.4 ipv4.ignore-auto-dns yes"
fx_out_fixed "# would run: sudo nmcli connection up Home"
fx_out "name-resolution check for flathub.org cannot run in dry-run"
fx_empty "dry-run probed nothing" "$OPS"
if [[ -e "$FX_TMP/h_dry" ]]; then fx_bad "dry-run created state"; else fx_ok; fi
if cmp -s -- "$NMSTATE" "$NMPRISTINE"; then fx_ok; else fx_bad "dry-run mutated the fake NM state"; fi

printf -- '--- cell: dry-run without a connection: marker + no probe\n'
nm_reset
rm -rf "$FX_TMP/h_dry2"
dns_run h_dry2 "dry marker" 0 1
fx_out "RESOLVED-AT-RUN-TIME"
fx_out "set FS_DNS_CONNECTION to render the exact connection name"
fx_empty "dry marker probed nothing" "$OPS"
if grep -q 'resolv.conf\|chattr' "$FX_OUT" "$OPS"; then fx_bad "plan mentions resolv.conf/chattr"; else fx_ok; fi

printf -- '--- cell: dry-run, custom servers + no reactivation\n'
nm_reset
rm -rf "$FX_TMP/h_dry3"
dns_run h_dry3 "dry custom" 0 1 'FS_DNS_CONNECTION=Home' 'FS_DNS_SERVERS=1.1.1.1' 'FS_DNS_REACTIVATE=0'
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok \
    || fx_bad "dry custom plan is 1 line (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out_fixed "ipv4.dns 1.1.1.1 ipv4.ignore-auto-dns yes"

printf -- '--- cell: the fake-nmcli guard is not vacuous\n'
build_farm "$FX_TMP/farm_leak" nmcli
PATH="$FX_TMP/farm_leak:$PATH"
export PATH
if _nmcli_is_fake "$FX_TMP/farm_leak"; then
    fx_bad "guard accepted a PATH whose nmcli is the real binary"
else
    fx_ok
fi
if [[ -x "$FX_TMP/farm_leak/nmcli" ]]; then
    fx_bad "farm_leak unexpectedly has an nmcli"
else
    fx_ok
fi
PATH="$FX_TMP/fakebin:$PATH"
export PATH
guard_fake_nmcli "$FX_TMP/fakebin"

printf -- '--- cell: non-NetworkManager host: graceful skip\n'
nm_reset
rm -rf "$FX_TMP/h_nonm"
: >"$OPS"
build_farm "$FX_TMP/farm_nm" nmcli
install_fake "$FX_TMP/farm_nm" ip
if [[ -e "$FX_TMP/farm_nm/nmcli" ]]; then
    fx_bad "could not build a PATH without nmcli"
else
    fx_ok
fi
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_nonm"
    export PATH="$FX_TMP/farm_nm"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes dns
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "non-NM rc" 0
fx_out "nmcli not found"
if grep -q '^# would run:' "$FX_OUT"; then fx_bad "non-NM host rendered a plan"; else fx_ok; fi

printf -- '--- cell: NetworkManager not running: graceful skip\n'
nm_reset
rm -rf "$FX_TMP/h_nmdown"
dns_run h_nmdown "NM down" 0 0 'FS_FAKE_NM_RUNNING=not-running'
fx_out "NetworkManager is not running; skipping"
if grep -q 'connection modify' "$OPS"; then fx_bad "modified DNS with NM down"; else fx_ok; fi

printf -- '--- cell: no active connection: graceful skip\n'
nm_reset
rm -rf "$FX_TMP/h_noact"
dns_run h_noact "no active conn" 0 0 'FS_FAKE_NM_CONNS='
fx_out "no active NetworkManager connection; skipping"
if grep -q 'connection modify' "$OPS"; then fx_bad "modified DNS with no active connection"; else fx_ok; fi

printf -- '--- cell: only loopback active: graceful skip\n'
nm_reset
rm -rf "$FX_TMP/h_lo"
dns_run h_lo "loopback only" 0 0 'FS_FAKE_NM_CONNS=lo:lo:activated
' 'FS_FAKE_NM_ROUTE='
fx_out "no active NetworkManager connection; skipping"
if grep -q 'connection modify' "$OPS"; then fx_bad "selected the loopback connection"; else fx_ok; fi

printf -- '--- cell: two active connections: fail closed, never guess\n'
nm_reset
rm -rf "$FX_TMP/h_amb"
dns_run h_amb "ambiguous" 1 0 'FS_FAKE_NM_CONNS=Home:wlp0s20f3:activated
Cafe:wlp0s20f4:activated
' 'FS_FAKE_NM_ROUTE='
fx_err "2 active connections; refusing to guess"
if grep -q 'connection modify' "$OPS"; then fx_bad "guessed a connection"; else fx_ok; fi

printf -- '--- cell: default-route device wins over the other active one\n'
nm_reset
rm -rf "$FX_TMP/h_route"
dns_run h_route "default route" 0 0 'FS_FAKE_NM_CONNS=Home:wlp0s20f3:activated
Cafe:wlp0s20f4:activated
lo:lo:activated
'
fx_out "dns: Home now uses 8.8.8.8,8.8.4.4 (ignore-auto-dns=yes)"
fx_out "^  - 1 modules ok · 0 skipped · 0 failed ·"
grep -q 'connection modify Home ' "$OPS" && fx_ok || fx_bad "did not modify the default-route connection"
if grep -q 'connection modify Cafe' "$OPS"; then fx_bad "touched the non-default connection"; else fx_ok; fi
[[ "$(cat "$FX_TMP/h_route/.local/state/fedora-setup/notes/dns")" == "Home|no|" ]] && fx_ok \
    || fx_bad "prior-state record wrong: $(cat "$FX_TMP/h_route/.local/state/fedora-setup/notes/dns" 2>/dev/null)"
[[ -f "$FX_TMP/h_route/.local/state/fedora-setup/modules/dns" ]] && fx_ok || fx_bad "module not marked done"

printf -- '--- cell: apply order is detect, read, modify, verify, up, resolve\n'
nm_reset
rm -rf "$FX_TMP/h_order"
dns_run h_order "apply order" 0 0 'FS_DNS_CONNECTION=Home'
expected="nmcli -g ipv4.ignore-auto-dns connection show Home
nmcli -g ipv4.dns connection show Home
nmcli connection modify Home ipv4.dns 8.8.8.8,8.8.4.4 ipv4.ignore-auto-dns yes
nmcli -g ipv4.ignore-auto-dns connection show Home
nmcli -g ipv4.dns connection show Home
nmcli connection up Home
getent hosts flathub.org"
got="$(grep -v 'nmcli -t -f\|nmcli -t -f\|ip -o route' "$OPS")"
[[ "$got" == "$expected" ]] && fx_ok || fx_bad "apply order wrong:
--- got
$got
--- want
$expected"
fx_out "name resolution for flathub.org works"

printf -- '--- cell: idempotent re-apply changes nothing\n'
nm_reset
printf 'ipv4.dns=8.8.8.8,8.8.4.4\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
rm -rf "$FX_TMP/h_idem"
dns_run h_idem "idempotent" 0 0 'FS_DNS_CONNECTION=Home'
fx_out "Home already uses 8.8.8.8,8.8.4.4; no change"
if grep -q 'connection modify' "$OPS"; then fx_bad "re-applied an already-correct DNS"; else fx_ok; fi
if [[ -e "$FX_TMP/h_idem/.local/state/fedora-setup/notes/dns" ]]; then
    fx_bad "recorded a change it never made"
else
    fx_ok
fi

printf -- '--- cell: revert restores the exact prior values\n'
nm_reset
printf 'ipv4.dns=1.1.1.1\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
rm -rf "$FX_TMP/h_rev"
dns_run h_rev "apply for revert" 0 0 'FS_DNS_CONNECTION=Home'
[[ "$(cat "$FX_TMP/h_rev/.local/state/fedora-setup/notes/dns")" == "Home|yes|1.1.1.1" ]] && fx_ok \
    || fx_bad "record before revert wrong"
rm -f -- "$FX_TMP/h_rev/.local/state/fedora-setup/modules/dns"
nm_reset
printf 'ipv4.dns=8.8.8.8,8.8.4.4\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
dns_run h_rev "revert" 0 0 'FS_DNS_CONNECTION=Home' 'FS_DNS_REVERT=1'
fx_out "reverting Home (ignore-auto-dns=yes, dns=1.1.1.1)"
fx_out "revert complete (Home)"
[[ "$(cat "$NMSTATE")" == "ipv4.dns=1.1.1.1
ipv4.ignore-auto-dns=yes" ]] && fx_ok || fx_bad "revert did not restore prior state:
$(cat "$NMSTATE")"
if [[ -e "$FX_TMP/h_rev/.local/state/fedora-setup/notes/dns" ]]; then
    fx_bad "revert left the record behind"
else
    fx_ok
fi

printf -- '--- cell: revert with no record is a no-op\n'
nm_reset
rm -rf "$FX_TMP/h_norec"
dns_run h_norec "revert no record" 0 0 'FS_DNS_CONNECTION=Home' 'FS_DNS_REVERT=1'
fx_out "no recorded change; nothing to revert"
if grep -q 'connection modify' "$OPS"; then fx_bad "reverted without a record"; else fx_ok; fi

printf -- '--- cell: revert target mismatch fails closed\n'
nm_reset
rm -rf "$FX_TMP/h_mismatch"
printf 'ipv4.dns=1.1.1.1\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
dns_run h_mismatch "record other" 0 0 'FS_DNS_CONNECTION=Home'
rm -f -- "$FX_TMP/h_mismatch/.local/state/fedora-setup/modules/dns"
nm_reset
printf 'ipv4.dns=8.8.8.8,8.8.4.4\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
dns_run h_mismatch "revert mismatch" 1 0 'FS_DNS_CONNECTION=Cafe' 'FS_DNS_REVERT=1'
fx_err "revert target mismatch"
if grep -q 'connection modify' "$OPS"; then fx_bad "reverted the wrong connection"; else fx_ok; fi

printf -- '--- cell: modify that does not stick fails the postcondition\n'
nm_reset
rm -rf "$FX_TMP/h_post"
dns_run h_post "postcondition" 1 0 'FS_DNS_CONNECTION=Home' 'FS_FAKE_NM_MODIFY_NOOP=1'
fx_err "DNS was not applied"
fx_err "module failed: dns"
fx_err "stopping run (destructive module dns)"
if [[ -f "$FX_TMP/h_post/.local/state/fedora-setup/modules/dns" ]]; then
    fx_bad "marked done after a failed change"
else
    fx_ok
fi
if [[ -f "$FX_TMP/h_post/.local/state/fedora-setup/notes/dns" ]]; then
    fx_ok
else
    fx_bad "discarded the revert record after a failed change"
fi

printf -- '--- cell: broken resolution fails the run and prints the revert\n'
nm_reset
rm -rf "$FX_TMP/h_res"
dns_run h_res "resolution fails" 1 0 'FS_DNS_CONNECTION=Home' 'FS_FAKE_GETENT_RC=1'
fx_err "name resolution for flathub.org failed after the change"
fx_err "revert with FS_DNS_REVERT=1 ./setup install --yes dns"
[[ "$(cat "$NMSTATE")" == "ipv4.dns=8.8.8.8,8.8.4.4
ipv4.ignore-auto-dns=yes" ]] && fx_ok || fx_bad "expected the change to stay applied"

printf -- '--- cell: a settling network is retried, not reported broken\n'
nm_reset
rm -rf "$FX_TMP/h_retry"
dns_run h_retry "resolution retry" 0 0 'FS_DNS_CONNECTION=Home' 'FS_FAKE_GETENT_FAILS=2'
fx_out "name resolution for flathub.org works"
[[ "$(cat "$GETENT_CALLS")" == 3 ]] && fx_ok || fx_bad "expected 3 resolution attempts"

printf -- '--- cell: missing getent warns but does not fail\n'
nm_reset
rm -rf "$FX_TMP/h_nogetent" "$FX_TMP/farm"
: >"$OPS"
build_farm "$FX_TMP/farm" getent
install_fake "$FX_TMP/farm" nmcli ip
PATH="$FX_TMP/farm"
export PATH
guard_fake_nmcli "$FX_TMP/farm"
if [[ ! -L "$FX_TMP/farm/ip" ]] && cmp -s -- "$FX_TMP/farm/ip" "$FX_TMP/fakebin/ip"; then
    fx_ok
else
    fx_bad "the ip fake did not land in the farm"
fi
if [[ -e "$FX_TMP/farm/getent" ]]; then
    fx_bad "could not build a PATH without getent"
else
    fx_ok
fi
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_nogetent"
    export PATH="$FX_TMP/farm"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_NM_STATE="$NMSTATE"
    export FS_DNS_CONNECTION=Home
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes dns
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no-getent rc" 0
fx_err "getent not found; skipping the name-resolution check"
PATH="$FX_TMP/fakebin:$PATH"
export PATH
[[ -f "$FX_TMP/h_nogetent/.local/state/fedora-setup/modules/dns" ]] && fx_ok || fx_bad "module not marked done"

printf -- '--- cell: a failed reactivation is a warning, not a failure\n'
nm_reset
rm -rf "$FX_TMP/h_noup"
dns_run h_noup "reactivate fails" 0 0 'FS_DNS_CONNECTION=Home' 'FS_FAKE_NM_UP_RC=1'
fx_err "could not reactivate Home; run: nmcli connection up Home"
fx_out "^  - 1 modules ok · 0 skipped · 0 failed ·"
[[ -f "$FX_TMP/h_noup/.local/state/fedora-setup/modules/dns" ]] && fx_ok || fx_bad "module not marked done"

printf -- '--- cell: a revert that breaks resolution keeps the record\n'
nm_reset
printf 'ipv4.dns=1.1.1.1\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
rm -rf "$FX_TMP/h_revres"
dns_run h_revres "apply for revertres" 0 0 'FS_DNS_CONNECTION=Home'
rm -f -- "$FX_TMP/h_revres/.local/state/fedora-setup/modules/dns"
nm_reset
printf 'ipv4.dns=8.8.8.8,8.8.4.4\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
dns_run h_revres "revert resolution fails" 1 0 'FS_DNS_CONNECTION=Home' 'FS_DNS_REVERT=1' 'FS_FAKE_GETENT_RC=1'
fx_err "name resolution for flathub.org failed after the revert"
fx_err "the record is kept; retry with FS_DNS_REVERT=1"
fx_err_not "revert complete"
if [[ -f "$FX_TMP/h_revres/.local/state/fedora-setup/notes/dns" ]]; then
    fx_ok
else
    fx_bad "revert deleted the record on a failed resolution check"
fi
if [[ -f "$FX_TMP/h_revres/.local/state/fedora-setup/modules/dns" ]]; then
    fx_bad "marked done after a failed revert"
else
    fx_ok
fi

printf -- '--- cell: invalid seams fail closed before any command\n'
nm_reset
rm -rf "$FX_TMP/h_bad1"
dns_run h_bad1 "bad servers" 1 0 'FS_DNS_CONNECTION=Home' 'FS_DNS_SERVERS=8.8.8.8 999.1.1.1'
fx_err "invalid DNS server list"
if [[ -s "$OPS" ]]; then fx_bad "probed after an invalid server list"; else fx_ok; fi
nm_reset
rm -rf "$FX_TMP/h_bad2"
dns_run h_bad2 "bad connection" 1 0 'FS_DNS_CONNECTION=--option'
fx_err "invalid FS_DNS_CONNECTION"
if [[ -s "$OPS" ]]; then fx_bad "probed after an invalid connection name"; else fx_ok; fi

printf -- '--- cell: an unexpected probed value fails closed\n'
nm_reset
rm -rf "$FX_TMP/h_odd"
dns_run h_odd "odd value" 1 0 'FS_DNS_CONNECTION=Home' 'FS_FAKE_NM_CONN=Other'
fx_err "cannot read ipv4.ignore-auto-dns of connection: Home"
if grep -q 'connection modify' "$OPS"; then fx_bad "modified after a failed read"; else fx_ok; fi

printf -- '--- cell: resolv.conf and chattr are never touched\n'
nm_reset
rm -rf "$FX_TMP/h_safe"
dns_run h_safe "no /etc writes" 0 0 'FS_DNS_CONNECTION=Home'
if grep -q 'chattr' "$OPS"; then fx_bad "ran chattr"; else fx_ok; fi
if grep -q 'resolv' "$OPS"; then fx_bad "touched resolv.conf"; else fx_ok; fi
if grep -rn 'resolv\.conf\|chattr' "$ROOT/modules/dns/" \
    | grep -v ':[[:space:]]*#' | grep -q .; then
    fx_bad "module touches resolv.conf/chattr outside a comment"
    grep -rn 'resolv\.conf\|chattr' "$ROOT/modules/dns/" \
        | grep -v ':[[:space:]]*#' >&2 || :
else
    fx_ok
fi

printf -- '--- cell: verify() paths\n'
nm_reset
rm -rf "$FX_TMP/h_verify"
dns_run h_verify "verify pass" 0 0 'FS_DNS_CONNECTION=Home'
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_verify"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_NM_STATE="$NMSTATE" FS_GETENT_CALLS="$GETENT_CALLS"
    export FS_DNS_CONNECTION=Home
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/dns/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry rc" 0
fx_out "verify skipped in dry-run"
nm_reset
printf 'ipv4.dns=8.8.8.8,8.8.4.4\nipv4.ignore-auto-dns=yes\n' >"$NMSTATE"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_OPS="$OPS" FS_NM_STATE="$NMSTATE" FS_GETENT_CALLS="$GETENT_CALLS"
    export FS_DNS_CONNECTION=Home
    unset FS_DRY_RUN 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/dns/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify pass rc" 0
fx_out "verify passed (Home uses 8.8.8.8,8.8.4.4)"
nm_reset
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_OPS="$OPS" FS_NM_STATE="$NMSTATE" FS_GETENT_CALLS="$GETENT_CALLS"
    export FS_DNS_CONNECTION=Home
    unset FS_DRY_RUN 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/dns/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify fail rc" 1
fx_err "Home still uses automatic DNS"

printf -- '--- cell: state notes are confined and validated\n'
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_notes"
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/state.sh"
    state_init
    state_note dns 'Home|no|'
    state_note dns 'Home|no|'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "state_note rc" 0
[[ "$(cat "$FX_TMP/h_notes/.local/state/fedora-setup/notes/dns")" == "Home|no|" ]] && fx_ok \
    || fx_bad "note content wrong"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_notes2"
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/state.sh"
    state_init
    state_note dns 'a
b'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "multiline note rc" 1
fx_err "must be a single line"
(
    set -euo pipefail
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/state.sh"
    state_note dns 'x'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "uninitialized note rc" 1
fx_err "state not initialized"

fx_summary
