#!/usr/bin/env bash
# SOL-01 Seam B — full-table custody sweep (build-seam gate).
# Catches what triggers cannot: LEGACY databases created before the triggers
# existed, or databases whose triggers were dropped. A diff-scoped check misses
# raw writes that bypassed the sanctioned tool (§11.4.146(D3) Seam B is a
# FULL-TABLE sweep by design).
#
# Usage: custody_sweep.sh <db-path>
# Exit:  0 = custody-clean   1 = findings (each named)   2 = blind/empty instrument
set -u
DB="${1:?usage: custody_sweep.sh <db-path>}"
SQLITE="${SQLITE:-sqlite3}"

q() { "$SQLITE" -readonly "$DB" "$1"; }

# Control needle (§11.4.201(7)(b)): prove the instrument can see rows at all
# before reporting any zero. An empty items table is BLIND-OR-EMPTY, never PASS.
TOTAL=$(q "SELECT COUNT(*) FROM items;") || { echo "SWEEP-BLIND: cannot read items table"; exit 2; }
if [ "${TOTAL:-0}" -eq 0 ]; then
  echo "SWEEP-BLIND-OR-EMPTY: items table has 0 rows — a zero here certifies nothing"
  exit 2
fi

FINDINGS=0
report() { echo "CUSTODY-FINDING[$1]: $2"; FINDINGS=$((FINDINGS+1)); }

# C1 — terminal-status items with ZERO history rows (the M2 class: 52/108 = 48%).
while IFS='|' read -r id st; do
  [ -n "$id" ] && report C1 "item $id status='$st' has zero item_history rows"
done < <(q "SELECT i.atm_id, i.status FROM items i
            WHERE i.status IN ('Fixed','Implemented','Completed')
              AND NOT EXISTS (SELECT 1 FROM item_history h WHERE h.atm_id = i.atm_id);")

# C2 — Reopened items with no Reopened event (the M4 class: 13/26).
while IFS='|' read -r id; do
  [ -n "$id" ] && report C2 "item $id is Reopened with no Reopened event"
done < <(q "SELECT i.atm_id FROM items i
            WHERE i.status = 'Reopened'
              AND NOT EXISTS (SELECT 1 FROM item_history h WHERE h.atm_id = i.atm_id AND h.event_type = 'Reopened');")

# C3 — impossible sequences: reopen events with zero terminal events (the R1/M5
#      class: you cannot reopen what was never closed — proves ledger bypass).
while IFS='|' read -r id; do
  [ -n "$id" ] && report C3 "item $id has Reopened events but zero terminal events (ledger bypassed)"
done < <(q "SELECT DISTINCT h.atm_id FROM item_history h
            WHERE h.event_type = 'Reopened'
              AND NOT EXISTS (SELECT 1 FROM item_history t WHERE t.atm_id = h.atm_id
                              AND t.event_type IN ('Fixed','Implemented','Completed'));")

# C4 — terminal-status items with no valid verdict-pair custody (the M7 class:
#      92.5% of done-claimers unguarded).
while IFS='|' read -r id st; do
  [ -n "$id" ] && report C4 "item $id status='$st' has no RED/GREEN verdict pair on distinct fingerprints"
done < <(q "SELECT i.atm_id, i.status FROM items i
            WHERE i.status IN ('Fixed','Implemented','Completed')
              AND NOT EXISTS (
                SELECT 1 FROM guard_registry g
                JOIN verdicts red   ON red.guard_id = g.guard_id AND red.polarity='RED'   AND red.exit_code <> 0
                JOIN verdicts green ON green.guard_id = g.guard_id AND green.polarity='GREEN' AND green.exit_code = 0
                 AND green.artifact_fingerprint <> red.artifact_fingerprint
                WHERE g.atm_id = i.atm_id);")

echo "SWEEP: items=$TOTAL findings=$FINDINGS"
[ "$FINDINGS" -eq 0 ]
