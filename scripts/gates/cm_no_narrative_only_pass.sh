#!/usr/bin/env bash
# cm_no_narrative_only_pass.sh — CM-NO-NARRATIVE-ONLY-PASS gate
# (§11.4.262(C) — a claimed PASS/success MUST cite a machine-created
# evidence artefact; a free-text report claiming "PASS" with no nearby
# `evidence:` citation is the narrative-only-PASS bluff §11.4.262 forbids).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.262 strengthens the §11.4 covenant preamble from CAPTURED to
# CAPTURED-AND-MACHINE-VERIFIABLE evidence: operator eyeballing / narrative-
# only PASS / "looks fine" / "no error" claims are FORBIDDEN. This gate
# audits a declared manifest of report/verdict files:
#   (1) a report whose file EXTENSION is .json or .jsonl is AUTO-OK -- it is
#       already machine-structured, and this gate's presence-only contract
#       does not re-parse/re-validate its schema (that is a deeper,
#       consumer-specific concern);
#   (2) a report whose declared path does not exist at all is a FAIL (a
#       manifest entry naming a report that was never produced);
#   (3) for every other (free-text: .md/.txt/.log/etc.) declared report, the
#       gate scans line-by-line for a standalone word-boundary "PASS" token
#       (never a substring match -- "PASSWORD" must NOT false-match) and
#       requires a nearby (same line, or within the following
#       EVIDENCE_PROXIMITY_LINES lines) case-insensitive "evidence:"
#       citation; a PASS claim with no nearby evidence citation is a FAIL
#       naming the file + line number.
#
# Honest boundary (§11.4.6): this gate proves PRESENCE of an evidence:
# citation near a narrative PASS claim, via static text scan -- it does NOT
# verify the cited evidence path is real, non-empty, or genuinely supports
# the claim (that is CM-EVIDENCE-ANALYZER-SELF-VALIDATED's and the
# consuming project's deeper job). A declared manifest with zero entries, or
# a report containing zero standalone PASS-claims, is a legitimate vacuous
# PASS -- this gate targets narrative bluffing, not the mere ABSENCE of the
# word "PASS".
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_no_narrative_only_pass.sh [--root <project-root>] [--manifest <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  a TSV manifest of `<report_id>\t<report_path>` rows
#                         (report_path relative to --root unless absolute;
#                         `#`-comments and blank lines tolerated), relative
#                         to --root unless absolute (default:
#                         docs/evidence/narrative_reports_manifest.tsv).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-report OK/FAIL line(s) + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None — read-only.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed, awk. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.262 (this gate's mandate — narrative-PASS ban), §11.4 (covenant
#   preamble strengthened to captured-and-machine-verifiable), §11.4.6
#   (no-guessing — a proxy word-scan is not truth-verification, only a
#   presence-of-citation check), §1.1 (paired mutation test
#   cm_no_narrative_only_pass_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared report is JSON/JSONL (auto-OK), or every narrative
#       PASS claim it contains cites a nearby evidence: reference.
#   1 — a declared report is missing, OR contains a narrative PASS claim
#       with no nearby evidence: citation.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-NO-NARRATIVE-ONLY-PASS"
ANCHOR="11.4.262"
EVIDENCE_PROXIMITY_LINES=2

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/evidence/narrative_reports_manifest.tsv"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,55p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$manifest_rel" in
    /*) manifest="$manifest_rel" ;;
    *) manifest="${root}/${manifest_rel}" ;;
esac

if [ ! -f "$manifest" ]; then
    echo "${GATE}: OK manifest='${manifest}' absent — no declared reports (vacuous PASS)"
    echo "${GATE}: PASS — no reports declared (§${ANCHOR})"
    exit 0
fi

fail=0
declared=0

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    trimmed="$(echo "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$trimmed" ] && continue
    case "$trimmed" in \#*) continue ;; esac

    report_id="$(echo "$trimmed" | awk -F'\t' '{print $1}')"
    report_path_rel="$(echo "$trimmed" | awk -F'\t' '{print $2}')"
    [ -z "$report_path_rel" ] && continue
    declared=$((declared + 1))

    case "$report_path_rel" in
        /*) report_path="$report_path_rel" ;;
        *) report_path="${root}/${report_path_rel}" ;;
    esac

    if [ ! -f "$report_path" ]; then
        echo "${GATE}: FAIL report='${report_id}' path='${report_path}' reason=DECLARED_REPORT_MISSING"
        fail=$((fail + 1))
        continue
    fi

    case "$report_path" in
        *.json|*.jsonl)
            echo "${GATE}: OK report='${report_id}' path='${report_path}' auto-OK (machine-structured JSON/JSONL)"
            continue
            ;;
    esac

    # free-text report: scan for standalone word-boundary "PASS" claims
    # lacking a nearby evidence: citation.
    total_lines="$(wc -l < "$report_path" | tr -d '[:space:]')"
    report_fail=0
    line_no=0
    while IFS= read -r content_line || [ -n "$content_line" ]; do
        line_no=$((line_no + 1))
        if echo "$content_line" | grep -qE '\bPASS\b'; then
            # look at this line + the following EVIDENCE_PROXIMITY_LINES lines
            window_start="$line_no"
            window_end=$((line_no + EVIDENCE_PROXIMITY_LINES))
            window_text="$(sed -n "${window_start},${window_end}p" "$report_path")"
            if echo "$window_text" | grep -qiE 'evidence:[[:space:]]*[^[:space:]]'; then
                echo "${GATE}: OK report='${report_id}' line=${line_no} PASS-claim cites nearby evidence:"
            else
                echo "${GATE}: FAIL report='${report_id}' path='${report_path}' line=${line_no} reason=NARRATIVE_PASS_NO_EVIDENCE"
                fail=$((fail + 1))
                report_fail=$((report_fail + 1))
            fi
        fi
    done < "$report_path"

    if [ "$report_fail" -eq 0 ]; then
        echo "${GATE}: OK report='${report_id}' path='${report_path}' (${total_lines} lines scanned, no bluff citations missing)"
    fi
done < "$manifest"

echo "${GATE}: SUMMARY manifest=${manifest} declared=${declared} fail=${fail}"

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} narrative-only PASS claim(s) or missing report(s) (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — every declared report is machine-structured or cites evidence for every PASS claim (§${ANCHOR})"
exit 0
