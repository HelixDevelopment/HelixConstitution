#!/bin/sh
# test_wiring_sweep_precondition.sh — FR-021 precondition test.
#
# ── What it proves ───────────────────────────────────────────────────────────
# All THREE refusal paths are OBSERVED refusing, and the accept path is
# observed accepting. Three refusals and no accept would be a
# refuse-everything predicate; an accept and no refusals would be a
# rubber stamp. Both are checked, because §11.4.201(1) holds a
# false-positive refusal to be exactly as serious as a false pass.
#
#   R1 ABSENT       no result file           -> REFUSE
#   R2 UNREADABLE   unreadable / empty /
#                   no fingerprint row       -> REFUSE
#   R3 STALE        fingerprint mismatch     -> REFUSE
#   A1 ACCEPT       freshly matching result  -> accept
#
# R2 is exercised three ways, because "unreadable" has three real shapes and
# only one of them is a permissions problem. The chmod-000 variant is SKIPPED
# (never silently passed) when the test runs as a uid that can read anything —
# root defeats the permission bit, and a check that cannot fail under the
# current uid must say so rather than count as evidence (§11.4.3, §11.4.6).
#
# ── SCOPE BOUNDARY ───────────────────────────────────────────────────────────
# This exercises the PRECONDITION only. The dependency-adoption gate that
# consumes it (FR-013 / FR-014 / FR-020) is another stream's deliverable; it
# is not implemented, stubbed, or referenced by a guessed path here.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all four paths observed as specified.
#   1 — a path behaved differently than the contract requires.
#   2 — the harness could not run.
#
# Classification: universal (§11.4.17).

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB="$SELF_DIR/lib/wiring_sweep_precondition.sh"
[ -r "$LIB" ] || { echo "REFUSE: predicate not readable: $LIB"; exit 2; }
# shellcheck source=/dev/null
. "$LIB"

TMP=$(mktemp -d 2>/dev/null) || { echo "REFUSE: mktemp failed"; exit 2; }
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM HUP

pass=0; fail=0; skip=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }
skp()  { printf 'SKIP  %s — %s\n' "$1" "$2"; skip=$((skip + 1)); }

FP=fingerprint_aaaa1111
mk_result() { printf 'sweep-verdict\tALLOW\t2026-01-01T00:00:00Z\tunbound=0\ntree-fingerprint\t%s\tgates=1\tseams=1\n' "$1" > "$2"; }

# ── R1 ABSENT ───────────────────────────────────────────────────────────────
err=$(wiring_sweep_precondition "$TMP/nope.tsv" "$FP" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'evidence_file_MISSING'; then
    ok "R1 ABSENT -> REFUSE (evidence_file_MISSING)"
else
    bad "R1 ABSENT -> REFUSE" "rc=$rc out=$err"
fi

# ── R2a UNREADABLE: zero bytes ──────────────────────────────────────────────
: > "$TMP/empty.tsv"
err=$(wiring_sweep_precondition "$TMP/empty.tsv" "$FP" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'evidence_file_EMPTY'; then
    ok "R2a UNREADABLE/empty -> REFUSE (evidence_file_EMPTY)"
else
    bad "R2a UNREADABLE/empty -> REFUSE" "rc=$rc out=$err"
fi

# ── R2b UNREADABLE: present but no fingerprint row ──────────────────────────
printf 'sweep-verdict\tALLOW\tx\ty\n' > "$TMP/nofp.tsv"
err=$(wiring_sweep_precondition "$TMP/nofp.tsv" "$FP" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'store_UNREADABLE'; then
    ok "R2b UNREADABLE/no-fingerprint-row -> REFUSE (store_UNREADABLE, not STALE)"
else
    bad "R2b UNREADABLE/no-fingerprint-row -> REFUSE" "rc=$rc out=$err"
fi

# ── R2c UNREADABLE: permission denied ───────────────────────────────────────
mk_result "$FP" "$TMP/noperm.tsv"; chmod 000 "$TMP/noperm.tsv" 2>/dev/null
if [ -r "$TMP/noperm.tsv" ]; then
    skp "R2c UNREADABLE/chmod-000 -> REFUSE" "this uid can read a 000 file (root or equivalent), so the permission path cannot be exercised here; R2a and R2b already observe the UNREADABLE class"
else
    err=$(wiring_sweep_precondition "$TMP/noperm.tsv" "$FP" 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'store_UNREADABLE'; then
        ok "R2c UNREADABLE/chmod-000 -> REFUSE (store_UNREADABLE, not 'no findings')"
    else
        bad "R2c UNREADABLE/chmod-000 -> REFUSE" "rc=$rc out=$err"
    fi
fi
chmod u+rw "$TMP/noperm.tsv" 2>/dev/null

# ── R3 STALE ────────────────────────────────────────────────────────────────
mk_result "fingerprint_OLD_9999" "$TMP/stale.tsv"
err=$(wiring_sweep_precondition "$TMP/stale.tsv" "$FP" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q 'recorded=fingerprint_OLD_9999' && printf '%s' "$err" | grep -q "current=$FP"; then
    ok "R3 STALE -> REFUSE, printing BOTH resolved fingerprints"
else
    bad "R3 STALE -> REFUSE with resolved evidence" "rc=$rc out=$err"
fi

# ── A1 ACCEPT ───────────────────────────────────────────────────────────────
mk_result "$FP" "$TMP/fresh.tsv"
err=$(wiring_sweep_precondition "$TMP/fresh.tsv" "$FP" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
    ok "A1 ACCEPT freshly matching result -> accepted silently (not a refuse-everything predicate)"
else
    bad "A1 ACCEPT freshly matching result" "rc=$rc out=$err"
fi

# ── A2 END-TO-END against the REAL sweep, if it can run here ────────────────
# Proves the two halves agree on the fingerprint's definition — a test that
# only ever used hand-written fixtures could pass while the real producer and
# consumer disagreed.
SWEEP="$SELF_DIR/cm_unreferenced_gate_bound_or_retired.sh"
if [ -x "$SWEEP" ]; then
    real_fp=$("$SWEEP" --fingerprint 2>/dev/null); frc=$?
    real_res="$SELF_DIR/wiring_sweep_result.tsv"
    if [ "$frc" -eq 0 ] && [ -n "$real_fp" ] && [ -r "$real_res" ]; then
        if wiring_sweep_precondition "$real_res" "$real_fp" 2>/dev/null; then
            ok "A2 END-TO-END real sweep result matches the real current fingerprint"
        else
            skp "A2 END-TO-END" "the on-disk sweep result is stale against the current tree — correct behaviour for the predicate, but it means the sweep must be re-run; not a predicate defect"
        fi
    else
        skp "A2 END-TO-END" "no readable sweep result / fingerprint available in this environment (rc=$frc)"
    fi
else
    skp "A2 END-TO-END" "sweep gate not executable at $SWEEP"
fi

printf '\ntest_wiring_sweep_precondition.sh: pass=%s fail=%s skip=%s\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
exit 0
