#!/usr/bin/env bash
# SOL-05 — gate ledger + implementation ratchet.
# Makes "named-but-unimplemented gate" a VISIBLE, MONOTONICALLY-DECREASING,
# citation-guarded quantity instead of a silent 58% [M12].
#
#   generate <corpus.md> <impl-dir>            -> ledger TSV on stdout
#   check <ledger> <baseline> <deferrals.tsv> <prev-gate-set> [removals.tsv]
#
# Structure rules (§11.4.201(7)(a) — match structure, not substring):
#   * a gate NAME is a CM-… token found in the rule corpus;
#   * an IMPLEMENTATION is that token inside an EXECUTABLE site (*.sh) under the
#     implementation tree — prose files (.md) mentioning a gate are carriers and
#     never count.
# Ratchet caveat (§11.4.201(8), validated against the definition of done):
#   at the correct end-state (every named gate implemented) unimplemented==0 —
#   the metric reaches target, so it is valid as a NECESSARY floor. Its known
#   gaming channel — deleting the NAME to lower the count — is closed by the
#   prev-set comparison: a vanished name FAILs unless a removal citation exists.
set -u
MODE="${1:?generate|check}"; shift

case "$MODE" in
generate)
  CORPUS="${1:?corpus}"; IMPL="${2:?impl-dir}"
  [ -r "$CORPUS" ] || { echo "BLIND: cannot read corpus $CORPUS" >&2; exit 2; }
  [ -d "$IMPL" ]  || { echo "BLIND: impl dir $IMPL absent" >&2; exit 2; }
  # Control needle: the token extractor must see at least one CM- token in a
  # corpus that names gates; an empty extraction over a non-empty corpus is
  # reported, never silently emitted as an empty ledger.
  names=$(grep -ohE 'CM-[A-Z0-9][A-Z0-9-]+' "$CORPUS" | sed 's/-$//' | sort -u)
  if [ -z "$names" ]; then
    echo "BLIND-OR-EMPTY: zero CM- tokens extracted from $CORPUS — needle your corpus before trusting this" >&2
    exit 2
  fi
  while IFS= read -r g; do
    # NOTE (live trap caught by this POC's own RED->GREEN loop): with
    # `grep -rlE -- "$g" "$IMPL" --include='*.sh'` the `--` terminator turned
    # `--include` into a FILENAME, so a prose .md carrier counted as an
    # implementation — the §11.4.201(7)(c) path-is-part-of-the-instrument class,
    # reproduced inside the very tool built to fight it. Options MUST precede `--`.
    hit=$(grep -rlE --include='*.sh' -- "$g" "$IMPL" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
      printf '%s\tIMPLEMENTED\t%s\n' "$g" "$hit"
    else
      printf '%s\tUNIMPLEMENTED\t-\n' "$g"
    fi
  done <<< "$names"
  ;;
check)
  LEDGER="${1:?ledger}"; BASE="${2:?baseline}"; DEF="${3:?deferrals}"; PREV="${4:?prev-gate-set}"; REM="${5:-}"
  for f in "$LEDGER" "$BASE" "$DEF" "$PREV"; do [ -r "$f" ] || { echo "BLIND: cannot read $f"; exit 2; }; done
  fails=0
  # 1) every UNIMPLEMENTED gate must carry a registered deferral (explicit debt
  #    with a tracked item id — the legal form; silent debt is the 85-deferral /
  #    241-gate state this closes).
  while IFS=$'\t' read -r g st _; do
    [ "$st" = "UNIMPLEMENTED" ] || continue
    if ! cut -f1 "$DEF" | grep -qx -- "$g"; then
      echo "LEDGER-FAIL: $g is UNIMPLEMENTED with no registered deferral (gate_id -> tracked item)"
      fails=$((fails+1))
    fi
  done < "$LEDGER"
  # 2) monotone ratchet on the unimplemented count.
  count=$(awk -F'\t' '$2=="UNIMPLEMENTED"{n++} END{print n+0}' "$LEDGER")
  baseline=$(cat "$BASE")
  if [ "$count" -gt "$baseline" ]; then
    echo "LEDGER-FAIL: ratchet — unimplemented=$count exceeds baseline=$baseline (naming a gate without landing or registering it is refused)"
    fails=$((fails+1))
  fi
  # 3) name-deletion guard: a gate present in the previous set but absent from
  #    the current ledger needs an explicit removal citation.
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if ! cut -f1 "$LEDGER" | grep -qx -- "$g"; then
      if [ -z "$REM" ] || ! cut -f1 "$REM" 2>/dev/null | grep -qx -- "$g"; then
        echo "LEDGER-FAIL: gate $g vanished from the corpus without a removal citation (silent deletion would game the ratchet)"
        fails=$((fails+1))
      fi
    fi
  done < "$PREV"
  echo "LEDGER: unimplemented=$count baseline=$baseline fails=$fails"
  [ "$fails" -eq 0 ] || exit 1
  ;;
*) echo "usage: gate_ledger.sh generate|check ..." >&2; exit 2;;
esac
