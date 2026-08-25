#!/bin/sh
# cm_escape_ratchet_selftest.sh — OUTSIDE self-check for cm_escape_ratchet.sh
# (feature 002-anti-slop-enforcement, task T405c; FR-043, FR-044; quickstart S22)
#
# ── Why this file exists, when the gate already has --selftest ───────────────
# `cm_escape_ratchet.sh --selftest` calls the gate's INTERNAL `run_gate()`
# function. It therefore never crosses the gate's own CLI layer — argument
# parsing, default-path resolution, and the final `run_gate …; rc=$?; exit
# "$rc"` dispatch. That is a §11.4.249 gate=verifier collapse: the oracle lives
# inside the artifact it grades.
#
# MEASURED, not asserted (2026-08-22, scratch copy, never the tracked file):
# mutating ONLY the dispatch line `exit "$rc"` -> `exit 0` leaves the gate
# unable to refuse anything, while its own `--selftest` still reports
# `pass=13 fail=0`. Same fixture through the REAL CLI path: rc=0 while the
# body printed `RATCHET FAIL escape count 2 EXCEEDS baseline 1`. A seam doing
# `if ! gate; then refuse; fi` would ALLOW that release.
#
# This check therefore drives the gate ONLY through `sh <gate> …` — the real
# invocation path a seam uses (§11.4.201(11): probe the ARTIFACT, not a
# prerequisite; §11.4.224(A): a shell script's test executes it, never a
# `sh -n` parse-check alone).
#
# It is COLOCATED in the constitution submodule deliberately. The project-layer
# paired §1.1 mutation (T405d, in the consumer's meta-test) also crosses the
# CLI path, but it does NOT travel with this submodule; a project inheriting
# `constitution/` by reference (§11.4.177) would otherwise receive the gate
# with only its blind in-file selftest.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   cm_escape_ratchet_selftest.sh [--gate <path>] [--verbose]
#     --gate <path>  gate under test (default: cm_escape_ratchet.sh beside this
#                    file). The override exists so the SAME check can be aimed
#                    at a disposable MUTATED copy to prove it is RED-capable
#                    (§11.4.115(F) polarity; §11.4.224(C) forbids counting an
#                    assertion-free test). It is never pointed at a tracked
#                    file it would modify — this check is read-only on the gate.
#     --verbose      echo each case's captured gate output.
#
# ── What it asserts (BOTH halves, every case) ───────────────────────────────
# Exit code AND verdict reason. Exit codes alone are a low-resolution oracle:
# the measured dispatch mutation above kept the REASON correct while the CODE
# lied, and the inverse (right code, fabricated reason) is equally possible.
#
#   golden-good        a clean cycle within baseline               ALLOW  rc=0
#   golden-bad         an escape-count INCREASE                    REFUSE rc=1
#                      and the refusal NAMES the offending defect rows
#   negative-control   `manual_qa_ran:false` is NO DATA POINT      ALLOW  rc=0
#                      and MUST NOT lower the baseline under --ratchet.
#                      Refusing here would be a false-positive refusal — a
#                      FAIL-bluff of equal severity to a false pass
#                      (§11.4.201(1)).
#   operator-pending   an UNSET baseline SKIPs honestly            ALLOW  rc=0
#                      (never a silent pass, never an invented metric)
#
# ── Control needle (§11.4.201(7)(b)) ────────────────────────────────────────
# An all-green run is only evidence if the harness can observe a refusal at
# all. The golden-bad case is the needle: if ZERO refusals were observed
# across the run, this check reports BLIND (rc=2) rather than success.
#
# ── Side-effects ────────────────────────────────────────────────────────────
# Writes only inside a `mktemp -d` removed on exit. It never reads or writes
# the production ledger or the production baseline, and asserts both are
# byte-identical (sha256) before and after (§11.4.84).
#
# ── Exit codes ──────────────────────────────────────────────────────────────
#   0 every case held   1 a case failed   2 BLIND / usage / unreadable gate
#
# Classification: universal MECHANISM (§11.4.17) — no project literal; the
# gate path is an argument with a colocated default (§11.4.35).

set -u

PROG=$(basename "$0")
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
GATE="$SELF_DIR/cm_escape_ratchet.sh"
VERBOSE=0

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case $1 in
        --gate)    shift; [ $# -gt 0 ] || die "--gate needs a value"; GATE=$1 ;;
        --verbose) VERBOSE=1 ;;
        -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
    shift
done

[ -r "$GATE" ] || die "gate not readable: $GATE"

PASS=0
FAIL=0
REFUSALS_SEEN=0

D=$(mktemp -d) || die "mktemp failed"
# shellcheck disable=SC2064
trap "rm -rf '$D'" EXIT INT TERM

# ---------------------------------------------------------------------------
# expect <name> <want_rc> <want_reason_regex> <ledger> <baseline> [gate args…]
# rc is captured DIRECTLY from the gate, never through a pipeline — a
# `gate | tail` reports the PAGER's status, not the gate's (§11.4.201(12)).
# ---------------------------------------------------------------------------
expect() {
    _name=$1; _want_rc=$2; _want_re=$3; _lg=$4; _bl=$5
    shift 5
    sh "$GATE" --ledger "$_lg" --baseline "$_bl" "$@" > "$D/out" 2>&1
    _got=$?
    [ "$_got" -ne 0 ] && REFUSALS_SEEN=$((REFUSALS_SEEN + 1))
    [ "$VERBOSE" -eq 1 ] && sed 's/^/      | /' "$D/out"

    if [ "$_got" -ne "$_want_rc" ]; then
        printf 'SELFCHECK\tFAIL\t%s — exit code: want rc=%s got rc=%s\n' "$_name" "$_want_rc" "$_got"
        sed 's/^/      | /' "$D/out"
        FAIL=$((FAIL + 1))
        return 1
    fi
    if ! grep -q "$_want_re" "$D/out"; then
        printf 'SELFCHECK\tFAIL\t%s — rc=%s was right but the REASON is wrong; expected to match: %s\n' "$_name" "$_got" "$_want_re"
        sed 's/^/      | /' "$D/out"
        FAIL=$((FAIL + 1))
        return 1
    fi
    printf 'SELFCHECK\tPASS\t%s (rc=%s, reason matched)\n' "$_name" "$_got"
    PASS=$((PASS + 1))
    return 0
}

note_pass() { printf 'SELFCHECK\tPASS\t%s\n' "$1"; PASS=$((PASS + 1)); }
note_fail() { printf 'SELFCHECK\tFAIL\t%s\n' "$1"; FAIL=$((FAIL + 1)); }

# ── production artefacts: recorded BEFORE, compared AFTER (§11.4.84) ────────
PROD_LEDGER="$SELF_DIR/../../../docs/requests/discovery_channel.jsonl"
PROD_BASELINE="$SELF_DIR/escape_ratchet_baseline.txt"
prod_sha() { [ -r "$1" ] && sha256sum "$1" | cut -d' ' -f1 || printf 'ABSENT'; }
SHA_LEDGER_BEFORE=$(prod_sha "$PROD_LEDGER")
SHA_BASELINE_BEFORE=$(prod_sha "$PROD_BASELINE")

# ── fixtures ────────────────────────────────────────────────────────────────
printf '3\n' > "$D/base3.txt"
printf '1\n' > "$D/base1.txt"
printf 'OPERATOR_DECISION_PENDING\n' > "$D/base_pending.txt"
printf '3\n' > "$D/base_nodata.txt"

# GOLDEN-GOOD — the healthy §11.4.238 shape: the automated seam did the
# discovering, the manual pass ran and found nothing new. Zero escapes.
cat > "$D/good.jsonl" <<'EOJ'
# comment lines are ignored by the reader
{"event":"defect","cycle":"c1","defect_id":"ATM-7","channel":"automated_seam","should_have_been_caught_by":"pre-build","authored_by":"verifier","produced_by":"producer","ts":"2026-08-22T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-good","authored_by":"verifier","ts":"2026-08-22T01:00:00Z"}
EOJ

# GOLDEN-BAD — two escapes against a baseline of 1. MUST refuse, and MUST name
# the offending rows: a refusal an operator cannot act on is not actionable.
cat > "$D/bad.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"pre-build","authored_by":"verifier","produced_by":"producer","ts":"2026-08-22T00:00:00Z"}
{"event":"defect","cycle":"c1","defect_id":"ATM-2","channel":"operator","should_have_been_caught_by":"release-tag","authored_by":"verifier","produced_by":"producer","ts":"2026-08-22T00:10:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-bad","authored_by":"verifier","ts":"2026-08-22T01:00:00Z"}
EOJ

# NEGATIVE CONTROL — nobody ran the manual pass. Zero escapes recorded, but
# that zero is an ABSENCE OF LOOKING, not a measurement (FR-044).
cat > "$D/nodata.jsonl" <<'EOJ'
{"event":"cycle","cycle":"c1","manual_qa_ran":false,"artifact_fingerprint":"fp-nodata","authored_by":"verifier","ts":"2026-08-22T01:00:00Z"}
EOJ

printf '— cm_escape_ratchet.sh OUTSIDE self-check (real CLI path) —\n'
printf 'gate under test: %s\n' "$GATE"

# ── 1. golden-good ──────────────────────────────────────────────────────────
expect "golden-good: a clean cycle within baseline ALLOWs" \
    0 'ESC-VERDICT.*RATCHET.*PASS' "$D/good.jsonl" "$D/base3.txt" --quiet

# the tally must count an automated_seam find as CAUGHT, never as an escape
sh "$GATE" --ledger "$D/good.jsonl" --baseline "$D/base3.txt" --quiet > "$D/g.out" 2>&1
if grep -q 'escapes=0.*caught_by_automated_seam=1' "$D/g.out"; then
    note_pass "golden-good tally: the automated_seam find is counted as CAUGHT (escapes=0 caught_by_automated_seam=1)"
else
    note_fail "golden-good tally: expected 'escapes=0 … caught_by_automated_seam=1', got: $(grep '^REPORT' "$D/g.out" || echo '<no REPORT line>')"
fi

# ── 2. golden-bad ───────────────────────────────────────────────────────────
expect "golden-bad: an escape-count INCREASE REFUSEs" \
    1 'ESC-VERDICT.*RATCHET.*FAIL.*EXCEEDS' "$D/bad.jsonl" "$D/base1.txt"

# …and the refusal must NAME the offending defect rows. The gate knows the
# defect_ids (they are in the ledger it just parsed); a refusal that prints
# some OTHER field where the id belongs sends the operator to the wrong row.
sh "$GATE" --ledger "$D/bad.jsonl" --baseline "$D/base1.txt" > "$D/b.out" 2>&1
_missing=""
for _id in ATM-1 ATM-2; do
    grep -q "$_id" "$D/b.out" || _missing="$_missing $_id"
done
if [ -z "$_missing" ]; then
    note_pass "golden-bad names the offending rows (ATM-1, ATM-2 both appear in the refusal)"
else
    note_fail "golden-bad does NOT name the offending row(s):$_missing — the refusal is not actionable. Emitted rows: $(grep -c '^  defect' "$D/b.out" 2>/dev/null || echo 0); first: $(grep -m1 '^  defect' "$D/b.out" 2>/dev/null || echo '<none>')"
fi

# ── 3. negative control (the §11.4.201(1) false-positive guard) ─────────────
expect "negative-control: manual_qa_ran=false is NO DATA POINT, not a refusal" \
    0 'ESC-VERDICT.*NODATA.*SKIP' "$D/nodata.jsonl" "$D/base_nodata.txt" --ratchet --quiet

_bv_after=$(grep -v '^[[:space:]]*#' "$D/base_nodata.txt" | grep -v '^[[:space:]]*$' | head -1 | tr -d ' \t')
if [ "$_bv_after" = "3" ]; then
    note_pass "negative-control: baseline UNCHANGED at 3 even under --ratchet (a cycle nobody inspected cannot ratchet)"
else
    note_fail "negative-control: baseline moved to '$_bv_after' on a no-data-point cycle — not looking became the cheapest way to a green ratchet (FR-044)"
fi

# ── 4. operator-gated baseline ──────────────────────────────────────────────
expect "operator-pending: an UNSET baseline SKIPs honestly, never invents a metric" \
    0 'operator_decision_pending' "$D/bad.jsonl" "$D/base_pending.txt" --quiet

# ── 5. no production pollution ──────────────────────────────────────────────
if [ "$(prod_sha "$PROD_LEDGER")" = "$SHA_LEDGER_BEFORE" ] \
   && [ "$(prod_sha "$PROD_BASELINE")" = "$SHA_BASELINE_BEFORE" ]; then
    note_pass "no pollution: the production ledger and baseline are byte-identical before/after"
else
    note_fail "POLLUTION: a production artefact changed during this check (§11.4.84)"
fi

# ── control needle ──────────────────────────────────────────────────────────
if [ "$REFUSALS_SEEN" -eq 0 ]; then
    printf 'SELFCHECK\tBLIND\tthis harness observed ZERO refusals across the whole run — it cannot distinguish a working gate from a gate that never refuses, so an all-green result here would be evidence of nothing (§11.4.201(7)(b))\n'
    printf 'SELFCHECK\tSUMMARY\tpass=%d fail=%d BLIND\n' "$PASS" "$FAIL"
    exit 2
fi

printf 'SELFCHECK\tSUMMARY\tpass=%d fail=%d refusals_observed=%d\n' "$PASS" "$FAIL" "$REFUSALS_SEEN"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
