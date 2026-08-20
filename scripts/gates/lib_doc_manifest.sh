#!/usr/bin/env bash
# lib_doc_manifest.sh — shared manifest-parsing + target-file-verification
# helpers for the §11.4.257 documentation-coverage gate family
# (cm_user_manual_per_component.sh, cm_guide_per_user_workflow.sh,
# cm_faq_from_real_questions.sh).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.257 mandates that EVERY component/service/product ships a user
# manual, EVERY user-facing workflow ships a task-oriented guide, and FAQs
# are derived from real captured questions. All three cooperating checks
# share one shape: a consumer-owned TSV MANIFEST (project-specific DATA per
# §11.4.28/§11.4.35 — never hardcoded by this project-agnostic constitution
# submodule) names the items in scope; for each item the gate verifies its
# target documentation file genuinely exists, is non-trivial, and is not
# explicitly marked incomplete.
#
# This library intentionally does NOT judge doc semantic-correctness
# (§11.4.257's own honest boundary: "mandates existence + sync +
# reachability, not doc semantic-correctness") — it verifies structural
# presence + an explicit incomplete-marker escape hatch (mirrors the
# §11.4.223 provenance-marker discipline: an item honestly tracked as
# `<!-- STATUS: INCOMPLETE -->` is a tracked gap per §11.4.197, not a silent
# lie — but it still FAILs THIS gate, because the anchor's floor is "every
# capability ships its trio," and an item still marked incomplete has not).
#
# ── Manifest format (TSV, tab-separated) ────────────────────────────────────
#   Lines starting with `#` and blank lines are ignored (comments/header).
#   Each data row: <item_id><TAB><doc_path relative to --root>[<TAB>...]
#   A manifest with ZERO data rows (header/comments only, or the file simply
#   absent-of-rows) is a legitimate "nothing in scope yet" declaration and
#   PASSes vacuously — §11.4.257's honest boundary: a project genuinely
#   without a given capability class owes it nothing (never a bluff-by-
#   absence, because the manifest itself is the consumer's affirmative
#   declaration of scope, not an inferred one).
#
# ── Functions ────────────────────────────────────────────────────────────────
#   dm_read_rows <manifest_path>
#       Emits each non-comment non-blank line verbatim (still tab-separated)
#       on stdout. Caller loops `while IFS=$'\t' read -r ...`.
#
#   dm_check_target <root> <doc_relpath>
#       Verifies <root>/<doc_relpath>:
#         - exists and is a regular file                  -> else "MISSING"
#         - is non-empty (size > 0)                        -> else "EMPTY"
#         - its first non-blank line is NOT the literal
#           incomplete marker `<!-- STATUS: INCOMPLETE -->` -> else "INCOMPLETE"
#       Prints one of MISSING / EMPTY / INCOMPLETE / OK on stdout (exactly
#       one token) and returns 0 always (the caller decides pass/fail from
#       the printed token — keeps this a pure query, no side-exit, so it
#       composes cleanly inside a loop that must keep tallying every row
#       rather than stopping at the first failure per §11.4.6's discipline
#       of "know exactly what is happening everywhere", never just the
#       first hit).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.257 (the mandate this library serves), §11.4.197 (tracked-gap
#   INCOMPLETE marker semantics), §11.4.223 (the provenance-marker pattern
#   this marker borrows), §11.4.6 (no-guessing — structural checks only,
#   never a semantic-quality judgement), §11.4.28/§11.4.35 (manifest is
#   consumer DATA, never a project literal in this submodule).
#
# Classification: universal (§11.4.17).

DM_INCOMPLETE_MARKER='<!-- STATUS: INCOMPLETE -->'

dm_read_rows() {
    local manifest="$1"
    [ -f "$manifest" ] || return 0
    # Strip comments/blank lines; preserve tabs.
    grep -v -E '^[[:space:]]*(#|$)' "$manifest" 2>/dev/null || true
}

dm_check_target() {
    local root="$1" relpath="$2"
    local full="${root%/}/${relpath}"
    if [ ! -f "$full" ]; then
        echo "MISSING"
        return 0
    fi
    if [ ! -s "$full" ]; then
        echo "EMPTY"
        return 0
    fi
    local first_nonblank
    first_nonblank="$(grep -m1 -v -E '^[[:space:]]*$' "$full" 2>/dev/null || true)"
    # Trim leading/trailing whitespace for a robust marker compare.
    first_nonblank="$(printf '%s' "$first_nonblank" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$first_nonblank" = "$DM_INCOMPLETE_MARKER" ]; then
        echo "INCOMPLETE"
        return 0
    fi
    echo "OK"
    return 0
}
