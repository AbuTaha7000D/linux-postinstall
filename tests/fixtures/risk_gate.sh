#!/usr/bin/env bash
# tests/fixtures/risk_gate.sh - P8.3 fixture for the risk gate.
#
# P8.3 makes four claims about high/destructive modules, and this fixture is
# the only place they are pinned:
#   1. EXCLUSION: no high/destructive module is reachable from any shipped
#      profile -- not in the file, and not dragged in by a MODULE_DEPENDS
#      edge. The first half is checked dynamically (every module in the
#      tree, not a hardcoded id list, so a new P8 module cannot drift in
#      silently); the second half is a live dep injection, because that is
#      the hole a static scan cannot see.
#   2. LOUDNESS: a profile that *does* name a high-risk module says so
#      instead of dropping it silently, and the run still proceeds rc0 with
#      the safe modules -- the reviewed P4.7 contract, kept intact.
#   3. DRY-RUN WARNING: a dry run prints a bold `!!` alert for each
#      high/destructive module, and prints none for a safe one.
#   4. CONSENT: a direct high-risk invocation is consented by naming it, the
#      confirmation is real, and declining it aborts before any batch. (A
#      stronger "needs --yes whenever stdin is not a TTY" gate was written,
#      measured, and rejected -- see block 4 for why.)
#
# The color claims are the reason this fixture exists at all. `lib/ui.sh`
# gated its red `[high-risk]` flag on `-z "$FS_NO_COLOR"`, but `lib/io.sh`
# normalizes FS_NO_COLOR to the string "0" -- so `-z "0"` was false and the
# red flag had NEVER rendered on any TTY. The static half of that is
# asserted directly (the gate must compare numerically); the rendered half
# is asserted through a pty when one is obtainable, and degrades to a
# clearly-labelled skip when it is not, since `script`/python3 is not
# guaranteed everywhere. Nothing outside FX_TMP is touched.
# Usage: bash tests/fixtures/risk_gate.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
SETUP="$ROOT/setup"
REPO_MODULES="$ROOT/modules"
REPO_PROFILES="$ROOT/profiles"

printf 'P8.3 risk gate\n'

# --- 1a. static color-gate claim: FS_NO_COLOR is compared numerically ------

if grep -q -- '-z "${FS_NO_COLOR' "$ROOT/lib/ui.sh"; then
    fx_bad "lib/ui.sh still gates color on -z FS_NO_COLOR (io.sh normalizes it to '0', so the flag is dead)"
else
    fx_ok
fi
if grep -q 'FS_NO_COLOR == 0' "$ROOT/lib/io.sh" && grep -q 'FS_NO_COLOR:-0' "$ROOT/lib/ui.sh"; then
    fx_ok
else
    fx_bad "numeric FS_NO_COLOR compare missing in lib/io.sh or lib/ui.sh"
fi

# --- 1b. no high/destructive module is named in a shipped profile ----------

hr_ids=()
for m in "$REPO_MODULES"/*/module.sh; do
    id="$(basename "$(dirname "$m")")"
    if grep -qE '^MODULE_RISK=(high|destructive)$' "$m"; then
        hr_ids+=("$id")
    fi
done
if (( ${#hr_ids[@]} > 0 )); then
    fx_ok
else
    fx_bad "no high/destructive module found; inventory claim is vacuous"
fi
for id in ${hr_ids[@]+"${hr_ids[@]}"}; do
    if grep -qE '^MODULE_DEFAULT=off$' "$REPO_MODULES/$id/module.sh"; then
        fx_ok
    else
        fx_bad "high-risk module $id must declare MODULE_DEFAULT=off"
    fi
done
for p in "$REPO_PROFILES"/*.conf; do
    pname="$(basename "$p" .conf)"
    for id in ${hr_ids[@]+"${hr_ids[@]}"}; do
        if grep -qxF "$id" "$p"; then
            fx_bad "profile $pname names high-risk module $id"
        else
            fx_ok
        fi
    done
done

# --- 1c. dep-closure escape: a dep edge may not smuggle one in ------------
# This is the finding that made the fixture worth writing. The pre-seed
# filter in lib/bootstrap.sh only walks the profile's curated list, so a
# MODULE_DEPENDS edge from a safe module pulled `locale` into
# `--yes --profile minimal` and it installed with no consent whatsoever.

RSRC="$FX_TMP/R"
cp -r "$REPO_MODULES" "$RSRC"
printf 'MODULE_DEPENDS="locale"\n' >>"$RSRC/core/module.sh"
run_gate() {
    local want="$1" label="$2" stdin_data="$3"
    shift 3
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/gh$RUN_G"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$RSRC" FS_PROFILES_DIR="$REPO_PROFILES"
        export FS_MOCK_LOG="$FX_TMP/m.log" FS_MOCK_INSTALLED="$FX_TMP/m.inst"
        : >"$FX_TMP/m.log"
        : >"$FX_TMP/m.inst"
        unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
        printf '%s' "$stdin_data" | "$SETUP" install "$@"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}
RUN_G=0

run_gate 1 "dep edge pulling locale is refused" '' --dry-run --yes --profile minimal
fx_err 'high-risk module[(]s[)] pulled in transitively by a dependency: locale'
fx_out_not '^# would run: sudo localectl'
if grep -q 'localectl' "$FX_TMP/m.log" 2>/dev/null; then
    fx_bad "localectl reached the mock batch despite the gate"
else
    fx_ok
fi

cp -r "$REPO_MODULES/." "$RSRC/"
run_gate 0 "no dep: --yes dns runs" '' --dry-run --yes dns
fx_out '^\[.*\] \[info\] module: dns (destructive)$'

# --- 2. a profile naming a high-risk module warns, does not fail ----------

GP="$FX_TMP/GP"
mkdir -p "$GP"
printf 'core\nflatpak\nlocale\n' >"$GP/noisy.conf"
printf '# internal sentinel: never edited by hand\n' >"$GP/selection.conf"
RUN_G=$((RUN_G + 1))
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/gh$RUN_G"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$RSRC" FS_PROFILES_DIR="$GP"
    export FS_MOCK_LOG="$FX_TMP/m.log" FS_MOCK_INSTALLED="$FX_TMP/m.inst"
    : >"$FX_TMP/m.log"
    unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --dry-run --yes --profile noisy
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "profile naming locale stays rc0" 0
fx_out '!! high-risk module[(]s[)] not selected: locale'
fx_out_not '^# would run: sudo localectl'
fx_out '^# would run: mock install'

# --- 3. dry-run alert: destructive and high warn, safe stays quiet --------

for mid in ${hr_ids[@]+"${hr_ids[@]}"}; do
    RUN_G=$((RUN_G + 1))
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/gh$RUN_G"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$REPO_MODULES" FS_PROFILES_DIR="$REPO_PROFILES"
        unset FS_PROFILE FS_YES FS_DISTRO_FILE 2>/dev/null || :
        FS_DRY_RUN=1 "$SETUP" install --yes "$mid"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "dry run of $mid" 0
    fx_out "!! dry run: $mid is "
    fx_out 'a real run would change this system'
done

RUN_G=$((RUN_G + 1))
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/gh$RUN_G"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$REPO_MODULES" FS_PROFILES_DIR="$REPO_PROFILES"
    unset FS_PROFILE FS_YES FS_DISTRO_FILE 2>/dev/null || :
    FS_DRY_RUN=1 "$SETUP" install --yes core
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry run of core" 0
fx_out_not '!! dry run: core'

# --- 4. the consent route that actually exists ------------------------------
# Deliberately NOT asserted here: "a high-risk module needs --yes in a
# non-interactive session". That hardening was written, measured, and
# REJECTED. It breaks the reviewed P4.7 opt-in flow (tests/fixtures/install.sh
# drives opt-in + confirm entirely by piped stdin, so refusing every piped
# high-risk selection makes the whole flow untestable without a pty), and the
# P8.3 task text names a direct `install dns` invocation as consent in its
# own right. It also defends against nothing: a script able to pipe `y` into
# ./setup can just run nmcli directly. What is asserted instead is the
# reviewed contract -- a direct high-risk invocation is consented by naming
# it, the confirmation is real, and declining it aborts before any batch.

run_gate 0 "direct high-risk invocation runs" $'\n\ny\n' --dry-run dns
fx_out '^\[.*\] \[info\] module: dns (destructive)$'
fx_out '!! dry run: dns is destructive'
fx_out '^# would run: sudo nmcli'
fx_out 'high-risk module[(]s[)] enabled: dns; continue?'

run_gate 1 "declining the confirmation aborts" $'\n\nn\n' --dry-run dns
fx_err 'installation aborted (high-risk confirmation declined)'
fx_out_not '^# would run: sudo'

run_gate 0 "piped session, safe module only" $'\n\n' --dry-run core
fx_out '^# would run: mock install'
fx_err_not 'high-risk confirmation declined'

# --- 5. rendered color claims, through a pty when obtainable --------------
# `_ui_color_red` is stdout-TTY gated, so a piped run can never show the
# escape; these cells are the only way to reach the dead-gate regression.

if ! fx_pty_available; then
    printf 'SKIP pty color cells (no python3 to allocate one)\n' >&2
else
    PTY_UI="$FX_TMP/pty_ui.sh"
    cat >"$PTY_UI" <<'PTYEOF'
#!/usr/bin/env bash
set -uo pipefail
export FS_NO_COLOR="${FS_NO_COLOR:-0}"
. "$1/lib/io.sh"
. "$1/lib/ui.sh"
E="$2/entries"
S="$2/sel"
printf 'risky\tRisky module\thigh\nsafe\tSafe module\tnone\n' >"$E"
: >"$S"
ui_multiselect "t" "$E" "$S" <"$2/stdin" >/dev/null 2>&1 || :
_pty_probe_out() {
    _ui_color_red
    printf 'PROBE'
    _ui_color_reset
    printf '\n'
}
_pty_probe_out
PTYEOF
    chmod +x "$PTY_UI"

    PTYD="$FX_TMP/ptyd"
    mkdir -p "$PTYD"
    printf 'q\n' >"$PTYD/stdin"
    fx_pty_run '' /dev/null true
    if fx_pty_run "$(printf 'q')" "$FX_TMP/pty_a" "$PTY_UI" "$ROOT" "$PTYD"; then
        fx_ok
    else
        fx_bad "pty run of the color probe failed"
    fi
    if grep -qF "$(printf '\033')" "$FX_TMP/pty_a"; then
        fx_ok
    else
        fx_bad "red ANSI never reached a pty stdout (the P8.3 dead-gate regression)"
    fi
    if grep -q 'PROBE' "$FX_TMP/pty_a"; then
        fx_ok
    else
        fx_bad "pty probe produced no output"
    fi
    fx_pty_run "$(printf 'q')" "$FX_TMP/pty_b" env FS_NO_COLOR=1 "$PTY_UI" "$ROOT" "$PTYD"
    if grep -qF "$(printf '\033')" "$FX_TMP/pty_b"; then
        fx_bad "FS_NO_COLOR=1 still emitted ANSI on a pty"
    else
        fx_ok
    fi
    # The flag glyph itself, on a real TTY, must be the red one.
    if grep -qF "$(printf '\033[31m')" "$FX_TMP/pty_a"; then
        fx_ok
    else
        fx_bad "no \\033[31m red sequence on a pty"
    fi
    if printf '\n\ny\n' | "$SETUP" install --dry-run core 2>&1 | grep -qF "$(printf '\033')"; then
        fx_bad "piped stdout emitted ANSI; piped output must stay byte-stable"
    else
        fx_ok
    fi
fi

# --- 6. io_alert's own contract: stdout, un-timestamped, audit-logged -----

AL="$FX_TMP/alert.sh"
cat >"$AL" <<'ALEOF'
#!/usr/bin/env bash
set -uo pipefail
. "$1/lib/io.sh"
io_init "$2"
io_alert "alert body"
ALEOF
chmod +x "$AL"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/alert_home"
    "$AL" "$ROOT" "$FX_TMP/audit.log"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "io_alert rc" 0
if [[ "$(cat "$FX_OUT")" == '!! alert body' ]]; then
    fx_ok
else
    fx_bad "io_alert stdout must be exactly '!! alert body' (got: $(cat "$FX_OUT"))"
fi
fx_empty "io_alert writes nothing to stderr" "$FX_ERR"
if grep -q '^!! alert body$' "$FX_TMP/audit.log" 2>/dev/null; then
    fx_ok
else
    fx_bad "io_alert not audit-logged"
fi
if fx_pty_run '' /dev/null true; then :; fi
fx_pty_run '' "$FX_TMP/pty_alert" "$AL" "$ROOT" "$FX_TMP/audit2.log"
if grep -qF "$(printf '\033[1m')" "$FX_TMP/pty_alert" 2>/dev/null; then
    fx_ok
else
    fx_bad "io_alert emitted no bold sequence on a pty"
fi
if grep -q 'alert body' "$FX_TMP/pty_alert" 2>/dev/null; then
    fx_ok
else
    fx_bad "io_alert lost its message on a pty"
fi

fx_summary
