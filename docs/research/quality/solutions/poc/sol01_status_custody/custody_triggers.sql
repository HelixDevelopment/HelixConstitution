-- SOL-01 custody triggers. THE LOAD-BEARING DESIGN CHOICE: these live IN THE
-- DATABASE FILE, so they bind EVERY writer — the sanctioned mutation tool AND the
-- raw `sqlite3 ... "UPDATE ..."` bypass that PC-1's three forensic fingerprints
-- proved. A seam implemented in a wrapper tool can be gone around; a trigger
-- travels with the data it protects.
--
-- POC terminal vocabulary: Fixed / Implemented / Completed (the §11.4.33 map,
-- suffixes stripped for POC brevity). Obsolete has a different evidence shape
-- (obsolete_details) and is intentionally out of POC scope — stated, not hidden.

-- T1 — a terminal status is UNWRITABLE without the full custody chain:
--      registry row keyed by the EXACT item id
--      → RED verdict with exit<>0
--      → GREEN verdict with exit=0 on a DIFFERENT artifact fingerprint
--      (identical fingerprints prove the fix was never deployed, §11.4.115(F)).
CREATE TRIGGER custody_terminal_refuse
BEFORE UPDATE OF status ON items
WHEN NEW.status IN ('Fixed','Implemented','Completed')
 AND NOT EXISTS (
   SELECT 1
   FROM guard_registry g
   JOIN verdicts red
     ON red.guard_id = g.guard_id AND red.polarity = 'RED' AND red.exit_code <> 0
   JOIN verdicts green
     ON green.guard_id = g.guard_id AND green.polarity = 'GREEN' AND green.exit_code = 0
    AND green.artifact_fingerprint <> red.artifact_fingerprint
   WHERE g.atm_id = NEW.atm_id
 )
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: terminal status requires registered guard + RED/GREEN verdict pair on distinct artifact fingerprints (§11.4.146(D3) + §11.4.115(F))');
END;

-- T2 — 'Reopened' is UNWRITABLE without staged attribution (by/reason/evidence).
CREATE TRIGGER custody_reopen_refuse
BEFORE UPDATE OF status ON items
WHEN NEW.status = 'Reopened'
 AND NOT EXISTS (SELECT 1 FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0)
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: Reopened requires a staged reopen_intake row (By/Reason/Evidence, §11.4.34)');
END;

-- T3 — every status change writes its own audit row. The DB is the historian;
--      no writer can "forget". Attribution comes from the staged intake row when
--      one exists (reopens), else from the GREEN verdict evidence (closures),
--      else the honest literal 'UNATTRIBUTED' (§11.4.6 — never invented).
CREATE TRIGGER custody_history_auto
AFTER UPDATE OF status ON items
WHEN OLD.status <> NEW.status
BEGIN
  INSERT INTO item_history(atm_id, event_type, by_actor, reason, evidence_path)
  VALUES(
    NEW.atm_id,
    NEW.status,
    COALESCE(
      (SELECT by_actor FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      'UNATTRIBUTED'),
    (SELECT reason FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
    COALESCE(
      (SELECT evidence_path FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      (SELECT v.evidence_path FROM guard_registry g JOIN verdicts v ON v.guard_id = g.guard_id
        WHERE g.atm_id = NEW.atm_id AND v.polarity = 'GREEN' AND v.exit_code = 0
        ORDER BY v.at DESC, v.verdict_id DESC LIMIT 1))
  );
  UPDATE reopen_intake SET consumed = 1 WHERE atm_id = NEW.atm_id AND consumed = 0;
END;

-- T4/T5 — the audit ledger is append-only. History that can be edited is not
--         history (the M2/M4/M5 impossible-sequence forensics depended on rows
--         that happened to survive; these make survival unconditional).
CREATE TRIGGER history_no_update
BEFORE UPDATE ON item_history
BEGIN SELECT RAISE(ABORT, 'CUSTODY-REFUSED: item_history is append-only'); END;

CREATE TRIGGER history_no_delete
BEFORE DELETE ON item_history
BEGIN SELECT RAISE(ABORT, 'CUSTODY-REFUSED: item_history is append-only'); END;
