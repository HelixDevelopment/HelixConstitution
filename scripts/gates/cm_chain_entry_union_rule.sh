#!/bin/sh
# cm_chain_entry_union_rule.sh — CM-CHAIN-ENTRY-UNION-RULE gate (T325).
#
# ── What this gate asserts ───────────────────────────────────────────────────
# The union rule (FR-026, FR-027, FR-028) says a chain entry is REQUIRED for
# every state-changing call (write, exec, deploy) and for every read CITED as
# evidence, and is NOT required for an uncited read.
#
#   UNION-A0  the classifier source is present                     (structural)
#   UNION-A1  write / exec / deploy REQUIRE an entry                  (RUNTIME)
#   UNION-A2  a CITED read REQUIRES an entry                          (RUNTIME)
#   UNION-A3  an UNCITED read does NOT                                (RUNTIME)
#   UNION-A4  VerifyComplete PASSes a chain whose only missing entries
#             are for uncited reads — FR-027 where it actually bites  (RUNTIME)
#   UNION-A5  VerifyComplete still DETECTs a genuine shortfall        (RUNTIME)
#   UNION-A6  the classifier is WIRED at the recording path         (structural)
#
# A3 and A4 are the FR-027 FALSE-POSITIVE half, and they are HARD ASSERTIONS,
# not comments. A gate that demanded an entry for every read would not be
# stricter — it would be WRONG, and per §11.4.201(1) a false refusal is a
# FAIL-bluff exactly as serious as a false pass: it condemns correct behaviour
# and teaches people to route around the verifier. A5 is the guard in the other
# direction, so the rule cannot be "satisfied" by a classifier that demands
# nothing of anybody.
#
# ── Why the assertions are RUN, not grepped ──────────────────────────────────
# §11.4.227(A): a prose carrier never counts as an implementation, and a gate
# that greps for a function name is the exact bluff this feature exists to
# kill. A1-A5 therefore EXECUTE the shipped classifier through a throwaway Go
# probe that imports the real package, and assert on what it actually returns.
#
# ── Why A6 is a hard assertion and may FAIL ──────────────────────────────────
# §11.4.108: source-present is NOT runtime-active. A classifier that exists but
# is called from nothing except its own unit test does not classify anything
# that happens. If A6 FAILs, the gate is working: the honest reading is that
# the recording path has not yet been wired (see T315 / T323 / T333), NOT that
# the gate is broken.
#
# ── Absence discipline ───────────────────────────────────────────────────────
# Every absence this gate reports is certified by a class-matched control
# needle through the SAME tool, flags and targets (§11.4.201(7)(b), T324). An
# uncertified zero is reported BLIND and fails the gate — it is an undecided
# result, and undecided reported as intact is the bluff §11.4.201(6) forbids.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_chain_entry_union_rule.sh [--module <continuum-root>]
#     --module <dir>  the continuum module root
#                     (default: <this script>/../../submodules/continuum)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   CN-VERDICT<TAB><ID><TAB><PASS|FAIL|BLIND|SKIP><TAB><message> per assertion,
#   then CN-SUMMARY. Exit 0 only when nothing FAILed and nothing was BLIND.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only w.r.t. the repository. The Go probe is built and run ENTIRELY
#   inside a mktemp -d removed on exit; it reaches the module read-only via a
#   `replace` directive and never writes into it.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, grep, awk, mktemp; `go` for A1-A5 (SKIPped with reason if absent).

set -u

GATE_ID=CM-CHAIN-ENTRY-UNION-RULE
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/chain_control_needle.sh"

MODULE="$SELF_DIR/../../submodules/continuum"
while [ $# -gt 0 ]; do
    case $1 in
        --module) MODULE=$2; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

cn_reset
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_union_rule.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

if [ ! -d "$MODULE" ]; then
    cn_blind UNION-A0-CLASSIFIER-PRESENT "module root not found: $MODULE — nothing was examined"
    cn_summary "$GATE_ID"
    exit 1
fi
MODULE=$(CDPATH= cd -- "$MODULE" && pwd)
UNION_SRC="$MODULE/pkg/chain/union_rule.go"

# ── UNION-A0 — the classifier source exists and exports the API ──────────────
# Structural precondition only. It proves nothing about behaviour (that is
# A1-A5) and nothing about wiring (that is A6); it exists so a missing FILE is
# reported as a missing file rather than surfacing as five confusing runtime
# failures.
if [ ! -f "$UNION_SRC" ]; then
    cn_fail UNION-A0-CLASSIFIER-PRESENT "union-rule classifier absent: $UNION_SRC"
else
    # Needle and query are both anchored func declarations with an alternation:
    # same class, same file, same flags.
    cn_certified_absence '-E' '^func (RequiresEntry|RequiredEntries)\(' \
        '^func (VerifyComplete|RequiredEntries)\(' "$UNION_SRC"
    case $CN_RESULT in
        PRESENT) cn_pass UNION-A0-CLASSIFIER-PRESENT "classifier API declared in $UNION_SRC" ;;
        ABSENT)  cn_fail UNION-A0-CLASSIFIER-PRESENT "classifier file exists but declares no union-rule API: $CN_DETAIL" ;;
        *)       cn_blind UNION-A0-CLASSIFIER-PRESENT "$CN_RESULT: $CN_DETAIL" ;;
    esac
fi

# ── UNION-A1..A5 — RUN the shipped classifier ────────────────────────────────
if ! command -v go >/dev/null 2>&1; then
    # §11.4.3 honest SKIP: the capability is genuinely absent. It is NOT
    # upgraded to a PASS — nothing about behaviour was observed.
    for id in UNION-A1-STATE-CHANGING UNION-A2-CITED-READ UNION-A3-UNCITED-READ-EXCLUDED \
              UNION-A4-COMPLETE-WITH-UNCITED-GAP UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL; do
        cn_skip "$id" 'go toolchain absent: the classifier could not be executed, so its behaviour was NOT observed'
    done
else
    P="$TMP/probe"
    mkdir -p "$P"
    cat > "$P/go.mod" <<EOF
module unionprobe

go 1.22

require github.com/vasic-digital/continuum v0.0.0

replace github.com/vasic-digital/continuum => $MODULE
EOF
    cat > "$P/main.go" <<'PROBE_EOF'
// Throwaway probe: executes the SHIPPED union-rule classifier and prints what
// it actually returns. It asserts nothing itself — the gate does the asserting
// — so that the probe cannot quietly "pass" by disagreeing with the gate.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/vasic-digital/continuum/pkg/chain"
	"github.com/vasic-digital/continuum/pkg/verify"
)

func main() {
	for _, c := range []chain.Call{
		{Kind: chain.CallWrite, Cited: false},
		{Kind: chain.CallExec, Cited: false},
		{Kind: chain.CallDeploy, Cited: false},
		{Kind: chain.CallRead, Cited: true},
		{Kind: chain.CallRead, Cited: false},
	} {
		fmt.Printf("UNION_REQUIRES %s %t %t\n", c.Kind, c.Cited, chain.RequiresEntry(c))
	}

	// A real, valid one-record chain, built by the module's OWN builder so this
	// probe carries no second canonicaliser (§11.4.251).
	dir, err := os.MkdirTemp("", "unionprobe")
	if err != nil {
		fmt.Fprintln(os.Stderr, "tempdir:", err)
		os.Exit(1)
	}
	defer os.RemoveAll(dir)
	p := filepath.Join(dir, "chain.jsonl")
	if err := verify.WriteHealthyChainForTest(p, 1); err != nil {
		fmt.Fprintln(os.Stderr, "chain:", err)
		os.Exit(1)
	}
	b, err := os.ReadFile(p)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read:", err)
		os.Exit(1)
	}
	recs, err := chain.Decode(b)
	if err != nil {
		fmt.Fprintln(os.Stderr, "decode:", err)
		os.Exit(1)
	}

	// FR-027 where it bites: one state-changing call (recorded) plus two
	// UNCITED reads (not recorded). The chain is COMPLETE.
	uncitedGap := []chain.Call{
		{Kind: chain.CallWrite, Cited: false},
		{Kind: chain.CallRead, Cited: false},
		{Kind: chain.CallRead, Cited: false},
	}
	fmt.Printf("UNION_COMPLETE uncited_gap %s\n", chain.VerifyComplete(recs, uncitedGap).Verdict)

	// The other direction: three state-changing calls, one record. Genuinely
	// short, and it must be caught -- otherwise "PASS" would mean nothing.
	realShortfall := []chain.Call{
		{Kind: chain.CallWrite, Cited: false},
		{Kind: chain.CallExec, Cited: false},
		{Kind: chain.CallDeploy, Cited: false},
	}
	fmt.Printf("UNION_COMPLETE real_shortfall %s\n", chain.VerifyComplete(recs, realShortfall).Verdict)
}
PROBE_EOF

    OUT="$TMP/probe.out"
    ( cd "$P" && go run . ) > "$OUT" 2> "$TMP/probe.err"
    PROBE_RC=$?

    if [ "$PROBE_RC" -ne 0 ]; then
        for id in UNION-A1-STATE-CHANGING UNION-A2-CITED-READ UNION-A3-UNCITED-READ-EXCLUDED \
                  UNION-A4-COMPLETE-WITH-UNCITED-GAP UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL; do
            cn_blind "$id" "the classifier probe failed to build or run (rc=$PROBE_RC): $(head -3 "$TMP/probe.err" | tr '\n' ' ')"
        done
    else
        # Every read of the probe output is needled: if the reader cannot see
        # the probe's lines, that is blindness, not a classifier defect.
        probe_line() { # probe_line <id> <query> <expect-present:yes|no> <msg-present> <msg-absent>
            _id=$1; _q=$2; _want=$3; _mp=$4; _ma=$5
            # The needle carries anchor + alternation + group + class +
            # quantifier, so it covers every class any query below uses. A
            # bare-literal or alternation-free needle would be refused, which
            # is §11.4.201(7)(b) working, not an obstacle to route around.
            cn_certified_absence '-E' '^UNION_(REQUIRES|COMPLETE) [a-z_]+' "$_q" "$OUT"
            case $CN_RESULT in
                PRESENT) if [ "$_want" = yes ]; then cn_pass "$_id" "$_mp"; else cn_fail "$_id" "$_ma"; fi ;;
                ABSENT)  if [ "$_want" = no ];  then cn_pass "$_id" "$_mp"; else cn_fail "$_id" "$_ma"; fi ;;
                *)       cn_blind "$_id" "$CN_RESULT reading the probe output: $CN_DETAIL" ;;
            esac
        }

        # A1 — all three state-changing kinds require an entry. Asserted as the
        # ABSENCE of any state-changing kind answering false, so a newly added
        # kind that answers false is caught rather than ignored.
        probe_line UNION-A1-STATE-CHANGING \
            '^UNION_REQUIRES (write|exec|deploy) (true|false) false$' no \
            'write, exec and deploy all REQUIRE a chain entry (FR-026)' \
            'a state-changing call did NOT require a chain entry — FR-026 broken'

        probe_line UNION-A2-CITED-READ \
            '^UNION_REQUIRES read true true$' yes \
            'a CITED read REQUIRES a chain entry (FR-028)' \
            'a cited read did not require an entry — FR-028 broken'

        # A3 — the FR-027 exclusion. THIS is the assertion T329's mutation flips.
        probe_line UNION-A3-UNCITED-READ-EXCLUDED \
            '^UNION_REQUIRES read false false$' yes \
            'an UNCITED read does NOT require a chain entry (FR-027) — the false-positive half holds' \
            'an uncited read was DEMANDED an entry: FR-027 broken, and per §11.4.201(1) this false refusal is as serious as a false pass'

        # A4 — FR-027 at the level that actually gates work.
        probe_line UNION-A4-COMPLETE-WITH-UNCITED-GAP \
            '^UNION_COMPLETE uncited_gap PASS$' yes \
            'a chain missing entries ONLY for uncited reads verifies COMPLETE (FR-027)' \
            'a chain missing only uncited-read entries was reported incomplete — FR-027 broken at the verification seam'

        # A5 — the guard against a rule that demands nothing.
        probe_line UNION-A5-COMPLETE-DETECTS-REAL-SHORTFALL \
            '^UNION_COMPLETE real_shortfall DETECTED$' yes \
            'a genuine entry shortfall is still DETECTED — the rule is not vacuous' \
            'a genuine shortfall was NOT detected: the union rule demands nothing and asserts nothing'
    fi
fi

# ── UNION-A6 — wired at the recording path (§11.4.108) ───────────────────────
# The query looks for a CALL to the classifier from a non-test Go file other
# than the classifier's own source. Comment lines are excluded: a doc comment
# that mentions RequiresEntry is a CARRIER, not a call (§11.4.201(7)(a)).
#
# The needle is `chain.(Verify|Decode)(` — same escape+group+alternation class,
# and known to be called from non-test code in this very file set. If the
# needle stops being visible the result is BLIND, never "not wired".
A6_FLAGS="-R -E --include=*.go --exclude=*_test.go --exclude=union_rule.go"
cn_certified_absence_noncarrier "$A6_FLAGS" \
    'chain\.(Verify|Decode)\(' \
    'chain\.(RequiresEntry|RequiredEntries|VerifyComplete|IsStateChanging)\(' \
    "$MODULE"
case $CN_RESULT in
    PRESENT)
        cn_pass UNION-A6-WIRED-AT-RECORDING-PATH \
            "the classifier is CALLED from $CN_COUNT non-test site(s): it classifies real recorded calls" ;;
    ABSENT)
        cn_fail UNION-A6-WIRED-AT-RECORDING-PATH \
            "the classifier has NO non-test caller — it is source-present but runtime-inactive (§11.4.108). The recording path does not consult it, so nothing it says binds anything. Wiring is owed by T315 (adopt the store), T323 (expose to the shell seams) and T333 (bind into the reader). $CN_DETAIL" ;;
    *)
        cn_blind UNION-A6-WIRED-AT-RECORDING-PATH "$CN_RESULT: $CN_DETAIL" ;;
esac

cn_summary "$GATE_ID"
exit $?
