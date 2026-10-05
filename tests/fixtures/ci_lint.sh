#!/usr/bin/env bash
# tests/fixtures/ci_lint.sh - P11-R D1 fixture for CI lint provisioning.
#
# D1 fixes ROADMAP finding F2: the CI lint job runs on ubuntu-latest, but
# scripts/install-tools.sh fetched shfmt with `dnf download shfmt` +
# `rpm2cpio | cpio`, an rpm-family-only chain that does not exist on an Ubuntu
# runner. The lint job therefore could never provision its own tooling. The
# failure was also SILENT: the call sat under `set -e` with 2>&1 into
# /dev/null, so the shell aborted with the failing command's 127 before the
# script's own "shfmt download failed" guard could print. CI saw
# "downloading shfmt 3.7.0..." and then a bare red step with no explanation.
#
# This fixture pins the properties D1 claims, and it pins them WITHOUT network
# access and without the real 16MB shellcheck tarball. The four claims:
#
#   1. PROVISIONING IS DISTRO-INDEPENDENT. Every provisioning cell below runs
#      on a PATH that provably contains no dnf/dnf5/rpm2cpio/rpm/cpio/yum/
#      zypper/microdnf, so a script that reached for any of them could not
#      reach the behaviour being asserted. Each cell states that precondition
#      with its own assertion instead of trusting the bindir contents.
#   2. FAILURES ARE CLEAR, NOT SILENT. A missing prerequisite, a corrupted
#      download and a stale pre-existing tool each fail non-zero WITH a message
#      naming the cause. This is the regression the D1 defect was: a bare 127.
#   3. make lint STILL RUNS THE REAL LINT PATH, unweakened. Contract-coupled
#      recording stubs prove scripts/lint invokes shellcheck with
#      --severity=warning and shfmt with -i 4 -d over the real target set and
#      propagates a non-zero tool as `lint: FAILED`; and where the real pinned
#      tools are present on this host, the REAL lint is run for real -- clean
#      copy passes, an injected shellcheck violation and an injected shfmt
#      violation each fail non-zero naming the file.
#   4. THE WORKFLOW STAYS VALID AND FAILURE-VISIBLE. ci.yml is parsed with a
#      real YAML parser, the lint job is asserted to provision and then lint in
#      that order, and neither step (nor any other step in the file) may hide a
#      failure behind `|| true` or `continue-on-error`.
##   5. (P11-R D3, ROADMAP finding F4b) THE WORKFLOW IS SUPPLY-CHAIN PINNED AND
#      TIME-BOUNDED. Every action reference is a full 40-hex commit SHA with
#      the release version kept in a trailing comment, every job declares a
#      positive integral `timeout-minutes`, and the container job's cap stays
#      ABOVE FS_CTR_TIMEOUT -- the cap is read out of ci.yml itself, so the
#      relation cannot rot into comparing against a constant restated here.
#      Group 7 below. This is a STATIC property of a file: see the limits.
#
# HONEST LIMITS, so nothing here reads as more coverage than it is.
#   * The recording stubs prove the real lint SCRIPT's invocation contract
#     (which tool, which flags, which targets, does a failure propagate). They
#     do NOT prove any real linter would catch a given defect -- that is what
#     the real-tool cells are for, and they are counted as SKIPS, visibly, when
#     the pinned tools are not installed on this host. A skip here means "not
#     exercised", never "passed".
#   * D1 did not change the shellcheck download contract at all (same URL, same
#     pinned digest); it made that block's error reporting explicit and added a
#     postcondition. The shellcheck ARCHIVE path is therefore covered by the
#     control-flow cells, while the shfmt path is additionally driven end to
#     end with real bytes, because tools/shfmt IS the downloaded file verbatim
#     and can be re-served by a fake curl with no network and no vendored
#     fixture binary.
#   * The pins are read out of scripts/install-tools.sh rather than restated
#     here, so this fixture asserts "installed == pin" and cannot rot into
#     pinning a stale constant. It deliberately does NOT assert the pin is the
#     CORRECT upstream digest: the pin is the trust anchor, and no test can
#     validate a trust anchor from inside the thing it anchors.
#   * No GitHub-hosted run is claimed or simulated anywhere in this file. A
#     green fixture is a claim about this repository's files, not about GitHub
#     Actions (ROADMAP P10.3 row: the workflow has never been executed on a
#     runner and no run id or status URL exists).
#   * The rpm-freedom claim is about THIS provisioning script on a Linux host
#     without rpm-family tooling. It is not a claim that the workflow runs on a
#     real ubuntu-latest runner.
##   * `actionlint` is NOT installed on this host (`command -v actionlint` finds
#     nothing), so the workflow has had no Actions-aware semantic linter over
#     it. D3's task text asks for that absence to be recorded, and this is the
#     record. The two parsers used instead are python3+PyYAML and bash, and
#     neither knows the Actions schema: they can prove the file is well-formed
#     YAML carrying the required keys, not that GitHub accepts it.
#   * GROUP 7 IS STATIC, AND THAT IS THE WHOLE OF WHAT IT PROVES. It reads
#     .github/workflows/*.yml; it never executes a job. It therefore proves the
#     file says what it must say, and nothing about whether GitHub accepts it,
#     whether the SHAs are the commits their comments claim, or whether any
#     job passes. The SHA-to-tag correspondence was verified ONCE, out of band,
#     with `git ls-remote --tags` (refs/tags/v4 = refs/tags/v4.4.0 =
#     11d5960a...), exactly like D1's download digests: the pin is a trust
#     anchor and no in-repo test can validate a trust anchor from inside the
#     thing it anchors. Reproduce that command before moving a pin.
#   * Group 7's timeout cells cannot detect a timeout that is too LOW in
#     absolute terms (a 1-minute lint job satisfies "positive integral"). Only
#     the container-vs-FS_CTR_TIMEOUT relation is bounded, because it is the
#     one with a derivable bound. The lint and unit values are measured host
#     figures recorded in ci.yml's header; treat them as review material, not
#     as tested constants.
#   * The text path in group 7 counts `timeout-minutes` lines per FILE and
#     requires at least one, so it cannot see a job added without a bound. The
#     YAML path is per job and does; that split is deliberate (the text path
#     must work without PyYAML) and it is why both are asserted. Measured: a
#     fourth, unbounded job is caught by the YAML path alone.
#   * Where PyYAML is unavailable the YAML cells SKIP, visibly, and only the
#     text path runs -- so on such a host group 7 is strictly weaker, and the
#     skip line is the only thing that says so.
#
# MEASURED LIMITS OF THE EVIDENCE, so "N/N mutations caught" is not read as
# more than it is.
#   * The mutation evidence counts ASSERT-COUNT DELTAS, which detect the REMOVAL
#     of an assertion but not its WEAKENING: de-anchoring every
#     `fx_err '^lint: FAILED$'` to `fx_err 'lint: FAILED'`, or re-deriving a
#     pinned literal from the script under test, leaves the suite fully green.
#     Both were measured. "All mutations caught" therefore means
#     removal-detection, and no count is quoted here because a quoted count goes
#     stale the moment a cell is added.
#   * TWO guards are deliberately UNCOVERED and are recorded here rather than
#     left reading as protection, following the same reasoning as the dead-guard
#     deletion in P9.3: (a) install-tools.sh's shellcheck archive-member check
#     is unreachable once the tarball is digest-pinned, and (b) fx_fakecurl's
#     scratch-tree guard. Removing either produces no FAIL, by design.
#   * The three shfmt postconditions (download checksum, installed digest,
#     installed version) are mutually redundant. Measured: any one alone still
#     refuses bad bytes, and only removing ALL THREE lets a 15-byte text file be
#     installed and reported as success. The fixture proves each layer fires; it
#     cannot tell you which one did.
#   * The FX_SKIP>0 summary branch is UNEXERCISED on a host that has both
#     pinned tools and PyYAML (this one): 0 skips, so only its format is pinned.
#   * The skip count counts CELLS, not assertions: hiding tools/{shfmt,shellcheck}
#     reports ONE skipped cell while roughly a dozen assertions across cells 6,
#     6b, 6c, 6d and group 5 go unexercised. The number is a count of skipped
#     guards, never of lost coverage.

set -uo pipefail

FX_SKIP=0
fx_skip() {
    FX_SKIP=$((FX_SKIP + 1))
    printf 'SKIP %s\n' "$1"
}

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/fixtures/lib.sh
source "$_here/lib.sh"
fx_init

REPO="$(cd "$_here/../.." && pwd)"
INSTALL_TOOLS="$REPO/scripts/install-tools.sh"
LINT_SCRIPT="$REPO/scripts/lint"
MAKEFILE="$REPO/Makefile"
SHELLCHECKRC="$REPO/.shellcheckrc"
SETUP_BIN="$REPO/setup"
CI_YML="$REPO/.github/workflows/ci.yml"
REAL_SHFMT="$REPO/tools/shfmt"
REAL_SHELLCHECK="$REPO/tools/shellcheck"

SHFMT_VER="$(sed -n 's/^SHFMT_VERSION="\(.*\)"$/\1/p' "$INSTALL_TOOLS")"
SHFMT_PIN="$(sed -n 's/^SHFMT_SHA256="\(.*\)"$/\1/p' "$INSTALL_TOOLS")"
SHFMT_URL="$(sed -n 's/^SHFMT_URL="\(.*\)"$/\1/p' "$INSTALL_TOOLS")"
SC_VER="$(sed -n 's/^SHELLCHECK_VERSION="\(.*\)"$/\1/p' "$INSTALL_TOOLS")"
# Absolute paths, captured before any cell narrows PATH. Helpers that shell out
# must not resolve their own tools through a bindir a cell is mutating: a fake
# curl that called plain `cp` broke as soon as cell 6c replaced `cp` with a
# deliberately failing one, and failed at the wrong step.
REAL_CP="$(command -v cp)"
REAL_RM="$(command -v rm)"
REAL_MKTEMP="$(command -v mktemp)"

# Every provisioning cell runs on one of these bindirs. None of them contains a
# single rpm-family tool, which is the whole point of claim 1.
# Every external command scripts/install-tools.sh actually invokes. `mv` is here
# because the atomic temp+rename install needs it; the lists mirror the header's
# declared dependency set, so adding a command to the script means adding it here
# or these cells fail for the wrong reason.
TOOLS_ALL="bash uname mktemp mkdir readlink dirname cp chmod mv rm sed sha256sum tar curl xz"
TOOLS_NO_CURL="bash uname mktemp mkdir readlink dirname cp chmod mv rm sed sha256sum tar xz"
TOOLS_NO_XZ="bash uname mktemp mkdir readlink dirname cp chmod mv rm sed sha256sum tar curl"
RPM_FAMILY="dnf dnf5 microdnf rpm rpm2cpio cpio yum zypper"

# Populate a provisioning cell's bindir.
#
# These are COPIES, not symlinks, and that is a safety decision rather than a
# style one. A cell needs to replace some of them with fakes (a fake curl, a
# deliberately failing cp), and a redirect onto a symlinked bindir entry
# follows it to the target -- so `> "$bindir/curl"` truncated the host's real
# /usr/bin/curl. On uid 1000 the write was refused, which is the only reason
# the host survived; as root it would not have been. Symlinking was removed so
# the hazard cannot recur, and any cell that must fake a tool can now write to
# its own private copy with no guard at all.
fx_mkbin() { # $1=bindir $2=space-separated tool list to provide
    local name src miss=""
    mkdir -p "$1"
    for name in $2; do
        src="$(command -v "$name" 2>/dev/null || true)"
        if [[ -z "$src" ]]; then
            miss="$miss $name"
        else
            cp -f -- "$src" "$1/$name"
            chmod +x "$1/$name" 2>/dev/null || :
        fi
    done
    if [[ -n "$miss" ]]; then
        printf 'fx_mkbin: this host lacks:%s\n' "$miss" >&2
        return 1
    fi
}

fx_assert_rpm_free() { # $1=label $2=bindir -- the precondition of every provisioning cell
    local t
    for t in $RPM_FAMILY; do
        if [[ -e "$2/$t" ]]; then
            fx_bad "$1: bindir contains rpm-family tool $t, so the cell is not rpm-free"
            return
        fi
    done
    fx_ok
}

fx_mkrepo() { # $1=dirname -> creates <d>/repo{,.scripts,.bin}; echoes the repo path
    mkdir -p "$1/repo/scripts" "$1/bin"
    cp "$INSTALL_TOOLS" "$1/repo/scripts/install-tools.sh"
    chmod +x "$1/repo/scripts/install-tools.sh"
    printf '%s\n' "$1/repo"
}

# A fake curl that never touches the network. $2 is the file to serve for every
# URL, or the literal "none" to serve deliberately wrong bytes.
#
# It MUST unlink the bindir entry before writing, and that requirement is now
# defence-in-depth rather than load-bearing: fx_mkbin populates the bindir with
# COPIES, so the redirect cannot reach a host binary. It was load-bearing once.
# The first draft of this fixture symlinked the bindir to the host's real tools,
# and a plain `> "$1/curl"` therefore followed the link and truncated
# /usr/bin/curl -- a real, measured failure, refused only because the host runs
# as uid 1000, which would not have saved a root CI. Symlinking was removed
# rather than guarded, and the guard below now checks the weaker property that
# is still worth having: the bindir really is inside this fixture's scratch
# tree, so the write cannot land outside it even if a future cell reintroduces
# links. That guard is NOT the reason the host is safe; the copies are.
fx_fakecurl() { # $1=bindir $2=store-file|none
    local store="$2" target
    target="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
    case "$target" in
    "$FX_TMP"/*) ;;
    *)
        printf 'fx_fakecurl: refusing to write outside the scratch tree: %s\n' "$1" >&2
        return 1
        ;;
    esac
    if [[ -L "$1/curl" || -e "$1/curl" ]]; then
        # The status is checked: this fixture runs without `errexit`, so an
        # unchecked unlink would fall through to a redirect that follows the
        # symlink, which is the exact hazard this function exists to prevent.
        rm -f "$1/curl" || return 1
    fi
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'out=""; prev=""'
        printf '%s\n' 'for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done'
        printf '%s\n' '[[ -n "$out" ]] || exit 1'
        if [[ "$store" == none ]]; then
            printf '%s\n' 'printf "tampered-not-the-real-artifact\n" >"$out"'
        else
            printf '%s %s "$out"\n' "$REAL_CP" "$store"
        fi
        printf '%s\n' 'exit 0'
    } >"$1/curl"
    chmod +x "$1/curl"
}

# rpm-family stubs that record being invoked and then succeed. Used on the
# SUCCESSFUL provisioning cells instead of a grep for "dnf download": a static
# text search cannot tell a command invocation from the same words inside a
# printf'd error message (which is exactly what a first draft of this fixture
# matched), and it cannot tell "not reached" from "not present". These stubs
# answer the real question -- was any rpm-family tool executed at all -- and a
# stub that exits 0 without doing anything means a regression would still
# provision successfully, so the empty log is the only thing that can fail it.
fx_rpmstubs() { # $1=bindir $2=call-log
    local t
    for t in $RPM_FAMILY; do
        rm -f "$1/$t"
        printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$0" >>"'"$2"'"' 'exit 0' >"$1/$t"
        chmod +x "$1/$t"
    done
}

# Build a private, writable copy of everything scripts/lint lints, plus tools/.
fx_mklinttree() { # $1=dirname; creates <d>/{Makefile,scripts,lib,modules,setup,tools}
    mkdir -p "$1/scripts" "$1/tools"
    cp "$MAKEFILE" "$1/Makefile"
    cp "$LINT_SCRIPT" "$1/scripts/lint"
    cp "$SHELLCHECKRC" "$1/.shellcheckrc"
    cp -r "$REPO/lib" "$1/lib"
    cp -r "$REPO/modules" "$1/modules"
    cp "$SETUP_BIN" "$1/setup"
    chmod +x "$1/scripts/lint" "$1/setup"
}

RUN_LINT_DESC=""
RUN_LINT=()
if command -v make >/dev/null 2>&1; then
    RUN_LINT=(make lint)
    RUN_LINT_DESC="make lint"
else
    RUN_LINT=(bash scripts/lint)
    RUN_LINT_DESC="bash scripts/lint (make is absent on this host)"
fi

printf -- '--- D1 group 1: provisioning is distro-independent and fails clearly ---\n'

# fx_err/fx_out take a BRE (plain grep), so a literal bracket is \[ and an
# interval is \{n\}; both were got wrong in this fixture's first draft and both
# failed against visibly correct output rather than revealing a product bug.

# --- cell 1: no curl on PATH -> named prerequisite error, non-zero, nothing installed
D1="$FX_TMP/c1"
R1="$(fx_mkrepo "$D1")"
fx_mkbin "$D1/bin" "$TOOLS_NO_CURL" || exit 1
fx_assert_rpm_free "cell1" "$D1/bin"
(
    PATH="$D1/bin"
    export PATH
    bash "$R1/scripts/install-tools.sh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "provisioning without curl is refused" 1
fx_err 'missing required provisioning tool[(]s[)]: curl'
fx_err 'it installs no packages'
if [[ ! -e "$R1/tools/shfmt" ]]; then
    fx_ok
else fx_bad "cell1 installed a shfmt despite having no curl"; fi

# --- cell 2: no xz on PATH -> the second, hidden host assumption is now named
D2="$FX_TMP/c2"
R2="$(fx_mkrepo "$D2")"
fx_mkbin "$D2/bin" "$TOOLS_NO_XZ" || exit 1
fx_assert_rpm_free "cell2" "$D2/bin"
(
    PATH="$D2/bin"
    export PATH
    bash "$R2/scripts/install-tools.sh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "provisioning without xz is refused" 1
fx_err 'missing required provisioning tool[(]s[)]: xz'
if [[ ! -e "$R2/tools/shellcheck" ]]; then
    fx_ok
else fx_bad "cell2 installed shellcheck despite having no xz"; fi

# --- cell 3: a corrupted download is refused loudly (the pin is load-bearing)
D3="$FX_TMP/c3"
R3="$(fx_mkrepo "$D3")"
fx_mkbin "$D3/bin" "$TOOLS_ALL" || exit 1
fx_fakecurl "$D3/bin" none
fx_assert_rpm_free "cell3" "$D3/bin"
(
    PATH="$D3/bin"
    export PATH
    bash "$R3/scripts/install-tools.sh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "a tampered download is refused" 1
fx_err 'shellcheck checksum mismatch [(]expected [0-9a-f]\{64\}[)]'
fx_err 'refusing to install'
if [[ ! -e "$R3/tools/shellcheck" ]]; then
    fx_ok
else fx_bad "cell3 installed shellcheck from a tampered download"; fi

# --- cell 4: a stale PRE-EXISTING shfmt is refused, and the remedy is named.
# This is the exact state a workstation is left in by the pre-D1 dnf path: the
# rpm-extracted binary, which reports NO version at all and matches no pin.
D4="$FX_TMP/c4"
R4="$(fx_mkrepo "$D4")"
fx_mkbin "$D4/bin" "$TOOLS_ALL" || exit 1
fx_assert_rpm_free "cell4" "$D4/bin"
mkdir -p "$R4/tools"
printf '#!/usr/bin/env bash\nexit 0\n' >"$R4/tools/shfmt"
chmod +x "$R4/tools/shfmt"
(
    PATH="$D4/bin"
    export PATH
    bash "$R4/scripts/install-tools.sh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "a stale pre-existing shfmt is refused" 1
fx_err 'installed shfmt does not match the pinned digest'
fx_err 'remove .*/tools/shfmt and re-run'
if [[ -e "$R4/tools/shfmt" ]] && grep -q 'exit 0' "$R4/tools/shfmt"; then
    fx_ok
else fx_bad "cell4 overwrote or removed the stale shfmt instead of refusing"; fi

# --- cell 5: a pre-existing shellcheck reporting the WRONG version is refused
D5="$FX_TMP/c5"
R5="$(fx_mkrepo "$D5")"
fx_mkbin "$D5/bin" "$TOOLS_ALL" || exit 1
fx_assert_rpm_free "cell5" "$D5/bin"
mkdir -p "$R5/tools"
printf '%s\n' '#!/usr/bin/env bash' 'printf "version: 0.9.9\n"' >"$R5/tools/shellcheck"
chmod +x "$R5/tools/shellcheck"
(
    PATH="$D5/bin"
    export PATH
    bash "$R5/scripts/install-tools.sh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "a stale pre-existing shellcheck is refused" 1
# The brackets are escaped deliberately: unescaped `[0.9.9]` is a grep bracket
# expression matching a single character, which this fixture's first draft did
# and which then failed against its own, visibly correct, stderr.
fx_err 'installed shellcheck reports version \[0.9.9\], expected \[0.11.0\]'
fx_err 'remove .*/tools/shellcheck and re-run'

printf -- '--- D1 group 2: the real shfmt path, end to end, with no network ---\n'

# --- cell 6: real bytes, served by a fake curl, on a PATH whose rpm-family
# tools are stubs that log and succeed. Proves two things at once: the rewritten
# path provisions from real bytes, and NO rpm-family tool is ever executed.
# Needs tools/shfmt present locally because the fixture will not vendor a 2.9MB
# binary; that is a SKIP, counted visibly, never a silent pass.
if [[ -x "$REAL_SHFMT" && -x "$REAL_SHELLCHECK" ]]; then
    D6="$FX_TMP/c6"
    R6="$(fx_mkrepo "$D6")"
    fx_mkbin "$D6/bin" "$TOOLS_ALL" || exit 1
    fx_fakecurl "$D6/bin" "$REAL_SHFMT" || exit 1
    fx_rpmstubs "$D6/bin" "$D6/rpm-calls.log"
    # Pre-place a valid copy so the run reaches the shfmt stage without needing
    # a real shellcheck tarball; the shfmt stage is the one D1 rewrote.
    mkdir -p "$R6/tools"
    cp "$REAL_SHELLCHECK" "$R6/tools/shellcheck"
    chmod +x "$R6/tools/shellcheck"
    (
        PATH="$D6/bin"
        export PATH
        bash "$R6/scripts/install-tools.sh"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "shfmt provisions from real bytes with no package manager" 0
    # Deliberately a LITERAL, not "$SHFMT_VER", even though every other pin in
    # this fixture is read out of the script. Deriving it would make this
    # assertion agree with the script by construction; the literal is an
    # independent cross-check that the installed binary really is shfmt 3.7.0,
    # and it is expected to fail loudly if the pin is ever bumped on purpose.
    fx_out 'shfmt: v3.7.0'
    if [[ -x "$R6/tools/shfmt" ]]; then
        fx_ok
    else fx_bad "cell6 did not produce an executable shfmt"; fi
    if printf '%s  %s\n' "$SHFMT_PIN" "$R6/tools/shfmt" | sha256sum -c - >/dev/null 2>&1; then
        fx_ok
    else fx_bad "the shfmt cell6 installed does not match the pinned digest"; fi
    if [[ "$("$R6/tools/shfmt" --version 2>/dev/null || true)" == "$SHFMT_VER" ]]; then
        fx_ok
    else fx_bad "the provisioned shfmt does not report the pinned version"; fi
    if [[ -s "$D6/rpm-calls.log" ]]; then
        fx_bad "cell6 invoked an rpm-family tool: $(tr '\n' ' ' <"$D6/rpm-calls.log")"
    else fx_ok; fi

    # --- cell 6b: the shfmt DOWNLOAD checksum, which cell 3 cannot reach.
    # Cell 3 tampers the FIRST download, so it is refused by the shellcheck
    # checksum and never gets as far as shfmt; cell 6 serves real bytes for both.
    # Pre-placing a valid shellcheck skips the tarball block entirely (no 16MB
    # fixture needed), which leaves the shfmt download as the first thing the
    # run actually fetches -- so this is the only cell that reaches the shfmt
    # download checksum on its own.
    D6B="$FX_TMP/c6b"
    R6B="$(fx_mkrepo "$D6B")"
    fx_mkbin "$D6B/bin" "$TOOLS_ALL" || exit 1
    fx_fakecurl "$D6B/bin" none || exit 1
    fx_rpmstubs "$D6B/bin" "$D6B/rpm-calls.log"
    mkdir -p "$R6B/tools"
    cp "$REAL_SHELLCHECK" "$R6B/tools/shellcheck"
    chmod +x "$R6B/tools/shellcheck"
    (
        PATH="$D6B/bin"
        export PATH
        bash "$R6B/scripts/install-tools.sh"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "a tampered shfmt download is refused" 1
    fx_err 'shfmt checksum mismatch [(]expected [0-9a-f]\{64\}[)]'
    fx_err 'refusing to install'
    if [[ ! -e "$R6B/tools/shfmt" ]]; then
        fx_ok
    else fx_bad "cell6b installed a shfmt from a tampered download"; fi
    if [[ -s "$D6B/rpm-calls.log" ]]; then
        fx_bad "cell6b invoked an rpm-family tool"
    else fx_ok; fi

    # --- cell 6c: a FAILING INSTALL is reported, not left to `set -e`.
    # This is the cell that pins the NB1 fix: before it, the install was a bare
    # `cp` + `chmod`, so a write failure aborted the script carrying nothing but
    # the shell's own "cp: ... Permission denied" and no install-tools: message.
    #
    # The failure is injected with a contract-coupled failing `cp` rather than by
    # making tools/ read-only. That is deliberate: `chmod 555` on a directory
    # owned by the test does NOT stop root, so a permission-based cell would
    # silently stop exercising this branch on a root CI while still reporting
    # green -- the uid-dependence trap AGENTS.md records for P9.5 B2. A fake that
    # exits non-zero fails identically for uid 0 and uid 1000.
    #
    # The fake CREATES the destination (`: >"$3"`) before failing, and that line
    # is what makes this cell atomicity-aware rather than vacuous. `$3` is the
    # destination because the script calls `cp -- src dst`. Without the create,
    # the staging-litter assertion below passed for the wrong reason -- there was
    # simply no staging file -- and a fully NON-atomic install (direct cp to
    # tools/shfmt, no staging, no rename) kept every message byte-identical and
    # the whole suite green at 91/0. With the create, the non-atomic variant
    # leaves tools/shfmt behind and fails here.
    D6C="$FX_TMP/c6c"
    R6C="$(fx_mkrepo "$D6C")"
    fx_mkbin "$D6C/bin" "$TOOLS_ALL" || exit 1
    fx_fakecurl "$D6C/bin" "$REAL_SHFMT" || exit 1
    mkdir -p "$R6C/tools"
    cp "$REAL_SHELLCHECK" "$R6C/tools/shellcheck"
    chmod +x "$R6C/tools/shellcheck"
    printf '%s\n' '#!/usr/bin/env bash' \
        ': >"$3"' \
        'printf "cp: cannot create regular file %s: Permission denied\n" "$3" >&2' \
        'exit 1' >"$D6C/bin/cp"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$D6C/bin/mv"
    chmod +x "$D6C/bin/cp" "$D6C/bin/mv"
    (
        PATH="$D6C/bin"
        export PATH
        bash "$R6C/scripts/install-tools.sh"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "a failing install is refused, not left to set -e" 1
    fx_err 'install-tools: could not stage shfmt into .*/tools'
    fx_err 'check free space and permissions on .*/tools, then re-run'
    # The destination must NOT exist: the atomic install only ever creates a
    # staging file and renames it, so a failed copy cannot have created it.
    if [[ ! -e "$R6C/tools/shfmt" ]]; then
        fx_ok
    else fx_bad "cell6c created tools/shfmt even though the copy failed (non-atomic install?)"; fi
    if [[ -z "$(find "$R6C/tools" -name '.tool-install.*' 2>/dev/null)" ]]; then
        fx_ok
    else fx_bad "cell6c left a staging file behind in tools/"; fi

    # --- cell 6d: the RENAME leg specifically (cp succeeds, mv fails). Without
    # it the whole `if ! mv -f ...` branch was uncovered: deleting it, or
    # corrupting its message, both left the suite at 91/0. The staging file is
    # created by mktemp here (a real file), cp is the real cp, and only the
    # rename is made to fail.
    D6D="$FX_TMP/c6d"
    R6D="$(fx_mkrepo "$D6D")"
    fx_mkbin "$D6D/bin" "$TOOLS_ALL" || exit 1
    fx_fakecurl "$D6D/bin" "$REAL_SHFMT" || exit 1
    mkdir -p "$R6D/tools"
    cp "$REAL_SHELLCHECK" "$R6D/tools/shellcheck"
    chmod +x "$R6D/tools/shellcheck"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$D6D/bin/mv"
    chmod +x "$D6D/bin/mv"
    (
        PATH="$D6D/bin"
        export PATH
        bash "$R6D/scripts/install-tools.sh"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "a failing rename is refused" 1
    fx_err 'install-tools: could not install shfmt into .*/tools'
    if [[ ! -e "$R6D/tools/shfmt" ]]; then
        fx_ok
    else fx_bad "cell6d created tools/shfmt even though the rename failed"; fi
    if [[ -z "$(find "$R6D/tools" -name '.tool-install.*' 2>/dev/null)" ]]; then
        fx_ok
    else fx_bad "cell6d left a staging file behind in tools/"; fi

    # --- cell 6e: the staging name is UNPREDICTABLE (B2).
    # The staging path used to be "$dest.install.$$". That is attacker-
    # predictable: pre-create it as a symlink and `cp -- src symlink` writes
    # THROUGH it. Measured before the fix -- a 24-byte file outside tools/ grew
    # to the full 2.9MB shfmt, and the script printed nothing and exited 0.
    #
    # The fix is `mktemp`, which creates the file with O_EXCL under a random
    # name, so the collision cannot be pre-created. A fixture cannot make a name
    # random, but it CAN observe the property that produces the randomness: the
    # staging file is created by mktemp, inside the destination directory (so
    # the rename stays on one filesystem and really is atomic), with an
    # `XXXXXX` template that is not derived from the destination basename (so it
    # cannot be guessed from the tool being installed). Reverting to `$dest.
    # install.$$` fails all three, because it calls mktemp zero times.
    #
    # mktemp is wrapped rather than replaced: it is also used for the scratch
    # temp dir, and the wrapper records every invocation and then delegates, so
    # the cell exercises the real mktemp.
    D6E="$FX_TMP/c6e"
    R6E="$(fx_mkrepo "$D6E")"
    fx_mkbin "$D6E/bin" "$TOOLS_ALL" || exit 1
    fx_fakecurl "$D6E/bin" "$REAL_SHFMT" || exit 1
    mkdir -p "$R6E/tools"
    cp "$REAL_SHELLCHECK" "$R6E/tools/shellcheck"
    chmod +x "$R6E/tools/shellcheck"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "$*" >>"'"$D6E"'/mktemp.log"' \
        'exec '"$REAL_MKTEMP"' "$@"' >"$D6E/bin/mktemp"
    chmod +x "$D6E/bin/mktemp"
    (
        PATH="$D6E/bin"
        export PATH
        bash "$R6E/scripts/install-tools.sh"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "a successful install still works when mktemp is wrapped" 0
    if [[ -x "$R6E/tools/shfmt" ]]; then
        fx_ok
    else fx_bad "cell6e did not install shfmt"; fi
    # A staging template must exist, inside tools/, ending in the `*.XXXXXX`
    # convention this repo uses for every temp file it creates.
    if grep -q -- "^$R6E/tools/[^ ]*XXXXXX\$" "$D6E/mktemp.log" 2>/dev/null; then
        fx_ok
    else fx_bad "cell6e: no mktemp staging template inside $R6E/tools/ (non-atomic install?)"; fi
    # And it must not be derivable from the tool being installed, which is what
    # made the old name guessable.
    if grep -q 'shfmt' "$D6E/mktemp.log" 2>/dev/null; then
        fx_bad "cell6e: staging template is derived from the destination name (predictable)"
    else fx_ok; fi
    if [[ -z "$(find "$R6E/tools" -name '.tool-install.*' 2>/dev/null)" ]]; then
        fx_ok
    else fx_bad "cell6e left a staging file behind in tools/ after a successful install"; fi
else
    fx_skip "cell6 real-bytes shfmt provisioning (tools/{shfmt,shellcheck} not installed on this host)"
fi

printf -- '--- D1 group 3: make lint runs the real lint path, unweakened ---\n'

# --- cell 7: contract-coupled recording stubs. These prove which tool
# scripts/lint invokes, with which flags, over which targets -- and that a
# non-zero tool becomes `lint: FAILED` rather than being ignored.
D7="$FX_TMP/c7"
R7="$D7/repo"
fx_mklinttree "$R7"
mkdir -p "$R7/tools"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"'"$D7"'/shellcheck.argv"' 'exit "${FAKE_SC_RC:-0}"' >"$R7/tools/shellcheck"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"'"$D7"'/shfmt.argv"' 'exit "${FAKE_FMT_RC:-0}"' >"$R7/tools/shfmt"
chmod +x "$R7/tools/shellcheck" "$R7/tools/shfmt"
(
    cd "$R7" && "${RUN_LINT[@]}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "lint passes when both tools succeed" 0
fx_out '^== shellcheck ==$'
fx_out '^== shfmt ==$'
fx_out '^lint: OK$'
if [[ -s "$D7/shellcheck.argv" ]]; then
    fx_ok
else fx_bad "scripts/lint never invoked the shellcheck tool"; fi
if [[ -s "$D7/shfmt.argv" ]]; then
    fx_ok
else fx_bad "scripts/lint never invoked the shfmt tool"; fi
if grep -q -- '--severity=warning' "$D7/shellcheck.argv"; then
    fx_ok
else fx_bad "shellcheck was not invoked with --severity=warning"; fi
if grep -q -- '-i 4 -d' "$D7/shfmt.argv"; then
    fx_ok
else fx_bad "shfmt was not invoked with -i 4 -d (the pinned indent rule)"; fi
if grep -q -- "$R7/lib/cli.sh" "$D7/shellcheck.argv"; then
    fx_ok
else fx_bad "shellcheck was not given the lib/ target set"; fi
if grep -q -- "$R7/lib/pkg/rpm.sh" "$D7/shellcheck.argv"; then
    fx_ok
else fx_bad "shellcheck was not given the lib/pkg/ target set"; fi
if grep -q -- "$R7/modules/gnome-base/hooks.sh" "$D7/shellcheck.argv"; then
    fx_ok
else fx_bad "shellcheck was not given the modules/*/ target set"; fi
if grep -q -- "$R7/setup" "$D7/shfmt.argv"; then
    fx_ok
else fx_bad "shfmt was not given the setup target"; fi

# A failing tool must fail the lint, not be tolerated.
(
    cd "$R7" && FAKE_SC_RC=1 "${RUN_LINT[@]}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if ((FX_BLOCK_RC != 0)); then
    fx_ok
else fx_bad "a failing shellcheck still produced lint rc 0"; fi
fx_err '^lint: FAILED$'
fx_out_not '^lint: OK$'
(
    cd "$R7" && FAKE_FMT_RC=1 "${RUN_LINT[@]}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if ((FX_BLOCK_RC != 0)); then
    fx_ok
else fx_bad "a failing shfmt still produced lint rc 0"; fi
fx_err '^lint: FAILED$'
fx_out_not '^lint: OK$'

printf -- '--- D1 group 4: missing tooling fails clearly, never a false PASS ---\n'

# --- cell 8: tools/shellcheck absent -> non-zero, names the path and the fix
D8="$FX_TMP/c8"
R8="$D8/repo"
fx_mklinttree "$R8"
(
    cd "$R8" && "${RUN_LINT[@]}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if ((FX_BLOCK_RC != 0)); then
    fx_ok
else fx_bad "lint passed with no tools installed (a false PASS)"; fi
fx_err 'shellcheck not found at .*/tools/shellcheck'
fx_err 'run: bash scripts/install-tools.sh'
fx_out_not '^lint: OK$'
if [[ ! -e "$R8/tools/shellcheck" ]]; then
    fx_ok
else fx_bad "the lint path invented a shellcheck binary"; fi

# --- cell 9: shellcheck present, shfmt absent -> names shfmt specifically
D9="$FX_TMP/c9"
R9="$D9/repo"
fx_mklinttree "$R9"
mkdir -p "$R9/tools"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$R9/tools/shellcheck"
chmod +x "$R9/tools/shellcheck"
(
    cd "$R9" && "${RUN_LINT[@]}"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if ((FX_BLOCK_RC != 0)); then
    fx_ok
else fx_bad "lint passed with shfmt absent (a false PASS)"; fi
fx_err 'shfmt not found at .*/tools/shfmt'
fx_err 'run: bash scripts/install-tools.sh'
fx_out_not '^lint: OK$'

printf -- '--- D1 group 5: the real lint, on the real pinned tools ---\n'

if [[ -x "$REAL_SHELLCHECK" && -x "$REAL_SHFMT" ]]; then
    if printf '%s  %s\n' "$SHFMT_PIN" "$REAL_SHFMT" | sha256sum -c - >/dev/null 2>&1; then
        fx_ok
    else fx_bad "this host's tools/shfmt does not match the pinned digest"; fi
    if [[ "$("$REAL_SHELLCHECK" --version 2>/dev/null | sed -n 's/^version: //p' || true)" == "${SC_VER#v}" ]]; then
        fx_ok
    else fx_bad "this host's tools/shellcheck is not the pinned ${SC_VER}"; fi

    # clean copy of the shipped code -> the real lint passes
    DA="$FX_TMP/rclean"
    fx_mklinttree "$DA"
    cp "$REAL_SHELLCHECK" "$DA/tools/shellcheck"
    cp "$REAL_SHFMT" "$DA/tools/shfmt"
    chmod +x "$DA/tools/shellcheck" "$DA/tools/shfmt"
    (
        cd "$DA" && "${RUN_LINT[@]}"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "the real lint passes on the shipped code" 0
    fx_out '^lint: OK$'

    # an injected shellcheck violation must be caught by the real shellcheck.
    # SC2155 is used deliberately: SC2034 is DISABLED in .shellcheckrc, so the
    # obvious "unused variable" injection would have made this cell vacuous.
    DB="$FX_TMP/rsc"
    fx_mklinttree "$DB"
    cp "$REAL_SHELLCHECK" "$DB/tools/shellcheck"
    cp "$REAL_SHFMT" "$DB/tools/shfmt"
    chmod +x "$DB/tools/shellcheck" "$DB/tools/shfmt"
    cat >"$DB/lib/pkg/zz_d1_probe.sh" <<'PROBE'
#!/usr/bin/env bash
_d1_probe() {
    local out="$(echo d1)"
    printf '%s' "$out"
}
PROBE
    (
        cd "$DB" && "${RUN_LINT[@]}"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    if ((FX_BLOCK_RC != 0)); then
        fx_ok
    else fx_bad "the real lint passed a shellcheck violation"; fi
    # Findings are printed on STDOUT (measured for the same run: 463 bytes on
    # stdout, 0 on stderr), so pinning them to stderr would be vacuous.
    fx_out 'SC2155'
    fx_out 'zz_d1_probe.sh'
    fx_err '^lint: FAILED$'
    fx_out_not '^lint: OK$'

    # an injected shfmt violation must be caught by the real shfmt.
    DC="$FX_TMP/rfmt"
    fx_mklinttree "$DC"
    cp "$REAL_SHELLCHECK" "$DC/tools/shellcheck"
    cp "$REAL_SHFMT" "$DC/tools/shfmt"
    chmod +x "$DC/tools/shellcheck" "$DC/tools/shfmt"
    cat >"$DC/lib/zz_d1_fmt_probe.sh" <<'PROBE'
#!/usr/bin/env bash
if  true
then
    printf 'x\n'
fi
PROBE
    (
        cd "$DC" && "${RUN_LINT[@]}"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    if ((FX_BLOCK_RC != 0)); then
        fx_ok
    else fx_bad "the real lint passed an shfmt violation"; fi
    # shfmt -d writes its diff to STDOUT too (measured: 170 bytes / 0).
    fx_out 'zz_d1_fmt_probe.sh'
    fx_err '^lint: FAILED$'
    fx_out_not '^lint: OK$'
else
    fx_skip "real pinned lint cells (tools/{shellcheck,shfmt} not installed on this host)"
fi

printf -- '--- D1 group 6: the workflow is valid YAML and stays failure-visible ---\n'

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
    (cd "$REPO" && python3 -c '
import sys, yaml
with open(".github/workflows/ci.yml") as fh:
    doc = yaml.safe_load(fh)
jobs = doc["jobs"]
lint = jobs["lint"]
assert lint["runs-on"] == "ubuntu-latest", lint["runs-on"]
runs = [s.get("run") for s in lint["steps"] if "run" in s]
assert runs == ["bash scripts/install-tools.sh", "make lint"], runs
for name, job in jobs.items():
    for step in job["steps"]:
        assert "continue-on-error" not in step, (name, step)
        r = step.get("run")
        if r:
            for line in r.splitlines():
                assert "|| true" not in line, (name, line)
                assert "|| :" not in line, (name, line)
                assert not line.rstrip().endswith("|| exit 0"), (name, line)
print("workflow-ok")
') >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "ci.yml parses and the lint job provisions then lints" 0
    fx_out '^workflow-ok$'
else
    fx_skip "ci.yml YAML validation (python3 with PyYAML is unavailable on this host)"
fi

# The provisioning and lint steps must not hide failure. Pinned as text as
# well, so the assertion survives a future reordering of the YAML keys.
if grep -q 'run: bash scripts/install-tools.sh' "$CI_YML"; then
    fx_ok
else fx_bad "ci.yml no longer provisions tools with scripts/install-tools.sh"; fi
if grep -q 'run: make lint' "$CI_YML"; then
    fx_ok
else fx_bad "ci.yml no longer runs make lint"; fi
# Comment lines are stripped first: this fixture's own header explains that
# `|| true` was the defect, and a naive grep matched that prose. Only real
# workflow content may decide this assertion.
if grep -vE '^[[:space:]]*#' "$CI_YML" | grep -nE '\|\| *true|continue-on-error' >/dev/null 2>&1; then
    fx_bad "ci.yml hides a failure behind '|| true' or continue-on-error"
else fx_ok; fi
# That no rpm-family tool is invoked is NOT asserted here by grepping the script
# for those words: a static text search cannot distinguish an invocation from the
# same words inside a printf'd error message, and a first draft of this fixture
# matched exactly that. Cell 6 answers it behaviourally with logging stubs.
# What IS worth pinning statically is that the shfmt artifact is version-pinned
# rather than floating, since the old D1 defect was an unversioned `dnf download`.
if [[ "$SHFMT_URL" == *'${SHFMT_VERSION}'* ]]; then
    fx_ok
else fx_bad "SHFMT_URL does not interpolate SHFMT_VERSION (it may be floating)"; fi
if [[ "$SHFMT_URL" == *latest* ]]; then fx_bad "SHFMT_URL floats on 'latest'"; else fx_ok; fi
if [[ "$SHFMT_URL" == *'shfmt_${SHFMT_VERSION}_linux_amd64'* ]]; then
    fx_ok
else fx_bad "SHFMT_URL is no longer the pinned upstream release asset name"; fi
if [[ "$SHFMT_VER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fx_ok
else fx_bad "SHFMT_VERSION is not a concrete vMAJOR.MINOR.PATCH pin"; fi
if [[ ${#SHFMT_PIN} -eq 64 ]]; then
    fx_ok
else fx_bad "SHFMT_SHA256 is not a 64-character digest"; fi
if [[ "$SHFMT_PIN" =~ ^[0-9a-f]{64}$ ]]; then
    fx_ok
else fx_bad "SHFMT_SHA256 is not lowercase hex"; fi
if [[ ${#SC_VER} -gt 1 && "$SC_VER" == v* ]]; then
    fx_ok
else fx_bad "SHELLCHECK_VERSION is not a v-prefixed pin"; fi

printf -- '--- D3 group 7: every action is SHA-pinned and every job is timeout-bounded ---\n'

# ROADMAP finding F4b. Two properties, both static because the workflow has
# never been executed and no execution may be claimed:
#
#   7a. PINNING. Every action reference is a full 40-hex commit SHA, and the
#       release version stays readable in a trailing comment. A floating tag
#       (@v4) means the code CI runs can change under a green build with no
#       diff in this repository, which is the supply-chain gap itself.
#   7b. BOUNDING. Every job declares timeout-minutes, and the container job's
#       cap stays ABOVE FS_CTR_TIMEOUT -- on that deadline the smoke script
#       reports INCONCLUSIVE and exits non-zero, so a cap at or below it would
#       replace a diagnosable failure with a bare "exceeded timeout".
#
# Both the YAML path and a parser-free text path are asserted. The text path
# strips comment lines FIRST: this fixture's own header, and D3's header in
# ci.yml, both discuss these very words, and D1 already shipped one cell that
# matched its own prose.
WF_DIR="$REPO/.github/workflows"
shopt -s nullglob
wf_files=("$WF_DIR"/*.yml "$WF_DIR"/*.yaml)
shopt -u nullglob
if ((${#wf_files[@]} == 0)); then
    fx_bad "no workflow files found under .github/workflows"
else fx_ok; fi

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
    (cd "$REPO" && python3 -c '
import glob, re, sys, yaml
sha = re.compile(r"^[0-9a-f]{40}$")
ctr_env = None
for path in sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")):
    doc = yaml.safe_load(open(path))
    for line in open(path):
        m = re.search(r"FS_CTR_TIMEOUT=([0-9]+)", line)
        if m:
            ctr_env = int(m.group(1))
    for name, job in doc["jobs"].items():
        steps = job["steps"]
        # 7a, per job: at least one action, and every action SHA-pinned.
        refs = [s["uses"] for s in steps if "uses" in s]
        assert refs, (path, name, "job checks out nothing")
        for r in refs:
            at = r.rsplit("@", 1)
            assert len(at) == 2, (path, name, r)
            assert sha.match(at[1]), (path, name, "not a 40-hex commit SHA", r)
        # 7b, per job: an explicit, positive, integral bound.
        assert "timeout-minutes" in job, (path, name, "no timeout-minutes")
        t = job["timeout-minutes"]
        assert isinstance(t, int) and t > 0, (path, name, t)
        if name == "container":
            assert ctr_env is not None, (path, "no FS_CTR_TIMEOUT to compare against")
            assert t * 60 > ctr_env, (path, "job cap", t * 60, "<= FS_CTR_TIMEOUT", ctr_env)
print("pinning-ok")
') >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "every job is SHA-pinned, version-commented and timeout-bounded" 0
    fx_out '^pinning-ok$'
else
    fx_skip "D3 YAML assertions (python3 with PyYAML is unavailable on this host)"
fi

# Text path, parser-free, so the two properties are still asserted on a host
# without PyYAML. It reads real content only: comment lines are dropped before
# any match, and the two greps below count the SAME lines.
for wf in ${wf_files[@]+"${wf_files[@]}"}; do
    wf_base="$(basename "$wf")"
    wf_uses="$(grep -vE '^[[:space:]]*#' "$wf" | grep -cE '^[[:space:]]*-[[:space:]]+uses:' || true)"
    wf_pinned="$(grep -vE '^[[:space:]]*#' "$wf" |
        grep -cE '^[[:space:]]*-[[:space:]]+uses:[[:space:]]*[^[:space:]@]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+(\.[0-9]+)*[[:space:]]*$' || true)"
    if ((wf_uses > 0)); then fx_ok; else fx_bad "$wf_base has no action references at all"; fi
    if ((wf_uses == wf_pinned)); then
        fx_ok
    else
        fx_bad "$wf_base has $wf_uses action references but only $wf_pinned are SHA-pinned with a version comment"
    fi
    wf_timeouts="$(grep -vE '^[[:space:]]*#' "$wf" | grep -cE '^[[:space:]]*timeout-minutes:[[:space:]]*[0-9]+[[:space:]]*$' || true)"
    if ((wf_timeouts >= 1)); then fx_ok; else fx_bad "$wf_base declares no timeout-minutes"; fi
done

# The container cap must exceed FS_CTR_TIMEOUT, read from the workflow itself so
# the relation cannot rot into comparing against a restated constant. Parsed
# with sed rather than eval'd, and the value is range-checked first.
CTR_ENV_RAW="$(grep -oE 'FS_CTR_TIMEOUT=[0-9]+' "$CI_YML" | head -1 | cut -d= -f2)"
if [[ "$CTR_ENV_RAW" =~ ^[0-9]+$ ]] && ((CTR_ENV_RAW > 0)); then
    fx_ok
else fx_bad "could not read a positive FS_CTR_TIMEOUT out of ci.yml"; fi
CTR_JOB_TMO=""
awk '/^  container:/{inc=1; next} /^  [a-z]+:/{inc=0} inc && /^    timeout-minutes:[[:space:]]*[0-9]+/{
    gsub(/[^0-9]/, "", $0); print
}' "$CI_YML" >"$FX_TMP/ctr_tmo"
CTR_JOB_TMO="$(cat "$FX_TMP/ctr_tmo")"
if [[ "$CTR_JOB_TMO" =~ ^[0-9]+$ ]] && ((CTR_JOB_TMO * 60 > CTR_ENV_RAW)); then
    fx_ok
else
    fx_bad "container job cap (${CTR_JOB_TMO:-none} min) does not exceed FS_CTR_TIMEOUT (${CTR_ENV_RAW:-none}s): the diagnosable INCONCLUSIVE path would never be reached"
fi

printf 'lint-driver: %s\n' "$RUN_LINT_DESC"

if ((FX_SKIP > 0)); then
    printf 'summary: %s passed, %s failed, %s skipped (real pinned tools or PyYAML unavailable)\n' \
        "$FX_PASS" "$FX_FAIL" "$FX_SKIP"
    ((FX_FAIL == 0))
else
    fx_summary
fi
