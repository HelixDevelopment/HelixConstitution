#!/bin/sh
# =============================================================================
# cm_control_needle_required_mutation_test.sh — paired §1.1 mutation for
# CM-CONTROL-NEEDLE-REQUIRED (T228).
#
# ── The mutation is BEHAVIOURAL, not textual ────────────────────────────────
# §11.4.115(F) refuses a mutation whose diff only deletes the literal strings
# the gate greps for: that proves the gate can read its own source, not that it
# can catch the defect. This mutation instead REMOVES THE NEEDLE-HITS
# COMPARISON from the evaluator — the single line of logic that decides whether
# an instrument proved it can see — and leaves every string in place. The
# mutated evaluator still says the words; it just no longer means them.
#
# ── It asserts the NAMED assertion flipped ──────────────────────────────────
# §11.4.194(6)(d): a mutation that flips SOME assertion proves nothing about
# the one it claims to bind. This test reads CNR-A3 BY NAME through
# cn_verdict_of and requires that specific verdict to move PASS -> FAIL, and it
# additionally requires CNR-A1 (the false-refusal guard) to stay PASS, so the
# mutation is shown to be surgical rather than a general breakage.
#
# ── Single-resource-owner (§11.4.84) ────────────────────────────────────────
# The mutation is applied to a COPY in an out-of-repo mktemp -d. The tracked
# library is never edited; its sha256 is captured before and after and compared,
# so "restored" is a measured fact rather than an assumption.
#
# Usage : sh cm_control_needle_required_mutation_test.sh
#         rc 0 = the pair is valid (mutation flips the named assertion, restore
#                brings it back); rc 1 = the pair was NOT demonstrated.
# =============================================================================

set -u

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
GATE="$SELF_DIR/cm_control_needle_required.sh"
LIB="$SELF_DIR/lib/control_needle.sh"
REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
READER="$REPO/scripts/lib/critical_blocker_gate.sh"

fails=0
say() { printf '%s\n' "$*"; }
ok()  { say "  [ok]   $*"; }
bad() { fails=$((fails + 1)); say "  [FAIL] $*"; }

for f in "$GATE" "$LIB"; do
    [ -f "$f" ] || { say "PAIR-NOT-DEMONSTRATED: required file absent: $f"; exit 1; }
done

_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_cnr_mut.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

sum_before=$(sha256sum "$LIB" | cut -d' ' -f1)

# Out-of-repo working copy, same relative layout so the gate resolves its lib.
mkdir -p "$TMP/gates/lib"
cp "$GATE" "$TMP/gates/" || exit 2
cp "$SELF_DIR/lib/chain_control_needle.sh" "$TMP/gates/lib/" || exit 2
cp "$LIB" "$TMP/gates/lib/" || exit 2
MUT_GATE="$TMP/gates/$(basename "$GATE")"
MUT_LIB="$TMP/gates/lib/$(basename "$LIB")"

say '=== T228 paired §1.1 mutation for CM-CONTROL-NEEDLE-REQUIRED ==='
say "tracked library (READ-ONLY to this harness): $LIB"
say "mutating an out-of-repo copy at:            $MUT_LIB"

# --- direction 0: baseline on the unmutated copy ------------------------------
sh "$MUT_GATE" --reader "$READER" > "$TMP/base.out" 2>&1
base_a3=$(cn_verdict_of "$TMP/base.out" CNR-A3-BLIND-NEEDLE-DISTINCT)
base_a1=$(cn_verdict_of "$TMP/base.out" CNR-A1-NEEDLED-ZERO-ACCEPTED)
say "--- direction 0: unmutated copy ---"
if [ "$base_a3" = PASS ]; then ok "baseline CNR-A3 = PASS (the assertion this mutation targets is live)"
else bad "baseline CNR-A3 = $base_a3; the mutation cannot be shown to flip an assertion that is not passing to begin with"; fi
if [ "$base_a1" = PASS ]; then ok "baseline CNR-A1 = PASS (the false-refusal guard is live)"
else bad "baseline CNR-A1 = $base_a1"; fi

# --- the behavioural mutation -------------------------------------------------
# Remove the needle-hits comparison: `[ "${_cne_h}" -eq 0 ]` becomes a test that
# can never fire. Every literal string the gate looks for is left untouched.
awk '
  /if \[ "\$_cne_h" -eq 0 \]; then/ { print "    if false; then   # MUTATED for paired-mutation: needle-hits comparison removed"; next }
  { print }
' "$MUT_LIB" > "$MUT_LIB.new" && mv "$MUT_LIB.new" "$MUT_LIB"

mut_applied=$(grep -Ec 'MUTATED for paired-mutation' "$MUT_LIB" || true)
if [ "${mut_applied:-0}" -gt 0 ]; then ok "mutation applied to the copy (needle-hits comparison disabled, all literals intact)"
else bad "the mutation did not apply — the pair cannot be demonstrated and is NOT reported as valid"; fi

# It must still parse, or the flip would be a crash rather than a behaviour change.
if sh -n "$MUT_LIB" 2>/dev/null; then ok "the mutated copy still parses (the flip is behavioural, not a syntax error)"
else bad "the mutated copy no longer parses; a crash is not the behaviour change this pair claims"; fi

# --- direction 1: mutated -> the NAMED assertion must FAIL --------------------
say '--- direction 1: needle-hits comparison removed -> CNR-A3 must FAIL ---'
sh "$MUT_GATE" --reader "$READER" > "$TMP/mut.out" 2>&1
mut_a3=$(cn_verdict_of "$TMP/mut.out" CNR-A3-BLIND-NEEDLE-DISTINCT)
mut_a1=$(cn_verdict_of "$TMP/mut.out" CNR-A1-NEEDLED-ZERO-ACCEPTED)
if [ "$mut_a3" = FAIL ]; then ok "CNR-A3 flipped PASS -> FAIL: with the comparison gone, a needle that found NOTHING is accepted as certification"
else bad "CNR-A3 = $mut_a3 under mutation (expected FAIL) — the gate does not actually depend on the needle-hits comparison, so its PASS was not load-bearing"; fi
if [ "$mut_a1" = PASS ]; then ok "CNR-A1 stayed PASS — the mutation is SURGICAL, it did not simply break the gate"
else bad "CNR-A1 = $mut_a1 under mutation; the flip is not attributable to the targeted assertion (§11.4.194(6)(d))"; fi

# --- direction 2: restored -> the assertion must come back --------------------
say '--- direction 2: restore -> CNR-A3 must return to PASS ---'
cp "$LIB" "$MUT_LIB" || exit 2
sh "$MUT_GATE" --reader "$READER" > "$TMP/res.out" 2>&1
res_a3=$(cn_verdict_of "$TMP/res.out" CNR-A3-BLIND-NEEDLE-DISTINCT)
if [ "$res_a3" = PASS ]; then ok "CNR-A3 restored to PASS — the flip tracks the mutation in both directions"
else bad "CNR-A3 = $res_a3 after restore; a one-way flip does not demonstrate a pair"; fi

# --- the tracked library was never touched -----------------------------------
sum_after=$(sha256sum "$LIB" | cut -d' ' -f1)
if [ "$sum_before" = "$sum_after" ]; then ok "tracked library unchanged (sha256 $sum_before) — single-resource-owner respected (§11.4.84)"
else bad "the TRACKED library changed during this run ($sum_before -> $sum_after); that is a working-tree violation, not a test result"; fi

say ''
if [ "$fails" -eq 0 ]; then
    say '=== MUTATION PAIR VALID — CNR-A3 is load-bearing on the needle-hits comparison ==='
    exit 0
fi
say "=== PAIR NOT DEMONSTRATED ($fails failed) ==="
exit 1
