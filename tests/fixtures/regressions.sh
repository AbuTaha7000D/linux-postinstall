#!/usr/bin/env bash
# tests/fixtures/regressions.sh - P10.5 fixture: the six DOCUMENTED
# prototype bugs, each locked as a named regression.
#
# Reference for every "old behavior" below is tag `proto-baseline`
# (commit 048f969), the shell prototype deleted in 16bdb1e. Each cell names
# the prototype's own idiom, embeds that idiom verbatim as a POSITIVE
# CONTROL, and then asserts the current tree cannot do it.
#
#   cell 1  sudoers   setup.sh READ /etc/sudoers (line 33) and WROTE it with
#                     `sed -i` (39, 131, 144) and `tee -a` (42). AGENTS.md §9
#                     forbids read AND write. Production: zero references.
#   cell 2  .bashrc   set_aliases.sh line 15: `cp additions/shell_conf
#                     ~/.bashrc` - wholesale replace. Production writes
#                     dotfiles only through lib/fs.sh managed blocks.
#   cell 3  flathub   install_apps.sh ran `flatpak install flathub <app>` with
#                     ZERO `flatpak remote-add` anywhere in the prototype
#                     (`git grep remote-add proto-baseline` -> no match), so
#                     every GUI install failed on a host without the remote.
#                     Cell 3 pins remote-add strictly before install, in BOTH
#                     the real and the dry-run branch.
#   cell 4  gsettings add_custom_shortcut.sh line 33 rewrote the
#                     custom-keybindings array with
#                     `sed "s/]$/, '/$new_binding/']/"` and lines 21-23
#                     stripped retrieved values with `sed "s/'//g"`. Two
#                     separate, separately-pinned defects; see the cell.
#   cell 5  fonts     install_fonts.sh line 14: `cp -r additions/fonts/*
#                     ~/.fonts/`, with 234 files / 261,322,112 bytes
#                     (249.22 MiB) of font binaries COMMITTED to the repo
#                     (`git ls-tree -r -l proto-baseline additions/fonts/`).
#   cell 6  tab loop  gnome_extensions.sh opened 18 URLs in a BACKGROUNDED
#                     loop and answered any non-Y with `bash "$0"` (line 43),
#                     reopening every tab forever. Cell 6 pins no self-re-exec
#                     and a hard cap of 2, sequential, once.
#
# WHY EVERY STATIC SCAN HAS A POSITIVE CONTROL: a "0 hits" assertion is
# satisfied by a broken scanner just as happily as by clean code. Every
# pattern below is therefore also run over a synthetic control carrying the
# prototype's own idiom, and that control MUST be reported. The comment
# stripper has three controls of its own, including one that proves it does
# not over-strip a `#` inside a quoted string (an over-stripping stripper
# would blind the scan, which is the dangerous direction).
#
# THE CONTROLS ARE INJECTED BY THIS FIXTURE, NOT FOUND IN THE TREE - stated
# explicitly, because a header claiming the repository already contains the
# forbidden pattern would be false (there is no `additions/` directory, no
# sed-based gsettings rewriter, and no backgrounded xdg-open anywhere in
# production; all three are the BUGS being tested for). Each cell writes its
# control into $FX_TMP and requires the matcher to report it:
#   $FX_TMP/ctrl1/prototype.sh   the prototype's 3 sudoers lines (read, sed -i,
#                                tee -a) plus a safe run_sudo control
#   $FX_TMP/ctrl2/prototype.sh   cp / > redirect / sed -i.bak onto ~/.bashrc
#   $FX_TMP/ctrl2b/proto.sh      an additions/ reference (the vendored dir)
#   $FX_TMP/ctrl4/prototype.sh   the prototype's multi-line sed+gsettings stanza
#   $FX_TMP/ctrl4/sedscript.sh   gsettings set INSIDE a multi-line sed script
#   $FX_TMP/ctrl4/clean.sh       gsettings with no sed nearby - must NOT fire
#   $FX_TMP/ctrl5/*.ttf          a font path, for the by-NAME vendored check
#   $FX_TMP/ctrl6/rebash.sh      `bash "$0"` self-re-exec
#   $FX_TMP/ctrl6/reexec.sh      `exec "$0"` self-re-exec
#   $FX_TMP/ctrl6/bgamp*.sh      xdg-open backgrounded with `&>` and with a
#                                bare trailing `&`
#
# HONEST LIMIT OF THE METHOD, stated because it is the whole story: blinding
# the scanner cannot fail any production "0 hits" assertion BY CONSTRUCTION -
# all the failures it produces come from the positive controls. So the negative
# control that proves this suite works is a one-way proof: it shows the
# controls are live, not that the production scans are. That is why every
# production scan is paired with a control carrying the prototype's VERBATIM
# idiom, and why two review findings (a same-line `sed ... gsettings` pattern
# that missed the prototype's multi-line stanza, and a browse pattern that
# missed `&>`) existed at all: both scans were unvalidated token greps.
#
# WHAT EACH CELL ADDS OVER EXISTING COVERAGE, honestly:
#   cell 1, 2, 5, 6  new - no existing suite pins the prototype bug itself.
#   cell 3    the real-mode ordering is ALSO pinned by P10.4's
#             tests/fixtures/integration.sh (its cell 3) and by
#             tests/fixtures/mod_flatpak.sh; the DRY-RUN branch ordering added
#             here was NOT covered by either.
#   cell 4    the strv primitives are covered by tests/fixtures/gnome.sh; the
#             "no sed rewriter anywhere in production" scan is new.
#   cell 6    the cap of 2 is ALSO pinned by tests/fixtures/
#             mod_gnome_extensions.sh (P6.3, NOT integration.sh - a first draft
#             of this header credited integration.sh, which contains no
#             browse/xdg-open assertion at all); the 20-URL overflow and the
#             self-re-exec scan are new.
#
# SCOPE: the production tree is derived from `git ls-files` minus `tests/` and
# minus `*.md`, so it covers every tracked file including a new top-level
# directory, and excludes the vendored gitignored toolchain in tools/.
# Documentation is excluded by CONTENT TYPE, not by a directory allowlist: an
# earlier revision scanned `lib/* modules/* setup`, which silenced a false
# positive on ROADMAP.md (it DESCRIBES the prototype's sed/gsettings rewriter
# in prose) by reintroducing the very defect the N3 review finding was about -
# a new top-level directory became invisible and a sudoers write there escaped.
# If the list comes back empty the fixture FAILS LOUD rather than reporting six
# vacuous passes. `sed` proximity scanning is deliberately window-based: the
# prototype put `sed` and `gsettings` on DIFFERENT lines, and a same-line
# alternation missed it.
#
# THE CELL-4 WINDOW IS TUNED, AND ITS MARGIN IS 1 (measured, not assumed):
# cell 4 fires when a `sed` line and a `gsettings`/`custom-keybinding` line are
# within 4 lines. In this tree the CLOSEST such pair in legitimate code is 5
# lines apart (modules/gnome-base/hooks.sh: sed@29, gsettings@5), so 4 is the
# widest window that does not false-positive on the shipped tree. Two
# consequences a future edit must respect: (a) the window CANNOT be widened to
# catch more shapes - at 5 it would already fire on clean production - so a
# genuinely more distant rewrite is out of this scan's reach and is a stated
# limit, not a gap to be papered over; (b) editing modules/gnome-base/hooks.sh
# so those two tokens approach each other WILL make cell 4 fail, and that
# failure means "re-tune this deliberately", not "the scan is broken".
#
# LIMIT OF THE "committed" framing (cells 1-2, 5-6): the scans read TRACKED
# files, which is exactly the state the bug occurred in - the prototype shipped
# 249.22 MiB of font binaries IN the repository. An UNTRACKED file is out of
# scope by construction: a runtime download is deliberately invisible to these
# scans, because the fonts module itself downloads archives into the worktree.
# For cell 5 there is a second, independent line of defence (.gitignore:35
# `assets/fonts/*`), which is why the vendored-font mutation must use `git add
# -f` to reproduce the committed state at all.
#
# MEASURED EVIDENCE (re-run on every change to this file):
#   baseline            69 passed, 0 failed
#   mutations           17 applied, 17 caught (M1-M7 round one; R1-R9 and R1b
#                       are reviewer-driven reintroductions, incl. the
#                       multi-line sed stanza, gsettings set INSIDE a
#                       multi-line sed script, the `>` redirect, `sed -i.bak`,
#                       `&>`, `exec "$0"`, a sudoers write in a NEW top-level
#                       dir, a COMMITTED zip at the repo root, the dry-run
#                       branch order, and a warn-only digest check). Every one
#                       is caught BY THE INTENDED CELL, not by a side effect:
#                       the harness prints the FAIL line, and the bytes are
#                       compared with cmp so a no-op edit cannot pass as a catch.
#   negative controls   2, both failing the suite as they must: blinding all
#                       four matchers (69->57) and loosening the managed-block
#                       marker pin to a prefix (69->68). The prefix control is
#                       load-bearing only because cell 2 writes a SECOND named
#                       block into the same .bashrc; with one block the two
#                       pins are equivalent and the control escapes by
#                       construction. That is stated rather than discovered.
#   wider suite         make lint OK; smoke 169/0 (stderr empty);
#                       tests/run rc 0, 59 tests, regressions = #53;
#                       full battery byte-identical across 3 runs,
#                       sha256 first 16 = f844c619d560cf2c
#
# The prototype is deliberately NOT read at run time: these cells stay
# hermetic and need no prototype history, so they behave identically in a
# shallow CI clone. Its lines are embedded verbatim above instead.
#
# Mock strategy: the REAL production code does the work (lib/fs.sh,
# lib/state.sh, lib/gnome.sh, lib/pkg/flatpak.sh, the shipped browse.list and
# config/nerdfonts.sha256). Only external programs are faked, on PATH under
# FX_TMP. Nothing touches the network, /etc, or the real $HOME.
#
# Usage: bash tests/fixtures/regressions.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
printf 'P10.5 prototype-bug regressions (proto-baseline %s)\n' "048f969"

# ---------------------------------------------------------------- scanners
# prod_files: every tracked production file (tests/ excluded - by construction
# it contains the very patterns being scanned for).
prod_files() {
    git -C "$ROOT" ls-files 2>/dev/null | grep -v '^tests/' || true
}

# strip_comments: drop full-line and trailing comments, quote-aware, so a `#`
# inside a quoted string (e.g. a sed script) survives.
strip_comments() {
    awk '{
        line = $0; out = ""; i = 1; n = length(line); sq = 0; dq = 0
        while (i <= n) {
            c = substr(line, i, 1)
            if (sq) {
                if (c == "\047") {
                    if (substr(line, i + 1, 1) == "\047") { out = out c c; i += 2; continue }
                    sq = 0
                }
            } else if (dq) {
                if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
                if (c == "\042") dq = 0
            } else {
                if (c == "\047") sq = 1
                else if (c == "\042") dq = 1
                else if (c == "#" && (i == 1 || substr(line, i - 1, 1) == " " ||
                    substr(line, i - 1, 1) == "\t")) break
            }
            out = out c
            i++
        }
        print out
    }'
}

# code_hits <ere> <file...>: report "file:line: text" for every NON-COMMENT
# line matching <ere>. grep runs with -a and its rc is checked, so a binary or
# unreadable file is reported as UNSCANNABLE rather than silently yielding
# nothing (the fail-open shape P9.4 found in [[ -e ]]).
code_hits() {
    local pat="$1"
    shift
    local f ln text grc
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r ln; do
            text="${ln#*:}"
            text="${text#"${text%%[![:space:]]*}"}"
            case "$text" in
                '#'*) continue ;;
            esac
            printf '%s:%s\n' "$f" "$ln"
        done < <(strip_comments <"$f" | grep -naE "$pat" || true)
        grc=0
        grep -qaE "$pat" "$f" >/dev/null 2>&1 || grc=$?
        if ((grc > 1)); then
            printf 'UNSCANNABLE: %s\n' "$f"
        fi
    done
}

# near_hits <ere-a> <ere-b> <window> <file...>: report lines where <ere-a> and
# <ere-b> co-occur within <window> lines. Needed because the prototype's
# gsettings rewriter spans three lines.
near_hits() {
    local pa="$1" pb="$2" win="$3"
    shift 3
    local f al bl
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        al="$(strip_comments <"$f" | grep -naE "$pa" | cut -d: -f1 || true)"
        bl="$(strip_comments <"$f" | grep -naE "$pb" | cut -d: -f1 || true)"
        for al in $al; do
            for bl in $bl; do
                if ((al >= bl - win && al <= bl + win)); then
                    printf '%s:%s+%s\n' "$f" "$al" "$bl"
                fi
            done
        done
    done
}

# code_files: every tracked non-test file that is not documentation.
#
# Deliberately NOT a directory allowlist. A previous revision of this fixture
# scanned `lib/* modules/* setup`, which fixed a false positive on ROADMAP.md
# (it DESCRIBES the prototype's sed/gsettings rewriter in prose) by
# reintroducing the exact defect reviewer finding N3 was about: a new
# top-level directory is then invisible, and a sudoers write there escapes.
# Excluding by CONTENT TYPE instead means a new directory is covered the day it
# is added, with no edit to this list.
code_files() {
    local f
    for f in "${PROD_ALL[@]}"; do
        case "$f" in
            *.md) ;;
            *) printf '%s\n' "$f" ;;
        esac
    done
}

# name_hits <ere>: report tracked PATHS whose NAME matches, so the vendored-blob
# check is about what is COMMITTED, not about file contents.
name_hits() {
    local re="$1" f
    for f in "${PROD_ALL[@]}"; do
        [[ "$f" =~ $re ]] && printf '%s\n' "$f"
    done
    return 0
}

# name_hits_in <path> <ere>: the same relation over one explicit path, so a
# positive control can prove the matcher fires at all.
name_hits_in() {
    local p="$1" re="$2"
    [[ "$p" =~ $re ]] && printf '%s\n' "$p"
    return 0
}

mapfile -t PROD_ALL < <(prod_files)
if ((${#PROD_ALL[@]} == 0)); then
    printf 'FATAL: production file list is empty (not a git checkout?)\n' >&2
    printf 'summary: 0 passed, 1 failed\n'
    exit 1
fi
mapfile -t CODE_ALL < <(code_files)

# =====================================================================
printf -- '--- cell 1: no sudoers read or write anywhere in production\n'
# =====================================================================
mkdir -p "$FX_TMP/ctrl1"
printf '# never touches /etc/sudoers (full-line comment)\n' \
    >"$FX_TMP/ctrl1/only_full_comment.sh"
printf '    io_error "x"   # and never /etc/sudoers (trailing comment)\n' \
    >"$FX_TMP/ctrl1/only_trail_comment.sh"
{
    printf '#!/usr/bin/env bash\n'
    printf "sudo sed -i 's/^Defaults\\s\\+timestamp_timeout=.*/Defaults timestamp_timeout=-1/' /etc/sudoers\n"
    printf "echo 'Defaults timestamp_timeout=-1' | sudo tee -a /etc/sudoers > /dev/null\n"
    printf 'original_timeout=$(sudo grep %s /etc/sudoers)\n' "'^Defaults'"
} >"$FX_TMP/ctrl1/prototype.sh"

[[ -z "$(code_hits 'sudoers' "$FX_TMP/ctrl1/only_full_comment.sh" || true)" ]] && fx_ok || \
    fx_bad "cell1 control: a full-line comment mention must NOT be reported"
[[ -z "$(code_hits 'sudoers' "$FX_TMP/ctrl1/only_trail_comment.sh" || true)" ]] && fx_ok || \
    fx_bad "cell1 control: a trailing comment mention must NOT be reported"
pc1p="$(code_hits 'sudoers' "$FX_TMP/ctrl1/prototype.sh" || true)"
[[ "$(grep -c . <<<"$pc1p")" == 3 ]] && fx_ok || \
    fx_bad "cell1 control: all 3 prototype sudoers lines must be reported (got $(grep -c . <<<"$pc1p"))"
grep -q 'sed -i' <<<"$pc1p" && fx_ok || fx_bad "cell1 control: prototype sed -i line detected"
grep -q 'tee -a' <<<"$pc1p" && fx_ok || fx_bad "cell1 control: prototype tee -a line detected"
grep -q 'grep' <<<"$pc1p" && fx_ok || fx_bad "cell1 control: prototype read line detected"

s1="$(code_hits 'sudoers' "${CODE_ALL[@]}" 2>&1 || true)"
grep -q '^UNSCANNABLE' <<<"$s1" && fx_bad "cell1: some production file was UNSCANNABLE: $s1"
[[ -z "$s1" ]] && fx_ok || \
    fx_bad "cell1: production references sudoers (AGENTS §9 forbids read AND write): $s1"
# Pin the real escalation, not the WORD "run_sudo" (an io_error string
# mentioning run_sudo satisfied a looser version of this pin).
grep -qE '^[^#]*-- sudo -- ' "$ROOT/lib/run.sh" && fx_ok || \
    fx_bad "cell1 sanity: lib/run.sh must contain the real `sudo --` escalation"

# C1 widened this cell rather than opening a parallel one. C1 added a NEW
# sudo invocation (`sudo -v`, the credential refresh), so the invariant now
# also covers the ways a tool persists privilege WITHOUT necessarily
# spelling "sudoers": `visudo` on some other path, a NOPASSWD rule, and the
# prototype's own timestamp_timeout mutation (which writes a file whose
# contents never contain the word "sudoers"). Each pattern carries its own
# positive control, because a "0 hits" assertion is satisfied just as
# happily by a dead scanner as by clean code.
printf '#!/usr/bin/env bash\nvisudo -f "$1" <<EOF\nroot ALL=(ALL) ALL\nEOF\n' \
    >"$FX_TMP/ctrl1/visudo_write.sh"
printf '#!/usr/bin/env bash\nprintf "%%user ALL=(ALL) NOPASSWD: ALL\\n" > /run/nopasswd.new\n' \
    >"$FX_TMP/ctrl1/nopasswd_rule.sh"
printf '#!/usr/bin/env bash\nsudo sed -i "s/^Defaults\\s\\+timestamp_timeout=.*/Defaults timestamp_timeout=-1/" /run/tmo.new\n' \
    >"$FX_TMP/ctrl1/timestamp_timeout.sh"
c1v="$(code_hits 'visudo' "$FX_TMP/ctrl1/visudo_write.sh" || true)"
[[ -n "$c1v" ]] && fx_ok || fx_bad "cell1 control: a visudo write must be reported"
c1n="$(code_hits 'NOPASSWD' "$FX_TMP/ctrl1/nopasswd_rule.sh" || true)"
[[ -n "$c1n" ]] && fx_ok || fx_bad "cell1 control: a NOPASSWD rule must be reported"
c1t="$(code_hits 'timestamp_timeout' "$FX_TMP/ctrl1/timestamp_timeout.sh" || true)"
[[ -n "$c1t" ]] && fx_ok || fx_bad "cell1 control: a timestamp_timeout write must be reported"
# A comment naming the mechanism is documentation, not a write: the
# stripper must not report it, or a header would trip the scan.
printf '# this comment mentions visudo, NOPASSWD and timestamp_timeout\n' \
    >"$FX_TMP/ctrl1/only_comment.sh"
c1z="$(code_hits 'visudo|NOPASSWD|timestamp_timeout' "$FX_TMP/ctrl1/only_comment.sh" || true)"
[[ -z "$c1z" ]] && fx_ok || \
    fx_bad "cell1 control: comment-only mentions must NOT be reported: $c1z"

for pat in visudo NOPASSWD timestamp_timeout; do
    hits="$(code_hits "$pat" "${CODE_ALL[@]}" 2>&1 || true)"
    grep -q '^UNSCANNABLE' <<<"$hits" && \
        fx_bad "cell1: some production file was UNSCANNABLE ($pat): $hits"
    [[ -z "$hits" ]] && fx_ok || \
        fx_bad "cell1: production references '$pat' (AGENTS §9 forbids read AND write; C1 forbids a persistent credential change): $hits"
done

# =====================================================================
printf -- '--- cell 2: .bashrc gets a managed block, never a wholesale overwrite\n'
# =====================================================================
mkdir -p "$FX_TMP/ctrl2"
{
    printf '#!/usr/bin/env bash\n'
    printf 'cp "$ADDITIONS_DIR/shell_conf" "$HOME/.bashrc"\n'
    printf 'printf %%s\\\\n "$body" >"$HOME/.bashrc"\n'
    printf 'sed -i.bak "1d" "$HOME/.bashrc"\n'
} >"$FX_TMP/ctrl2/prototype.sh"
PC2='(cp|mv|install|tee|truncate|shred)[[:space:]][^#]*\.(bashrc|zshrc|profile)|sed[[:space:]]+-[a-zA-Z.]*[[:space:]][^#]*\.(bashrc|zshrc|profile)|>[[:space:]]*"[^"]*\.(bashrc|zshrc|profile)"'
pc2="$(code_hits "$PC2" "$FX_TMP/ctrl2/prototype.sh" || true)"
[[ "$(grep -c . <<<"$pc2")" == 3 ]] && fx_ok || \
    fx_bad "cell2 control: cp, > redirect and sed -i.bak forms all detected (got $(grep -c . <<<"$pc2"))"

s2="$(code_hits "$PC2" "${CODE_ALL[@]}" 2>&1 || true)"
[[ -z "$s2" ]] && fx_ok || fx_bad "cell2: production clobbers a dotfile: $s2"
mkdir -p "$FX_TMP/ctrl2b"
printf '#!/usr/bin/env bash\nFONT_DIR="$SCRIPT_DIR/additions/fonts"\ncp -r "$FONT_DIR"/* "$HOME/.fonts/"\n' \
    >"$FX_TMP/ctrl2b/proto.sh"
[[ -n "$(code_hits '(^|[^a-zA-Z_])additions/' "$FX_TMP/ctrl2b/proto.sh" || true)" ]] && fx_ok || \
    fx_bad "cell2 control: an additions/ reference must be reported"
s2b="$(code_hits '(^|[^a-zA-Z_])additions/' "${CODE_ALL[@]}" 2>&1 || true)"
[[ -z "$s2b" ]] && fx_ok || fx_bad "cell2: production still references the prototype additions/ dir: $s2b"

BRC="$FX_TMP/home2/.bashrc"
BRC_CONTENT="git config --global --add safe.directory '*'"
TERM_CONTENT="alias ll='ls -l'"
mkdir -p "$(dirname "$BRC")"
printf '# my own rc\nexport MINE=1\nalias ll="ls -l"\n# tail comment\n' >"$BRC"
(
    set -uo pipefail
    export FS_HOME="$FX_TMP/state2"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/state.sh"
    source "$ROOT/lib/fs.sh"
    state_init || exit 1
    fs_managed_block "$BRC" "git" "$BRC_CONTENT"
    printf 'rc=%s\n' "$?" >"$FX_TMP/brc1.rc"
    fs_managed_block "$BRC" "git" "$BRC_CONTENT"
    printf 'rc=%s\n' "$?" >"$FX_TMP/brc2.rc"
    # a SECOND, differently-named block, exactly as a real .bashrc accumulates
    # one per module. Without it a prefix-tolerant marker pin (say
    # '^# BEGIN fedora-setup' instead of '^# BEGIN fedora-setup git$') is
    # EQUIVALENT on this input, so the cell could not tell the two apart.
    fs_managed_block "$BRC" "terminal" "$TERM_CONTENT"
    printf 'rc=%s\n' "$?" >"$FX_TMP/brc3.rc"
) >"$FX_TMP/brc.out" 2>&1
grep -qx 'rc=0' "$FX_TMP/brc1.rc" && fx_ok || fx_bad "cell2: first managed-block write returns 0"
grep -qx 'rc=0' "$FX_TMP/brc2.rc" && fx_ok || fx_bad "cell2: re-run (idempotency) returns 0"
grep -qx 'rc=0' "$FX_TMP/brc3.rc" && fx_ok || fx_bad "cell2: a second named block returns 0"
n_begin_t="$(grep -c '^# BEGIN fedora-setup terminal$' "$BRC")"
[[ "$n_begin_t" == 1 ]] && fx_ok || \
    fx_bad "cell2: exactly one BEGIN marker for terminal (got $n_begin_t)"
grep -Fqx "$TERM_CONTENT" "$BRC" && fx_ok || fx_bad "cell2: the second block's content is present"
grep -Fqx '# my own rc' "$BRC" && fx_ok || fx_bad "cell2: pre-existing header survives"
grep -Fqx 'export MINE=1' "$BRC" && fx_ok || fx_bad "cell2: pre-existing export survives"
grep -Fqx 'alias ll="ls -l"' "$BRC" && fx_ok || fx_bad "cell2: pre-existing alias survives"
grep -Fqx '# tail comment' "$BRC" && fx_ok || fx_bad "cell2: content AFTER the block survives too"
n_begin="$(grep -c '^# BEGIN fedora-setup git$' "$BRC")"
[[ "$n_begin" == 1 ]] && fx_ok || \
    fx_bad "cell2: exactly one BEGIN marker for git (got $n_begin)"
[[ "$(grep -c '^# END fedora-setup git$' "$BRC")" == 1 ]] && fx_ok || \
    fx_bad "cell2: exactly one END marker (got $(grep -c '^# END fedora-setup git$' "$BRC"))"
grep -Fq "safe.directory" "$BRC" && fx_ok || fx_bad "cell2: managed content was written"
[[ "$(grep -c "safe.directory" "$BRC")" == 1 ]] && fx_ok || \
    fx_bad "cell2: managed content is not duplicated on re-run"
[[ "$(wc -l <"$BRC")" -gt 5 ]] && fx_ok || fx_bad "cell2: result is longer than a bare replacement"

# =====================================================================
printf -- '--- cell 3: the flathub remote is established strictly before any install\n'
# =====================================================================
mkdir -p "$FX_TMP/fakebin3"
cat >"$FX_TMP/fakebin3/flatpak" <<'EOF'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
case "$1" in
    info) exit 1 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin3/flatpak"

fp_run() {
    local mode="$1" label="$2"
    : >"$FX_TMP/flatpak.log"
    (
        set -uo pipefail
        export PATH="$FX_TMP/fakebin3:$PATH" FAKE_LOG="$FX_TMP/flatpak.log"
        export FS_DRY_RUN="$mode"
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/run.sh"
        source "$ROOT/lib/pkg/flatpak.sh"
        flatpak_install_batch org.gnome.Builder org.mozilla.firefox
        printf 'rc=%s\n' "$?" >"$FX_TMP/fp3.$label.rc"
    ) >"$FX_TMP/fp3.$label.out" 2>&1
}
fp_order_ok() {
    local label="$1" log="${2:-$FX_TMP/flatpak.log}"
    grep -qx 'rc=0' "$FX_TMP/fp3.$label.rc" && fx_ok || fx_bad "cell3: $label returns 0"
    local n_add n_inst i_add i_inst
    n_add="$(grep -c 'flatpak remote-add' "$log" || true)"
    n_inst="$(grep -c 'flatpak install' "$log" || true)"
    [[ "$n_add" == 1 ]] && fx_ok || fx_bad "cell3: $label exactly one remote-add (got $n_add)"
    [[ "$n_inst" == 1 ]] && fx_ok || fx_bad "cell3: $label exactly one install batch (got $n_inst)"
    i_add="$(grep -n 'flatpak remote-add' "$log" | cut -d: -f1)"
    i_inst="$(grep -n 'flatpak install' "$log" | cut -d: -f1)"
    [[ -n "$i_add" && -n "$i_inst" && "$i_add" -lt "$i_inst" ]] && fx_ok || \
        fx_bad "cell3: $label remote-add (line $i_add) must precede install (line $i_inst)"
}
fp_run 0 real
fp_order_ok "real"
grep -q 'remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' \
    "$FX_TMP/flatpak.log" && fx_ok || fx_bad "cell3: remote-add is --if-not-exists flathub <url>"
grep -q 'install --user --noninteractive --assumeyes org.gnome.Builder org.mozilla.firefox' \
    "$FX_TMP/flatpak.log" && fx_ok || fx_bad "cell3: install batch carries both app ids"

fp_run 1 dry-run
fp_order_ok "dry-run" "$FX_TMP/fp3.dry-run.out"
# fp_order_ok matched substrings, so prove the file it just read really is the
# rendered PLAN and not an accidental execution: dry-run must use the
# `# would run:` rendering, and the fake flatpak must have run ZERO times.
[[ "$(grep -c '# would run: flatpak' "$FX_TMP/fp3.dry-run.out" || true)" == 2 ]] && fx_ok || \
    fx_bad "cell3: dry-run renders both steps with the would-run prefix"
[[ ! -s "$FX_TMP/flatpak.log" ]] && fx_ok || \
    fx_bad "cell3: dry-run must not execute flatpak (log: $(cat "$FX_TMP/flatpak.log"))"

# =====================================================================
printf -- '--- cell 4: gsettings array edits are escaped-aware, never sed rewrites\n'
# =====================================================================
source "$ROOT/lib/io.sh"
source "$ROOT/lib/gnome.sh"

mapfile -t G4 < <(gnome_strv_parse "['/custom0/', '/custom1/']")
[[ "${#G4[@]}" == 2 ]] && fx_ok || fx_bad "cell4: parse yields 2 elements (got ${#G4[@]})"
g4_rt="$(gnome_strv_build "${G4[@]}" 2>/dev/null || true)"
[[ "$g4_rt" == "['/custom0/', '/custom1/']" ]] && fx_ok || \
    fx_bad "cell4: parse->build round-trips byte-identically (got $g4_rt)"
g4_m="$(gnome_strv_merge "['/custom0/', '/custom1/']" '/custom1/' '/custom2/' 2>/dev/null || true)"
[[ "$g4_m" == "['/custom0/', '/custom1/', '/custom2/']" ]] && fx_ok || \
    fx_bad "cell4: merge appends once and dedupes, order preserved (got $g4_m)"
# An element needing escaping must be REFUSED, not written out unescaped.
# The element is deliberately quote-only and space-free: `a'b` isolates GVariant
# escaping from the separate space restriction, so this assertion is about the
# escaping rule alone. (A first draft used `sh -c 'echo hi'`, which the space
# rule already refuses - a mutation relaxing ONLY the quote rule did not move
# the count, which the harness correctly flagged as a broken mutation.)
g4_bad="$(gnome_strv_merge "['/custom0/']" "a'b" >/dev/null 2>&1 && echo accepted || echo refused)"
[[ "$g4_bad" == refused ]] && fx_ok || fx_bad "cell4: merge must refuse a quote-bearing element"

# The prototype's line 33, verbatim. Its replacement is `, '/$nb/'']`: the
# trailing `''` leaves an UNBALANCED quote, so no GVariant parser accepts the
# result - in the plain case, with no escaped element present at all. (An
# earlier draft attributed this refusal to the escaped element; it does not
# parse that element wrongly, it parses it correctly. The stray quote is the
# real cause, so the plain case is the load-bearing control here.)
P4_NB="/custom2/"
P4_PLAIN="$(printf %s "['/custom0/', '/custom1/']" | sed "s/]$/, '\/\$P4_NB\/'']/")"
[[ "$P4_PLAIN" == *"/\$P4_NB/"* ]] && fx_ok || \
    fx_bad "cell4 control: prototype sed left the binding unexpanded (got $P4_PLAIN)"
gnome_strv_parse "$P4_PLAIN" >/dev/null 2>&1 && fx_bad \
    "cell4: prototype sed output unexpectedly parsed: $P4_PLAIN" || fx_ok
# And the prototype's lines 21-23, `sed "s/'//g"`, cannot reproduce a true value.
P4_STRIP="$(printf %s "'sh -c \\'echo hi\\''" | sed "s/'//g")"
[[ "$P4_STRIP" != "sh -c 'echo hi'" ]] && fx_ok || \
    fx_bad "cell4 control: prototype s/'//g must not reproduce the true value"
# And the production scan must fire on the prototype's VERBATIM MULTI-LINE
# stanza, which a same-line `sed ... gsettings` alternation missed.
mkdir -p "$FX_TMP/ctrl4"
cat >"$FX_TMP/ctrl4/prototype.sh" <<'PCEOF'
#!/usr/bin/env bash
current_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
new_binding="custom$(echo "$current_bindings" | grep -o 'custom[0-9]*')"
updated_bindings=$(echo "$current_bindings" | sed "s/]$/, '\/\$new_binding\/'']/")
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_bindings"
PCEOF
pc4="$(near_hits '\bsed\b' 'gsettings|custom-keybinding' 4 "$FX_TMP/ctrl4/prototype.sh" || true)"
[[ -n "$pc4" ]] && fx_ok || \
    fx_bad "cell4 control: the prototype's multi-line sed/gsettings stanza must be reported"
# A SECOND multi-line shape: `gsettings set` living inside the TEXT of a
# multi-line sed script rather than in a separate statement. The control above
# covers sed-then-gsettings as two statements; this covers one token pair
# inside one command spanning several lines.
cat >"$FX_TMP/ctrl4/sedscript.sh" <<'PC4EOF'
#!/usr/bin/env bash
_rewrite_theme() {
    sed -n '
      /somepattern/ {
        s/.*/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"/
      }
    ' "$1" >"$2"
}
PC4EOF
[[ -n "$(near_hits '\bsed\b' 'gsettings|custom-keybinding' 4 "$FX_TMP/ctrl4/sedscript.sh" || true)" ]] && \
    fx_ok || fx_bad "cell4 control: gsettings set inside a multi-line sed script must be reported"
# Control: a file that only mentions gsettings, with no sed nearby, must NOT fire.
printf '#!/usr/bin/env bash\ngsettings get org.gnome.desktop.background picture-uri\n' \
    >"$FX_TMP/ctrl4/clean.sh"
[[ -z "$(near_hits '\bsed\b' 'gsettings|custom-keybinding' 4 "$FX_TMP/ctrl4/clean.sh" || true)" ]] && \
    fx_ok || fx_bad "cell4 control: a gsettings-only file must NOT be reported"
s4="$(near_hits '\bsed\b' 'gsettings|custom-keybinding' 4 "${CODE_ALL[@]}" 2>&1 || true)"
[[ -z "$s4" ]] && fx_ok || fx_bad "cell4: production rewrites a gsettings value with sed: $s4"

# =====================================================================
printf -- '--- cell 5: no vendored font blob; fonts are digest-pinned downloads\n'
# =====================================================================
mkdir -p "$FX_TMP/ctrl5"
: >"$FX_TMP/ctrl5/Junk.ttf"
FONT_RE='\.(ttf|otf|woff|woff2|ttc|zip)$'
printf 'x' >"$FX_TMP/ctrl5/Junk.ttf"
pc5="$(name_hits_in "$FX_TMP/ctrl5/Junk.ttf" "$FONT_RE")"
[[ "$(grep -c . <<<"$pc5")" == 1 ]] && fx_ok || fx_bad "cell5 control: a .ttf path must be detected"
# The prototype vendored its assets in additions/; cell 2 proves that scan fires.
[[ ! -d "$ROOT/additions" ]] && fx_ok || fx_bad "cell5: additions/ (the vendored asset dir) is back"
s5="$(name_hits "$FONT_RE")"
[[ -z "$s5" ]] && fx_ok || fx_bad "cell5: font binaries are vendored in the repo: $s5"
big5=""
for f in "${PROD_ALL[@]}"; do
    [[ -f "$ROOT/$f" ]] || continue
    if [[ "$(wc -c <"$ROOT/$f")" -gt 2097152 ]]; then
        big5+="$f "
    fi
done
[[ -z "$big5" ]] && fx_ok || \
    fx_bad "cell5: >2MiB tracked file in production (prototype shipped 249.22 MiB): $big5"
[[ -s "$ROOT/config/nerdfonts.sha256" ]] && fx_ok || fx_bad "cell5: config/nerdfonts.sha256 missing/empty"
grep -q 'nerdfonts.sha256' "$ROOT/modules/fonts/hooks.sh" && fx_ok || \
    fx_bad "cell5: fonts module does not use the pinned digest map"
# A digest check that only WARNS is not a digest check. Require that every
# `sha256sum -c` failure path is followed by an abort.
fonts_aborts() {
    local f="$1" n i
    mapfile -t n < <(grep -n 'sha256sum -c' "$f" | cut -d: -f1 || true)
    ((${#n[@]} > 0)) || return 1
    for i in "${n[@]}"; do
        sed -n "$((i + 1)),$((i + 3))p" "$f" | grep -q 'return 1' || return 1
    done
    return 0
}
printf 'a\nif ! printf x | sha256sum -c - ; then\n    io_error "mismatch"\n    return 1\nfi\n' \
    >"$FX_TMP/ctrl5/aborting.sh"
printf 'a\nif ! printf x | sha256sum -c - ; then\n    io_warn "mismatch"\nfi\n' \
    >"$FX_TMP/ctrl5/warnonly.sh"
fonts_aborts "$FX_TMP/ctrl5/aborting.sh" && fx_ok || \
    fx_bad "cell5 control: an aborting digest check must be recognised"
fonts_aborts "$FX_TMP/ctrl5/warnonly.sh" && fx_bad \
    "cell5 control: a warn-only digest check must NOT be recognised" || fx_ok
fonts_aborts "$ROOT/modules/fonts/hooks.sh" && fx_ok || \
    fx_bad "cell5: the real digest check does not abort on mismatch"

# =====================================================================
printf -- '--- cell 6: no self-re-exec tab loop; browse is capped, sequential, once\n'
# =====================================================================
mkdir -p "$FX_TMP/ctrl6"
printf '#!/usr/bin/env bash\n  bash "$0"\n' >"$FX_TMP/ctrl6/rebash.sh"
printf '#!/usr/bin/env bash\n  exec "$0" --again\n' >"$FX_TMP/ctrl6/reexec.sh"
printf '#!/usr/bin/env bash\nrun_cmd x -- xdg-open "$u" &>/dev/null\n' >"$FX_TMP/ctrl6/bgamp.sh"
printf '#!/usr/bin/env bash\nrun_cmd x -- xdg-open "$u" >/dev/null 2>&1 &\n' >"$FX_TMP/ctrl6/bgamp2.sh"
SELF_RE='(bash|exec)[[:space:]]+"?\$\{?(BASH_SOURCE\[0\]|[0-9])'
[[ -n "$(code_hits "$SELF_RE" "$FX_TMP/ctrl6/rebash.sh" || true)" ]] && fx_ok || \
    fx_bad "cell6 control: bash \"\$0\" self-re-exec must be reported"
[[ -n "$(code_hits "$SELF_RE" "$FX_TMP/ctrl6/reexec.sh" || true)" ]] && fx_ok || \
    fx_bad "cell6 control: exec \"\$0\" self-re-exec must be reported"
BG='xdg-open.*&(>|[[:space:]]*$)'
[[ -n "$(code_hits "$BG" "$FX_TMP/ctrl6/bgamp.sh" "$FX_TMP/ctrl6/bgamp2.sh" || true)" ]] && fx_ok || \
    fx_bad "cell6 control: both &> and trailing-& background forms must be reported"
s6="$(code_hits "$SELF_RE" "${CODE_ALL[@]}" 2>&1 || true)"
[[ -z "$s6" ]] && fx_ok || fx_bad "cell6: production re-executes itself: $s6"
s6b="$(code_hits "$BG" "${CODE_ALL[@]}" 2>&1 || true)"
[[ -z "$s6b" ]] && fx_ok || fx_bad "cell6: production backgrounds xdg-open: $s6b"

mkdir -p "$FX_TMP/fakebin6" "$FX_TMP/seam6"
cat >"$FX_TMP/fakebin6/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$1" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
exit 0
EOF
chmod +x "$FX_TMP/fakebin6/xdg-open"
: >"$FX_TMP/opened.log"
for i in $(seq 1 20); do
    printf 'https://extensions.gnome.org/extension/%d/x/\n' "$i" >>"$FX_TMP/seam6/browse.list"
done
(
    set -uo pipefail
    export PATH="$FX_TMP/fakebin6:$PATH" FAKE_LOG="$FX_TMP/opened.log" FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    _gnome_ext_browse "$FX_TMP/seam6"
    printf 'rc=%s\n' "$?" >"$FX_TMP/b6.rc"
) >"$FX_TMP/b6.out" 2>&1
grep -qx 'rc=0' "$FX_TMP/b6.rc" && fx_ok || fx_bad "cell6: browse returns 0"
[[ "$(grep -c . "$FX_TMP/seam6/browse.list")" == 20 ]] && fx_ok || fx_bad "cell6: 20 URLs offered"
[[ "$(grep -c . "$FX_TMP/opened.log")" == 2 ]] && fx_ok || \
    fx_bad "cell6: exactly 2 opened from 20 (got $(grep -c . "$FX_TMP/opened.log"))"
grep -qx 'xdg-open https://extensions.gnome.org/extension/1/x/' "$FX_TMP/opened.log" && fx_ok || \
    fx_bad "cell6: first URL opened first"
grep -qx 'xdg-open https://extensions.gnome.org/extension/2/x/' "$FX_TMP/opened.log" && fx_ok || \
    fx_bad "cell6: second URL opened second"
[[ -z "$(sed -n '3p' "$FX_TMP/opened.log")" ]] && fx_ok || fx_bad "cell6: no third URL opened"

fx_summary
