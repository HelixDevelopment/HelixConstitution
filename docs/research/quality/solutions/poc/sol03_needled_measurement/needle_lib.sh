#!/usr/bin/env bash
# SOL-03 — the needle-carrying measurement primitive.
#
# Design law (§11.4.201(6)(7)(8), R5.3 negative-control methodology):
#   1. A NULL IS NOT EVIDENCE until a control needle proves the instrument can see
#      — same instrument, same path, same artifact.
#   2. The needle must share the query's LOAD-BEARING regex features; a bare-literal
#      needle certifies only the layers a bare literal crosses.
#   3. A COUNT IS A LEAD; THE LINES ARE THE FINDING (MU-6) — presence output always
#      carries sample lines.
#   4. Never early-exit a consumer under pipefail (the SIGPIPE false-absent class —
#      measured on this host: 400/400 false-absent at a 2 MB payload).
#
# The instrument is injectable (NQ_GREP) so the blind-instrument case is testable —
# an untestable instrument is unvalidated instrumentation (§11.4.115(F) applied to
# measurements).

NQ_GREP="${NQ_GREP:-grep}"

# _nq_features <ere> -> prints the feature classes the pattern exercises
_nq_features() {
  local p="$1" out=""
  case "$p" in *'|'*) out="$out alternation";; esac
  case "$p" in *'('*|*')'*) out="$out group";; esac
  case "$p" in '^'*) out="$out anchor_start";; esac
  case "$p" in *'$') out="$out anchor_end";; esac
  case "$p" in *'\'*) out="$out escape";; esac
  printf '%s\n' "$out"
}

# nq_absent <file> <query-ere> <needle-ere>
# 0 CERTIFIED-ABSENT | 1 PRESENT (+ sample lines) | 2 INSTRUMENT-BLIND | 3 NEEDLE-CLASS-MISMATCH
nq_absent() {
  local file="$1" query="$2" needle="$3"
  [ -r "$file" ] || { echo "INSTRUMENT-BLIND: cannot read $file"; return 2; }

  # (2) needle-class check: every load-bearing feature the query uses must appear
  # in the needle, or the needle cannot certify the query's path.
  local qf nf f missing=""
  qf=$(_nq_features "$query"); nf=$(_nq_features "$needle")
  for f in $qf; do
    case " $nf " in *" $f "*) : ;; *) missing="$missing $f";; esac
  done
  if [ -n "$missing" ]; then
    echo "NEEDLE-CLASS-MISMATCH: query exercises{$qf } needle lacks{$missing } — refusing certification"
    return 3
  fi

  # (1) the query, through the injectable instrument. Read to EOF (grep over a
  # file argument, no early-exit pipe) — SIGPIPE-immune by construction.
  local hits
  hits=$("$NQ_GREP" -En -- "$query" "$file" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "PRESENT: query '$query' matched in $file — the lines (first 5):"
    printf '%s\n' "$hits" | head -5
    return 1
  fi

  # (3) zero hits — run the needle through the SAME instrument + path before
  # reporting anything.
  if ! "$NQ_GREP" -Eq -- "$needle" "$file" 2>/dev/null; then
    echo "INSTRUMENT-BLIND: needle '$needle' returned 0 through the same path — the query's zero says NOTHING (report the blindness, never the absence)"
    return 2
  fi
  echo "CERTIFIED-ABSENT: query '$query' 0 hits; needle '$needle' sighted through the same path in $file"
  return 0
}

# nq_count <file> <query-ere> <needle-ere>
# Prints "count=N" + first 5 matching lines; same blind/mismatch semantics.
nq_count() {
  local file="$1" query="$2" needle="$3" out rc
  out=$(nq_absent "$file" "$query" "$needle"); rc=$?
  case "$rc" in
    0) echo "count=0 (certified)"; return 0 ;;
    1) local n; n=$("$NQ_GREP" -Ec -- "$query" "$file"); echo "count=$n"; printf '%s\n' "$out" | tail -n +2; return 0 ;;
    *) printf '%s\n' "$out"; return "$rc" ;;
  esac
}

# nq_stream_contains <producer-cmd...> -- <ere>
# SIGPIPE-safe stream presence: the consumer reads the producer to EOF (grep -c,
# never grep -q), so the producer is never SIGPIPE-killed and pipefail never
# converts a present literal into an absent verdict.
# 0 present | 1 absent | 2 blind (producer failed)
nq_stream_contains() {
  local -a producer=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do producer+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  local query="${1:?nq_stream_contains: missing query after --}"
  local tmp rc n
  tmp=$(mktemp)
  "${producer[@]}" > "$tmp" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$tmp"; echo "INSTRUMENT-BLIND: producer exited $rc"; return 2; fi
  n=$("$NQ_GREP" -Ec -- "$query" "$tmp"); rc=$?
  rm -f "$tmp"
  if [ "${n:-0}" -gt 0 ]; then echo "PRESENT: $n line(s) match '$query'"; return 0; fi
  echo "ABSENT: 0 matches for '$query' (producer read to EOF — no SIGPIPE truncation possible)"
  return 1
}
