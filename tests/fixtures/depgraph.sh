#!/usr/bin/env bash
# tests/fixtures/depgraph.sh - P4.4 fixture for dependency ordering and
# cycle detection (lib/depgraph.sh). Covers the P4.4 verification bullet:
# a valid DAG orders correctly; A->B->A errors with the cycle path
# printed. Parse/read-only (module.sh metadata only; nothing executed),
# no real system state, everything under FX_TMP.
# Usage: bash tests/fixtures/depgraph.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
FX_EXPECT="$FX_TMP/expect"
M="$FX_TMP/mod"
mkdir -p \
    "$M/linc" "$M/linb" "$M/lina" \
    "$M/midb" "$M/midc" "$M/roota" \
    "$M/ind_a" "$M/ind_z" "$M/ind_m" \
    "$M/ca" "$M/cb" \
    "$M/sa" \
    "$M/gm" "$M/b" \
    "$M/ddeps" \
    "$M/zzz" "$M/aaa" \
    "$M/cx" "$M/cy" "$M/dx" "$M/dy" \
    "$M/m6" "$M/m5" "$M/m4" "$M/m3" "$M/m2" "$M/m1" \
    "$M/baddir"

printf 'P4.4 dependency ordering + cycle detection\n'

printf 'MODULE_ID=linc\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/linc/module.sh"
printf 'MODULE_ID=linb\nMODULE_DEPENDS=linc\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/linb/module.sh"
printf 'MODULE_ID=lina\nMODULE_DEPENDS=linb\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/lina/module.sh"

printf 'MODULE_ID=midb\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/midb/module.sh"
printf 'MODULE_ID=midc\nMODULE_DEPENDS=midb\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/midc/module.sh"
printf 'MODULE_ID=roota\nMODULE_DEPENDS=midc midb\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/roota/module.sh"

printf 'MODULE_ID=ind_a\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/ind_a/module.sh"
printf 'MODULE_ID=ind_z\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/ind_z/module.sh"
printf 'MODULE_ID=ind_m\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/ind_m/module.sh"

printf 'MODULE_ID=ca\nMODULE_DEPENDS=cb\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/ca/module.sh"
printf 'MODULE_ID=cb\nMODULE_DEPENDS=ca\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/cb/module.sh"

printf 'MODULE_ID=sa\nMODULE_DEPENDS=sa\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/sa/module.sh"

printf 'MODULE_ID=gm\nMODULE_DEPENDS=nonexist\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/gm/module.sh"
printf 'MODULE_ID=b\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/b/module.sh"

printf 'MODULE_ID=other\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/zzz/module.sh"
printf 'MODULE_ID=aaa\nMODULE_DEPENDS=other\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/aaa/module.sh"

printf 'MODULE_ID=cx\nMODULE_DEPENDS=cy\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/cx/module.sh"
printf 'MODULE_ID=cy\nMODULE_DEPENDS=cx\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/cy/module.sh"
printf 'MODULE_ID=dx\nMODULE_DEPENDS=dy\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/dx/module.sh"
printf 'MODULE_ID=dy\nMODULE_DEPENDS=dx\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/dy/module.sh"

printf 'MODULE_ID=ddeps\nMODULE_DEPENDS=b b\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/ddeps/module.sh"

i=1
while (( i <= 6 )); do
    printf 'MODULE_ID=m%d\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' "$i" >"$M/m$i/module.sh"
    i=$((i + 1))
done
printf 'MODULE_ID=m1\nMODULE_DEPENDS=m2 m3 m4 m5 m6\nMODULE_RISK=none\nMODULE_DEFAULT=off\n' >"$M/m1/module.sh"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/lina" "$M/linb" "$M/linc"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "linear chain rc0" 0
printf "linc\nlinb\nlina\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "dependency before dependent"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/midc" "$M/roota" "$M/midb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "diamond rc0" 0
printf "midb\nmidc\nroota\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "shared dep ordered once before both"

for argorder in "$M/ind_m $M/ind_a $M/ind_z" "$M/ind_z $M/ind_m $M/ind_a"; do
    (
        set -euo pipefail
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/modules.sh"
        source "$ROOT/lib/depgraph.sh"
        dep_toposort $argorder
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "independent set rc0" 0
    printf "ind_a\nind_m\nind_z\n" >"$FX_EXPECT"
    cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "arg-order-independent id sort"
done

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/ca" "$M/cb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "two-cycle rejects rc1" 1
fx_empty "no output on cycle" "$FX_OUT"
fx_err "cycle: ca -> cb -> ca"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/sa"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "self-cycle rejects rc1" 1
fx_err "cycle: sa -> sa"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/m1" "$M/m2" "$M/m3" "$M/m4" "$M/m5" "$M/m6"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "six-deep chain rc0" 0
printf "m2\nm3\nm4\nm5\nm6\nm1\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "deep chain all deps first, sorted"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/linc" "$M/ca" "$M/cb"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "mixed valid+cycle rejects rc1" 1
fx_empty "cycle in mixed set = nothing printed" "$FX_OUT"
fx_err "cycle: ca -> cb -> ca"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/gm" "$M/b"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown dependency rejects rc1" 1
fx_empty "no output on unknown dep" "$FX_OUT"
fx_err "gm depends on unknown module 'nonexist'"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/ddeps" "$M/b" "$M/b"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "duplicate dep arg rc0" 0
printf "b\nddeps\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "in-module dupe collapsed, dup dir arg deduped"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty set rc0" 0
fx_empty "empty set prints nothing" "$FX_OUT"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/baddir"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dir without module.sh rejects rc1" 1
fx_err "module metadata missing"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    source "$ROOT/lib/depgraph.sh"
    dep_toposort "$M/aaa" "$M/zzz"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "id from MODULE_ID rc0" 0
printf "other\naaa\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "ordered by MODULE_ID, not dir basename"

for argorder in "$M/cy $M/dx $M/cx $M/dy" "$M/dy $M/cx $M/cy $M/dx"; do
    (
        set -euo pipefail
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/modules.sh"
        source "$ROOT/lib/depgraph.sh"
        dep_toposort $argorder
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "two disjoint cycles reject rc1" 1
    fx_err "cycle: cx -> cy -> cx"
done

fx_summary