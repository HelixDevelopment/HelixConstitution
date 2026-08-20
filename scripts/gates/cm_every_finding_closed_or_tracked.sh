#!/usr/bin/env bash
# cm_every_finding_closed_or_tracked.sh — CM-EVERY-FINDING-CLOSED-OR-TRACKED gate
# (§11.4.261(D) — every finding in the §11.4.261 zero-findings ledger MUST be
# either CLOSED (with mitigation_evidence) or TRACKED (with tracker_ref +
# mitigation_evidence) — a persisted `open` finding, or any finding with no
# disposition at all, is the silent-absorption bluff §11.4.261 forbids).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.261 mandates a monotone-decreasing findings ledger where every row is
# EITHER CLOSED (evidence at the defect layer, code repaired) OR TRACKED
# (§11.4.197 item + §11.4.148 description + §11.4.223 marker + §11.4.101
# mitigation + §11.4.135 regression guard where needed) — NEVER silently
# absorbed. This gate reads the ledger CM-ZERO-FINDINGS-AUDIT-SWEEP's sweep
# script emits and checks each row's disposition:
#   (1) the declared ledger file exists (a MISSING ledger when findings are
#       genuinely expected is a separate concern of the sweep gate — THIS
#       gate is a no-op PASS on a missing/empty ledger, per its honest
#       boundary below);
#   (2) every JSON row parses (has a `status` field);
#   (3) `status` is one of the CLOSED SET {tracked, closed} — `open`, any
#       other value, or a missing status is a FAIL naming the offending
#       finding_id;
#   (4) a `tracked` row has non-empty `tracker_ref` AND non-empty
#       `mitigation_evidence`;
#   (5) a `closed` row has non-empty `mitigation_evidence`.
#
# Honest boundary (§11.4.6): this gate checks the LEDGER'S OWN internal
# disposition discipline — it does NOT verify the cited tracker_ref actually
# exists in the tracker system, nor that mitigation_evidence's path is real
# (those are deeper, project-specific verifications a consuming project may
# layer on top). An empty or absent ledger is treated as the genuinely-clean
# "zero findings outstanding" state and PASSES vacuously — that is the
# TARGET state §11.4.261 aims for, not a bluff.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_every_finding_closed_or_tracked.sh [--root <project-root>]
#                                         [--ledger <path>]
#     --root <dir>     project root (default: $CONSUMER_ROOT or ".").
#     --ledger <path>  the JSONL findings ledger, relative to --root unless
#                       absolute (default: docs/findings/zero_findings_ledger.jsonl
#                       — the §11.4.261 Lava-style binding).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-finding OK/FAIL line + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None — read-only.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.261 (this gate's mandate — clause D closed-or-tracked discipline),
#   §11.4.197 (a tracked finding's obligation), §11.4.226 (evidence-at-the-
#   defect-layer for closed findings), §11.4.6 (no silent absorption), §1.1
#   (paired mutation test cm_every_finding_closed_or_tracked_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — ledger absent/empty (vacuous clean state) OR every row is tracked
#       (with tracker_ref+mitigation_evidence) or closed (with
#       mitigation_evidence).
#   1 — at least one row is `open`, has an unrecognised/missing status, or is
#       `tracked`/`closed` without its required fields.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-EVERY-FINDING-CLOSED-OR-TRACKED"
ANCHOR="11.4.261"

root="${CONSUMER_ROOT:-.}"
ledger_rel="docs/findings/zero_findings_ledger.jsonl"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --ledger) ledger_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,50p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$ledger_rel" in
    /*) ledger="$ledger_rel" ;;
    *) ledger="${root}/${ledger_rel}" ;;
esac

json_field() {
    local line="$1" field="$2"
    echo "$line" | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/^\"${field}\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"
}

if [ ! -f "$ledger" ]; then
    echo "${GATE}: OK ledger='${ledger}' absent — vacuous clean state (zero findings outstanding, §11.4.261 honest boundary)"
    echo "${GATE}: PASS — no findings to disposition (§${ANCHOR})"
    exit 0
fi

fail=0
checked=0
line_no=0

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    # blank/comment-only lines in the JSONL are tolerated (never a finding)
    trimmed="$(echo "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$trimmed" ] && continue
    case "$trimmed" in \#*) continue ;; esac

    checked=$((checked + 1))
    fid="$(json_field "$trimmed" finding_id)"
    [ -z "$fid" ] && fid="line-${line_no}"
    status="$(json_field "$trimmed" status)"
    tracker_ref="$(json_field "$trimmed" tracker_ref)"
    mitigation_evidence="$(json_field "$trimmed" mitigation_evidence)"

    case "$status" in
        tracked)
            if [ -z "$tracker_ref" ] || [ -z "$mitigation_evidence" ]; then
                echo "${GATE}: FAIL finding='${fid}' reason=TRACKED_MISSING_FIELDS (tracker_ref='${tracker_ref}' mitigation_evidence='${mitigation_evidence}')"
                fail=$((fail + 1))
            else
                echo "${GATE}: OK finding='${fid}' status=tracked tracker_ref='${tracker_ref}'"
            fi
            ;;
        closed)
            if [ -z "$mitigation_evidence" ]; then
                echo "${GATE}: FAIL finding='${fid}' reason=CLOSED_MISSING_MITIGATION_EVIDENCE"
                fail=$((fail + 1))
            else
                echo "${GATE}: OK finding='${fid}' status=closed mitigation_evidence='${mitigation_evidence}'"
            fi
            ;;
        open)
            echo "${GATE}: FAIL finding='${fid}' reason=FINDING_STILL_OPEN (§11.4.261 forbids a persisted open finding — must be tracked or closed)"
            fail=$((fail + 1))
            ;;
        *)
            echo "${GATE}: FAIL finding='${fid}' reason=UNRECOGNISED_OR_MISSING_STATUS (status='${status}')"
            fail=$((fail + 1))
            ;;
    esac
done < "$ledger"

echo "${GATE}: SUMMARY ledger=${ledger} checked=${checked} fail=${fail}"

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} finding(s) not properly dispositioned (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — every finding in the ledger is tracked (with tracker_ref+mitigation_evidence) or closed (with mitigation_evidence) (§${ANCHOR})"
exit 0
