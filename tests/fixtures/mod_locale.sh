#!/usr/bin/env bash
# tests/fixtures/mod_locale.sh - P8.2 fixture for the high-risk `locale`
# module. Drives the REAL repo modules/ + profiles/ through
# `./setup install`.
# Mock strategy: a PATH-visible fake `localectl` implements a stateful
# systemd-localed: an FS_LC_CONF file holds the current LANG, `set-locale`
# writes it, `status` prints the real `localectl status` shape
# ("System Locale: LANG=<v>"), and `list-locales` answers from a canned
# list. Every fake invocation is appended to $FS_OPS, so a cell can assert
# both that the right commands ran and that nothing else did.
# The apply path also takes a real backup through fs_backup, so the cell
# state root is redirected via FS_HOME and asserted for real.
# FS_EUID=0 is the documented run.sh seam, so run_sudo executes directly
# without a password prompt.
# Covers: metadata + opt-in default + not in any profile; dry-run purity
# (exact plan line, ZERO probes, no state dir, no record, no backup) with
# the default and with an explicit locale; the non-systemd skip; the
# unavailable-locale fail-closed path (before any backup or write); the
# real apply with backup, record and readback postcondition; idempotent
# re-apply (no set-locale, no backup); a set-locale that does not stick
# (postcondition rc1, record kept, no mark); the revert restoring the exact
# recorded value; revert with no record; revert mismatch/invalid record;
# a revert that does not stick; a missing locale.conf (not an error);
# invalid FS_LOCALE values failing closed before any command; the read-only
# verify() paths; and that /etc/locale.conf is never written directly and
# `source` is never used.
# Usage: bash tests/fixtures/mod_locale.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
# Every path this fixture builds is absolute, but run from the scratch dir
# anyway: a relative path escaping into the caller's CWD (i.e. into the
# repo) is the one failure mode the EXIT trap cannot clean up, and it is
# exactly what a mistyped STATE_SUBDIR produces.
cd "$FX_TMP" || exit 1

SETUP="$ROOT/setup"
OPS="$FX_TMP/ops"
LCCONF="$FX_TMP/locale.conf"
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/farm"

cat >"$FX_TMP/fakebin/localectl" <<'LOCALECTL'
#!/usr/bin/env bash
printf 'localectl %s\n' "$*" >>"${FS_OPS:-/dev/null}"
conf="${FS_LC_CONF:-/dev/null}"
case "${1:-}" in
    status)
        v=""
        if [[ -f "$conf" ]]; then
            v="$(sed -n 's/^LANG="\{0,1\}\(.*\)"\{0,1\}$/\1/p' "$conf" | head -1)"
        fi
        printf 'System Locale: LANG=%s\n' "$v"
        printf '   VC Keymap: us\n'
        exit 0
        ;;
    set-locale)
        [[ "${FS_FAKE_LC_SETNOOP:-0}" == 0 ]] || exit 0
        want=""
        for a in "${@:2}"; do
            case "$a" in
                LANG=*) want="${a#LANG=}" ;;
            esac
        done
        printf 'LANG="%s"\n' "$want" >"$conf"
        exit 0
        ;;
    list-locales)
        if [[ "${FS_FAKE_LC_LIST_RC:-0}" != 0 ]]; then
            exit 1
        fi
        printf '%s\n' "${FS_FAKE_LC_LOCALES:-en_US.UTF-8
ar_EG.UTF-8}"
        exit 0
        ;;
esac
exit 0
LOCALECTL

chmod +x "$FX_TMP/fakebin/localectl"

printf 'P8.2 locale module\n'

# The host value the fake starts from. Deliberately NEITHER of the two
# target locales, so the default apply is always a real change; otherwise
# the "already set" branch would swallow the whole apply path.
FX_LC_PRIOR="C.UTF-8"

lc_reset() {
    : >"$OPS"
    printf 'LANG="%s"\n' "$FX_LC_PRIOR" >"$LCCONF"
}

lc_set() {
    printf 'LANG="%s"\n' "${1:-en_US.UTF-8}" >"$LCCONF"
}

STATE_SUBDIR() {
    printf '%s/%s/.local/state/fedora-setup' "$FX_TMP" "${1}"
}

# The one thing this fixture must never do is reach the REAL localectl: the
# cells set FS_EUID=0 (the documented run.sh seam), so the sudo barrier is
# gone, and a leaked real localectl would rewrite this machine's system
# locale. Every non-dry cell therefore asserts, from the same PATH the child
# will see, that localectl is our fake regular file.
_lc_is_fake() {
    local dir="${1:-$FX_TMP/fakebin}" resolved
    [[ -n "$dir" ]] || return 1
    resolved="$(command -v localectl 2>/dev/null || :)"
    [[ "$resolved" == "$dir/localectl" && -f "$dir/localectl" && ! -L "$dir/localectl" ]] || return 1
    cmp -s -- "$dir/localectl" "$FX_TMP/fakebin/localectl"
}

guard_fake_lc() {
    if _lc_is_fake "${1:-$FX_TMP/fakebin}"; then
        fx_ok
    else
        fx_bad "localectl on PATH is not the fake (resolved: $(command -v localectl 2>/dev/null || printf none))"
    fi
}

lc_run() {
    local state_dir="$1" label="$2" want="$3" dry="${4:-0}"
    shift 4 || :
    local -a extra=("$@")
    PATH="$FX_TMP/fakebin:$PATH"
    export PATH
    guard_fake_lc "$FX_TMP/fakebin"
    : >"$OPS"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_OPS="$OPS" FS_LC_CONF="$LCCONF"
        export FS_LOCALE_CONF="$LCCONF"
        if [[ "$dry" == 1 ]]; then
            export FS_DRY_RUN=1
        fi
        if (( ${#extra[@]} > 0 )); then
            export "${extra[@]}"
        fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes locale
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

printf -- '--- cell: metadata + opt-in default\n'
line="$(FS_MODULES_DIR="$ROOT/modules" FS_DISTRO_FAMILY=rpm "$SETUP" list 2>/dev/null | grep -P '^locale\t' || :)"
[[ "$line" == "locale	System locale (systemd)	destructive	off	-" ]] && fx_ok \
    || fx_bad "setup list row wrong: $line"
for p in minimal desktop developer full; do
    if grep -qx "locale" "$ROOT/profiles/$p.conf" 2>/dev/null; then
        fx_bad "profile $p includes locale"
    else
        fx_ok
    fi
done

printf -- '--- cell: dry-run, default locale: exact plan, zero probes\n'
lc_reset
rm -rf "$FX_TMP/l_dry"
lc_run l_dry "dry default" 0 1
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok \
    || fx_bad "dry plan is 1 line (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out '# would run: sudo localectl set-locale LANG=en_US.UTF-8'
fx_out 'the readback check cannot run in dry-run'
fx_empty "dry-run probed nothing" "$OPS"
if [[ -e "$FX_TMP/l_dry" ]]; then fx_bad "dry-run created state"; else fx_ok; fi
if [[ "$(cat "$LCCONF")" == "LANG=\"$FX_LC_PRIOR\"" ]]; then fx_ok; else fx_bad "dry-run rewrote the locale"; fi

printf -- '--- cell: dry-run with an explicit locale, and no backup\n'
lc_reset
rm -rf "$FX_TMP/l_dry2"
lc_run l_dry2 "dry explicit" 0 1 'FS_LOCALE=ar_EG.UTF-8'
fx_out '# would run: sudo localectl set-locale LANG=ar_EG.UTF-8'
fx_empty "dry explicit probed nothing" "$OPS"

printf -- '--- cell: non-systemd host: graceful skip\n'
lc_reset
rm -rf "$FX_TMP/l_nonm" "$FX_TMP/farm_nolc"
: >"$OPS"
mkdir -p "$FX_TMP/farm_nolc"
for d in /usr/local/bin /usr/bin /bin; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
        [[ -x "$f" && -f "$f" ]] || continue
        [[ "${f##*/}" == localectl ]] && continue
        ln -sf "$f" "$FX_TMP/farm_nolc/${f##*/}" 2>/dev/null || :
    done
done
if [[ -e "$FX_TMP/farm_nolc/localectl" ]]; then
    fx_bad "could not build a PATH without localectl"
else
    fx_ok
fi
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/l_nonm"
    export PATH="$FX_TMP/farm_nolc"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_LC_CONF="$LCCONF" FS_LOCALE_CONF="$LCCONF"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_LOCALE FS_LOCALE_REVERT 2>/dev/null || :
    "$SETUP" install --yes locale
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "non-systemd rc" 0
fx_out 'localectl not found (not a systemd host); skipping'
if grep -q '^# would run:' "$FX_OUT"; then fx_bad "non-systemd host rendered a plan"; else fx_ok; fi
if grep -q 'set-locale' "$OPS"; then fx_bad "ran set-locale without systemd"; else fx_ok; fi

printf -- '--- cell: an unavailable locale fails closed before any write\n'
lc_reset
rm -rf "$FX_TMP/l_unknown"
lc_run l_unknown "unknown locale" 1 0 'FS_LOCALE=zz_ZZ.UTF-8'
fx_err 'locale not available on this system: zz_ZZ.UTF-8'
fx_err 'generate it first'
if grep -q 'set-locale' "$OPS"; then fx_bad 'set an unavailable locale'; else fx_ok; fi
if find "$FX_TMP/l_unknown" -path '*backups/files*' 2>/dev/null | grep -q .; then
    fx_bad 'backed up before the locale check'
else
    fx_ok
fi
if [[ -e "$(STATE_SUBDIR l_unknown)/notes/locale" ]]; then
    fx_bad 'recorded a change it refused to make'
else
    fx_ok
fi

printf -- '--- cell: list-locales that cannot be read does not block a valid locale\n'
lc_reset
rm -rf "$FX_TMP/l_nolist"
lc_run l_nolist "list-locales fails" 0 0 'FS_FAKE_LC_LIST_RC=1'
fx_out 'system LANG is now en_US.UTF-8'

printf -- '--- cell: real apply takes a timestamped backup, records, then reads back\n'
lc_reset
rm -rf "$FX_TMP/l_apply"
lc_run l_apply "apply" 0 0
fx_out 'system LANG is now en_US.UTF-8'
[[ "$(cat "$LCCONF")" == 'LANG="en_US.UTF-8"' ]] && fx_ok || fx_bad "fake locale not written"
bkps="$(find "$(STATE_SUBDIR l_apply)" -path '*backups/files*' -name 'locale.conf.*' 2>/dev/null | wc -l)"
[[ "$bkps" -ge 1 ]] && fx_ok || fx_bad "no timestamped backup of locale.conf (found $bkps)"
[[ "$(cat "$(STATE_SUBDIR l_apply)/notes/locale")" == "$FX_LC_PRIOR" ]] && fx_ok \
    || fx_bad "prior-LANG record wrong: $(cat "$(STATE_SUBDIR l_apply)/notes/locale" 2>/dev/null)"
[[ -f "$(STATE_SUBDIR l_apply)/modules/locale" ]] && fx_ok || fx_bad "module not marked done"
# fs_backup is a lib/fs.sh primitive: it copies directly and does NOT go
# through run_cmd, so the audit assertion is the backup REGISTRY, not $OPS.
reg="$(STATE_SUBDIR l_apply)/backups/registry"
if [[ -f "$reg" ]] && grep -qE "^$LCCONF\|.*/locale\.conf\.[0-9]{8}T[0-9]{6}\.[0-9]+" "$reg"; then
    fx_ok
else
    fx_bad "backup not timestamped+registered in the registry: $(cat "$reg" 2>/dev/null)"
fi
# The backup must be a real copy of the pre-change file, not an empty stub.
bkp="$(find "$(STATE_SUBDIR l_apply)" -path '*backups/files*' -name 'locale.conf.*' | head -1)"
[[ -n "$bkp" && "$(cat "$bkp")" == "LANG=\"$FX_LC_PRIOR\"" ]] && fx_ok \
    || fx_bad "backup does not hold the pre-change content: $bkp"
fx_out_not 'LC_ALL'

printf -- '--- cell: apply order is read, backup, set-locale, read back\n'
lc_reset
rm -rf "$FX_TMP/l_order"
lc_run l_order "apply order" 0 0
got="$(grep -v 'list-locales' "$OPS")"
expected="localectl status
localectl set-locale LANG=en_US.UTF-8
localectl status"
[[ "$got" == "$expected" ]] && fx_ok || fx_bad "apply order wrong:
--- got
$got
--- want
$expected"

printf -- '--- cell: a repeat run backs up again and never clobbers the first\n'
lc_reset
rm -rf "$FX_TMP/l_repeat"
lc_run l_repeat "first apply" 0 0
first="$(find "$(STATE_SUBDIR l_repeat)" -path '*backups/files*' -name 'locale.conf.*' | head -1)"
lc_set ar_EG.UTF-8
rm -f -- "$(STATE_SUBDIR l_repeat)/modules/locale"
lc_run l_repeat "second apply" 0 0
second="$(find "$(STATE_SUBDIR l_repeat)" -path '*backups/files*' -name 'locale.conf.*' | sort | tail -1)"
if [[ -n "$first" && -n "$second" && "$first" != "$second" ]]; then fx_ok; else fx_bad "second run reused the first backup name"; fi
if [[ -f "$first" ]]; then fx_ok; else fx_bad "the first backup was clobbered"; fi
[[ "$(cat "$LCCONF")" == 'LANG="en_US.UTF-8"' ]] && fx_ok || fx_bad "second apply did not take effect"

printf -- '--- cell: idempotent re-apply changes nothing\n'
lc_set en_US.UTF-8
rm -rf "$FX_TMP/l_idem"
lc_run l_idem "idempotent" 0 0
fx_out 'LANG is already en_US.UTF-8; no change'
if grep -q 'set-locale' "$OPS"; then fx_bad "re-applied an already-correct LANG"; else fx_ok; fi
if [[ -e "$(STATE_SUBDIR l_idem)/notes/locale" ]]; then
    fx_bad "recorded a change it never made"
else
    fx_ok
fi
if find "$(STATE_SUBDIR l_idem)" -path '*backups/files*' -name 'locale.conf.*' 2>/dev/null | grep -q .; then
    fx_bad "backed up a file it never changed"
else
    fx_ok
fi

printf -- '--- cell: set-locale that does not stick fails the postcondition\n'
lc_reset
rm -rf "$FX_TMP/l_post"
lc_run l_post "postcondition" 1 0 'FS_FAKE_LC_SETNOOP=1'
fx_err 'LANG was not applied'
fx_err 'module failed: locale'
fx_err 'stopping run (destructive module locale)'
if [[ -f "$(STATE_SUBDIR l_post)/modules/locale" ]]; then
    fx_bad "marked done after a failed change"
else
    fx_ok
fi
if [[ -f "$(STATE_SUBDIR l_post)/notes/locale" ]]; then
    fx_ok
else
    fx_bad "discarded the revert record after a failed change"
fi

printf -- '--- cell: revert restores the exact recorded value\n'
lc_reset
lc_set ar_EG.UTF-8
rm -rf "$FX_TMP/l_rev"
lc_run l_rev "apply for revert" 0 0 'FS_LOCALE=en_US.UTF-8'
[[ "$(cat "$(STATE_SUBDIR l_rev)/notes/locale")" == "ar_EG.UTF-8" ]] && fx_ok \
    || fx_bad "record before revert wrong"
rm -f -- "$(STATE_SUBDIR l_rev)/modules/locale"
lc_set en_US.UTF-8
lc_run l_rev "revert" 0 0 'FS_LOCALE=en_US.UTF-8' 'FS_LOCALE_REVERT=1'
fx_out 'reverting LANG to ar_EG.UTF-8'
fx_out 'revert complete (LANG=ar_EG.UTF-8)'
[[ "$(cat "$LCCONF")" == 'LANG="ar_EG.UTF-8"' ]] && fx_ok || fx_bad "revert did not restore the prior locale"
if [[ -e "$(STATE_SUBDIR l_rev)/notes/locale" ]]; then
    fx_bad "revert left the record behind"
else
    fx_ok
fi

printf -- '--- cell: revert with no record is a no-op\n'
lc_reset
rm -rf "$FX_TMP/l_norec"
lc_run l_norec "revert no record" 0 0 'FS_LOCALE_REVERT=1'
fx_out 'no recorded change; nothing to revert'
if grep -q 'set-locale' "$OPS"; then fx_bad "reverted without a record"; else fx_ok; fi

printf -- '--- cell: a revert that does not stick keeps the record\n'
lc_reset
rm -rf "$FX_TMP/l_revpost"
lc_set ar_EG.UTF-8
lc_run l_revpost "apply for revpost" 0 0
rm -f -- "$(STATE_SUBDIR l_revpost)/modules/locale"
lc_set en_US.UTF-8
lc_run l_revpost "revert postcondition" 1 0 'FS_LOCALE_REVERT=1' 'FS_FAKE_LC_SETNOOP=1'
fx_err 'revert did not take effect'
fx_err_not 'revert complete'
if [[ -f "$(STATE_SUBDIR l_revpost)/notes/locale" ]]; then
    fx_ok
else
    fx_bad "revert deleted the record after a failed postcondition"
fi

printf -- '--- cell: a malformed record fails closed\n'
lc_reset
rm -rf "$FX_TMP/l_badrec"
mkdir -p "$(STATE_SUBDIR l_badrec)/notes"
printf 'has space\n' >"$(STATE_SUBDIR l_badrec)/notes/locale"
lc_run l_badrec "bad record" 1 0 'FS_LOCALE_REVERT=1'
fx_err 'invalid locale in record'
if grep -q 'set-locale' "$OPS"; then fx_bad "reverted from a malformed record"; else fx_ok; fi

printf -- '--- cell: invalid FS_LOCALE fails closed before any command\n'
lc_reset
rm -rf "$FX_TMP/l_bad1"
lc_run l_bad1 "bad locale value" 1 0 'FS_LOCALE=en_US.UTF-8 extra'
fx_err 'invalid locale value'
if [[ -s "$OPS" ]]; then fx_bad "probed after an invalid locale"; else fx_ok; fi
lc_reset
rm -rf "$FX_TMP/l_bad2"
lc_run l_bad2 "quoting locale" 1 0 'FS_LOCALE=it'"'"'s'
fx_err 'invalid locale value'
if [[ -s "$OPS" ]]; then fx_bad "probed after a quoting locale"; else fx_ok; fi

printf -- '--- cell: a missing locale.conf is not an error\n'
lc_reset
rm -f -- "$LCCONF"
rm -rf "$FX_TMP/l_noconf"
lc_run l_noconf "no locale.conf" 0 0 'FS_LOCALE=ar_EG.UTF-8'
fx_out 'system LANG is now ar_EG.UTF-8'
if find "$(STATE_SUBDIR l_noconf)" -path '*backups/files*' 2>/dev/null | grep -q .; then
    fx_bad "backed up a file that did not exist"
else
    fx_ok
fi

printf -- '--- cell: locale.conf is never written directly and never sourced\n'
if grep -rn 'tee \|>> */etc/locale.conf\|> */etc/locale.conf\|source .*locale.conf\|\. .*locale.conf' \
    "$ROOT/modules/locale/" >/dev/null 2>&1; then
    fx_bad "module writes or sources locale.conf directly"
    grep -rn 'tee \|>> */etc/locale.conf\|> */etc/locale.conf\|source .*locale.conf\|\. .*locale.conf' \
        "$ROOT/modules/locale/" >&2 || :
else
    fx_ok
fi
fx_out_not 'LC_ALL'

printf -- '--- cell: verify() paths\n'
lc_reset
rm -rf "$FX_TMP/l_verify"
lc_run l_verify "verify seed" 0 0
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_OPS="$OPS" FS_LC_CONF="$LCCONF" FS_LOCALE_CONF="$LCCONF"
    export FS_DRY_RUN=1
    unset FS_LOCALE_REVERT 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/locale/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry rc" 0
fx_out 'verify skipped in dry-run'
lc_set en_US.UTF-8
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_OPS="$OPS" FS_LC_CONF="$LCCONF" FS_LOCALE_CONF="$LCCONF"
    unset FS_DRY_RUN FS_LOCALE 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/locale/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify pass rc" 0
fx_out 'verify passed (LANG=en_US.UTF-8)'
lc_set en_US.UTF-8
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_OPS="$OPS" FS_LC_CONF="$LCCONF" FS_LOCALE_CONF="$LCCONF"
    export FS_LOCALE=ar_EG.UTF-8
    unset FS_DRY_RUN 2>/dev/null || :
    . "$ROOT/lib/io.sh"
    . "$ROOT/lib/run.sh"
    . "$ROOT/lib/state.sh"
    source "$ROOT/modules/locale/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify fail rc" 1
fx_err 'LANG is en_US.UTF-8, expected ar_EG.UTF-8'

printf -- '--- cell: non-TTY without --yes never runs a destructive module\n'
lc_set "$FX_LC_PRIOR"
rm -rf "$FX_TMP/l_noyes"
: >"$OPS"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/l_noyes"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_EUID=0
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_OPS="$OPS" FS_LC_CONF="$LCCONF" FS_LOCALE_CONF="$LCCONF"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_LOCALE FS_LOCALE_REVERT 2>/dev/null || :
    "$SETUP" install locale < /dev/null
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no --yes, no TTY rc" 1
fx_out 'locale - System locale (systemd)'
# fx_out greps with a BRE, so the brackets need escaping or they read as a
# character class and the pin silently never matches.
fx_out '\[x\] locale - .*\[high-risk\]'
fx_empty "no --yes reached localectl" "$OPS"
if [[ "$(cat "$LCCONF")" == "LANG=\"$FX_LC_PRIOR\"" ]]; then fx_ok; else fx_bad "no --yes changed the locale"; fi
if [[ -f "$(STATE_SUBDIR l_noyes)/modules/locale" ]]; then
    fx_bad "marked done without --yes"
else
    fx_ok
fi

printf -- '--- cell: the fake-localectl guard is not vacuous\n'
rm -rf "$FX_TMP/farm_leak"
mkdir -p "$FX_TMP/farm_leak"
for d in /usr/local/bin /usr/bin /bin; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
        [[ -x "$f" && -f "$f" ]] || continue
        [[ "${f##*/}" == localectl ]] && continue
        ln -sf "$f" "$FX_TMP/farm_leak/${f##*/}" 2>/dev/null || :
    done
done
PATH="$FX_TMP/farm_leak:$PATH"
export PATH
if _lc_is_fake "$FX_TMP/farm_leak"; then
    fx_bad "guard accepted a PATH whose localectl is the real binary"
else
    fx_ok
fi
if [[ -x "$FX_TMP/farm_leak/localectl" ]]; then
    fx_bad "farm_leak unexpectedly has a localectl"
else
    fx_ok
fi
PATH="$FX_TMP/fakebin:$PATH"
export PATH
guard_fake_lc "$FX_TMP/fakebin"

fx_summary
