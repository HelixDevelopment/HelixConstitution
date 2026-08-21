#!/usr/bin/env bash
# cm_first_refusal_observed_mutation_test.sh — paired §1.1 mutation for the
# FR-022 first-refusal gate `cm_first_refusal_observed.sh`.
#
# ── What a paired mutation must prove ────────────────────────────────────────
# §1.1 / §11.4.115(F): a gate is trusted only once it has been OBSERVED to
# FAIL on a genuinely-broken input. A mutation that makes the gate fail for
# SOME OTHER reason proves nothing — it must flip the SPECIFIC assertion it
# names. Both cases below therefore capture the PRE-mutation verdict first
# (which must be ACCEPT), then assert the flip, then assert the refusal
# REASON is the one the mutation targeted.
#
#   CASE 1 (the named mutation — DATA):
#       blank the evidence path on a SEEDED row and assert the newly bound
#       gate's PASS stops counting, with reason EVIDENCE-EMPTY.
#   CASE 2 (the sentinel check is load-bearing — CODE):
#       A BLANK field cannot isolate the emptiness check: it also fails the
#       path-resolution check downstream, so stripping one still refuses via
#       the other (measured — this test caught exactly that and was corrected
#       rather than being weakened to accept the ambiguity). CASE 2 therefore
#       uses the `PENDING-FIRST-REFUSAL` SENTINEL against a fixture in which a
#       real, non-empty file of that very name EXISTS. The sentinel must be
#       rejected by MEANING, not by the accident that no such file is around:
#         intact gate  -> REFUSE (EVIDENCE-EMPTY)
#         check stripped -> ACCEPT (the resolving non-empty file sails through)
#       That is a true flip-to-accept isolating exactly the sentinel check.
#   NEGATIVE CONTROL (§11.4.201(1)):
#       the un-mutated row citing real, resolving, non-empty RED evidence MUST
#       let the PASS count, so the mechanism cannot block every gate
#       indiscriminately.
#
# ── §11.4.84 working-tree quiescence ─────────────────────────────────────────
# Every mutation runs against an OUT-OF-REPO copy under `mktemp -d`. The
# tracked registry and the tracked gate are never written. The test md5sums
# both BEFORE and AFTER and FAILS if either byte changed — a mutation that
# leaks into the working tree is exactly the residue §11.4.84 forbids.
#
# ── HONEST BOUNDARY (§11.4.6) ────────────────────────────────────────────────
# The fixture evidence file is a FIXTURE standing in for a recorded RED run.
# This test proves the gate's REGISTRY CONTRACT (a resolving non-empty path
# accepts; a blanked one refuses). It does NOT assert the authenticity of any
# real evidence file — authenticity is the job of the task that RUNS a real
# mutation and records the row.
#
# Exit: 0 all cases correct; 1 a case wrong; 2 BLIND (missing prerequisite).

set -u

TEST="cm_first_refusal_observed_mutation_test.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="${here}/cm_first_refusal_observed.sh"
registry="${here}/gate_first_refusal.tsv"

[ -x "$gate" ]     || { echo "${TEST}: BLIND — gate not found/executable: $gate" >&2; exit 2; }
[ -r "$registry" ] || { echo "${TEST}: BLIND — registry not readable: $registry" >&2; exit 2; }

md5_before_reg="$(md5sum "$registry"  | awk '{print $1}')"
md5_before_gate="$(md5sum "$gate"     | awk '{print $1}')"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

# The seeded row this mutation operates on. Chosen from the shipped registry
# rather than invented, so the mutation acts on real seeded data.
TOK="CM-GATE-LEDGER-RATCHET"
if ! grep -v '^[[:space:]]*#' -- "$registry" | awk -F'\t' -v t="$TOK" '$1==t{f=1} END{exit !f}'; then
    echo "${TEST}: BLIND — seeded row for ${TOK} not present in ${registry}; nothing to mutate" >&2
    exit 2
fi

repo="$tmp/repo"; mkdir -p "$repo/ev"
printf 'RED transcript fixture: the paired mutation was run and the gate refused.\n' > "$repo/ev/red.log"
# the row's cited mutation path must resolve for the run to reach the
# evidence check at all — mirror the real one into the fixture repo root.
mut_rel="$(grep -v '^[[:space:]]*#' -- "$registry" | awk -F'\t' -v t="$TOK" '$1==t{print $2; exit}')"
mkdir -p "$repo/$(dirname "$mut_rel")"
: > "$repo/${mut_rel}"

# ── build the PRE-mutation fixture: the seeded row, evidence made real ───────
pre="$tmp/registry_pre.tsv"
awk -F'\t' -v OFS='\t' -v t="$TOK" \
    '/^[[:space:]]*#/{print;next} $1==t{$3="ev/red.log"} {print}' \
    "$registry" > "$pre"

run_gate() { # run_gate <registry> [gate-path]
    _rg_reg="$1"; _rg_gate="${2:-$gate}"
    "$_rg_gate" --registry "$_rg_reg" --repo-root "$repo" --root "$tmp" --token "$TOK" 2>&1
}

# ── PRE-mutation baseline: must ACCEPT (else the flip proves nothing) ────────
pre_out="$(run_gate "$pre")"; pre_rc=$?
if [ "$pre_rc" -ne 0 ]; then
    echo "MUTATION-FAIL: PRE-mutation baseline did NOT accept (rc=${pre_rc}); the flip asserted below would prove nothing" >&2
    printf '%s\n' "$pre_out" >&2
    fails=$((fails + 1))
fi

# ── CASE 1 — the named mutation: blank the evidence path on the seeded row ──
mut1="$tmp/registry_mut_blank.tsv"
awk -F'\t' -v OFS='\t' -v t="$TOK" \
    '/^[[:space:]]*#/{print;next} $1==t{$3=""} {print}' \
    "$pre" > "$mut1"
if ! grep -v '^[[:space:]]*#' -- "$mut1" | awk -F'\t' -v t="$TOK" '$1==t{exit !($3=="")}'; then
    echo "MUTATION-FAIL: CASE 1 mutation did not actually blank the evidence field — the mutation is inert" >&2
    fails=$((fails + 1))
fi
mut1_out="$(run_gate "$mut1")"; mut1_rc=$?
if [ "$mut1_rc" -eq 0 ]; then
    echo "MUTATION-FAIL: CASE 1 — blanking the evidence path on a seeded row still let the gate's PASS count (rc=0); FR-022 is not load-bearing" >&2
    printf '%s\n' "$mut1_out" >&2
    fails=$((fails + 1))
fi
if ! printf '%s\n' "$mut1_out" | grep -q 'EVIDENCE-EMPTY'; then
    echo "MUTATION-FAIL: CASE 1 — the gate refused, but NOT for the reason this mutation names (expected EVIDENCE-EMPTY); a refusal for an unrelated reason proves nothing" >&2
    printf '%s\n' "$mut1_out" >&2
    fails=$((fails + 1))
fi

# ── CASE 2 — the SENTINEL check is what refuses: isolate it, then strip it ──
# Fixture hazard: a real, non-empty file literally NAMED `PENDING-FIRST-REFUSAL`
# exists, so the downstream resolve/non-empty checks CANNOT be what refuses.
printf 'a real non-empty file that merely happens to be named like the sentinel\n' \
    > "$repo/PENDING-FIRST-REFUSAL"
sent="$tmp/registry_sentinel.tsv"
awk -F'\t' -v OFS='\t' -v t="$TOK" \
    '/^[[:space:]]*#/{print;next} $1==t{$3="PENDING-FIRST-REFUSAL"} {print}' \
    "$pre" > "$sent"

sent_out="$(run_gate "$sent")"; sent_rc=$?
if [ "$sent_rc" -eq 0 ]; then
    echo "MUTATION-FAIL: CASE 2 — the PENDING-FIRST-REFUSAL sentinel was ACCEPTED because a file of that name resolves; the sentinel must be rejected by MEANING, not by the accident of a missing file" >&2
    printf '%s\n' "$sent_out" >&2
    fails=$((fails + 1))
fi
if ! printf '%s\n' "$sent_out" | grep -q 'EVIDENCE-EMPTY'; then
    echo "MUTATION-FAIL: CASE 2 — the sentinel refusal did not come from the sentinel/emptiness check (expected EVIDENCE-EMPTY)" >&2
    printf '%s\n' "$sent_out" >&2
    fails=$((fails + 1))
fi

gate_mut="$tmp/gate_mutated.sh"
sed 's/^        ""|PENDING-FIRST-REFUSAL)/        "__NEVER_MATCHES__")/' "$gate" > "$gate_mut"
chmod +x "$gate_mut"
if cmp -s "$gate" "$gate_mut"; then
    echo "MUTATION-FAIL: CASE 2 code mutation changed nothing — the sed target no longer matches the gate source; the mutation is inert" >&2
    fails=$((fails + 1))
fi
mut2_out="$("$gate_mut" --registry "$sent" --repo-root "$repo" --root "$tmp" --token "$TOK" 2>&1)"
mut2_rc=$?
if [ "$mut2_rc" -ne 0 ]; then
    echo "MUTATION-FAIL: CASE 2 — with the sentinel/emptiness check stripped, the sentinel row STILL refused (rc=${mut2_rc}); that check is not what produces the EVIDENCE-EMPTY refusal" >&2
    printf '%s\n' "$mut2_out" >&2
    fails=$((fails + 1))
fi

# ── NEGATIVE CONTROL — the intact evidenced row must still let PASS count ────
neg_out="$(run_gate "$pre")"; neg_rc=$?
if [ "$neg_rc" -ne 0 ]; then
    echo "MUTATION-FAIL: NEGATIVE CONTROL — a row citing resolving, non-empty RED evidence was REFUSED (rc=${neg_rc}); the mechanism blocks indiscriminately (§11.4.201(1) false-positive refusal)" >&2
    printf '%s\n' "$neg_out" >&2
    fails=$((fails + 1))
fi

# ── §11.4.84 — prove nothing leaked into the working tree ────────────────────
md5_after_reg="$(md5sum "$registry" | awk '{print $1}')"
md5_after_gate="$(md5sum "$gate"    | awk '{print $1}')"
if [ "$md5_before_reg" != "$md5_after_reg" ]; then
    echo "MUTATION-FAIL: the tracked registry CHANGED during the run (${md5_before_reg} -> ${md5_after_reg}) — mutation residue in the working tree (§11.4.84)" >&2
    fails=$((fails + 1))
fi
if [ "$md5_before_gate" != "$md5_after_gate" ]; then
    echo "MUTATION-FAIL: the tracked gate CHANGED during the run (${md5_before_gate} -> ${md5_after_gate}) — mutation residue in the working tree (§11.4.84)" >&2
    fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
    echo "❌ ${TEST}: FAIL — ${fails} case(s) wrong"
    exit 1
fi
echo "✅ ${TEST}: PASS — PRE-mutation row ACCEPTED (rc=0); blanking the seeded row's evidence path flipped it to REFUSE with the named reason EVIDENCE-EMPTY; the PENDING-FIRST-REFUSAL sentinel was REFUSED even though a real non-empty file of that name resolved, and stripping the sentinel check from an out-of-repo gate copy flipped that same row to a wrong ACCEPT (so that check, by MEANING, is what refuses); the intact evidenced row still accepts (no indiscriminate refusal); tracked registry + gate byte-identical before/after (§11.4.84)"
exit 0
