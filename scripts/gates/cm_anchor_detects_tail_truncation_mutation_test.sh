#!/usr/bin/env bash
# cm_anchor_detects_tail_truncation_mutation_test.sh — paired §1.1 mutation for
# T328 (task T332), covering gate CM-ANCHOR-DETECTS-TAIL-TRUNCATION.
#
# ── What this proves ─────────────────────────────────────────────────────────
# T332: "removes the anchor comparison and asserts the gate FAILs; it MUST also
#        assert the gate still PASSes the lagging-anchor negative control, so
#        the mutation cannot be 'satisfied' by making the gate refuse
#        everything."
#
# Those two halves are one requirement. A gate that turned red for ANY reason
# would satisfy a naive "the mutation makes it fail" test, including a gate
# that had simply started refusing every chain — and a verifier that refuses
# healthy work is a §11.4.201(1) FAIL-bluff exactly as serious as a false pass.
# So this script asserts BOTH that the truncation check went red AND that the
# lagging-anchor negative control stayed green under the same mutation.
#
# ── The mutation ─────────────────────────────────────────────────────────────
#   M1  pkg/anchor/check.go — Check() returns PASS immediately, so the anchor
#       comparison (the count direction and the anchored-prefix re-derivation)
#       never runs. Tail truncation leaves a structurally VALID chain, so with
#       the comparison gone there is nothing left in the system that can see it.
#         MUST flip to FAIL : B2_truncation_chain_plus_anchor_detected
#                             B3_two_distinct_results
#                             B6_observed_matches_declared_intent
#         MUST remain PASS  : B4_lagging_anchor_negative_control
#                             B1_truncation_chain_alone_pass
#                             B5_golden_good_clean
#
# ── Why this is not a tautology (§11.4.115(F)) ───────────────────────────────
# The mutation deletes no string the gate greps for. It changes what the
# mechanism DECIDES; the gate notices because it reads the decision.
#
# ── Anti-bluff on the mutation itself ────────────────────────────────────────
#   * applied to a COPY under mktemp -d (§11.4.84); the repository is never
#     written to, proven by a source-tree checksum taken before and after;
#   * a mutation whose diff changed nothing is refused as a tautology;
#   * the BASELINE must be green first — a mutation test on a red baseline
#     proves nothing;
#   * restoration is verified by checksum and re-proved by a green final run.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_anchor_detects_tail_truncation_mutation_test.sh [--engine <dir>] [--gate <path>]
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS | 1 FAIL | 4 REFUSE (could not decide — never 0)
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, go, jq, sed, sha256sum. Any absent -> REFUSE.
# ─────────────────────────────────────────────────────────────────────────────

set -u

NAME="CM-ANCHOR-DETECTS-TAIL-TRUNCATION mutation test (T332)"
engine=""
gate=""

while [ $# -gt 0 ]; do
    case "$1" in
        --engine) engine="${2:-}"; shift 2 ;;
        --engine=*) engine="${1#--engine=}"; shift ;;
        --gate) gate="${2:-}"; shift 2 ;;
        --gate=*) gate="${1#--gate=}"; shift ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) echo "$NAME: unknown argument: $1" >&2; exit 4 ;;
    esac
done

gates_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -n "$engine" ] || engine="${gates_dir}/../../submodules/continuum"
[ -n "$gate" ] || gate="${gates_dir}/cm_anchor_detects_tail_truncation.sh"

warn() { echo "$@" >&2; }
fail_count=0
bad()  { warn "❌ $*"; fail_count=$((fail_count + 1)); }
good() { echo "✅ $*"; }

refuse() {
    warn "🛑 REFUSE   ${NAME}: $*"
    warn "   Nothing was decided. This is not a pass (§11.4.201(6))."
    exit 4
}

for tool in go jq sed sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || refuse "required tool '$tool' is not on PATH"
done
[ -x "$gate" ] || refuse "the gate under test is not executable at '$gate'"
[ -d "$engine" ] || refuse "engine root '$engine' does not exist"
engine_abs=$(CDPATH= cd -- "$engine" && pwd) || refuse "engine root could not be resolved"

tmp=$(mktemp -d 2>/dev/null) || refuse "could not create a temporary working directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

tree_sum() {
    ( cd "$1" && find . -type f -name '*.go' | sort | xargs sha256sum ) 2>/dev/null | sha256sum | cut -d' ' -f1
}

ws=$(find "$engine_abs" -type f -name '* *' 2>/dev/null | head -1)
[ -z "$ws" ] || refuse "the engine tree contains a path with whitespace ('$ws'); the checksum instrument used here would be unreliable, so it refuses rather than report a number it cannot stand behind"

src_sum_before=$(tree_sum "$engine_abs")
[ -n "$src_sum_before" ] || refuse "the source-tree checksum instrument returned nothing — it is blind"

echo "──────────────────────────────────────────────────────────────────────"
echo "${NAME}"
echo "  gate   : ${gate}"
echo "  engine : ${engine_abs}"
echo "  source tree sha256(go files): ${src_sum_before}"
echo "──────────────────────────────────────────────────────────────────────"

cp -a "$engine_abs" "${tmp}/engine" || refuse "could not copy the engine out of the repo"
cp -a "$engine_abs" "${tmp}/pristine" || refuse "could not take a pristine reference copy"
copy_sum_before=$(tree_sum "${tmp}/engine")
[ "$copy_sum_before" = "$src_sum_before" ] || refuse "the out-of-repo copy does not match the source; mutating it would not be mutating the code under test"
good "out-of-repo copy is byte-faithful to the source (§11.4.84)"

run_gate() {
    rg_label="$1"
    "$gate" --engine "${tmp}/engine" --quiet >"${tmp}/${rg_label}.out" 2>"${tmp}/${rg_label}.err"
    GATE_RC=$?
}

verdict_of() {
    vo_line=$(grep -m1 "^RESULT $2 " "${tmp}/$1.out" 2>/dev/null)
    if [ -z "$vo_line" ]; then
        echo ABSENT
    else
        echo "$vo_line" | awk '{print $3}'
    fi
}

assert_flip() {
    af_v=$(verdict_of "$1" "$2")
    if [ "$af_v" = "$3" ]; then
        good "  $2 = $3 ($4)"
    else
        bad "  $2 = ${af_v}, expected $3 ($4)"
    fi
}

# --- baseline ---------------------------------------------------------------
run_gate baseline
base_rc=$GATE_RC
if [ "$base_rc" -ne 0 ]; then
    warn "$(cat "${tmp}/baseline.err")"
    refuse "the BASELINE gate run exited ${base_rc} on the unmutated copy; a mutation test against a red baseline proves nothing"
fi
needle=$(grep -c '^RESULT ' "${tmp}/baseline.out")
rc=$?
if [ "$rc" -ne 0 ] || [ "$needle" -lt 1 ]; then
    refuse "control needle failed: the RESULT parser found 0 lines in a gate run that emits them, so it is blind and every verdict claim below would be unfounded (§11.4.201(7)(b))"
fi
good "baseline is GREEN (exit 0) and the RESULT parser sees ${needle} verdict lines"

# --- M1: the anchor comparison is removed -----------------------------------
echo "── M1: anchor.Check() returns PASS immediately (the comparison never runs)"
sed -i 's|^func Check(a Anchor, cs ChainSummary) Result {|func Check(a Anchor, cs ChainSummary) Result {\n\treturn Result{PASS, "MUTATION T332-M1: the anchor comparison was removed"}|' \
    "${tmp}/engine/pkg/anchor/check.go"
rc=$?
[ "$rc" -eq 0 ] || refuse "M1 could not be applied (sed exit $rc)"
m1_sum=$(tree_sum "${tmp}/engine")
if [ "$m1_sum" = "$copy_sum_before" ]; then
    refuse "M1 changed nothing — a mutation whose diff is empty is a refused tautology (§11.4.115(F))"
fi
grep -qF 'MUTATION T332-M1: the anchor comparison was removed' "${tmp}/engine/pkg/anchor/check.go"
rc=$?
[ "$rc" -eq 0 ] || refuse "M1 did not land: the mutated text is absent from the copy"

run_gate m1
m1_rc=$GATE_RC
if [ "$m1_rc" -ne 0 ]; then
    good "M1 makes the gate FAIL (exit ${m1_rc}) — with the anchor comparison gone, nothing detects tail truncation"
else
    bad "M1 did NOT make the gate fail (exit ${m1_rc}); the gate would pass a mechanism that cannot see truncation at all"
fi

# the specific assertions that MUST have flipped
assert_flip m1 B2_truncation_chain_plus_anchor_detected FAIL "the truncation is no longer DETECTED"
assert_flip m1 B3_two_distinct_results FAIL "both halves now report the same verdict, so the pair carries no evidence"
assert_flip m1 B6_observed_matches_declared_intent FAIL "the observation no longer matches the corpus's declared anchor_detects=true"

# the false-positive guard that MUST NOT have flipped — this is the half T332
# names explicitly: the mutation must not be satisfiable by refusing everything.
assert_flip m1 B4_lagging_anchor_negative_control PASS "REQUIRED: the healthy lagging-anchor chain must still verify clean, so the gate went red for the truncation and NOT by refusing everything"
assert_flip m1 B1_truncation_chain_alone_pass PASS "specificity: chain-alone is untouched by this mutation"
assert_flip m1 B5_golden_good_clean PASS "specificity: the untampered chain is still clean"

rm -rf "${tmp}/engine" && cp -a "${tmp}/pristine" "${tmp}/engine" || refuse "M1 could not be restored"
restored=$(tree_sum "${tmp}/engine")
[ "$restored" = "$copy_sum_before" ] || bad "M1 restoration is not byte-identical to the baseline copy (${restored} vs ${copy_sum_before})"

run_gate restored
r_rc=$GATE_RC
if [ "$r_rc" -eq 0 ]; then
    good "the restored copy is GREEN again (exit 0) — the red run above was caused by the mutation, not by the harness"
else
    bad "the restored copy is NOT green (exit ${r_rc}); the mutation run cannot be attributed to the mutation"
fi

src_sum_after=$(tree_sum "$engine_abs")
if [ "$src_sum_after" = "$src_sum_before" ]; then
    good "the in-repo engine tree is byte-identical to how it started (${src_sum_after})"
else
    bad "the in-repo engine tree CHANGED during this run (${src_sum_before} -> ${src_sum_after})"
fi

echo "──────────────────────────────────────────────────────────────────────"
if [ "$fail_count" -ne 0 ]; then
    echo "❌ ${NAME}: FAIL — ${fail_count} assertion(s) did not hold"
    exit 1
fi
echo "✅ ${NAME}: PASS — removing the anchor comparison was OBSERVED making CM-ANCHOR-DETECTS-TAIL-TRUNCATION fail, while the lagging-anchor negative control stayed green"
exit 0
