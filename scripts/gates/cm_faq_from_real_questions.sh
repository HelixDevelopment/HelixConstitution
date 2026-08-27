#!/usr/bin/env bash
# cm_faq_from_real_questions.sh — CM-FAQ-FROM-REAL-QUESTIONS gate
# (§11.4.257(c) — every component's FAQ is properly created FROM real
# operator/QA/end-user questions, never invented).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Reads a consumer-owned FAQ manifest (DATA per §11.4.28/§11.4.35 — this
# project-agnostic constitution submodule carries zero project literals) and
# asserts, for every declared component's FAQ: (a) the FAQ document itself
# genuinely exists/is non-empty/is not marked incomplete (via the shared
# lib_doc_manifest.sh target check — same MISSING/EMPTY/INCOMPLETE/OK
# vocabulary as the manual + guide gates); (b) the FAQ contains at least one
# `Source: <id>` citation (an FAQ that answers zero cited real questions is
# not "derived from real questions" — it is invented); (c) EVERY `Source:
# <id>` citation in the FAQ resolves to a real `[<id>]`-bracketed entry in the
# component's declared real-question CORPUS file — a citation that does not
# resolve is a FABRICATED source and FAILs; (d) the corpus file itself
# genuinely exists and is non-empty (an FAQ cannot be "from real questions"
# if there is no real-question record to derive it from).
#
# Honest boundary (§11.4.6): this gate proves EVERY answered question traces
# to a real captured question and that at least one real question was
# actually answered — it does NOT judge whether the ANSWER text is correct
# (semantic correctness stays §11.4.257's stated boundary + §11.4.99/§11.4.194
# review territory).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_faq_from_real_questions.sh [--root <project-root>] [--manifest <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  FAQ manifest, relative to --root unless absolute
#                         (default: docs/faq/MANIFEST.tsv).
#
# ── Manifest format ──────────────────────────────────────────────────────────
#   TSV, `#`-comments + blank lines ignored. Data row:
#     <component_id><TAB><faq_path relative to --root><TAB><corpus_path relative to --root>
#   Zero data rows (or the manifest file itself absent) = nothing declared in
#   scope yet -> PASSes vacuously (§11.4.257 honest boundary).
#
# ── FAQ document format ─────────────────────────────────────────────────────
#   Free-form Markdown; each answered question cites the real question it
#   answers with a line of the exact shape (leading whitespace ignored):
#     Source: <id>
#   where <id> is any non-whitespace token. Multiple `Source:` lines are
#   permitted (one FAQ entry may synthesize several real questions).
#
# ── Corpus document format ──────────────────────────────────────────────────
#   Free-form text/Markdown; each real captured question is recorded as a
#   line containing a bracketed id token `[<id>]` (leading text before the
#   bracket, e.g. a Markdown heading marker, is ignored) — e.g.:
#     [q1] How do I reset my password?
#   Every `<id>` a FAQ's `Source:` line cites MUST appear as some `[<id>]` in
#   the corpus (exact, case-sensitive token match).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-component OK/FAIL line + final PASS/FAIL banner naming every
#   offending component_id + reason.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_doc_manifest.sh (same directory). Parses
#   clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.257 (this gate's mandate — the FAQ trio-member), lib_doc_manifest.sh
#   (shared target-existence engine), §11.4.6 (no-guessing — an unresolved
#   citation is a fabrication, never assumed real), §11.4.197 (INCOMPLETE
#   marker = tracked gap, still FAILs this gate), §1.1 (paired mutation test
#   cm_faq_from_real_questions_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared component's FAQ is OK + fully sourced, or zero
#       components declared.
#   1 — at least one declared component's FAQ is MISSING/EMPTY/INCOMPLETE, has
#       zero Source: citations, cites an unresolved id, or its corpus is
#       missing/empty.
#   2 — environment error (root not found, or lib_doc_manifest.sh missing).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-FAQ-FROM-REAL-QUESTIONS"
ANCHOR="11.4.257"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/faq/MANIFEST.tsv"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,75p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

while IFS=$'\t' read -r component_id faq_relpath corpus_relpath; do
    [ -n "${component_id:-}" ] || continue
    total=$((total + 1))

    faq_status="$(dm_check_target "$root" "$faq_relpath")"
    if [ "$faq_status" != "OK" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL component='${component_id}' faq='${faq_relpath}' reason=${faq_status}")
        echo "${fail_lines[-1]}"
        continue
    fi

    faq_abs="${root}/${faq_relpath}"
    corpus_status="$(dm_check_target "$root" "$corpus_relpath")"
    if [ "$corpus_status" != "OK" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL component='${component_id}' faq='${faq_relpath}' reason=CORPUS_${corpus_status}")
        echo "${fail_lines[-1]}"
        continue
    fi
    corpus_abs="${root}/${corpus_relpath}"

    # Extract every cited Source: id from the FAQ (order-preserving, dup-safe).
    cited_ids="$(grep -oE 'Source:[[:space:]]*[^[:space:]]+' "$faq_abs" 2>/dev/null \
                 | sed -E 's/^Source:[[:space:]]*//' || true)"

    if [ -z "${cited_ids//[$' \t\r\n']/}" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL component='${component_id}' faq='${faq_relpath}' reason=NO_SOURCE_CITATIONS")
        echo "${fail_lines[-1]}"
        continue
    fi

    # Extract every real [id] present in the corpus.
    corpus_ids="$(grep -oE '\[[^][:space:]]+\]' "$corpus_abs" 2>/dev/null \
                  | sed -E 's/^\[//; s/\]$//' || true)"

    unresolved=""
    while IFS= read -r cid; do
        [ -n "$cid" ] || continue
        # FIND-AV-01 hardening: NO PIPELINE on a GROWING payload. `grep -q`
        # exits on first match and SIGPIPEs the `printf` writer (141); under
        # `set -o pipefail` that converts a SUCCESSFUL match into a failed
        # pipeline, so a RESOLVED id would be reported unresolved
        # (§11.4.201(1) false positive). $corpus_ids grows with the FAQ corpus
        # and crosses the ~60 KB pipe buffer as it does. This gate sets only
        # `set -u` today, so the defect is LATENT here, not live; the
        # pure-bash whole-line form is immune regardless of future shell opts.
        if ! case $'\n'"$corpus_ids"$'\n' in *$'\n'"$cid"$'\n'*) true ;; *) false ;; esac; then
            unresolved="${unresolved:+$unresolved,}${cid}"
        fi
    done <<< "$cited_ids"

    if [ -n "$unresolved" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL component='${component_id}' faq='${faq_relpath}' reason=UNRESOLVED_SOURCE:${unresolved}")
        echo "${fail_lines[-1]}"
        continue
    fi

    echo "${GATE}: OK component='${component_id}' faq='${faq_relpath}' corpus='${corpus_relpath}'"
done < <(dm_read_rows "$manifest")

echo "${GATE}: SUMMARY manifest=${manifest} declared=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} declared component FAQ(s) not properly derived from real questions (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — ${total} declared component FAQ(s) all properly derived from real questions (§${ANCHOR})"
exit 0
