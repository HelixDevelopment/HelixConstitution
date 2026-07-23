#!/usr/bin/env bash
# SOL-02 — coverage-aware verdict gate for the release seam.
#
#   uncovered = registered ∧ topology-present ∧ no-verdict-for-the-CANDIDATE-fingerprint
#
# Exit semantics (the M9 fix — "never verified" and "verified good" are DIFFERENT colours):
#   0 = full coverage, all green            1 = >=1 FAIL on the candidate (dominates)
#   3 = zero FAILs but uncovered != empty   2 = blind instrument / unreadable inputs
#
# Topology-absent guards are ENUMERATED as exemptions (never silent, §11.4.3/§11.4.118)
# and never block — a flat "PENDING always blocks" is itself a §11.4.201(1) FAIL-bluff.
#
# Inputs (consumer DATA per §11.4.35):
#   $1 registry.tsv : guard_id <TAB> item_id <TAB> topology_class <TAB> guard_path
#   $2 verdicts.tsv : guard_id <TAB> polarity <TAB> exit_code <TAB> artifact_fingerprint <TAB> evidence_path
#   $3 topology.txt : one PRESENT topology class per line
#   $4 candidate artifact fingerprint
set -u
REG="${1:?registry}"; VER="${2:?verdicts}"; TOPO="${3:?topology}"; FP="${4:?candidate-fingerprint}"

for f in "$REG" "$VER" "$TOPO"; do
  [ -r "$f" ] || { echo "GATE-BLIND: cannot read $f"; exit 2; }
done
# Control needle (§11.4.201(7)(b)): an empty registry means the instrument sees
# nothing to require — that is a blind gate, never a green one.
REG_N=$(grep -c . "$REG" || true)
if [ "${REG_N:-0}" -eq 0 ]; then echo "GATE-BLIND: registry is empty — nothing was required, so nothing is proven"; exit 2; fi

fails=0; uncovered=0; covered=0; exempt=0
while IFS=$'\t' read -r gid item topo path; do
  [ -n "$gid" ] || continue
  if ! grep -qx "$topo" "$TOPO"; then
    echo "TOPOLOGY-EXEMPT: $gid ($item) class=$topo — enumerated honest gap, not blocking"
    exempt=$((exempt+1)); continue
  fi
  # latest verdict for THIS guard on THE CANDIDATE fingerprint only (stale
  # fingerprints are absence — the verdict self-clears on every new artifact)
  line=$(awk -F'\t' -v g="$gid" -v fp="$FP" '$1==g && $4==fp {last=$0} END{print last}' "$VER")
  if [ -z "$line" ]; then
    echo "UNCOVERED: $gid ($item) — registered, topology-present, NO verdict for candidate $FP"
    uncovered=$((uncovered+1)); continue
  fi
  ec=$(printf '%s' "$line" | cut -f3)
  if [ "$ec" -eq 0 ] 2>/dev/null; then
    covered=$((covered+1))
  else
    echo "FAIL-VERDICT: $gid ($item) exit=$ec on candidate $FP"
    fails=$((fails+1))
  fi
done < "$REG"

echo "SUMMARY: registered=$REG_N covered=$covered fails=$fails uncovered=$uncovered exempt=$exempt candidate=$FP"
if [ "$fails" -gt 0 ]; then exit 1; fi
if [ "$uncovered" -gt 0 ]; then exit 3; fi
exit 0
