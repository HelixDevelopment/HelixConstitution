#!/usr/bin/env bash
# SOL-07 — recurrence intake: dedup verdict + writer-repair closure classification.
#
# dedup: BEFORE minting a new id, resolve the report against existing items on
# normalized (subject, scope) token overlap — never bare substring (§11.4.186).
# Autonomous default on a candidate match is MINT-WITH-LINK, never auto-merge
# (§11.4.214(3): a spurious id is recoverable; a wrongly-merged defect is LOST).
#
# fixkind: a STATE-shaped defect (wrong config value / generated artifact / cache
# entry / route / marker) closed by a STATE-only repair is a MITIGATION whose
# recurrence horizon equals the defective writer's next run (corpus-2 §7.3 —
# measured horizons: fossil ~7 h, regen-loss same-day, stale artifact same-day).
set -u
MODE="${1:?dedup|fixkind}"; shift

normalize() { # lowercase, strip punctuation, drop trivial stopwords, sort tokens
  printf '%s\n' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' ' ' \
    | tr -s ' ' '\n' | grep -vwE 'the|a|an|on|in|of|to|is|after|again|and' \
    | sort -u
}

case "$MODE" in
dedup)
  DB="${1:?existing.tsv}"; SUBJ="${2:?subject}"; SCOPE="${3:?scope}"
  [ -r "$DB" ] || { echo "BLIND: cannot read $DB"; exit 2; }
  # Control needle: an empty item table means nothing can be resolved against —
  # that is a fresh tracker, DISTINCT verdict is legal, but say so.
  new_tokens=$(normalize "$SUBJ")
  new_n=$(printf '%s\n' "$new_tokens" | grep -c . || true)
  [ "${new_n:-0}" -gt 0 ] || { echo "BLIND: subject normalized to zero tokens"; exit 2; }
  best_id=""; best_score=0
  while IFS=$'\t' read -r id status scope subj; do
    [ -n "$id" ] || continue
    [ "$scope" = "$SCOPE" ] || continue      # scope is part of the key (§11.4.186)
    old_tokens=$(normalize "$subj")
    inter=$(comm -12 <(printf '%s\n' "$new_tokens") <(printf '%s\n' "$old_tokens") | grep -c . || true)
    union=$(printf '%s\n%s\n' "$new_tokens" "$old_tokens" | sort -u | grep -c . || true)
    score=$(( inter * 100 / (union>0 ? union : 1) ))
    if [ "$score" -gt "$best_score" ]; then best_score=$score; best_id=$id; best_status=$status; fi
  done < "$DB"
  if [ -n "$best_id" ] && [ "$best_score" -ge 50 ]; then
    echo "SAME-DEFECT-CANDIDATE: $best_id (scope=$SCOPE, overlap=${best_score}%) — mint-with-link; reopen through the duplicate-chain HEAD iff terminal (§11.4.214)"
    exit 10
  fi
  echo "DISTINCT: no same-scope candidate above threshold (best=${best_score}%) — mint a new id"
  exit 0
  ;;
fixkind)
  SHAPE="${1:?state|behaviour}"; KIND="${2:?writer-repair|state-repair}"
  case "$SHAPE/$KIND" in
    state/state-repair)
      echo "CLOSURE-REFUSED: state-shaped defect closed by a state-only repair is a MITIGATION — recurrence horizon = the defective writer's next run (repair the WRITER + the state + a seam asserting the invariant; corpus-2 §7.3)"
      exit 1;;
    state/writer-repair|behaviour/*)
      echo "CLOSURE-KIND-OK: $SHAPE defect closed by $KIND"
      exit 0;;
    *) echo "BLIND: unknown shape/kind '$SHAPE/$KIND'"; exit 2;;
  esac
  ;;
*) echo "usage: intake_check.sh dedup|fixkind ..."; exit 2;;
esac
