#!/usr/bin/env bash
# SOL-09 — detection-pressure scheduler.
# Corpus 3's one real recurrence surfaced at 24 DAYS — the next time someone
# LOOKED, not the next time it broke (§11.4.118: we only see what we test).
# Corpus 1's two standing guards emitted their latent FAILs the FIRST time they
# were actually executed on the deployed target [PC-7]. Low pressure produces a
# flattering, meaningless recurrence number; this scheduler raises pressure
# MECHANICALLY instead of waiting for a human to re-look.
#
# Usage: pressure_queue.sh <registry.tsv> <verdicts.tsv> <topology.txt> <current-fp> <max-age-days> <now-epoch>
# Exit: 0 all fresh | 3 rerun queue non-empty | 2 blind
set -u
REG="${1:?}"; VER="${2:?}"; TOPO="${3:?}"; FP="${4:?}"; MAXD="${5:?}"; NOW="${6:?}"
for f in "$REG" "$VER" "$TOPO"; do [ -r "$f" ] || { echo "BLIND: cannot read $f"; exit 2; }; done
REG_N=$(grep -c . "$REG" || true)
[ "${REG_N:-0}" -gt 0 ] || { echo "BLIND-OR-EMPTY: registry is empty — no pressure is computable over nothing"; exit 2; }

MAXS=$(( MAXD * 86400 ))
QUEUE="$(mktemp)"; trap 'rm -f "$QUEUE"' EXIT

while IFS=$'\t' read -r gid item topo reopens; do
  [ -n "$gid" ] || continue
  if ! grep -qx "$topo" "$TOPO"; then
    echo "TOPOLOGY-EXEMPT: $gid ($item) class=$topo — enumerated, not pressured"
    continue
  fi
  latest=$(awk -F'\t' -v g="$gid" '$1==g {last=$0} END{print last}' "$VER")
  reason=""
  if [ -z "$latest" ]; then
    reason="never-executed"; age=999999999
  else
    vfp=$(printf '%s' "$latest" | cut -f3)
    vep=$(printf '%s' "$latest" | cut -f4)
    age=$(( NOW - vep ))
    if [ "$vfp" != "$FP" ]; then
      reason="stale-fingerprint($vfp)"
    elif [ "$age" -gt "$MAXS" ]; then
      reason="over-age(${age}s > ${MAXS}s)"
    fi
  fi
  if [ -n "$reason" ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$reopens" "$age" "$gid" "$item" "$reason" >> "$QUEUE"
  fi
done < "$REG"

QN=$(grep -c . "$QUEUE" || true)
if [ "${QN:-0}" -eq 0 ]; then
  echo "PRESSURE: all topology-present guards fresh on candidate $FP"
  exit 0
fi
# Order: most-reopened FIRST (§11.4.189 — the empirically-most-fragile set gets
# the deepest scrutiny first), then stalest.
sort -t$'\t' -k1,1nr -k2,2nr "$QUEUE" | while IFS=$'\t' read -r reopens age gid item reason; do
  echo "QUEUE: $gid ($item) reopens=$reopens reason=$reason"
done
echo "PRESSURE: rerun-queue=$QN of $REG_N registered — detection latency is a choice, not a fact of nature"
exit 3
