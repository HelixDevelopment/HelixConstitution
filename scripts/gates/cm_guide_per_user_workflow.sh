#!/usr/bin/env bash
# cm_guide_per_user_workflow.sh — CM-GUIDE-PER-USER-WORKFLOW gate
# (§11.4.257(b) — every workflow/service/product ships a complete,
# operator-usable user guide).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Reads a consumer-owned guide manifest (DATA per §11.4.28/§11.4.35 — this
# project-agnostic constitution submodule carries zero project literals) and
# asserts, for every declared workflow, that its guide file genuinely
# exists, is non-empty, and is not explicitly marked incomplete. Honest
# boundary (§11.4.6): this gate mandates EXISTENCE, not semantic correctness
# — §11.4.257 states that boundary explicitly ("mandates existence + sync +
# reachability, not doc semantic-correctness").
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_guide_per_user_workflow.sh [--root <project-root>] [--manifest <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  guide manifest, relative to --root unless absolute
#                         (default: docs/guides/MANIFEST.tsv).
#
# ── Manifest format ──────────────────────────────────────────────────────────
#   TSV, `#`-comments + blank lines ignored. Data row:
#     <workflow_id><TAB><guide_path relative to --root>
#   Zero data rows (or the manifest file itself absent) = nothing declared in
#   scope yet -> PASSes vacuously (§11.4.257 honest boundary: a project owes
#   nothing for a capability it has not affirmatively declared).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-workflow OK/MISSING/EMPTY/INCOMPLETE line + final PASS/FAIL banner
#   naming every offending workflow_id + its resolved path.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_doc_manifest.sh (same directory). Parses
#   clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.257 (this gate's mandate), lib_doc_manifest.sh (shared engine),
#   §11.4.197 (INCOMPLETE marker = tracked gap, still FAILs this gate),
#   §1.1 (paired mutation test
#   cm_guide_per_user_workflow_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared workflow's guide is OK, or zero workflows declared.
#   1 — at least one declared workflow's guide is MISSING/EMPTY/INCOMPLETE.
#   2 — environment error (root not found, or lib_doc_manifest.sh missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-GUIDE-PER-USER-WORKFLOW"
ANCHOR="11.4.257"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/guides/MANIFEST.tsv"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,45p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

lib="${here}/lib_doc_manifest.sh"
[ -f "$lib" ] || { echo "${GATE}: BLIND — lib_doc_manifest.sh not found at $lib" >&2; exit 2; }
# shellcheck source=lib_doc_manifest.sh
. "$lib"

case "$manifest_rel" in
    /*) manifest="$manifest_rel" ;;
    *) manifest="${root}/${manifest_rel}" ;;
esac

total=0
fails=0
declare -a fail_lines=()

while IFS=$'\t' read -r workflow_id doc_relpath _rest; do
    [ -n "${workflow_id:-}" ] || continue
    total=$((total + 1))
    status="$(dm_check_target "$root" "$doc_relpath")"
    if [ "$status" = "OK" ]; then
        echo "${GATE}: OK workflow='${workflow_id}' guide='${doc_relpath}'"
    else
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL workflow='${workflow_id}' guide='${doc_relpath}' reason=${status}")
        echo "${fail_lines[-1]}"
    fi
done < <(dm_read_rows "$manifest")

echo "${GATE}: SUMMARY manifest=${manifest} declared=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} declared workflow(s) missing a complete user guide (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — ${total} declared workflow(s) all have a complete user guide (§${ANCHOR})"
exit 0
