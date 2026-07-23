-- SOL-01 POC schema — minimal tracker shape carrying the custody chain as DATA.
-- Consumers map their real tracker onto this shape (§11.4.35: table/column names are
-- consumer data; the INVARIANTS are the mechanism).
PRAGMA foreign_keys=ON;

CREATE TABLE items(
  atm_id        TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  type          TEXT NOT NULL CHECK(type IN ('Bug','Feature','Task')),
  status        TEXT NOT NULL DEFAULT 'Queued',
  last_modified TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Append-only audit ledger. SOL-01 makes rows here a SIDE EFFECT OF THE STATUS
-- WRITE ITSELF (trigger T3), so "status moved with zero history rows" [M2: 52/108]
-- becomes impossible by construction on a triggered DB.
CREATE TABLE item_history(
  seq           INTEGER PRIMARY KEY AUTOINCREMENT,
  atm_id        TEXT NOT NULL REFERENCES items(atm_id),
  event_type    TEXT NOT NULL,
  by_actor      TEXT NOT NULL,
  reason        TEXT,
  evidence_path TEXT,
  at            TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Guard registry keyed by the item's EXACT stable id (§11.4.146(D3): a guard keyed
-- to a non-item id fails the join and satisfies nothing).
CREATE TABLE guard_registry(
  guard_id   TEXT PRIMARY KEY,
  atm_id     TEXT NOT NULL REFERENCES items(atm_id),
  guard_path TEXT NOT NULL
);

-- Machine-written verdicts (§11.4.115(F)): polarity + exit code + the target's
-- artifact fingerprint READ FROM THE TARGET AT RUN TIME + evidence class + path.
CREATE TABLE verdicts(
  verdict_id           INTEGER PRIMARY KEY AUTOINCREMENT,
  guard_id             TEXT NOT NULL REFERENCES guard_registry(guard_id),
  polarity             TEXT NOT NULL CHECK(polarity IN ('RED','GREEN')),
  exit_code            INTEGER NOT NULL,
  artifact_fingerprint TEXT NOT NULL,
  evidence_class       TEXT NOT NULL,
  evidence_path        TEXT NOT NULL,
  at                   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Staged reopen attribution (§11.4.34). A status flip to 'Reopened' consumes a row
-- here; without one the flip is refused — this is what closes the M6 channel where
-- all 25 recorded reopen events said "AI" while the six operator-driven reopens
-- (the highest-severity escapes) left no events at all.
CREATE TABLE reopen_intake(
  intake_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  atm_id        TEXT NOT NULL REFERENCES items(atm_id),
  by_actor      TEXT NOT NULL CHECK(by_actor IN ('AI','User')),
  reason        TEXT NOT NULL,
  evidence_path TEXT NOT NULL,
  consumed      INTEGER NOT NULL DEFAULT 0,
  at            TEXT NOT NULL DEFAULT (datetime('now'))
);
