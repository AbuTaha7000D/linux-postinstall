#!/usr/bin/env bash
# tests/fixtures/profiles.sh - P4.5 fixture for profile loading and
# resolution (lib/profiles.sh). Covers the P4.5 verification bullet:
# profile -> resolved module set; CLI overrides; mutual-exclusion/conflict
# handling errors. Parse/read-only (module.sh metadata only; nothing
# executed), no real system state, everything under FX_TMP.
# Usage: bash tests/fixtures/profiles.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
FX_EXPECT="$FX_TMP/expect"
M="$FX_TMP/mod"
P="$FX_TMP/prof"
mkdir -p \
    "$M/a" "$M/b" "$M/c" "$M/d" \
    "$M/x" "$M/y" "$M/ghostc" \
    "$M/e" "$M/f" "$M/g" "$M/h" \
    "$P"

printf 'P4.5 profile loader + resolver\n'

printf 'MODULE_ID=a\nMODULE_DEPENDS=c\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/a/module.sh"
printf 'MODULE_ID=b\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/b/module.sh"
printf 'MODULE_ID=c\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/c/module.sh"
printf 'MODULE_ID=d\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/d/module.sh"
printf 'MODULE_ID=x\nMODULE_DEPENDS=y\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/x/module.sh"
printf 'MODULE_ID=y\nMODULE_DEPENDS=x\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/y/module.sh"

printf 'MODULE_ID=e\nMODULE_DEPENDS=f g\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/e/module.sh"
printf 'MODULE_ID=f\nMODULE_DEPENDS=g\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/f/module.sh"
printf 'MODULE_ID=g\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/g/module.sh"

printf 'MODULE_ID=h\nMODULE_DEPENDS=../evil\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/h/module.sh"

printf 'b\na\nd\n' >"$P/base.conf"
printf 'a\nc\na\n' >"$P/dup.conf"
printf '# comment line\n\n  b  \nc\r\n# trailing comment\na' >"$P/comments.conf"
printf '# empty profile skeleton\n' >"$P/empty.conf"
printf 'x\ny\n' >"$P/cycle.conf"
printf 'nope\n' >"$P/ghost.conf"
printf 'a\n' >"$P/profa.conf"
printf 'b\n' >"$P/profb.conf"
printf 'e\n' >"$P/de2.conf"
printf 'ghostc\n' >"$P/ghostdir.conf"
printf '../evil\n' >"$P/badid.conf"
printf '..\n' >"$P/dotdot.conf"

for name in minimal desktop developer deep.devel-1; do
    (
        set -euo pipefail
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        source "$ROOT/lib/profiles.sh"
        profile_validate "$P" "$name"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "valid profile name $name rc0" 0
    fx_empty "validate prints nothing" "$FX_OUT"
done

for bad in '../x' 'a/b' '.minimal' '-x' ''; do
    (
        set -euo pipefail
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        source "$ROOT/lib/profiles.sh"
        profile_validate "$P" "$bad"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "invalid profile name '$bad' rc1" 1
    fx_err "invalid profile name: $bad"
done

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P" "base"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "profile_load base rc0" 0
printf "b\na\nd\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "load order is file order"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P" "dup"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "profile_load dup rc0" 0
printf "a\nc\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "in-profile duplicate deduped first-seen"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P" "comments"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "profile_load comments rc0" 0
printf "b\nc\na\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "comments/blanks/trim/CRLF/no-final-newline"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P" "empty"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "profile_load empty rc0" 0
fx_empty "empty profile prints nothing" "$FX_OUT"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P" "nosuch"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing profile rc1" 1
fx_err "list file missing or not a regular file: $P/nosuch.conf"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "base"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resolve base rc0" 0
printf "b\nc\na\nd\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "deps-first closure, deterministic order"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "base" d
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resolve base + cli-overlap rc0" 0
printf "b\nc\na\nd\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "CLI id already in profile collapses"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "empty" a b
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile + CLI rc0" 0
printf "b\nc\na\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "CLI modules honored alone"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "empty" a a c
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resolve cli dup rc0" 0
printf "c\na\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "CLI duplicates collapse"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "empty"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty profile + no CLI rc0" 0
fx_empty "nothing resolves to nothing" "$FX_OUT"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    rc=0
    profile_resolve "$M" "$P" "cycle" || rc=$?
    exit "$rc"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "cycle profile rejects rc1" 1
fx_empty "no output on cycle" "$FX_OUT"
fx_err "cycle: x -> y -> x"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "ghost"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown module in profile rc1" 1
fx_empty "no output on unknown module" "$FX_OUT"
fx_err "module directory not found: $M/nope"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    rc=0
    profile_resolve "$M" "$P" "base" x || rc=$?
    exit "$rc"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "CLI module brings cycle rc1" 1
fx_empty "no output when CLI introduces cycle" "$FX_OUT"
fx_err "cycle: x -> y -> x"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "nosuch" a
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resolve missing profile rc1" 1
fx_err "list file missing or not a regular file: $P/nosuch.conf"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "profa"
    profile_resolve "$M" "$P" "profb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "two resolves sequential rc0" 0
printf "c\na\nb\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "module_load state reset across resolve calls"

for prof in minimal desktop developer full; do
    (
        set -euo pipefail
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        source "$ROOT/lib/profiles.sh"
        profile_load "$ROOT/profiles" "$prof"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "shipped profile $prof load rc0" 0
    fx_empty "shipped $prof resolves empty today" "$FX_OUT"
done

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "de2"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "two-level closure rc0" 0
printf "g\nf\ne\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "deps pulled transitively and multi-token DEPENDS split"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "ghostdir"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dir without module.sh in profile rc1" 1
fx_empty "no output for missing module.sh" "$FX_OUT"
fx_err "module metadata missing: $M/ghostc/module.sh"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "badid"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "traversal id in profile rc1" 1
fx_err "invalid module id in set: ../evil"

printf 'h\n' >"$P/profh.conf"
 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "profh"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "traversal MODULE_DEPENDS id rc1" 1
fx_empty "no output on bad dep token" "$FX_OUT"
fx_err "invalid module id in module 'h': ../evil"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P" "dotdot"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dot-dot id in profile rc1" 1
fx_err "invalid module id in set: .."

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_resolve "$M" "$P"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "resolve misuse arity rc1" 1
fx_err "profile_resolve requires a modules dir, a profiles dir, and a name"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    source "$ROOT/lib/profiles.sh"
    profile_load "$P"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "load misuse arity rc1" 1
fx_err "profile_load requires a directory and a name"

for loc in tr_TR.UTF-8 en_US.UTF-8 C; do
    (
        set -euo pipefail
        export LC_ALL="$loc"
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        source "$ROOT/lib/profiles.sh"
        profile_validate "$P" "minimal"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "locale-stable name gate LC_ALL=$loc rc0" 0
    fx_empty "validate prints nothing under $loc" "$FX_OUT"
done

fx_summary