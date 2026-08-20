#!/usr/bin/env bash
# cm_readme_badge_row_at_top.sh — CM-README-BADGE-ROW-AT-TOP gate
# (§11.4.259 — README carries a badge row at the TOP, immediately below the
# H1 title and above the introduction — the reader's first visual signal).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts that the project's README.md contains a badge row positioned per
# the §11.4.259 placement contract: the FIRST non-blank line strictly after
# the document's H1 heading consists entirely of one or more Markdown image
# links (badges), with nothing else on that line — never buried mid-document,
# never after the introduction. Uses the shared lib_badge_row.sh parser (same
# engine consumed by the sibling gates CM-BADGE-CLOSED-COLOR-VOCABULARY /
# CM-BADGE-MACHINE-DERIVED-SOURCE / CM-BADGE-SELF-VALIDATED).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_readme_badge_row_at_top.sh [--root <project-root>] [--readme <path>] [--min-badges <N>]
#     --root <dir>        project root (default: $CONSUMER_ROOT or ".").
#     --readme <path>     README entry point, relative to --root unless
#                          absolute (default: README.md).
#     --min-badges <N>    minimum badge count the row must carry (default: 1
#                          — the mechanical floor this project-agnostic gate
#                          can enforce; §11.4.259's own "comprehensive class
#                          floor" enumeration is consumer-owned DATA per
#                          §11.4.35, so a consumer tunes this to its own
#                          declared minimum).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   PASS/FAIL banner naming the badge count found + the reason on FAIL.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_badge_row.sh (same directory). Parses clean
#   under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.259 (this gate's mandate), lib_badge_row.sh (shared badge-row
#   parsing engine), §11.4.6 (no-guessing — strict positional contract, never
#   a document-wide search for a badge-shaped line), §1.1 (paired mutation
#   test cm_readme_badge_row_at_top_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — a badge row is present at the top with >= --min-badges entries.
#   1 — README has no H1, or the first non-blank line after the H1 is not a
#       pure badge row, or the badge row has fewer than --min-badges entries.
#   2 — environment error (root not found, README not found, lib missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-README-BADGE-ROW-AT-TOP"
ANCHOR="11.4.259"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
readme_rel="README.md"
min_badges=1
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --readme) readme_rel="$2"; shift 2 ;;
        --min-badges) min_badges="$2"; shift 2 ;;
        -h|--help) sed -n '1,45p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

lib="${here}/lib_badge_row.sh"
[ -f "$lib" ] || { echo "${GATE}: BLIND — lib_badge_row.sh not found at $lib" >&2; exit 2; }
# shellcheck source=lib_badge_row.sh
. "$lib"

case "$readme_rel" in
    /*) readme="$readme_rel" ;;
    *) readme="${root}/${readme_rel}" ;;
esac
[ -f "$readme" ] || { echo "${GATE}: BLIND — README not found: $readme" >&2; exit 2; }

row="$(br_badge_row_text "$readme")"
rc=$?
if [ "$rc" -ne 0 ] || [ -z "$row" ]; then
    echo "${GATE}: FAIL — no badge row found at the top of ${readme} (first non-blank line after the H1 must be a pure badge row) (§${ANCHOR})" >&2
    exit 1
fi

count="$(br_extract_entries "$row" | grep -c . || true)"

echo "${GATE}: badge row found with ${count} badge(s)"
if [ "$count" -lt "$min_badges" ]; then
    echo "${GATE}: FAIL — badge row has ${count} badge(s), fewer than required minimum ${min_badges} (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — README badge row present at the top with ${count} badge(s) (>= ${min_badges} required) (§${ANCHOR})"
exit 0
