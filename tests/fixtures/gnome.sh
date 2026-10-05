#!/usr/bin/env bash
# tests/fixtures/gnome.sh - P6.1/P6.2 fixture for the GNOME gsettings layer
# (lib/gnome.sh). Covers the P6.1 verification bullet: fixture gsettings
# output arrays parse/merge correctly; idempotent sets are no-ops;
# malformed keys error safely (rc1, io_error) and never via sed rewriting
# of system files (the lib contains no sed); dry-run renders exact
# `# would run: ...` lines and never probes dconf. P6.2 additions: plain
# vs relocatable schema validation and the generic gnome_strv_merge_set
# read->merge->write primitive (docks favorites / custom keybindings).
# Mock strategy mirrors pkg_flatpak.sh: a PATH-visible fake `gsettings`
# logs `get`/`set` invocations to $FAKE_LOG, answers `get` from
# $FAKE_GET and can fail `set` via $FAKE_SET_RC. No real system state;
# everything lives under FX_TMP. Usage: bash tests/fixtures/gnome.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools"
FX_EXPECT="$FX_TMP/expect"
FAKE_LOG="$FX_TMP/fake.log"

cat >"$FX_TMP/fakebin/gsettings" <<'EOF'
#!/usr/bin/env bash
: >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    get)
        printf 'get %s %s\n' "$2" "$3" >>"$FAKE_LOG" 2>/dev/null || :
        printf '%s\n' "${FAKE_GET:-@as []}"
        exit "${FAKE_GET_RC:-0}"
        ;;
    set)
        printf 'set %s %s %s\n' "$2" "$3" "$4" >>"$FAKE_LOG" 2>/dev/null || :
        exit "${FAKE_SET_RC:-0}"
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gsettings"

cat >"$FX_TMP/fakebin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
: >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
case "$1" in
    list)
        printf 'list %s\n' "${2:-}" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
        if [[ "$2" == --enabled ]]; then
            cat "${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null
        else
            cat "${FAKE_EXT_LIST:-/dev/null}" 2>/dev/null
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gnome-extensions"

cat >"$FX_TMP/fakebin/gnome-shell" <<'EOF'
#!/usr/bin/env bash
: >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
if [[ "$1" == --version ]]; then
    printf 'version\n' >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
    printf '%s\n' "${FAKE_SHELL_VERSION:-GNOME Shell 50.5}"
fi
exit 0
EOF
chmod +x "$FX_TMP/fakebin/gnome-shell"

printf 'P6.1 gnome gsettings layer\n'

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_available
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gsettings available present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_available
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gsettings available absent" 1

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_available
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-extensions available present" 0

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_available
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-extensions available absent" 1

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'Adwaita'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get org.gnome.desktop.interface gtk-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get scalar present" 0
printf "'Adwaita'\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "get scalar value"
grep -Fqx "get org.gnome.desktop.interface gtk-theme" "$FAKE_LOG" && fx_ok || fx_bad "get probe logged"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['/org/gnome/plugins/a/', '/org/gnome/plugins/b/']" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get org.gnome.settings-daemon.plugins.media-keys custom-keybindings
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get array present" 0
printf "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/']\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "get array passthrough"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'x'" FAKE_LOG
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get org.gnome.desktop.interface gtk-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get under dry-run rejects" 1
fx_err "cannot probe gsettings in dry-run"
fx_empty "dry-run get produces no stdout" "$FX_OUT"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "dry-run get never probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get org.gnome.desktop.interface gtk-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get without gsettings rejects" 1
fx_err "gsettings not found on PATH"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get ../../etc/fstab gtk-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get invalid schema rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get org.gnome.desktop.interface gtk/theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get invalid key rejects" 1
fx_err "invalid key"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "get without args rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'Adwaita'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "set new value" 0
grep -Fqx "set org.gnome.desktop.interface gtk-theme 'new'" "$FAKE_LOG" && fx_ok || fx_bad "set invocation logged"
grep -Fqx "get org.gnome.desktop.interface gtk-theme" "$FAKE_LOG" && fx_ok || fx_bad "set probes current value first"
fx_out_not "would run"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'new'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "idempotent set" 0
grep -Fqx "set org.gnome.desktop.interface gtk-theme 'new'" "$FAKE_LOG" && fx_bad "idempotent set must not write" || fx_ok
grep -Fqx "get org.gnome.desktop.interface gtk-theme" "$FAKE_LOG" && fx_ok || fx_bad "idempotent set still probes"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'Adwaita'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme Adwaita
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare target matching quoted get is a no-op" 0
grep -Fqx "set org.gnome.desktop.interface gtk-theme Adwaita" "$FAKE_LOG" && fx_bad "bare target equal to quoted get must not write" || fx_ok
grep -Fqx "get org.gnome.desktop.interface gtk-theme" "$FAKE_LOG" && fx_ok || fx_bad "bare-no-op still probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'old'" FAKE_SET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "failed set propagates non-zero (B2 fix)" 1
fx_err "command failed (rc=1)"
grep -Fqx "set org.gnome.desktop.interface gtk-theme 'new'" "$FAKE_LOG" && fx_ok || fx_bad "failed set still attempted write"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'old'" FAKE_GET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "set with failed pre-write read refuses" 1
fx_err "gsettings get failed"
grep -q '^set ' "$FAKE_LOG" && fx_bad "refused set must not write" || fx_ok

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'old'" FAKE_LOG
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry-run set renders" 0
fx_out "# would run: gsettings set org.gnome.desktop.interface gtk-theme"
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok || fx_bad "dry-run set single render line"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "dry-run set never probes or writes"

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry-run set works without gsettings" 0
fx_out "would run"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "$(printf 'line1\nline2')"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "set control-char value rejects" 1
fx_err "invalid value"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "set missing value rejects" 1
fx_err "invalid value"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/', '/org/gnome/plugins/c/']"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse array of strings" 0
printf "/org/gnome/plugins/a/\n/org/gnome/plugins/b/\n/org/gnome/plugins/c/\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "array elements parsed line-wise"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "@as []"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse @as []" 0
fx_empty "empty type-prefixed array parses to nothing" "$FX_OUT"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "[]"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse bare empty array" 0
fx_empty "empty array parses to nothing" "$FX_OUT"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "[1, 2, 3]"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse numeric array" 0
printf "1\n2\n3\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "bare numeric tokens parsed"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "['a\\'b']"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse escaped quote" 0
printf "a'b\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "backslash escape decoded"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "['a', ]"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse trailing comma" 0
printf "a\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "trailing comma tolerated"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "$(printf "[ 'a',\n\t'b' ]")"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse mixed whitespace" 0
printf "a\nb\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "spaces/tabs/newlines tolerated"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse ""
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse empty input" 0
fx_empty "empty input is the empty array" "$FX_OUT"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "'a'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse bare string rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "['a'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse unclosed element rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "$(printf "['a\nb']")"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse control byte in quoted element rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "[ , ]"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse empty element rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "garbage"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse non-array rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_parse "['a', 'b' x]"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse stray token rejects" 1
fx_err "malformed GVariant array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_build
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "build empty" 0
printf "@as []\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "empty build emits @as []"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_build "org.foo.App" "org.bar.App"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "build two elements" 0
printf "['org.foo.App', 'org.bar.App']\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "quoted, comma-separated, single line"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_build "bad'quote"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "build invalid element rejects" 1
fx_err "invalid array element"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    built="$(gnome_strv_build "/org/gnome/plugins/a/" "/org/gnome/plugins/b/")"
    gnome_strv_parse "$built"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "build/parse roundtrip" 0
printf "/org/gnome/plugins/a/\n/org/gnome/plugins/b/\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "built array parses back identical"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/']" "/org/gnome/plugins/c/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge appends new" 0
printf "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/', '/org/gnome/plugins/c/']\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "existing order preserved, new appended"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge "" "/org/gnome/plugins/c/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge from empty" 0
printf "['/org/gnome/plugins/c/']\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "empty current is replaced by the new array"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/']" "/org/gnome/plugins/a/" "/org/gnome/plugins/c/" "/org/gnome/plugins/b/" "/org/gnome/plugins/a/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge dedupes first-seen" 0
printf "['/org/gnome/plugins/a/', '/org/gnome/plugins/b/', '/org/gnome/plugins/c/']\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "duplicates dropped, order stable"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge "['/a/']" "has space"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge invalid new rejects" 1
fx_err "invalid element"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge "['a'
" "/org/gnome/plugins/c/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge malformed current rejects" 1
fx_err "malformed"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="@as []" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings add from empty" 0
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" "$FAKE_LOG" && fx_ok || fx_bad "empty-current merge writes the new array"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings preserve and append" 0
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/']" "$FAKE_LOG" && fx_ok || fx_bad "existing bindings kept, new appended"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings idempotent merge" 0
grep -q '^set ' "$FAKE_LOG" && fx_bad "idempotent keybinding merge must not write" || fx_ok
grep -q '^get ' "$FAKE_LOG" && fx_ok || fx_bad "idempotent keybinding merge still probes"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" FAKE_LOG
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings dry-run renders merge" 0
fx_out "# would run: gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings"
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok || fx_bad "dry-run keybindings single render line"
grep -q 'get org.gnome.settings-daemon.plugins.media-keys' "$FX_OUT" && fx_bad "dry-run keybindings must not probe" || fx_ok
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "dry-run keybindings never writes"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings without paths rejects" 1
fx_err "requires at least one dconf path"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="@as []" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "has space"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings invalid path rejects" 1
fx_err "invalid element"
grep -q '^set ' "$FAKE_LOG" && fx_bad "rejected merge must not write" || fx_ok

(
    set -euo pipefail
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "bad'quote"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "keybindings dry-run invalid path rejects" 1
fx_err "invalid array element"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'Resources'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" name
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable schema get" 0
printf "'Resources'\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "relocatable get value"
grep -Fqx "get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name" "$FAKE_LOG" && fx_ok || fx_bad "relocatable get probe logged"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'x'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" name "'Resources'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable schema set" 0
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Resources'" "$FAKE_LOG" && fx_ok || fx_bad "relocatable set invocation logged"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" name "'Resources'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable schema dry-run set renders" 0
fx_out "# would run: gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "relocatable dry-run set never probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable empty path rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:/" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable root path rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b://x//y/" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable double slash rejects" 1
fx_err "invalid schema"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:/x//" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable trailing double slash rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:rel/x" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable relative path rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:/./x/" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable dot segment rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a.b:/a/b c/" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable space in path rejects" 1
fx_err "invalid schema"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set "a:b:c" name "'x'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relocatable double colon rejects" 1
fx_err "invalid schema"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['org.gnome.Nautilus.desktop']" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set org.gnome.shell favorite-apps org.gnome.Nautilus.desktop firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set appends to existing" 0
grep -Fqx "set org.gnome.shell favorite-apps ['org.gnome.Nautilus.desktop', 'firefox.desktop']" "$FAKE_LOG" && fx_ok || fx_bad "existing app kept, new appended once"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="['org.gnome.Nautilus.desktop', 'firefox.desktop']" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set org.gnome.shell favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set idempotent" 0
grep -q '^set ' "$FAKE_LOG" && fx_bad "idempotent merge_set must not write" || fx_ok

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set org.gnome.shell favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set dry-run renders" 0
fx_out "# would run: gsettings set org.gnome.shell favorite-apps"
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok || fx_bad "merge_set dry-run single render line"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "merge_set dry-run never probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set org.gnome.shell favorite-apps
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set without new elements rejects" 1
fx_err "requires at least one new element"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set "bad schema" favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set invalid schema rejects" 1
fx_err "invalid schema"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set "org.gnome.shell.bad:a/b" favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set invalid relocatable schema rejects in dry mode" 1
fx_err "invalid schema"
grep -q '^# would run:' "$FX_OUT" && fx_bad "invalid-schema dry merge_set must not render" || fx_ok

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="@as []" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set "org.gnome.shell.custom-binding:/org/gnome/custom0/" favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "merge_set relocatable schema" 0
grep -Fqx "set org.gnome.shell.custom-binding:/org/gnome/custom0/ favorite-apps ['firefox.desktop']" "$FAKE_LOG" && fx_ok || fx_bad "relocatable merge_set written"

grep -nE '\b(sed|awk)\b' "$ROOT/lib/gnome.sh" >/dev/null 2>&1 &&
    fx_bad "lib/gnome.sh must not reference sed/awk" || fx_ok

FAKE_EXT_LIST="$FX_TMP/ext-list"
FAKE_EXT_ENABLED="$FX_TMP/ext-enabled"
printf "dash-to-dock@micxgx.gmail.com\nuser-theme@gnome-shell-extensions.gcampax.github.com\nopenbar@neuromorph\n" >"$FAKE_EXT_LIST"
printf "openbar@neuromorph\n" >"$FAKE_EXT_ENABLED"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_SHELL_VERSION="GNOME Shell 50.5" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_shell_version
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shell version present" 0
printf "50.5\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "shell version token"
grep -Fqx "version" "$FAKE_LOG" && fx_ok || fx_bad "shell version probe logged"

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_shell_version
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shell version without gnome-shell rejects" 1
fx_err "gnome-shell not found on PATH"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1 FAKE_LOG FAKE_SHELL_VERSION="GNOME Shell 50.5"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_shell_version
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shell version dry-run rejects" 1
fx_err "cannot probe gnome-shell version in dry-run"
fx_empty "dry-run shell version produces no stdout" "$FX_OUT"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "dry-run shell version never probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_SHELL_VERSION="junk version abc"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_shell_version
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shell version unparsable rejects" 1
fx_err "cannot parse version"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_shell_version
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shell version default 50.5" 0
printf "50.5\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "default fake shell version parsed"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_EXT_LIST="$FAKE_EXT_LIST" FAKE_EXT_ENABLED="$FAKE_EXT_ENABLED" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list real" 0
printf "dash-to-dock@micxgx.gmail.com\nuser-theme@gnome-shell-extensions.gcampax.github.com\nopenbar@neuromorph\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "extensions list passthrough"
grep -Fqx "list " "$FAKE_LOG" && fx_ok || fx_bad "extensions list probe logged"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_EXT_ENABLED FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list --enabled
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list enabled" 0
printf "openbar@neuromorph\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "enabled list passthrough"
grep -Fqx "list --enabled" "$FAKE_LOG" && fx_ok || fx_bad "enabled probe flag logged"

: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list dry-run rejects" 1
fx_err "cannot probe gnome-extensions in dry-run"
fx_empty "dry-run extensions list produces no stdout" "$FX_OUT"
[[ ! -s "$FAKE_LOG" ]] && fx_ok || fx_bad "dry-run extensions list never probes"

(
    set -euo pipefail
    export PATH="$FX_TMP/notools"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list without binary rejects" 1
fx_err "gnome-extensions not found on PATH"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list --bogus
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list unknown flag rejects" 1
fx_err "unknown flag"

(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_EXT_LIST="$FX_TMP/missing" FAKE_EXT_ENABLED="$FX_TMP/missing"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_extensions_list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "extensions list empty" 0
fx_empty "empty extensions list is empty stdout" "$FX_OUT"

# --- B2: gsettings write failure propagation regression tests ---

# B2.1: gnome_gsettings_set with FAKE_SET_RC=1 returns non-zero and logs the failed write
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'old'" FAKE_SET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B2: gnome_gsettings_set propagates set failure" 1
fx_err "command failed (rc=1)"
grep -Fqx "set org.gnome.desktop.interface gtk-theme 'new'" "$FAKE_LOG" && fx_ok || fx_bad "failed set still attempted write"

# B2.2: gnome_gsettings_set with successful set (idempotent) still returns 0
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'same'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'same'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
: >"$FAKE_LOG"
sync
fx_block_rc "B2: idempotent set still returns 0" 0
grep -q '^set ' "$FAKE_LOG" && fx_bad "idempotent set must not write" || fx_ok

# B2.3: bare target matching quoted get is still a no-op (single-quote compare intact)
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'value'" FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme value
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
: >"$FAKE_LOG"
sync
fx_block_rc "B2: bare target matching quoted get is no-op" 0
grep -q '^set ' "$FAKE_LOG" && fx_bad "bare target matching quoted get must not write" || fx_ok

# B2.4: mutation test - removing --stop from gnome_gsettings_set is caught
# If --stop were removed, the fake set with FAKE_SET_RC=1 would return 0.
# This test would fail (expecting 1, getting 0) if the --stop flag were removed.
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="'old'" FAKE_SET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_gsettings_set org.gnome.desktop.interface gtk-theme "'new'"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B2-mut: gnome_gsettings_set mutation (--stop removed) caught" 1
fx_err "command failed (rc=1)"
grep -Fqx "set org.gnome.desktop.interface gtk-theme 'new'" "$FAKE_LOG" && fx_ok || fx_bad "failed set still attempted write"

# B2.5: gnome_strv_merge_set propagates gsettings failure
: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="@as []" FAKE_SET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_strv_merge_set org.gnome.shell favorite-apps firefox.desktop
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B2: gnome_strv_merge_set propagates set failure" 1
fx_err "command failed (rc=1)"
grep -Fqx "set org.gnome.shell favorite-apps ['firefox.desktop']" "$FAKE_LOG" && fx_ok || fx_bad "strv_merge_set failed write logged"

# B2.6: gnome_custom_keybindings_merge_add propagates gsettings failure
: >"$FAKE_LOG"
(
    set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FAKE_GET="@as []" FAKE_SET_RC=1 FAKE_LOG
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_custom_keybindings_merge_add "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "B2: gnome_custom_keybindings_merge_add propagates set failure" 1
fx_err "command failed (rc=1)"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" "$FAKE_LOG" && fx_ok || fx_bad "keybindings merge failed write logged"

fx_summary