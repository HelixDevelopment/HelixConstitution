#!/usr/bin/env bash
# covenant_propagation_suite.sh — batch runner for the data-pack-driven
# CM-COVENANT-114-<N>-PROPAGATION gate family and its §1.1 mutation pairs.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Runs every gate named in `covenant_propagation_anchors.tsv` (mode `gates`)
# or every paired §1.1 mutation test (mode `mutations`) and prints one
# `<gate> <exit-code> <verdict>` line per entry plus a summary. Exists so the
# family can be exercised and evidenced in one shot (§11.4.262 machine-created
# evidence) without hand-listing 29 script names anywhere.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   covenant_propagation_suite.sh gates [--root <consumer-root>]
#   covenant_propagation_suite.sh mutations
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   `gates` is read-only. `mutations` delegates to the per-gate mutation
#   wrappers, which build + remove their own mktemp fixtures (the real tree is
#   never mutated).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, the sibling wrappers + data pack. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.227(A)/(B), §11.4.251 (data-pack-driven, no hand-maintained list),
#   §1.1, §11.4.262.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every entry exited 0.  1 — at least one entry exited non-zero.
#   2 — environment error (bad mode / data pack missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PACK="${COVENANT_PROPAGATION_ANCHORS:-${HERE}/covenant_propagation_anchors.tsv}"
MODE="${1:-}"; shift || true

[ -r "$PACK" ] || { echo "suite: data pack not readable: $PACK" >&2; exit 2; }
case "$MODE" in gates|mutations) ;; *) sed -n '1,32p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;; esac

rows="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1"\t"$2}' "$PACK")"
[ -n "$rows" ] || { echo "suite: zero rows in $PACK" >&2; exit 2; }

total=0; bad=0
printf '%-36s %-5s %s\n' "GATE" "EXIT" "VERDICT"
printf '%-36s %-5s %s\n' "------------------------------------" "-----" "----------------------------------"
while IFS=$'\t' read -r gate anchor; do
    [ -n "$gate" ] || continue
    slug="${anchor#11.4.}"
    if [ "$MODE" = "gates" ]; then
        script="${HERE}/cm_covenant_114_${slug}_propagation.sh"
        out="$(bash "$script" "$@" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -E '^(✅|❌) CM-COVENANT' | tail -1)"
        [ -n "$verdict" ] || verdict="$(printf '%s\n' "$out" | tail -1)"
        stats="$(printf '%s\n' "$out" | grep -E '^CM-COVENANT.*single-block-PRESENT' | tail -1)"
        [ -z "$stats" ] || verdict="${stats#*: }"
    else
        script="${HERE}/cm_covenant_114_${slug}_propagation_mutation_test.sh"
        out="$(bash "$script" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -cE '^✅ META OK') of 8 fixtures correct"
    fi
    total=$((total+1))
    [ "$rc" -eq 0 ] || bad=$((bad+1))
    printf '%-36s %-5s %s\n' "$gate" "$rc" "$verdict"
done <<< "$rows"

echo "----------------------------------------------------------------------"
echo "suite(${MODE}): ${total} entries, $((total-bad)) exit-0, ${bad} non-zero"
[ "$bad" -eq 0 ] || exit 1
exit 0
