#!/usr/bin/env bash
# tests/fixtures/install.sh - P4.7 fixture for `./setup install` (P2.8
# installer command, first real wiring in P4.7).
# Drives the actual launcher binary with hermetic env seams (FS_HOME state
# root, FS_PKG_BACKEND=mock, FS_MODULES_DIR/FS_PROFILES_DIR overrides,
# FS_DISTRO_FAMILY) and scripted stdin through the line-mode UI. Covers:
# interactive defaults -> profile run; edits -> `selection` sentinel run;
# --yes never prompting; --yes + CLI module ids; high-risk opt-in gated
# behind an explicit confirmation (decline aborts rc1; --yes bypass);
# dry-run purity (no state dir, no mock mutations, toggles still redraw
# the plan); unknown profile/id fail loud; distro-file detection; bare-CLI
# family->backend resolution (no FS_PKG_BACKEND, no FS_DISTRO_FAMILY: the
# family detected in-caller must reach pkg_backend and select the real rpm
# backend, proven by the dnf5 dry-render); module
# registry marks persist. Nothing outside FX_TMP is touched. Mock backend
# seams: FS_MOCK_LOG + FS_MOCK_INSTALLED.
# Usage: bash tests/fixtures/install.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/M" "$FX_TMP/P" "$FX_TMP/I"

printf 'P4.7 install wiring\n'

M="$FX_TMP/M"
P="$FX_TMP/P"
SETUP="$ROOT/setup"

mkmod() {
    local id="$1" risk="${2:-none}"
    mkdir -p "$M/$id"
    {
        printf 'MODULE_ID=%s\n' "$id"
        printf 'MODULE_TITLE=Title %s\n' "$id"
        printf 'MODULE_RISK=%s\n' "$risk"
        printf 'MODULE_DEFAULT=off\n'
    } >"$M/$id/module.sh"
    printf '%s\n' "${id}1" >"$M/$id/packages.list"
}

mkmod a
mkmod b
mkmod c
mkmod extra
mkmod z high

printf 'a\nb\nc\n' >"$P/full.conf"
printf 'a\nb\nz\n' >"$P/risky.conf"
printf '# empty skeleton\n' >"$P/minimal.conf"
printf '# internal sentinel: never edited by hand\n' >"$P/selection.conf"

RUN_I=0
LAST_LOG=""
LAST_INST=""
LAST_ST=""

inst_cell() {
    local want="$1" label="$2" stdin_file="$3"
    shift 3
    RUN_I=$((RUN_I + 1))
    LAST_LOG="$FX_TMP/I/m$RUN_I.log"
    LAST_INST="$FX_TMP/I/i$RUN_I"
    LAST_ST="$FX_TMP/h$RUN_I/.local/state/fedora-setup"
    : >"$LAST_LOG"
    : >"$LAST_INST"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h$RUN_I"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
        export FS_MOCK_LOG="$LAST_LOG" FS_MOCK_INSTALLED="$LAST_INST"
        unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install "$@" <"$stdin_file"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

# --- interactive: accept defaults -> real profile name ---------------------

printf '\n\n\n' >"$FX_TMP/I/in1"
inst_cell 0 "interactive defaults run" "$FX_TMP/I/in1"
fx_out 'Select modules for profile'
fx_out '^\[x\] a - Title a$'
fx_out '^\[ \] z - Title z  \[high-risk\]$'
fx_out 'profile: full'
fx_out '^== run complete ==$'
if grep -qxF 'mock install a1 b1 c1' "$LAST_LOG"; then fx_ok; else fx_bad "defaults batch"; cat "$LAST_LOG"; fi
if [[ -f "$LAST_ST/modules/a" && -f "$LAST_ST/modules/c" ]]; then fx_ok; else fx_bad "registry marks missing"; fi

# --- selection path pre-created as a directory fails loud (mv -fT) ---------

RUN_I=$((RUN_I + 1))
mkdir -p "$FX_TMP/hs/.local/state/fedora-setup/selections/full.sel"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hs"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_MOCK_LOG="$FX_TMP/I/sel.log" FS_MOCK_INSTALLED="$FX_TMP/I/seli"
    : >"$FX_TMP/I/sel.log"
    : >"$FX_TMP/I/seli"
    unset FS_PROFILE FS_DRY_RUN FS_YES FS_DISTRO_FILE 2>/dev/null || :
    printf '\n\n\n' | "$SETUP" install
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "sel path is a directory rc1" 1
fx_err 'cannot write defaults to'

# --- interactive: edit selection -> sentinel profile -----------------------

printf '3\n\n\n' >"$FX_TMP/I/in2"
inst_cell 0 "edited selection sentinel" "$FX_TMP/I/in2"
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1' "$LAST_LOG"; then fx_ok; else fx_bad "edited batch"; cat "$LAST_LOG"; fi
if grep -q '^mock install .*c1' "$LAST_LOG"; then fx_bad "deselected module still batched"; else fx_ok; fi

# --- --yes never prompts ---------------------------------------------------

printf '' >"$FX_TMP/I/in3"
inst_cell 0 "yes bypass no prompts" "$FX_TMP/I/in3" --yes
fx_out 'profile: full'
fx_out_not 'Select modules for profile'
fx_out_not 'toggle (ids'
fx_out_not 'Enable high-risk modules'
if grep -qxF 'mock install a1 b1 c1' "$LAST_LOG"; then fx_ok; else fx_bad "yes batch"; cat "$LAST_LOG"; fi

# --- --yes + CLI ids -------------------------------------------------------

inst_cell 0 "yes cli ids appended" "$FX_TMP/I/in3" --yes extra
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 extra1' "$LAST_LOG"; then fx_ok; else fx_bad "cli batch"; cat "$LAST_LOG"; fi

# --- high-risk: opt-in + confirmation decline aborts -----------------------

printf '\nz\nn\n' >"$FX_TMP/I/in4"
inst_cell 1 "high-risk confirm declined" "$FX_TMP/I/in4"
fx_err 'installation aborted (high-risk confirmation declined)'
if [[ ! -e "$LAST_ST/modules/z" ]]; then fx_ok; else fx_bad "aborted run marked state"; fi
if grep -q '^mock install ' "$LAST_LOG"; then fx_bad "declined run still batched"; else fx_ok; fi

# --- high-risk: opt-in + confirmation accepted ----------------------------

printf '\nz\ny\n' >"$FX_TMP/I/in5"
inst_cell 0 "high-risk confirm accepted" "$FX_TMP/I/in5"
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 z1' "$LAST_LOG"; then fx_ok; else fx_bad "high-risk batch"; cat "$LAST_LOG"; fi

# --- high-risk with --yes: bypass confirm, profile closure STILL excluded --

inst_cell 0 "yes bypass high-risk excluded" "$FX_TMP/I/in3" --yes
fx_out 'profile: full'
if grep -q '^mock install .*z1' "$LAST_LOG"; then fx_bad "closure high-risk ran under --yes"; else fx_ok; fi

# --- profile-listed high-risk is STILL never seeded (preseed filter) --------

inst_cell 0 "closure high-risk never seeded" "$FX_TMP/I/in3" --yes --profile risky
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1' "$LAST_LOG"; then fx_ok; else fx_bad "risky closure batch"; cat "$LAST_LOG"; fi
if grep -q '^mock install .*z1' "$LAST_LOG"; then fx_bad "closure high-risk seeded"; else fx_ok; fi
if [[ ! -e "$LAST_ST/modules/z" ]]; then fx_ok; else fx_bad "closure high-risk marked"; fi

# --- explicit CLI id can still reach a high-risk module under --yes --------

inst_cell 0 "yes cli high-risk explicit" "$FX_TMP/I/in3" --yes z
fx_out 'profile: selection'
if grep -qxF 'mock install a1 b1 c1 z1' "$LAST_LOG"; then fx_ok; else fx_bad "cli high-risk batch"; cat "$LAST_LOG"; fi

# --- dry-run: editable, nothing persists -----------------------------------

printf '3\n\n\n' >"$FX_TMP/I/in6"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hdry"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_MOCK_LOG="$FX_TMP/I/dry.log" FS_MOCK_INSTALLED="$FX_TMP/I/dryi"
    : >"$FX_TMP/I/dry.log"
    : >"$FX_TMP/I/dryi"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install <"$FX_TMP/I/in6"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry-run edited rc" 0
fx_out '^# would run: mock install a1 b1$'
fx_out 'profile: selection'
if grep -q '^mock install ' "$FX_TMP/I/dry.log"; then fx_bad "dry run recorded mock"; else fx_ok; fi
if [[ -e "$FX_TMP/hdry/.local/state/fedora-setup" ]]; then fx_bad "dry run created state dir"; else fx_ok; fi

# --- unknown profile -------------------------------------------------------

printf '' >"$FX_TMP/I/in7"
inst_cell 1 "unknown profile" "$FX_TMP/I/in7" --yes --profile ghost
fx_err 'list file missing or not a regular file'
if [[ ! -e "$LAST_ST/modules" ]]; then fx_ok; else fx_bad "unknown profile wrote state"; fi

# --- unknown CLI id --------------------------------------------------------

inst_cell 1 "unknown cli id" "$FX_TMP/I/in3" --yes ghostid
fx_err ': ghostid'

# --- distro-file detection (no FS_DISTRO_FAMILY) ---------------------------

printf 'ID=fedora\nID_LIKE=""\n' >"$FX_TMP/I/osrel"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hdt" FS_PKG_BACKEND=mock FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/I/osrel"
    unset FS_DISTRO_FAMILY FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes <"$FX_TMP/I/in3"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "distro-file detection rc" 0
fx_out 'profile: full'

# --- bare CLI: family resolved in-caller must reach pkg_backend ------------
# Regression (pre-fix): bootstrap resolved the family via command
# substitution (subshell), so FS_DISTRO_FAMILY never reached the caller env
# and the backend selection fell through with "no package backend selected".
# A bare run -- no FS_PKG_BACKEND, no FS_DISTRO_FAMILY -- must detect the
# family from the distro file in the caller shell and then select the real
# rpm backend through it (proven by the dnf5 dry-render, not the mock).

FBIN="$FX_TMP/I/fbin"
mkdir -p "$FBIN"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/dnf5"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/dnf"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FBIN/rpm"
chmod +x "$FBIN"/*
printf 'ID=fedora\nID_LIKE=""\n' >"$FX_TMP/I/osrel2"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hbare" FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/I/osrel2"
    export PATH="$FBIN:$PATH"
    unset FS_PKG_BACKEND FS_DISTRO_FAMILY FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare family->backend resolution rc" 0
fx_out 'profile: full'
fx_out 'module: a (none)'
fx_out 'module: b (none)'
fx_out 'module: c (none)'
fx_out '^# would run: sudo -- dnf5 install -y a1 b1 c1$'
fx_out '^== run complete ==$'
fx_out '^  - 3 modules ok · 0 skipped · 0 failed ·'
fx_err_not 'no package backend selected'
if [[ -e "$FX_TMP/hbare/.local/state/fedora-setup" ]]; then fx_bad "bare dry run created state dir"; else fx_ok; fi

# --- C1: a dry run renders exactly what a real run would execute ------------
# The audit behind C1 found that bootstrap SKIPPED sudo_detect entirely on the
# dry-run path, so FS_RUNNING_AS_ROOT stayed 0 and a ROOT dry run rendered
# `sudo -- ...` while a root real run executes the command directly. C1 calls
# sudo_detect on both paths; because sudo_detect returns before any probe in a
# dry run, the fix must cost ZERO probes and buy render parity.
#
# The fake sudo logs every invocation, so "probed nothing" is read from an
# emptied log rather than inferred. Both arms share this PATH, this fake and
# this backend, so the ONLY difference between them is the euid -- which is
# what makes "the root arm renders no sudo" attributable to the fix rather
# than to a backend that never escalates at all.
SBIN="$FX_TMP/C/sbin"
mkdir -p "$SBIN"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$C_FAKE_SUDO_LOG"\nexit 0\n' >"$SBIN/sudo"
cp "$FBIN/dnf5" "$SBIN/dnf5"
chmod +x "$SBIN"/*
printf 'ID=fedora\nID_LIKE=""\n' >"$FX_TMP/C/osrel"
: >"$FX_TMP/C/sudo.calls"

(   set -euo pipefail
    export FS_HOME="$FX_TMP/C/root" FS_DRY_RUN=1 FS_EUID=0
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$SBIN:$PATH" C_FAKE_SUDO_LOG="$FX_TMP/C/sudo.calls"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 root dry-run rc" 0
# Load-bearing: this warning is emitted by sudo_detect's euid arm, which the
# dry-run path used to skip entirely.
fx_err 'running as root [(]euid 0[)]; proceeding without sudo'
fx_out '^# would run: dnf5 install -y a1 b1 c1$'
fx_out_not '^# would run: sudo'
fx_empty "C1 root dry-run probed sudo zero times" "$FX_TMP/C/sudo.calls"

: >"$FX_TMP/C/sudo.calls"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/C/user" FS_DRY_RUN=1 FS_EUID=1000
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$SBIN:$PATH" C_FAKE_SUDO_LOG="$FX_TMP/C/sudo.calls"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 non-root dry-run rc" 0
fx_err_not 'running as root'
fx_out '^# would run: sudo -- dnf5 install -y a1 b1 c1$'
# The same zero-probe guarantee for the non-root arm. Without this, the root
# arm's "no sudo in the render" could just mean sudo was never consulted.
fx_empty "C1 non-root dry-run probed sudo zero times" "$FX_TMP/C/sudo.calls"

# --- C1: the install path establishes the credential, and fails closed if it
# --- cannot. Every other real-run install cell uses the mock backend, which
# --- SKIPS the bootstrap sudo block entirely, so nothing else covers this.
# The fake sudo logs every invocation, so "the refresh ran" is read from the
# log. Arm B is the requirement-(iii) integration proof: a credential that
# cannot be established must abort the run BEFORE any mutation, name the
# reason, and print no summary (the P9.5 abort-path rule).
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$C_FAKE_SUDO_LOG"\nif [[ "${1:-}" == "-n" ]]; then exit 1; fi\nif [[ "${1:-}" == "-v" ]]; then exit "${C_V_RC:-0}"; fi\nshift\nwhile [[ "${1:-}" == -* ]]; do shift; done\nif [[ "${1:-}" == "--" ]]; then shift; fi\nexec "$@"\n' >"$SBIN/sudo"
chmod +x "$SBIN/sudo"

: >"$FX_TMP/C/ok.calls"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/C/real" FS_EUID=1000
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$SBIN:$PATH" C_FAKE_SUDO_LOG="$FX_TMP/C/ok.calls"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 password-sudo real install rc" 0
if grep -qxF -- '-v' "$FX_TMP/C/ok.calls"; then fx_ok; else
    fx_bad "C1: the install path must refresh the credential before privileged work"; cat "$FX_TMP/C/ok.calls"
fi
if grep -q -- 'dnf5 install' "$FX_TMP/C/ok.calls"; then fx_ok; else
    fx_bad "C1: the batch must escalate through sudo on a password-sudo host"; cat "$FX_TMP/C/ok.calls"
fi
fx_out '^== run complete ==$'
fx_err_not 'sudo credential refresh failed'

: >"$FX_TMP/C/fail.calls"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/C/realfail" FS_EUID=1000 C_V_RC=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$SBIN:$PATH" C_FAKE_SUDO_LOG="$FX_TMP/C/fail.calls"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes --profile full
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 unrefreshable credential aborts the install" 1
fx_err '\[error\] sudo credential refresh failed; privileged steps cannot run$'
# Exact-log assert, not `grep -q 'dnf5 install'`: the requirement is that NO
# privileged command of ANY kind ran, and a grep for one command name cannot
# see `dnf5 makecache`, `dnf5 --refresh`, or anything else the batch might
# grow later. The fake sudo records every invocation, so the whole privileged
# footprint is two lines and nothing else.
printf '%s\n' '-n true' '-v' >"$FX_TMP/C/fail.expect"
if cmp -s -- "$FX_TMP/C/fail.expect" "$FX_TMP/C/fail.calls"; then fx_ok; else
    fx_bad "C1: the failing-credential path must run only the sudo probes"; cat "$FX_TMP/C/fail.calls"
fi
if [[ -d "$FX_TMP/C/realfail/.local/state/fedora-setup/modules" ]] && \
   [[ -n "$(ls -A -- "$FX_TMP/C/realfail/.local/state/fedora-setup/modules" 2>/dev/null)" ]]; then
    fx_bad "C1: aborted run marked modules done"
else
    fx_ok
fi
# An abort path must never render a summary: "0 modules ok" printed right
# after the run refused to touch the system is a false statement.
fx_out_not '^== run complete ==$'

# --- C1 fix: a selection with NO system-namespace work must not authenticate
# --- at all. This is the regression the Senior Review measured against the
# --- SHIPPED tree: `flatpak` ships only flatpaks.list (no packages.*.list, no
# --- hooks.sh, no prerepo.sh), so the run cannot escalate -- yet an
# --- unconditional up-front `sudo -v` aborted it rc1 on a password-sudo host,
# --- reporting "privileged steps cannot run" for a run executing none.
# Driven on the real repo modules/profiles (not synthetic $M/$P) because the
# property under test is a property of the SHIPPED tree.
#
# C_V_RC=1 is the harshest arm: the credential cannot be established at all.
# A privilege-free run must still succeed, because it never needed it.
# FS_PKG_BACKEND=rpm (a REAL backend, never mock) so the `!= mock` policy guard
# is live; the runner still routes the flatpak namespace to the flatpak backend.
FPB="$FX_TMP/C/fpbin"
mkdir -p "$FPB"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$C_FAKE_SUDO_LOG"\nif [[ "${1:-}" == "-n" ]]; then exit 1; fi\nif [[ "${1:-}" == "-v" ]]; then exit "${C_V_RC:-0}"; fi\nshift\nwhile [[ "${1:-}" == -* ]]; do shift; done\nif [[ "${1:-}" == "--" ]]; then shift; fi\nexec "$@"\n' >"$FPB/sudo"
cat >"$FPB/flatpak" <<'FPKEOF'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >>"${C_FAKE_FPK_LOG:?}"
case "${1:-}" in
    info)
        grep -qxF -- "${3:-}" "$C_FAKE_FPK_INST" 2>/dev/null
        exit $?
        ;;
    install)
        shift
        for a in "$@"; do
            case "$a" in --*) continue ;; esac
            grep -qxF -- "$a" "$C_FAKE_FPK_INST" 2>/dev/null || printf '%s\n' "$a" >>"$C_FAKE_FPK_INST"
        done
        exit 0
        ;;
    *) exit 0 ;;
esac
FPKEOF
chmod +x "$FPB"/sudo "$FPB"/flatpak
: >"$FX_TMP/C/fp.calls"
: >"$FX_TMP/C/fp.fpk"
: >"$FX_TMP/C/fp.inst"

(   set -euo pipefail
    export FS_HOME="$FX_TMP/C/fp" FS_EUID=1000 C_V_RC=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$FPB:$PATH"
    export C_FAKE_SUDO_LOG="$FX_TMP/C/fp.calls"
    export C_FAKE_FPK_LOG="$FX_TMP/C/fp.fpk" C_FAKE_FPK_INST="$FX_TMP/C/fp.inst"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes flatpak
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 privilege-free install rc" 0
# The load-bearing assert: not merely "no -v", but NO sudo invocation at all.
# sudo_detect's `sudo -n true` is itself unnecessary here, so an empty log is
# the honest postcondition for a run that provably cannot escalate.
fx_empty "C1 privilege-free install must not invoke sudo at all" "$FX_TMP/C/fp.calls"
fx_err_not 'sudo credential refresh failed'
fx_err_not 'running as root'
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
# "flatpak-only execution still works": the batch really ran and every declared
# app landed, so this cell cannot pass by skipping the work it was meant to do.
for app in com.mattjakeman.ExtensionManager com.bitwarden.desktop net.nokyan.Resources; do
    if grep -qxF -- "$app" "$FX_TMP/C/fp.inst"; then fx_ok; else
        fx_bad "C1 privilege-free install did not install $app"
    fi
done
if grep -q 'flatpak remote-add' "$FX_TMP/C/fp.fpk"; then fx_ok; else
    fx_bad "C1 privilege-free install did not ensure the flathub remote"
fi

# --- C1 fix: the OTHER side of the same condition. The refresh is skipped only
# --- when the run provably CANNOT escalate, so a module that escalates from a
# --- hook or a prerepo must still refresh up front even with an empty system
# --- namespace. Each probe ships NO list file and NO other privilege surface,
# --- so the single arm named is the only thing that can make `-v` appear.
# --- Both carry MODULE_PRIVILEGED=1 (P11-R C1), which is how a module DECLARES
# --- that its hook/prerepo needs privilege -- the runner reads that key, never
# --- the presence of the file. So these cells pin the declaration->refresh link
# --- itself: remove the key and the `-v` below vanishes, which is precisely the
# --- metadata mutation coverage C1 requires.
HPM="$FX_TMP/C/H"
HPPR="$FX_TMP/C/HPprof"
mkdir -p "$HPM/hp" "$HPM/pp" "$HPPR"
# bootstrap applies a default profile (`full`) when --profile is absent, so this
# needs a profile dir whose `full` contributes nothing: $P/full.conf lists the
# unrelated synthetic modules a/b/c, which do not exist under $HPM.
printf '# probe: no ids\n' >"$HPPR/full.conf"
# explicit ids run under the `selection` profile name, which profile_load
# reads, so it must exist too.
printf '# probe: no ids\n' >"$HPPR/selection.conf"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$C_HP_LOG"\n' >"$FX_TMP/C/hp.marker"
chmod +x "$FX_TMP/C/hp.marker"
for id in hp pp; do
    printf 'MODULE_ID=%s\nMODULE_TITLE=Probe %s\nMODULE_RISK=none\nMODULE_DEFAULT=off\nMODULE_PRIVILEGED=1\n' \
        "$id" "$id" >"$HPM/$id/module.sh"
done
printf 'run() {\n    run_sudo "%s: marker" --stop -- "$C_HP_MARK"\n}\n' hp >"$HPM/hp/hooks.sh"
printf 'prerepo() {\n    run_sudo "%s: marker" --stop -- "$C_HP_MARK"\n}\n' pp >"$HPM/pp/prerepo.sh"

hp_arm() {
    local id="$1" home="$2"
    : >"$FX_TMP/C/$home.calls"
    : >"$FX_TMP/C/$home.log"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/C/$home" FS_EUID=1000 C_V_RC=0
        export FS_MODULES_DIR="$HPM" FS_PROFILES_DIR="$HPPR"
        export FS_DISTRO_FILE="$FX_TMP/C/osrel"
        export PATH="$FPB:$PATH"
        export C_FAKE_SUDO_LOG="$FX_TMP/C/$home.calls"
        export C_HP_MARK="$FX_TMP/C/hp.marker" C_HP_LOG="$FX_TMP/C/$home.log"
        export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
        unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
        "$SETUP" install --yes "$id"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "C1 $id (${id}-only privileged surface) rc" 0
    if grep -qx -- '-v' "$FX_TMP/C/$home.calls"; then fx_ok; else
        fx_bad "C1: $id escalates from $([[ $id == hp ]] && echo hooks || echo prerepo) and must still refresh the credential"
        cat "$FX_TMP/C/$home.calls"
    fi
    # EXACTLY ONE refresh. Two would be a second interactive prompt for one run,
    # and presence-only would accept it: `-v` appearing twice is a different
    # defect from `-v` never appearing, so the count is pinned, not the match.
    if [[ "$(grep -cx -- '-v' "$FX_TMP/C/$home.calls")" == "1" ]]; then fx_ok; else
        fx_bad "C1: $id must refresh the credential exactly once (found $(grep -cx -- '-v' "$FX_TMP/C/$home.calls"))"
    fi
    # Ordering: the refresh must come BEFORE the first escalated command, or the
    # credential is obtained after the work that needed it. Line numbers, not
    # pattern order, so a reorder cannot satisfy it.
    local vline=0 eline=0
    vline=$(grep -nx -- '-v' "$FX_TMP/C/$home.calls" | head -1 | cut -d: -f1)
    eline=$(grep -n -- '-- ' "$FX_TMP/C/$home.calls" | head -1 | cut -d: -f1)
    if [[ -n "$vline" && -n "$eline" ]] && ((vline < eline)); then fx_ok; else
        fx_bad "C1: $id must refresh before its first escalated command (refresh line '$vline', escalation line '$eline')"
    fi
    if [[ -s "$FX_TMP/C/$home.log" ]]; then fx_ok; else
        fx_bad "C1: $id privileged command did not run after a successful refresh"
    fi
    fx_out '^== run complete ==$'
}

hp_arm hp hpk
hp_arm pp ppk

# --- C1 declarative privilege (P11-R C1): the SHIPPED hooks-only modules that
# --- do NOT escalate must not authenticate. This is the blocking finding the
# --- independent Dev 2 review measured against the first C1 revision, which
# --- inferred privilege from the PRESENCE of hooks.sh: apps, git, gnome-base,
# --- gnome-theme and terminal all ship hooks.sh, none of them escalates, and on
# --- a password-sudo host every one of them aborted rc1 with "sudo credential
# --- refresh failed; privileged steps cannot run" -- refusing to install a
# --- user's dotfiles because a credential it never needed could not be
# --- obtained. `flatpak` above escaped that bug only by accident (it ships no
# --- hooks.sh at all), which is why the shipped-tree property needs its own
# --- cells here rather than trusting that one.
# C_V_RC=1 is the harshest arm: the credential can never be established.
# Driven on the real repo modules/profiles because the property under test is a
# property of the SHIPPED declarations. HOME is redirected into the temp tree so
# a $HOME fallback in any hook cannot touch the real user's dotfiles; the
# assertion below is non-vacuous because each module must still be RECORDED done,
# which only happens if its hook actually ran to completion.
FREE_IDS="apps git gnome-base gnome-theme terminal"
for id in $FREE_IDS; do
    home="$FX_TMP/C/free_$id"
    : >"$FX_TMP/C/free_$id.calls"
    (   set -euo pipefail
        export HOME="$home" FS_HOME="$home/state" FS_EUID=1000 C_V_RC=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_DISTRO_FILE="$FX_TMP/C/osrel"
        export PATH="$FPB:$PATH"
        export C_FAKE_SUDO_LOG="$FX_TMP/C/free_$id.calls"
        export C_FAKE_FPK_LOG="$FX_TMP/C/free.fpk" C_FAKE_FPK_INST="$FX_TMP/C/free.inst"
        export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
        unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
        "$SETUP" install --yes "$id"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "C1 privilege-free hooks-only $id rc" 0
    fx_empty "C1 privilege-free $id must not invoke sudo at all" "$FX_TMP/C/free_$id.calls"
    fx_err_not 'sudo credential refresh failed'
    fx_err_not 'running as root'
    fx_out '^== run complete ==$'
    # A hooks-only module's NORMAL outcome is `ok` or, when the capability gate
    # finds nothing to do on this host, A1's `skipped` (MODULE_HOOK_SKIP) --
    # gnome-theme is shipped that way. Both are successes; what must never
    # appear is a failure, so the failed count is the pinned number.
    fx_out '^  - [0-9]* modules ok · [0-9]* skipped · 0 failed ·'
    # Non-vacuity: the hook really ran to a verdict. Either registry state is
    # written only after run() RETURNS, so a runner that never reached the
    # module, or a hook that aborted, cannot satisfy this.
    if grep -qE '^(done|skipped) ' "$home/state/.local/state/fedora-setup/modules/$id" 2>/dev/null; then fx_ok; else
        fx_bad "C1 privilege-free $id did not run to a verdict (registry: $(cat "$home/state/.local/state/fedora-setup/modules/$id" 2>/dev/null || echo MISSING))"
    fi
done

# --- C1 declarative privilege: the SHIPPED modules that DO escalate must
# --- declare it, and the privilege-free ones must not. This is the metadata
# --- half of the contract, and it is what makes the behavioural cells above
# --- non-vacuous in the other direction: if a module under-declares, the runner
# --- cannot know, and this audit is the only thing that notices.
for id in chrome dns locale vscode; do
    if grep -qx 'MODULE_PRIVILEGED=1' "$ROOT/modules/$id/module.sh"; then fx_ok; else
        fx_bad "C1 privileged module $id must declare MODULE_PRIVILEGED=1"
    fi
done
for id in $FREE_IDS; do
    # Absent means non-privileged (the documented default); an explicit 0 is
    # equally fine. What must never appear is a 1, nor any other value.
    if grep -qE '^MODULE_PRIVILEGED=(1|2|yes|true|on)$' "$ROOT/modules/$id/module.sh"; then
        fx_bad "C1 privilege-free module $id must not declare MODULE_PRIVILEGED=1"
    else fx_ok; fi
    if grep -qE '^MODULE_PRIVILEGED=' "$ROOT/modules/$id/module.sh" \
        && ! grep -qx 'MODULE_PRIVILEGED=0' "$ROOT/modules/$id/module.sh"; then
        fx_bad "C1 privilege-free module $id declares a MODULE_PRIVILEGED value that is neither absent nor 0"
    else fx_ok; fi
done

# --- C1 declarative privilege: malformed metadata must be REFUSED, never
# --- silently reinterpreted. `MODULE_PRIVILEGED` gates the only thing standing
# --- between a run and an unauthenticated escalation, so a typo (`yes`, `2`,
# --- `true`) that defaulted to either arm would be a silent security change:
# --- defaulting to 1 is safe-but-wrong, defaulting to 0 loses the prompt
# --- entirely. Validation is the only thing standing between the two, so each
# --- unsupported value is driven end to end and must abort the install.
BADPRIV="$FX_TMP/C/badpriv"
BPPROF="$FX_TMP/C/bpprof"
mkdir -p "$BADPRIV" "$BPPROF"
printf '# probe: no ids\n' >"$BPPROF/full.conf"
printf '# probe: no ids\n' >"$BPPROF/selection.conf"
for bad in 2 yes true on ""; do
    slug="$(printf '%s' "${bad:-empty}" | tr -c 'A-Za-z0-9' '_')"
    mkdir -p "$BADPRIV/bp$slug"
    printf 'MODULE_ID=bp%s\nMODULE_TITLE=Bad privilege\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' "$slug" \
        >"$BADPRIV/bp$slug/module.sh"
    if [[ -z "$bad" ]]; then
        printf 'MODULE_PRIVILEGED=\n' >>"$BADPRIV/bp$slug/module.sh"
    else
        printf 'MODULE_PRIVILEGED=%s\n' "$bad" >>"$BADPRIV/bp$slug/module.sh"
    fi
    : >"$FX_TMP/C/bad_$slug.calls"
    (   set -euo pipefail
        export HOME="$FX_TMP/C/bad_$slug" FS_HOME="$FX_TMP/C/bad_$slug/state" FS_EUID=1000 C_V_RC=1
        export FS_MODULES_DIR="$BADPRIV" FS_PROFILES_DIR="$BPPROF"
        export FS_DISTRO_FILE="$FX_TMP/C/osrel"
        export PATH="$FPB:$PATH"
        export C_FAKE_SUDO_LOG="$FX_TMP/C/bad_$slug.calls"
        export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
        unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
        "$SETUP" install --yes "bp$slug"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "C1 malformed MODULE_PRIVILEGED='${bad:-empty}' rc" 1
    fx_err "invalid MODULE_PRIVILEGED"
    fx_empty "C1 malformed MODULE_PRIVILEGED='${bad:-empty}' must not reach sudo" "$FX_TMP/C/bad_$slug.calls"
    fx_out_not '^== run complete ==$'
done
# ...and the two supported values are accepted: `0` means non-privileged, so a
# module that spells it out must behave exactly like an absent declaration.
ZERO="$FX_TMP/C/zeropriv"
mkdir -p "$ZERO/bpzero"
printf 'MODULE_ID=bpzero\nMODULE_TITLE=Explicit zero\nMODULE_RISK=none\nMODULE_DEFAULT=off\nMODULE_PRIVILEGED=0\n' \
    >"$ZERO/bpzero/module.sh"
printf 'run() { printf "%%s\\n" "ran" >>"$C_BP_LOG"; }\n' >"$ZERO/bpzero/hooks.sh"
: >"$FX_TMP/C/bp.calls"
: >"$FX_TMP/C/bp.log"
(   set -euo pipefail
    export HOME="$FX_TMP/C/bpzero" FS_HOME="$FX_TMP/C/bpzero/state" FS_EUID=1000 C_V_RC=1
    export FS_MODULES_DIR="$ZERO" FS_PROFILES_DIR="$BPPROF"
    export FS_DISTRO_FILE="$FX_TMP/C/osrel"
    export PATH="$FPB:$PATH"
    export C_FAKE_SUDO_LOG="$FX_TMP/C/bp.calls" C_BP_LOG="$FX_TMP/C/bp.log"
    export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
    unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes bpzero
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "C1 explicit MODULE_PRIVILEGED=0 rc" 0
fx_empty "C1 explicit MODULE_PRIVILEGED=0 must not invoke sudo" "$FX_TMP/C/bp.calls"
if [[ -s "$FX_TMP/C/bp.log" ]]; then fx_ok; else
    fx_bad "C1 explicit MODULE_PRIVILEGED=0 module did not run"
fi

# --- C1 declarative privilege: a MIXED selection. One declared-privileged
# --- module plus one privilege-free module in the same run, which is the case a
# --- per-module or lazy decision gets wrong in opposite directions: refreshing
# --- per module would prompt twice, refreshing never would escalate unprompted.
# The credential-OK arm proves exactly one prompt, that BOTH modules really
# executed, and that the privilege-free one is not collateral damage; the
# credential-FAIL arm proves the abort happens before ANY mutation, including
# the harmless module's.
mkdir -p "$HPM/free"
printf 'MODULE_ID=free\nMODULE_TITLE=Free probe\nMODULE_RISK=none\nMODULE_DEFAULT=off\nMODULE_PRIVILEGED=0\n' \
    >"$HPM/free/module.sh"
printf 'run() { printf "%%s\\n" "free" >>"$C_HP_LOG"; }\n' >"$HPM/free/hooks.sh"
mixed_arm() {
    local vrc="$1" home="$2" label="$3"
    : >"$FX_TMP/C/$home.calls"
    : >"$FX_TMP/C/$home.log"
    (   set -euo pipefail
        export HOME="$FX_TMP/C/$home" FS_HOME="$FX_TMP/C/$home/state" FS_EUID=1000 C_V_RC="$vrc"
        export FS_MODULES_DIR="$HPM" FS_PROFILES_DIR="$HPPR"
        export FS_DISTRO_FILE="$FX_TMP/C/osrel"
        export PATH="$FPB:$PATH"
        export C_FAKE_SUDO_LOG="$FX_TMP/C/$home.calls"
        export C_HP_MARK="$FX_TMP/C/hp.marker" C_HP_LOG="$FX_TMP/C/$home.log"
        export FS_PKG_BACKEND=rpm FS_DISTRO_FAMILY=rpm
        unset FS_YES FS_PROFILE FS_DRY_RUN 2>/dev/null || :
        "$SETUP" install --yes hp free
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    if [[ "$vrc" == "0" ]]; then
        fx_block_rc "C1 mixed selection ($label) rc" 0
        if [[ "$(grep -cx -- '-v' "$FX_TMP/C/$home.calls")" == "1" ]]; then fx_ok; else
            fx_bad "C1 mixed selection ($label) must refresh exactly once (found $(grep -cx -- '-v' "$FX_TMP/C/$home.calls"))"
        fi
        if grep -qx 'free' "$FX_TMP/C/$home.log"; then fx_ok; else
            fx_bad "C1 mixed selection ($label): privilege-free module did not execute"
        fi
        if [[ -s "$FX_TMP/C/$home.log" ]] && [[ "$(wc -l <"$FX_TMP/C/$home.log")" -ge 2 ]]; then fx_ok; else
            fx_bad "C1 mixed selection ($label): privileged module did not execute after the refresh"
        fi
        fx_out '^== run complete ==$'
        fx_out '^  - 2 modules ok · 0 skipped · 0 failed ·'
    else
        fx_block_rc "C1 mixed selection ($label) rc" 1
        fx_err 'sudo credential refresh failed; privileged steps cannot run'
        fx_empty "C1 mixed selection ($label): no escalation before a successful refresh" "$FX_TMP/C/$home.log"
        fx_out_not '^== run complete ==$'
        # Exactly the probes, nothing else: a `-n true` probe and one `-v`, so a
        # run that escalated anyway shows up as an extra line.
        if [[ "$(wc -l <"$FX_TMP/C/$home.calls")" == "2" ]]; then fx_ok; else
            fx_bad "C1 mixed selection ($label): expected only the probe+refresh, got:"; cat "$FX_TMP/C/$home.calls"
        fi
    fi
}
mixed_arm 0 mixok "credential OK"
mixed_arm 1 mixbad "credential FAILS"

# --- empty profile (minimal skeleton) via --yes ----------------------------

(   set -euo pipefail
    export FS_HOME="$FX_TMP/hempty" FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$M" FS_PROFILES_DIR="$P"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    printf '' | "$SETUP" install --profile minimal --yes </dev/null
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile rc" 0
fx_out 'profile: minimal'
fx_out '^== run complete ==$'
fx_out '^  - 0 modules ok · 0 skipped · 0 failed ·'

fx_summary