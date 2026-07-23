#!/usr/bin/env bash
# SOL-01 POC test — status custody at the database layer.
# Written FIRST per §11.4.224; must be RED before custody_schema.sql /
# custody_triggers.sql / custody_sweep.sh exist, GREEN after.
#
# Cases:
#   A  golden-good      : full custody chain -> terminal write SUCCEEDS, history auto-row, sweep PASS
#   B  golden-bad-1     : raw UPDATE to terminal with no verdicts -> REFUSED by trigger
#   C  golden-bad-2     : legacy DB (no triggers), terminal item, zero history -> sweep FAILS naming id
#   D  negative-control : open in-progress item with no history -> sweep MUST NOT flag (§11.4.201(1))
#   E  operator reopen  : staged User attribution -> Reopened SUCCEEDS with by_actor=User in history;
#      golden-bad-3     : un-staged Reopened -> REFUSED
#   F  append-only      : UPDATE on item_history -> REFUSED
#   G  golden-bad-4     : RED and GREEN share the same artifact fingerprint -> terminal REFUSED
#      (identical fingerprints prove the fix was never deployed, §11.4.115(F))
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE="${SQLITE:-sqlite3}"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

need() { [ -f "$HERE/$1" ] || { bad "missing artifact $1"; }; }
need custody_schema.sql
need custody_triggers.sql
need custody_sweep.sh
if [ "$FAIL" -gt 0 ]; then echo "RESULT: RED ($FAIL missing artifacts)"; exit 1; fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdb() { # $1=dbpath  $2=with_triggers(yes|no)
  "$SQLITE" "$1" < "$HERE/custody_schema.sql"
  [ "$2" = yes ] && "$SQLITE" "$1" < "$HERE/custody_triggers.sql"
  return 0
}
seed_item() { "$SQLITE" "$1" "INSERT INTO items(atm_id,title,type,status) VALUES('$2','t','Bug','In progress');"; }

# ---- A golden-good --------------------------------------------------------
DB="$T/good.db"; mkdb "$DB" yes; seed_item "$DB" ATM-001
"$SQLITE" "$DB" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('G1','ATM-001','tests/guard_ATM-001.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('G1','RED',1,'fp-broken','runtime','ev/red.log'),
 ('G1','GREEN',0,'fp-fixed','runtime','ev/green.log');"
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-001';" 2>"$T/a.err"; then
  ok "A1 terminal write with full custody chain succeeds"
else
  bad "A1 terminal write with full custody chain refused: $(cat "$T/a.err")"
fi
H=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM item_history WHERE atm_id='ATM-001' AND event_type='Fixed';")
[ "$H" = "1" ] && ok "A2 history row auto-written by the DB itself" || bad "A2 expected 1 auto history row, got $H"
if bash "$HERE/custody_sweep.sh" "$DB" >"$T/a.sweep" 2>&1; then
  ok "A3 sweep PASS on custody-clean DB"
else
  bad "A3 sweep failed on clean DB: $(cat "$T/a.sweep")"
fi

# ---- B golden-bad-1: bypass write refused --------------------------------
DB="$T/bad1.db"; mkdb "$DB" yes; seed_item "$DB" ATM-002
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-002';" 2>"$T/b.err"; then
  bad "B1 un-evidenced terminal write was ACCEPTED (custody trigger absent or blind)"
else
  grep -q 'CUSTODY-REFUSED' "$T/b.err" && ok "B1 un-evidenced terminal write refused with custody message" \
    || bad "B1 refused but without custody message: $(cat "$T/b.err")"
fi

# ---- C golden-bad-2: legacy DB caught by sweep ----------------------------
DB="$T/legacy.db"; mkdb "$DB" no
"$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('ATM-003','t','Bug','Fixed');"
if bash "$HERE/custody_sweep.sh" "$DB" >"$T/c.sweep" 2>&1; then
  bad "C1 sweep passed a legacy DB holding a zero-history terminal item"
else
  grep -q 'ATM-003' "$T/c.sweep" && ok "C1 sweep FAILs legacy DB and names the offending item" \
    || bad "C1 sweep failed but did not name ATM-003"
fi

# ---- D negative-control: open item never flagged --------------------------
DB="$T/negctl.db"; mkdb "$DB" yes; seed_item "$DB" ATM-004
if bash "$HERE/custody_sweep.sh" "$DB" >"$T/d.sweep" 2>&1; then
  ok "D1 sweep does NOT flag an ordinary open item (false-positive guard)"
else
  bad "D1 sweep flagged an open item: $(cat "$T/d.sweep")"
fi

# ---- E reopen attribution -------------------------------------------------
DB="$T/reopen.db"; mkdb "$DB" yes; seed_item "$DB" ATM-005
if "$SQLITE" "$DB" "UPDATE items SET status='Reopened' WHERE atm_id='ATM-005';" 2>"$T/e1.err"; then
  bad "E1 un-staged Reopened flip was ACCEPTED"
else
  grep -q 'CUSTODY-REFUSED' "$T/e1.err" && ok "E1 un-staged Reopened flip refused" \
    || bad "E1 refused without custody message"
fi
"$SQLITE" "$DB" "INSERT INTO reopen_intake(atm_id,by_actor,reason,evidence_path) VALUES('ATM-005','User','manual-testing-detected','qa/operator_note.md');"
if "$SQLITE" "$DB" "UPDATE items SET status='Reopened' WHERE atm_id='ATM-005';" 2>"$T/e2.err"; then
  BY=$("$SQLITE" "$DB" "SELECT by_actor FROM item_history WHERE atm_id='ATM-005' AND event_type='Reopened';")
  [ "$BY" = "User" ] && ok "E2 staged operator reopen recorded with by_actor=User (closes M6)" \
    || bad "E2 reopen recorded but by_actor='$BY' not 'User'"
else
  bad "E2 staged reopen refused: $(cat "$T/e2.err")"
fi

# ---- F append-only history ------------------------------------------------
if "$SQLITE" "$DB" "UPDATE item_history SET by_actor='AI';" 2>"$T/f.err"; then
  bad "F1 item_history UPDATE was ACCEPTED (audit trail mutable)"
else
  ok "F1 item_history is append-only (UPDATE refused)"
fi

# ---- G golden-bad-4: same-fingerprint pair refused ------------------------
DB="$T/bad4.db"; mkdb "$DB" yes; seed_item "$DB" ATM-006
"$SQLITE" "$DB" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('G6','ATM-006','tests/g6.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('G6','RED',1,'fp-same','runtime','ev/r.log'),
 ('G6','GREEN',0,'fp-same','runtime','ev/g.log');"
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-006';" 2>"$T/g.err"; then
  bad "G1 terminal write accepted on identical RED/GREEN fingerprints (undeployed fix)"
else
  ok "G1 identical-fingerprint verdict pair refused (§11.4.115(F))"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
