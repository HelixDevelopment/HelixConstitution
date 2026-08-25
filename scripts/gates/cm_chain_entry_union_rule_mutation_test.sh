#!/bin/sh
# cm_chain_entry_union_rule_mutation_test.sh — paired §1.1 mutation for T325.
#
# ── The mutation ─────────────────────────────────────────────────────────────
# In pkg/chain/union_rule.go, RequiresEntry's read branch is
#
#       case CallRead:
#               return c.Cited          <-- FR-027, the load-bearing exclusion
#
# The mutation strips that exclusion:
#
#               return true             <-- an entry is now demanded for EVERY read
#
# and this test asserts CM-CHAIN-ENTRY-UNION-RULE FAILs as a result. Until that
# flip has been OBSERVED, the gate's passes count for nothing (§11.4.115(F):
# a gate never seen to FAIL on the genuinely-broken artifact is unvalidated
# instrumentation).
#
# ── Why it asserts a NAMED assertion, not just the exit code ─────────────────
# §11.4.194(6)(d): a mutation must flip the assertion it NAMES, not a
# neighbouring one. A test that only checks "the gate exited non-zero" cannot
# tell a mutation-induced failure apart from an unrelated pre-existing failure
# — and a gate CAN have one. UNION-A6 was exactly that case when this test was
# first written (the recording path was not yet wired). It IS wired now and A6
# PASSes, which is precisely why the exit code alone still is not enough: with
# every assertion green, a non-zero exit proves only that SOMETHING broke, not
# that FR-027 did. So this test reads per-assertion verdicts by ID and
# requires:
#
#   FLIPPED   UNION-A3-UNCITED-READ-EXCLUDED        PASS -> FAIL
#   FLIPPED   UNION-A4-COMPLETE-WITH-UNCITED-GAP    PASS -> FAIL
#             (A4 is the same FR-027 clause at the verification seam; demanding
#              an entry for every read must break it too, and if it did not,
#              VerifyComplete would not be consulting the classifier at all)
#   UNCHANGED UNION-A0, UNION-A1, UNION-A2, UNION-A5, UNION-A6, UNION-A7
#             (the surgical-mutation proof: a mutation that broke everything
#              would satisfy a naive exit-code check while proving nothing)
#
# ── Why it is not a tautology ────────────────────────────────────────────────
# §11.4.194(6)(d) also refuses a mutation whose diff merely deletes the literal
# strings a gate greps for. This one deletes no such string: the gate reads the
# RUNTIME OUTPUT of the executed classifier, never its source text. That the
# mutation is behavioural rather than textual is asserted directly — UNION-A0
# (the structural check that DOES read the source) must stay PASS.
#
# ── Residue discipline (§11.4.84) ────────────────────────────────────────────
# The mutation is applied to an OUT-OF-REPO copy under mktemp -d. The real
# module is never written to, and that is proven, not asserted: this test
# checksums the real union_rule.go before and after and refuses if it moved.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_chain_entry_union_rule_mutation_test.sh [--module <continuum-root>]
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   MUT<TAB><check><TAB><ok|BAD><TAB><detail> lines, then MUT-SUMMARY.
#   Exit 0 only if every check held.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, grep, awk, mktemp, cp, sha256sum (or shasum), and `go` — without
#   a Go toolchain the classifier cannot be executed and the mutation cannot be
#   observed, so this test REFUSES rather than reporting a vacuous pass.

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE="$SELF_DIR/cm_chain_entry_union_rule.sh"
. "$SELF_DIR/lib/chain_control_needle.sh"

MODULE="$SELF_DIR/../../submodules/continuum"
while [ $# -gt 0 ]; do
    case $1 in
        --module) MODULE=$2; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

BAD=0
mut() { # mut <check> <ok|BAD> <detail>
    printf 'MUT%s%s%s%s%s%s\n' "$CN_TAB" "$1" "$CN_TAB" "$2" "$CN_TAB" "$3"
    [ "$2" = ok ] || BAD=$((BAD + 1))
}

[ -f "$GATE" ] || { printf 'META: gate script missing: %s\n' "$GATE" >&2; exit 2; }
[ -d "$MODULE" ] || { printf 'META: module missing: %s\n' "$MODULE" >&2; exit 2; }
MODULE=$(CDPATH= cd -- "$MODULE" && pwd)
REAL_SRC="$MODULE/pkg/chain/union_rule.go"
[ -f "$REAL_SRC" ] || { printf 'META: classifier missing: %s\n' "$REAL_SRC" >&2; exit 2; }

if ! command -v go >/dev/null 2>&1; then
    # A mutation that cannot be OBSERVED validates nothing. Refusing is the
    # honest outcome; reporting ok would be the bluff this file exists to stop.
    printf 'MUT%sREFUSE%sBAD%sno go toolchain: the mutation could not be executed, so it was NOT observed\n' \
        "$CN_TAB" "$CN_TAB" "$CN_TAB"
    exit 1
fi

_sum() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
BEFORE=$(_sum "$REAL_SRC")

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_union_mut.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

cp -a "$MODULE" "$TMP/continuum" || { printf 'META: copy failed\n' >&2; exit 2; }
COPY="$TMP/continuum"
COPY_SRC="$COPY/pkg/chain/union_rule.go"

# ── Baseline ─────────────────────────────────────────────────────────────────
BASE_OUT="$TMP/baseline.out"
sh "$GATE" --module "$COPY" > "$BASE_OUT" 2>&1
BASE_RC=$?

for id in UNION-A0-CLASSIFIER-PRESENT UNION-A3-UNCITED-READ-EXCLUDED UNION-A4-COMPLETE-WITH-UNCITED-GAP; do
    v=$(cn_verdict_of "$BASE_OUT" "$id")
    if [ "$v" = PASS ]; then
        mut "baseline:$id" ok "PASS before the mutation, as a flip requires"
    else
        # Not a mutation failure — the precondition for observing one is absent.
        mut "baseline:$id" BAD "expected PASS at baseline, got $v; the mutation cannot be shown to flip an assertion that was not passing"
    fi
done

# ── Apply the mutation ───────────────────────────────────────────────────────
# Fail CLOSED if the branch is not exactly where this test believes it is: a
# mutation applied to the wrong line proves nothing, and silently applying zero
# edits while reporting success is the precise failure mode being guarded.
cn_count '-E' '^[[:space:]]*return c\.Cited$' "$COPY_SRC"
if [ "$CN_COUNT" -ne 1 ]; then
    mut apply BAD "expected exactly one 'return c.Cited' branch in union_rule.go, found $CN_COUNT — the classifier moved and this mutation is stale"
    printf 'MUT-SUMMARY%sbad=%s\n' "$CN_TAB" "$((BAD + 1))"
    exit 1
fi
awk '{ if ($0 ~ /^[[:space:]]*return c\.Cited$/) print "\t\treturn true"; else print }' \
    "$COPY_SRC" > "$COPY_SRC.mut" && mv "$COPY_SRC.mut" "$COPY_SRC"

cn_count '-E' '^[[:space:]]*return true$' "$COPY_SRC"
if [ "$CN_COUNT" -ge 1 ]; then
    mut apply ok "FR-027 exclusion stripped: RequiresEntry now demands an entry for every read"
else
    mut apply BAD 'the mutation did not land — nothing was changed, so nothing was proven'
fi

# The mutation must be BEHAVIOURAL, not the deletion of greppable text: every
# API name the gate's structural check reads must survive it.
cn_certified_absence '-E' '^func (RequiresEntry|RequiredEntries)\(' \
    '^func (VerifyComplete|RequiredEntries)\(' "$COPY_SRC"
if [ "$CN_RESULT" = PRESENT ]; then
    mut not-a-tautology ok 'the classifier API text is untouched; the mutation changes behaviour, not the strings the gate reads'
else
    mut not-a-tautology BAD "the mutation removed API text ($CN_RESULT) — that would be a string-deletion tautology, not a behavioural mutation"
fi

# ── Mutated run ──────────────────────────────────────────────────────────────
MUT_OUT="$TMP/mutated.out"
sh "$GATE" --module "$COPY" > "$MUT_OUT" 2>&1
MUT_RC=$?

if [ "$MUT_RC" -ne 0 ]; then
    mut gate-fails ok "the gate FAILed under the mutation (rc=$MUT_RC)"
else
    mut gate-fails BAD 'the gate PASSed under the mutation: it does not assert FR-027 and its passes prove nothing'
fi

# FLIPPED — the named assertion and its verification-seam sibling.
for id in UNION-A3-UNCITED-READ-EXCLUDED UNION-A4-COMPLETE-WITH-UNCITED-GAP; do
    v=$(cn_verdict_of "$MUT_OUT" "$id")
    if [ "$v" = FAIL ]; then
        mut "flipped:$id" ok 'PASS -> FAIL under the mutation'
    else
        mut "flipped:$id" BAD "expected FAIL under the mutation, got $v — the gate does not actually assert this clause"
    fi
done

# UNCHANGED — the surgical proof.
#
# UNION-A7 is in this set because it is an assertion the gate MAKES, and
# §11.4.194(6)(d)'s surgical proof is only a proof if it covers the assertions
# that exist rather than the ones that existed when this test was written.
# A7 is expected to hold across the mutation on its own merits, not by
# assumption: its rows are three `exec` calls, and the mutation changes only
# how a READ is classified, so nothing A7 measures is in the mutation's blast
# radius. That expectation is CHECKED here, never asserted — if the mutation
# did move A7 it would be reported BAD, which is the whole point.
#
# HONEST BOUNDARY (§11.4.6, §11.4.201(6)). This comparison is base-vs-mutated,
# so it is polarity-neutral and cannot false-refuse on a host where A7 is
# environmentally unavailable — but for that same reason it is VACUOUS when A7
# is non-PASS on BOTH sides (a toolchain-blind A7 equals a toolchain-blind A7).
# The detail string therefore carries the verdict that was compared, so a
# vacuous pass is visible in the output instead of reading like a proof.
for id in UNION-A0-CLASSIFIER-PRESENT UNION-A1-STATE-CHANGING UNION-A2-CITED-READ \
          UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL UNION-A6-WIRED-AT-RECORDING-PATH \
          UNION-A7-WIRING-EXERCISED-AT-RUNTIME; do
    b=$(cn_verdict_of "$BASE_OUT" "$id")
    m=$(cn_verdict_of "$MUT_OUT" "$id")
    if [ "$b" = "$m" ]; then
        mut "unchanged:$id" ok "$b before and after: the mutation was surgical"
    else
        mut "unchanged:$id" BAD "$b -> $m: the mutation flipped a NEIGHBOURING assertion, so a FAIL cannot be attributed to FR-027"
    fi
done

# ── PHASE 2 — the kill-power proof for UNION-A7 (§11.4.115(F), §1.1) ─────────
# Phase 1 proves this gate asserts FR-027. It does NOT prove the gate asserts
# UNION-A7: the FR-027 mutation leaves A7 PASSing (that is its surgical half),
# so after Phase 1 alone A7 is a verdict that has never been OBSERVED to FAIL —
# and per §11.4.115(F) a guard never seen refusing the genuinely-broken
# artifact is unvalidated instrumentation, not a guard. This phase supplies the
# missing observation on a SECOND, independently-mutated copy.
#
# THE MUTATION: the consumer's verdict source is short-circuited to always-PASS
# (VerifyExecRows stops consulting VerifyComplete). That is exactly the failure
# A7's own comment names — "a consumer that only ever says PASS proves as
# little as one that only ever says DETECTED" — so it is the mutation that
# tests what A7 CLAIMS to test, not a neighbouring clause.
#
# NOT A TAUTOLOGY (§11.4.115(F)): the gate reads this consumer's RUNTIME
# OUTPUT. The mutation deletes none of the `UNIONRULE ` lines the gate greps —
# they are all still printed, they now print the WRONG verdict. That the
# strings survived is asserted below, not assumed.
A7_ID=UNION-A7-WIRING-EXERCISED-AT-RUNTIME
A7_BASE=$(cn_verdict_of "$BASE_OUT" "$A7_ID")
A7_SRC_REAL="$MODULE/pkg/chain/exec_call.go"
A7_BEFORE=$(_sum "$A7_SRC_REAL")

if [ "$A7_BASE" != PASS ]; then
    # Not a mutation failure — the precondition for OBSERVING a flip is absent.
    # Reported, never silently skipped: an unobserved kill is not a proof.
    mut "a7-killpower:precondition" BAD "UNION-A7 is $A7_BASE at baseline, so it cannot be observed flipping to FAIL; the kill-power of A7 is NOT proven by this run"
else
    A7COPY="$TMP/continuum_a7"
    if ! cp -a "$MODULE" "$A7COPY" 2>/dev/null; then
        mut "a7-killpower:setup" BAD 'second module copy failed; the A7 mutation could not be applied and its kill-power is NOT proven'
    else
        A7_SRC="$A7COPY/pkg/chain/exec_call.go"
        # Fail CLOSED if the delegation is not exactly where this test believes
        # it is: a mutation applied to the wrong line proves nothing.
        cn_count '-E' '^[[:space:]]*return VerifyComplete\(recs, calls\), calls, nil$' "$A7_SRC"
        if [ "$CN_COUNT" -ne 1 ]; then
            mut "a7-killpower:apply" BAD "expected exactly one VerifyExecRows delegation to VerifyComplete in exec_call.go, found $CN_COUNT — the consumer path moved and this mutation is stale"
        else
            awk '{ if ($0 ~ /^[[:space:]]*return VerifyComplete\(recs, calls\), calls, nil$/) print "\treturn Report{Verdict: PASS}, calls, nil"; else print }' \
                "$A7_SRC" > "$A7_SRC.mut" && mv "$A7_SRC.mut" "$A7_SRC"

            cn_count '-F' 'return Report{Verdict: PASS}, calls, nil' "$A7_SRC"
            if [ "$CN_COUNT" -ge 1 ]; then
                mut "a7-killpower:apply" ok 'the consumer verdict is now hardcoded PASS: it can no longer report a shortfall'
            else
                mut "a7-killpower:apply" BAD 'the A7 mutation did not land — nothing was changed, so nothing was proven'
            fi

            # Tautology guard: the lines the gate greps must SURVIVE.
            # Needle: a fixed string of the SAME class (bare -F literal, same file,
            # same tool, same path) that is known present independently of the
            # query, so a zero on the query means ABSENT rather than blind.
            cn_certified_absence '-F' 'func main()' \
                'UNIONRULE ' "$A7COPY/cmd/continuum-unionrule/main.go"
            if [ "$CN_RESULT" = PRESENT ]; then
                mut "a7-killpower:not-a-tautology" ok 'every `UNIONRULE ` line the gate reads is still printed; the mutation changes the verdict, not the strings'
            else
                mut "a7-killpower:not-a-tautology" BAD "the consumer output text was removed ($CN_RESULT) — that would be a string-deletion tautology, not a behavioural mutation"
            fi

            A7_OUT="$TMP/mutated_a7.out"
            sh "$GATE" --module "$A7COPY" > "$A7_OUT" 2>&1
            A7_RC=$?

            a7v=$(cn_verdict_of "$A7_OUT" "$A7_ID")
            if [ "$a7v" = FAIL ]; then
                mut "a7-killpower:flipped:$A7_ID" ok "PASS -> FAIL: the gate DOES refuse a consumer that cannot report a shortfall"
            else
                mut "a7-killpower:flipped:$A7_ID" BAD "expected FAIL under the always-PASS consumer mutation, got $a7v — UNION-A7 does not actually assert that both verdicts are reachable, and its PASSes prove nothing"
            fi
            if [ "$A7_RC" -ne 0 ]; then
                mut "a7-killpower:gate-fails" ok "the gate FAILed under the A7 mutation (rc=$A7_RC)"
            else
                mut "a7-killpower:gate-fails" BAD 'the gate PASSed under the A7 mutation: the runtime half of the wiring assertion is decoration'
            fi

            # Surgical proof for THIS mutation too: nothing else may move.
            for id in UNION-A0-CLASSIFIER-PRESENT UNION-A1-STATE-CHANGING UNION-A2-CITED-READ \
                      UNION-A3-UNCITED-READ-EXCLUDED UNION-A4-COMPLETE-WITH-UNCITED-GAP \
                      UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL UNION-A6-WIRED-AT-RECORDING-PATH; do
                b=$(cn_verdict_of "$BASE_OUT" "$id")
                m=$(cn_verdict_of "$A7_OUT" "$id")
                if [ "$b" = "$m" ]; then
                    mut "a7-killpower:unchanged:$id" ok "$b before and after: the A7 mutation was surgical"
                else
                    mut "a7-killpower:unchanged:$id" BAD "$b -> $m: the A7 mutation flipped a NEIGHBOURING assertion, so the A7 FAIL cannot be attributed to the consumer's verdict source"
                fi
            done
        fi
    fi
fi

A7_AFTER=$(_sum "$A7_SRC_REAL")
if [ "$A7_BEFORE" = "$A7_AFTER" ]; then
    mut a7-no-residue ok "real exec_call.go unchanged (sha256 $A7_BEFORE)"
else
    mut a7-no-residue BAD "real exec_call.go CHANGED ($A7_BEFORE -> $A7_AFTER): A7 mutation residue landed in the tree"
fi

# ── Residue proof (§11.4.84) ─────────────────────────────────────────────────
AFTER=$(_sum "$REAL_SRC")
if [ "$BEFORE" = "$AFTER" ]; then
    mut no-residue ok "real union_rule.go unchanged (sha256 $BEFORE)"
else
    mut no-residue BAD "real union_rule.go CHANGED ($BEFORE -> $AFTER): mutation residue landed in the tree"
fi

printf 'MUT-SUMMARY%sbad=%s%sbaseline_rc=%s mutated_rc=%s\n' \
    "$CN_TAB" "$BAD" "$CN_TAB" "$BASE_RC" "$MUT_RC"
[ "$BAD" -eq 0 ] || exit 1
exit 0
