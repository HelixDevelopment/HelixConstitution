#!/usr/bin/env bash
# cm_diagram_embedded_not_orphan.sh — CM-DIAGRAM-EMBEDDED-NOT-ORPHAN gate
# (§11.4.258 — every diagram is INCORPORATED at its point of use into the
# existing doc surface, reachable from README, never an orphan gallery).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Reads a consumer-owned diagram manifest (DATA per §11.4.28/§11.4.35 — this
# project-agnostic constitution submodule carries zero project literals) and
# asserts, for every declared diagram: (a) the diagram file itself genuinely
# exists/is non-empty/is not marked incomplete (via the shared
# lib_doc_manifest.sh target check); (b) the diagram is EMBEDDED — i.e. it is
# referenced by a markdown link/image target from at least one Markdown
# document that is itself reachable (directly or transitively) from the
# project's README.md, mirroring the §11.4.212 README-reachability discipline
# applied to diagrams specifically. A diagram file that exists but that no
# README-reachable document ever links to is an ORPHAN (sitting in a gallery
# directory nobody's real documentation path visits) and FAILs this gate.
#
# Honest boundary (§11.4.6): this gate proves REACHABILITY (the diagram is
# genuinely wired into the navigable doc graph), NOT diagram ACCURACY or
# render-correctness — §11.4.258's own text states the diagram-accuracy
# oracle is a distinct, harder problem; this gate covers only the decidable
# "embedded not orphan" sub-clause. It also only recognises FILE-based
# diagrams declared in the manifest — a diagram embedded purely as an inline
# fenced code block inside a page (with no separate file) is out of this
# gate's manifest-driven scope.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_diagram_embedded_not_orphan.sh [--root <project-root>] [--manifest <path>] [--readme <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  diagram manifest, relative to --root unless absolute
#                         (default: docs/diagrams/MANIFEST.tsv).
#     --readme <path>    README entry point, relative to --root unless
#                         absolute (default: README.md).
#
# ── Manifest format ──────────────────────────────────────────────────────────
#   TSV, `#`-comments + blank lines ignored. Data row:
#     <diagram_id><TAB><diagram_path relative to --root>
#   Zero data rows (or the manifest file itself absent) = nothing declared in
#   scope yet -> PASSes vacuously (§11.4.258 honest boundary — mirrors
#   §11.4.257's "a project owes nothing for an undeclared capability").
#
# ── Reachability algorithm ───────────────────────────────────────────────────
#   Breadth-first traversal starting at --readme. For each visited Markdown
#   file, extract every local (non-http/https/mailto, non-bare-anchor)
#   markdown link/image target `](<target>)`, resolve it relative to the
#   referring file's directory, and enqueue it if not already visited.
#   Bounded to 500 visited files (loop-safety) — well beyond any realistic
#   project doc tree; hitting the bound is reported as a BLIND environment
#   condition (exit 2), never silently truncated into a false FAIL.
#
#   A diagram is "embedded" iff its declared path (matched by basename,
#   inside `](...)` link/image syntax to avoid false-positives from prose
#   merely mentioning the filename) appears in at least one visited file's
#   content.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-diagram OK/FAIL line + final PASS/FAIL banner naming every offending
#   diagram_id + reason.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep, sed. Sources lib_doc_manifest.sh (same directory). Parses
#   clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.258 (this gate's mandate), §11.4.212 (the README-reachability
#   discipline this generalises to diagrams), lib_doc_manifest.sh (shared
#   target-existence engine), §11.4.6 (no-guessing — basename+link-syntax
#   match, never a substring-anywhere false-positive), §1.1 (paired mutation
#   test cm_diagram_embedded_not_orphan_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared diagram exists + is embedded in the README-reachable
#       doc graph, or zero diagrams declared.
#   1 — at least one declared diagram is MISSING/EMPTY/INCOMPLETE or is an
#       orphan (not referenced by any README-reachable document).
#   2 — environment error (root not found, lib_doc_manifest.sh missing,
#       README entry point absent, or the reachability bound was hit).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-DIAGRAM-EMBEDDED-NOT-ORPHAN"
ANCHOR="11.4.258"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MAX_VISITED=500

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/diagrams/MANIFEST.tsv"
readme_rel="README.md"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        --readme) readme_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,80p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
case "$readme_rel" in
    /*) readme="$readme_rel" ;;
    *) readme="${root}/${readme_rel}" ;;
esac

[ -f "$readme" ] || { echo "${GATE}: BLIND — README entry point not found: $readme" >&2; exit 2; }

# ---- BFS the README-reachable doc graph, collecting every visited file's
#      relative path (one per line) into $visited_list. ----
visited_list=""
queue_list="${readme#"$root"/}"
visited_count=0
bound_hit=""

while [ -n "$queue_list" ]; do
    # FIND-AV-01 hardening: NO PIPELINE on a GROWING payload. `head -n1` and
    # `grep -q` both exit on their first line/match, SIGPIPE the `printf`
    # writer (141), and under `set -o pipefail` that turns a SUCCESSFUL read
    # into a failed pipeline — a §11.4.201(1) false-positive. $queue_list and
    # $visited_list GROW with the doc graph, so this crosses the ~60 KB pipe
    # buffer as the corpus grows. This gate sets only `set -u` today, so the
    # defect is LATENT here, not live; the pure-bash forms below make it
    # unreachable regardless of what shell options a future edit turns on.
    cur="${queue_list%%$'\n'*}"
    if [ "$queue_list" = "$cur" ]; then queue_list=""; else queue_list="${queue_list#*$'\n'}"; fi
    [ -n "$cur" ] || continue

    # Whole-line membership (exactly `grep -qxF`), fork-free. Quoted expansions
    # in a `case` pattern are LITERAL, so path metacharacters cannot glob.
    if case $'\n'"$visited_list"$'\n' in *$'\n'"$cur"$'\n'*) true ;; *) false ;; esac; then
        continue
    fi
    cur_abs="${root}/${cur}"
    [ -f "$cur_abs" ] || continue

    visited_list="${visited_list:+$visited_list$'\n'}${cur}"
    visited_count=$((visited_count + 1))
    if [ "$visited_count" -gt "$MAX_VISITED" ]; then
        bound_hit=1
        break
    fi

    # Only traverse links FROM markdown files (diagram/asset targets are leaves).
    case "$cur" in
        *.md|*.MD|*.markdown) ;;
        *) continue ;;
    esac

    cur_dir="$(dirname "$cur_abs")"
    links="$(grep -oE '\]\([^)]*\)' "$cur_abs" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' || true)"
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        # Strip a trailing markdown title e.g. (path "title")
        target="${target%% \"*}"
        # Skip external / non-file targets.
        case "$target" in
            http://*|https://*|mailto:*|\#*|//*) continue ;;
        esac
        # Strip any #fragment.
        target="${target%%#*}"
        [ -n "$target" ] || continue
        case "$target" in
            /*) resolved="${root}${target}" ;;
            *) resolved="${cur_dir}/${target}" ;;
        esac
        # Normalize (best-effort, no realpath dependency assumed).
        resolved_rel="$(cd "$(dirname "$resolved")" 2>/dev/null && pwd)/$(basename "$resolved")"
        resolved_rel="${resolved_rel#"$root"/}"
        [ -n "$resolved_rel" ] || continue
        queue_list="${queue_list:+$queue_list$'\n'}${resolved_rel}"
    done <<< "$links"
done

if [ -n "$bound_hit" ]; then
    echo "${GATE}: BLIND — reachability traversal exceeded ${MAX_VISITED} visited files (loop-safety bound); refusing to report a possibly-truncated verdict" >&2
    exit 2
fi

total=0
fails=0
declare -a fail_lines=()

while IFS=$'\t' read -r diagram_id diagram_relpath; do
    [ -n "${diagram_id:-}" ] || continue
    total=$((total + 1))

    status="$(dm_check_target "$root" "$diagram_relpath")"
    if [ "$status" != "OK" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL diagram='${diagram_id}' path='${diagram_relpath}' reason=${status}")
        echo "${fail_lines[-1]}"
        continue
    fi

    diagram_basename="$(basename "$diagram_relpath")"
    embedded=""
    while IFS= read -r vf; do
        [ -n "$vf" ] || continue
        vf_abs="${root}/${vf}"
        [ -f "$vf_abs" ] || continue
        # A diagram embeds itself trivially (skip self-match noise); real
        # embedding requires a DIFFERENT reachable file linking to it.
        [ "$vf" = "$diagram_relpath" ] && continue
        if grep -qE "\]\([^)]*${diagram_basename//./\\.}[^)]*\)" "$vf_abs" 2>/dev/null; then
            embedded=1
            break
        fi
    done <<< "$visited_list"

    if [ -z "$embedded" ]; then
        fails=$((fails + 1))
        fail_lines+=("${GATE}: FAIL diagram='${diagram_id}' path='${diagram_relpath}' reason=ORPHAN_NOT_README_REACHABLE")
        echo "${fail_lines[-1]}"
        continue
    fi

    echo "${GATE}: OK diagram='${diagram_id}' path='${diagram_relpath}'"
done < <(dm_read_rows "$manifest")

echo "${GATE}: SUMMARY manifest=${manifest} readme=${readme} visited=${visited_count} declared=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} declared diagram(s) missing or orphaned (not embedded in the README-reachable doc graph) (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — ${total} declared diagram(s) all exist and are embedded in the README-reachable doc graph (§${ANCHOR})"
exit 0
