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
# — and this gate HAS one (UNION-A6, the recording path is not yet wired). So
# this test reads per-assertion verdicts by ID and requires:
#
#   FLIPPED   UNION-A3-UNCITED-READ-EXCLUDED        PASS -> FAIL
#   FLIPPED   UNION-A4-COMPLETE-WITH-UNCITED-GAP    PASS -> FAIL
#             (A4 is the same FR-027 clause at the verification seam; demanding
#              an entry for every read must break it too, and if it did not,
#              VerifyComplete would not be consulting the classifier at all)
#   UNCHANGED UNION-A0, UNION-A1, UNION-A2, UNION-A5, UNION-A6
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
for id in UNION-A0-CLASSIFIER-PRESENT UNION-A1-STATE-CHANGING UNION-A2-CITED-READ \
          UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL UNION-A6-WIRED-AT-RECORDING-PATH; do
    b=$(cn_verdict_of "$BASE_OUT" "$id")
    m=$(cn_verdict_of "$MUT_OUT" "$id")
    if [ "$b" = "$m" ]; then
        mut "unchanged:$id" ok "$b before and after: the mutation was surgical"
    else
        mut "unchanged:$id" BAD "$b -> $m: the mutation flipped a NEIGHBOURING assertion, so a FAIL cannot be attributed to FR-027"
    fi
done

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
