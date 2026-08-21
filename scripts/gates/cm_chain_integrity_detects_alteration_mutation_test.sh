#!/bin/sh
# cm_chain_integrity_detects_alteration_mutation_test.sh — paired §1.1 mutation
# for T326.
#
# ── The mutation ─────────────────────────────────────────────────────────────
# In pkg/verify/chain_verify.go, VerifyChainFile's INCOMPLETE-WALK branch — the
# one taken when the store cannot be decoded, i.e. the walk stopped and decided
# nothing — returns
#
#       return Result{REFUSE, fmt.Sprintf(
#               "chain store %q %s: %v — the walk stopped there, ...
#
# The mutation maps that branch to PASS:
#
#       return Result{PASS, fmt.Sprintf(   <-- undecided, reported as clean
#
# and this test asserts CM-CHAIN-INTEGRITY-DETECTS-ALTERATION FAILs as a
# result. This is FR-030's exact failure mode, and it is a nasty one: the
# `reason` string is left untouched, so the mutated verifier reports PASS while
# still explaining that every record beyond the tear is UNVERIFIED. A gate that
# read the prose instead of the verdict would sail straight past it.
#
# ── Why it asserts a NAMED assertion, not just the exit code ─────────────────
# §11.4.194(6)(d): a mutation must flip the assertion it NAMES. This one is
# aimed at CHAIN-A4-UNWALKABLE-REFUSES, and the surgical proof is
# CHAIN-A5-ABSENT-STORE-REFUSES: A5 asserts REFUSE too, but reaches it through
# the READ-failure branch, which this mutation does not touch. So:
#
#   FLIPPED   CHAIN-A4-UNWALKABLE-REFUSES     PASS -> FAIL
#   UNCHANGED CHAIN-A5-ABSENT-STORE-REFUSES   (a sibling REFUSE assertion on a
#             different branch — if it flipped too, the mutation would have
#             been broad and a FAIL could not be attributed to the walk branch)
#   UNCHANGED CHAIN-A0, A1, A2, A3, A6, A7
#
# ── Why it is not a tautology ────────────────────────────────────────────────
# §11.4.194(6)(d) refuses a mutation whose diff merely deletes the literal
# strings a gate greps for. This one deletes none: the gate never reads the
# verifier's source, only its executed output, and the mutation leaves every
# message string byte-identical. Both facts are asserted rather than claimed —
# the reason text must survive, and CHAIN-A0 (which proves the verifier still
# BUILDS) must stay PASS, so the FAIL cannot be a compile error in disguise.
#
# ── Residue discipline (§11.4.84) ────────────────────────────────────────────
# Applied to an OUT-OF-REPO copy under mktemp -d; the real chain_verify.go is
# checksummed before and after and the test refuses if it moved.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_chain_integrity_detects_alteration_mutation_test.sh [--module <root>]
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   MUT / MUT-SUMMARY lines. Exit 0 only if every check held.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, grep, awk, mktemp, cp, sha256sum (or shasum), `go`.

set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE="$SELF_DIR/cm_chain_integrity_detects_alteration.sh"
. "$SELF_DIR/lib/chain_control_needle.sh"

MODULE="$SELF_DIR/../../submodules/continuum"
while [ $# -gt 0 ]; do
    case $1 in
        --module) MODULE=$2; shift 2 ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

BAD=0
mut() {
    printf 'MUT%s%s%s%s%s%s\n' "$CN_TAB" "$1" "$CN_TAB" "$2" "$CN_TAB" "$3"
    [ "$2" = ok ] || BAD=$((BAD + 1))
}

[ -f "$GATE" ] || { printf 'META: gate script missing: %s\n' "$GATE" >&2; exit 2; }
[ -d "$MODULE" ] || { printf 'META: module missing: %s\n' "$MODULE" >&2; exit 2; }
MODULE=$(CDPATH= cd -- "$MODULE" && pwd)
REAL_SRC="$MODULE/pkg/verify/chain_verify.go"
[ -f "$REAL_SRC" ] || { printf 'META: verifier missing: %s\n' "$REAL_SRC" >&2; exit 2; }

if ! command -v go >/dev/null 2>&1; then
    printf 'MUT%sREFUSE%sBAD%sno go toolchain: the mutation could not be executed, so it was NOT observed\n' \
        "$CN_TAB" "$CN_TAB" "$CN_TAB"
    exit 1
fi

_sum() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
BEFORE=$(_sum "$REAL_SRC")

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_chain_mut.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

cp -a "$MODULE" "$TMP/continuum" || { printf 'META: copy failed\n' >&2; exit 2; }
COPY="$TMP/continuum"
COPY_SRC="$COPY/pkg/verify/chain_verify.go"

# ── Baseline ─────────────────────────────────────────────────────────────────
BASE_OUT="$TMP/baseline.out"
sh "$GATE" --module "$COPY" > "$BASE_OUT" 2>&1
BASE_RC=$?

if [ "$BASE_RC" -eq 0 ]; then
    mut baseline-clean ok "the gate PASSes the unmutated verifier (rc=0), so any FAIL below is the mutation's doing"
else
    mut baseline-clean BAD "the gate already FAILs before the mutation (rc=$BASE_RC); a flip could not be attributed to it"
fi
for id in CHAIN-A4-UNWALKABLE-REFUSES CHAIN-A5-ABSENT-STORE-REFUSES; do
    v=$(cn_verdict_of "$BASE_OUT" "$id")
    if [ "$v" = PASS ]; then
        mut "baseline:$id" ok 'PASS before the mutation, as a flip requires'
    else
        mut "baseline:$id" BAD "expected PASS at baseline, got $v"
    fi
done

# ── Apply the mutation ───────────────────────────────────────────────────────
# The branch is identified SEMANTICALLY — the REFUSE return whose very next
# line carries the incomplete-walk message — because chain_verify.go holds
# three `Result{REFUSE, fmt.Sprintf(` returns and mutating the wrong one would
# prove nothing while looking identical in a summary.
ANCHOR='the walk stopped there'
cn_count '-F' "$ANCHOR" "$COPY_SRC"
if [ "$CN_COUNT" -ne 1 ]; then
    mut locate BAD "expected exactly one incomplete-walk branch (anchor '$ANCHOR'), found $CN_COUNT — the verifier moved and this mutation is stale"
    printf 'MUT-SUMMARY%sbad=%s\n' "$CN_TAB" "$((BAD + 1))"
    exit 1
fi

awk -v anchor="$ANCHOR" '
    { line[NR] = $0 }
    END {
        for (i = 1; i <= NR; i++) {
            if (line[i] ~ /return Result\{REFUSE, fmt\.Sprintf\(/ &&
                i < NR && index(line[i+1], anchor) > 0) {
                sub(/Result\{REFUSE,/, "Result{PASS,", line[i])
                hit++
            }
            print line[i]
        }
        if (hit != 1) exit 9
    }
' "$COPY_SRC" > "$COPY_SRC.mut"
AWK_RC=$?
if [ "$AWK_RC" -ne 0 ]; then
    mut locate BAD "the incomplete-walk return could not be located next to its message (awk rc=$AWK_RC); nothing was mutated"
    printf 'MUT-SUMMARY%sbad=%s\n' "$CN_TAB" "$((BAD + 1))"
    exit 1
fi
mv "$COPY_SRC.mut" "$COPY_SRC"
mut locate ok 'the incomplete-walk branch was located by its own message and mapped REFUSE -> PASS'

# Non-tautology, asserted twice over: the message the branch emits must survive
# the mutation byte-for-byte (so the mutated verifier still explains that the
# records are UNVERIFIED while claiming PASS), and the file must still compile.
cn_count '-F' "$ANCHOR" "$COPY_SRC"
if [ "$CN_COUNT" -eq 1 ]; then
    mut not-a-tautology ok 'the incomplete-walk message is untouched: the mutation changes the VERDICT, not the text — the mutated verifier reports PASS while still saying the records are UNVERIFIED'
else
    mut not-a-tautology BAD "the mutation removed the branch text (anchor count now $CN_COUNT) — that would be a string-deletion tautology"
fi

# ── Mutated run ──────────────────────────────────────────────────────────────
MUT_OUT="$TMP/mutated.out"
sh "$GATE" --module "$COPY" > "$MUT_OUT" 2>&1
MUT_RC=$?

if [ "$MUT_RC" -ne 0 ]; then
    mut gate-fails ok "the gate FAILed under the mutation (rc=$MUT_RC)"
else
    mut gate-fails BAD 'the gate PASSed under the mutation: it does not assert FR-030 and its passes prove nothing'
fi

v=$(cn_verdict_of "$MUT_OUT" CHAIN-A4-UNWALKABLE-REFUSES)
if [ "$v" = FAIL ]; then
    mut flipped:CHAIN-A4-UNWALKABLE-REFUSES ok 'PASS -> FAIL under the mutation'
else
    mut flipped:CHAIN-A4-UNWALKABLE-REFUSES BAD "expected FAIL under the mutation, got $v — the gate does not actually assert that an unwalkable chain REFUSEs"
fi

# The verifier must still BUILD: a FAIL caused by a broken compile would prove
# nothing about the assertion.
a0=$(cn_verdict_of "$MUT_OUT" CHAIN-A0-VERIFIER-BUILDS)
if [ "$a0" = PASS ]; then
    mut still-builds ok 'the mutated verifier still builds, so the FAIL is behavioural rather than a compile error'
else
    mut still-builds BAD "CHAIN-A0 is $a0 under the mutation: the FAIL may be a build failure, which would prove nothing"
fi

for id in CHAIN-A1-MUTATION-DETECTED CHAIN-A2-DELETION-DETECTED CHAIN-A3-REORDER-DETECTED \
          CHAIN-A5-ABSENT-STORE-REFUSES CHAIN-A6-HEALTHY-PASSES \
          CHAIN-A7-DOCUMENTED-LIMITS-PASS-CHAIN-ALONE; do
    b=$(cn_verdict_of "$BASE_OUT" "$id")
    m=$(cn_verdict_of "$MUT_OUT" "$id")
    if [ "$b" = "$m" ]; then
        mut "unchanged:$id" ok "$b before and after: the mutation was surgical"
    else
        mut "unchanged:$id" BAD "$b -> $m: the mutation flipped a NEIGHBOURING assertion, so a FAIL cannot be attributed to the incomplete-walk branch"
    fi
done

# ── Residue proof (§11.4.84) ─────────────────────────────────────────────────
AFTER=$(_sum "$REAL_SRC")
if [ "$BEFORE" = "$AFTER" ]; then
    mut no-residue ok "real chain_verify.go unchanged (sha256 $BEFORE)"
else
    mut no-residue BAD "real chain_verify.go CHANGED ($BEFORE -> $AFTER): mutation residue landed in the tree"
fi

printf 'MUT-SUMMARY%sbad=%s%sbaseline_rc=%s mutated_rc=%s\n' \
    "$CN_TAB" "$BAD" "$CN_TAB" "$BASE_RC" "$MUT_RC"
[ "$BAD" -eq 0 ] || exit 1
exit 0
