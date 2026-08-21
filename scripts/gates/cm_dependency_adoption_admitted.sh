#!/bin/sh
# =============================================================================
# cm_dependency_adoption_admitted.sh — CM-DEPENDENCY-ADOPTION-ADMITTED (T233).
#
# ── What this gate asserts (FR-014, FR-020, FR-021 adoption side) ───────────
#   DAA-A0  the E6 reader and the recorded gap table are present   (structural)
#   DAA-A1  the gap table carries EXACTLY the four recorded gaps   (structural)
#   DAA-A2  GOLDEN-BAD : an UNVERIFIED entry is refused with
#                        dependency_NOT_VERIFIED                     (RUNTIME)
#   DAA-A3  GOLDEN-BAD : an AMBIGUOUS entry is refused the same way  (RUNTIME)
#   DAA-A4  GOLDEN-BAD : a VERIFIED entry outside the gaps is
#                        refused with dependency_GAP_UNMAPPED **and
#                        the COVERING RULE named**                   (RUNTIME)
#   DAA-A5  GOLDEN-BAD : adoption is refused while the wiring sweep
#                        has produced no result, and the refusal
#                        NAMES the absent path (FR-021)              (RUNTIME)
#   DAA-A6  NEGATIVE CONTROL: a VERIFIED entry mapped to a recorded
#                        gap, with a sweep result present, IS
#                        ADMITTED                                    (RUNTIME)
#
# ── Why A4 insists the covering rule is NAMED ───────────────────────────────
# A bare rejection tells the proposer nothing and invites the restatement
# FR-018 refuses. Naming the covering rule converts "no" into "bind to this
# seam instead", which is the only form of refusal that moves the work forward.
#
# ── Why A5 treats a missing sweep result as a REFUSAL ───────────────────────
# A missing result is NOT "no findings". A broken instrument and a clean tree
# produce the identical quiet zero, and reading the absent one as clean is the
# false null this whole feature exists to close (§11.4.201(6)).
#
# ── Why A6 is not optional ──────────────────────────────────────────────────
# Without it, A2-A5 are satisfiable by a seam that refuses every adoption. That
# is not a stricter gate, it is a broken one, and it would make the D-1 gap
# decision unenforceable by accident rather than by design (§11.4.201(1)).
#
# Usage : cm_dependency_adoption_admitted.sh [--gaps <tsv>] [--sweep <path>]
# Output: CN-VERDICT / CN-SUMMARY. Exit 0 only when nothing FAILed or was BLIND.
# Deps  : POSIX sh, grep, mktemp. Read-only w.r.t. the repository.
# =============================================================================

set -u

GATE_ID=CM-DEPENDENCY-ADOPTION-ADMITTED
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
DR="$SELF_DIR/lib/dependency_register.sh"
GAPS="$SELF_DIR/uncovered_capability_gaps.tsv"
SWEEP="$SELF_DIR/wiring_sweep_result.tsv"

while [ $# -gt 0 ]; do
    case $1 in
        --gaps)  GAPS=$2;  shift 2 ;;
        --sweep) SWEEP=$2; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

cn_reset
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_daa.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

# --- A0 -----------------------------------------------------------------------
a0=0
[ -f "$DR" ]   || { cn_fail DAA-A0-SEAM-PRESENT "the E6 adoption reader is absent: $DR"; a0=1; }
[ -r "$GAPS" ] || { cn_fail DAA-A0-SEAM-PRESENT "the recorded gap table is absent: $GAPS"; a0=1; }
if [ "$a0" -eq 0 ]; then cn_pass DAA-A0-SEAM-PRESENT "reader $DR and gap table $GAPS are present"
else cn_summary "$GATE_ID"; exit $?; fi

# --- A1 exactly the four recorded gaps ----------------------------------------
# Needle first: prove the ^G<n><TAB> query class can see anything at all here.
cn_count '-E' '^G[0-9]+	' "$GAPS"
if [ "${CN_COUNT:-0}" -eq 0 ]; then
    cn_blind DAA-A1-FOUR-RECORDED-GAPS "the gap-row query returned 0 rows in $GAPS through the same grep and flags — the instrument cannot see, so any count it reports says NOTHING (§11.4.201(7)(b))"
else
    total=$CN_COUNT
    missing=''
    for g in G1 G2 G3 G4; do
        cn_count '-E' "^${g}	" "$GAPS"
        [ "${CN_COUNT:-0}" -eq 1 ] || missing="$missing $g(${CN_COUNT:-0})"
    done
    if [ -z "$missing" ] && [ "$total" -eq 4 ]; then
        cn_pass DAA-A1-FOUR-RECORDED-GAPS "the gap table carries exactly the four recorded gaps G1..G4 (A-007)"
    else
        cn_fail DAA-A1-FOUR-RECORDED-GAPS "the gap table does not carry exactly G1..G4 once each (total rows=$total, anomalies:${missing:- none}) — a longer table would claim uncovered ground nobody measured, a shorter one would refuse admissible work"
    fi
fi

# --- fixtures ------------------------------------------------------------------
REG="$TMP/register.jsonl"
{
  printf '%s\n' '{"name":"fx-verified-mapped","verdict":"VERIFIED","artifact_url":"https://example.invalid/ok","gap_mapping":"G1","capability_status":"SHIPPED","covered_by":""}'
  printf '%s\n' '{"name":"fx-unverified","verdict":"UNVERIFIED","artifact_url":"not found on this search path (npm, PyPI, crates.io)","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}'
  printf '%s\n' '{"name":"fx-ambiguous","verdict":"AMBIGUOUS","artifact_url":"https://example.invalid/collision","gap_mapping":"G3","capability_status":"CLAIMED","covered_by":""}'
  printf '%s\n' '{"name":"fx-covered","verdict":"VERIFIED","artifact_url":"https://example.invalid/covered","gap_mapping":"G9-not-a-gap","capability_status":"SHIPPED","covered_by":"CM-COVENANT-114-109-PROPAGATION"}'
} > "$REG"
OKSWEEP="$TMP/sweep_ok.txt"
if [ -s "$SWEEP" ]; then cp "$SWEEP" "$OKSWEEP"; else printf 'wiring sweep result for the current tree state: 0 unreferenced gates\n' > "$OKSWEEP"; fi
NOSWEEP="$TMP/no_such_sweep_result.txt"

run_adopt() { sh "$DR" adopt "$REG" "$1" "$GAPS" "$2" 2>&1; }

# --- A2 / A3 non-VERIFIED verdicts --------------------------------------------
for pair in 'fx-unverified:DAA-A2-UNVERIFIED-REFUSED:UNVERIFIED' 'fx-ambiguous:DAA-A3-AMBIGUOUS-REFUSED:AMBIGUOUS'; do
    nm=${pair%%:*}; rest=${pair#*:}; id=${rest%%:*}; want=${rest#*:}
    out=$(run_adopt "$nm" "$OKSWEEP"); rc=$?
    reason=$(printf '%s\n' "$out" | grep -Ec 'dependency_NOT_VERIFIED' || true)
    shown=$(printf '%s\n' "$out" | grep -Ec "$want" || true)
    if [ "$rc" -ne 0 ] && [ "${reason:-0}" -gt 0 ] && [ "${shown:-0}" -gt 0 ]; then
        cn_pass "$id" "a $want entry is refused with dependency_NOT_VERIFIED and the resolved verdict is printed"
    else
        cn_fail "$id" "a $want entry was not properly refused (rc=$rc reason=$reason verdict-shown=$shown): $out"
    fi
done

# --- A4 already-covered capability, covering rule NAMED -----------------------
out=$(run_adopt fx-covered "$OKSWEEP"); rc=$?
reason=$(printf '%s\n' "$out" | grep -Ec 'dependency_GAP_UNMAPPED' || true)
cover=$(printf '%s\n' "$out" | grep -Ec 'CM-COVENANT-114-109-PROPAGATION' || true)
if [ "$rc" -ne 0 ] && [ "${reason:-0}" -gt 0 ] && [ "${cover:-0}" -gt 0 ]; then
    cn_pass DAA-A4-GAP-UNMAPPED-NAMES-RULE "an already-covered capability is refused with dependency_GAP_UNMAPPED AND the covering rule is named"
elif [ "$rc" -ne 0 ] && [ "${reason:-0}" -gt 0 ]; then
    cn_fail DAA-A4-GAP-UNMAPPED-NAMES-RULE "refused, but WITHOUT naming the covering rule — a bare rejection invites the restatement FR-018 refuses: $out"
else
    cn_fail DAA-A4-GAP-UNMAPPED-NAMES-RULE "an already-covered capability was admitted (rc=$rc): $out"
fi

# --- A5 FR-021: no sweep result ------------------------------------------------
out=$(run_adopt fx-verified-mapped "$NOSWEEP"); rc=$?
named=$(printf '%s\n' "$out" | grep -Ec 'no_such_sweep_result\.txt' || true)
phrase=$(printf '%s\n' "$out" | grep -Ec 'no findings' || true)
if [ "$rc" -ne 0 ] && [ "${named:-0}" -gt 0 ] && [ "${phrase:-0}" -gt 0 ]; then
    cn_pass DAA-A5-SWEEP-PRECONDITION "adoption is refused with no sweep result, the absent path is NAMED, and the refusal says a missing result is not 'no findings'"
elif [ "$rc" -ne 0 ]; then
    cn_fail DAA-A5-SWEEP-PRECONDITION "refused, but the refusal is bare (path-named=$named phrase=$phrase): $out"
else
    cn_fail DAA-A5-SWEEP-PRECONDITION "adoption proceeded with NO sweep result — a missing result was read as 'no findings', the exact false null this feature exists to close"
fi

# --- A6 NEGATIVE CONTROL --------------------------------------------------------
out=$(run_adopt fx-verified-mapped "$OKSWEEP"); rc=$?
if [ "$rc" -eq 0 ]; then
    cn_pass DAA-A6-MAPPED-ADMITTED "a VERIFIED dependency mapped to a recorded gap, with a sweep result present, IS admitted: $out"
else
    cn_fail DAA-A6-MAPPED-ADMITTED "an admissible dependency was refused (rc=$rc): $out — the gap map has degenerated into 'adopt nothing, ever' by accident rather than by the D-1 decision"
fi

cn_summary "$GATE_ID"
exit $?
