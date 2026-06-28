-- workable-items DDL — §11.4.93 SQLite-SSoT for workable items
--
-- Canonical authority: constitution/Constitution.md §11.4.93
-- Forensic anchor: User mandate 2026-05-27.
--
-- This schema is the AUTHORITATIVE source for every workable item.
-- All Markdown / HTML / PDF / Summary / Status surfaces are generator
-- output derived from this DB. Sync drift is mechanically impossible
-- because every regeneration starts from these tables.
--
-- Bidirectional regeneration guarantee (§11.4.93):
--   md→db: `workable-items sync md-to-db` parses Issues.md + Fixed.md +
--          Status.md fleet, upserts here.
--   db→md: `workable-items sync db-to-md` regenerates the same docs from
--          this DB. Round-trip MUST be byte-identical modulo whitespace.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;       -- crash-resistant + concurrent read
PRAGMA synchronous = NORMAL;     -- balance durability vs throughput

-- ============================================================
-- §11.4.93 — items: primary registry
-- ============================================================
CREATE TABLE IF NOT EXISTS items (
    -- §11.4.54 ATM-NNN ticket identifier (monotonic, append-only, never
    -- renumbered, never reused). NOT a bare PRIMARY KEY: the SAME ticket id
    -- legitimately appears in BOTH trackers — a tombstone in Issues.md AND a
    -- closure row in Fixed.md (e.g. HXC-017). The identity is therefore
    -- (atm_id, current_location); see the composite PRIMARY KEY below.
    atm_id           TEXT NOT NULL,

    -- §11.4.16 Type closed-set
    type             TEXT NOT NULL CHECK (type IN ('Bug', 'Feature', 'Task')),

    -- §11.4.15 + §11.4.21 + §11.4.90 Status closed-set (8 values)
    status           TEXT NOT NULL CHECK (status IN (
                         'Queued', 'In progress', 'Ready for testing',
                         'In testing', 'Reopened', 'Operator-blocked',
                         'Fixed (→ Fixed.md)', 'Implemented (→ Fixed.md)',
                         'Completed (→ Fixed.md)', 'Obsolete (→ Fixed.md)'
                     )),

    -- Severity (informational only; not closed-set, but recommended)
    severity         TEXT,

    -- Heading line text (full H2 heading including code prefix per §11.4.54)
    title            TEXT NOT NULL,

    -- §11.4.91 description floor: ≥ 6 words OR ≥ 40 chars (enforced at insert)
    description      TEXT NOT NULL,

    -- Forensic anchor — verbatim user mandate or operator quote
    forensic_anchor  TEXT,

    -- Closure criteria (markdown body)
    closure_criteria TEXT,

    -- Composes-with cross-references — JSON array of §-letter or ATM-NNN refs
    composes_with    TEXT,                    -- JSON-encoded array

    -- Participant attribution (§11.4.104 / Herald PARTICIPANT_ATTRIBUTION.md).
    -- created_by  = canonical handle that opened the item; assigned_to = canonical
    -- handle the item is assigned to. Canonical handle closed set: "Claude" (the
    -- system agent; never tagged), or a subscriber's @username. Empty '' = legacy
    -- item with no attribution recorded (back-compat default).
    created_by       TEXT NOT NULL DEFAULT '',
    assigned_to      TEXT NOT NULL DEFAULT '',

    -- Current document location for atomic-move discipline per §11.4.19
    current_location TEXT NOT NULL CHECK (current_location IN ('Issues', 'Fixed')) DEFAULT 'Issues',

    -- §11.4.93 byte-identical-round-trip mechanism: the verbatim raw Markdown
    -- block (Issues H2 item) or raw table row (Fixed) this item was parsed
    -- from. db→md regeneration concatenates these (interleaved with
    -- doc_segments raw prose) to reproduce the source byte-for-byte.
    body_md          TEXT,

    -- Representation discriminator (GAP A). The SAME ticket id can be present in
    -- the SAME tracker under TWO surface forms: a pipe-table closure ROW
    -- ('table') AND a detailed H2 SECTION ('section') — e.g. HXC-044 in Fixed.md.
    -- (atm_id, current_location) alone collided; the identity is therefore
    -- (atm_id, current_location, representation). Default 'section': CRUD-created
    -- items + every H2-form item are 'section'; only legacy pipe-table rows are
    -- 'table'. A DB materialised before this column carries the old 2-tuple PK
    -- and is rebuilt by migrateRepresentationColumn (lossless, idempotent).
    representation   TEXT NOT NULL DEFAULT 'section'
                     CHECK (representation IN ('section', 'table')),

    -- Per-item closure metadata (GAP B). Parsed FROM a Fixed.md pipe-table row
    -- (`| Closure | Title | Type | Status | Round | Commit(s) | Evidence |`) so
    -- db→md can SYNTHESIZE a pipe row from DB fields (not only replay raw
    -- body_md). NULL when the item has no pipe-table representation. Additive +
    -- nullable: existing rows are unaffected (migrateColumns ADDs them).
    closure_date     TEXT,
    round            TEXT,
    commit_ref       TEXT,

    -- §11.4.148/§11.4.149 sub-task hierarchy. A testing session against a parent
    -- item is itself a first-class workable item distinguished by a non-NULL
    -- parent_atm_id (the parent's id). session_ref is the human session label.
    -- NULL parent_atm_id = a top-level item. Back-compat: rows materialised under
    -- an older schema have these columns ADDed by migrateColumns (NULL = top-level).
    parent_atm_id    TEXT,
    session_ref      TEXT,

    -- Timestamps
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    last_modified    TEXT NOT NULL DEFAULT (datetime('now')),

    -- Composite identity: a ticket may be present in both trackers at once AND,
    -- within ONE tracker, under both a pipe-table row + an H2 section (GAP A).
    PRIMARY KEY (atm_id, current_location, representation)
);

-- NOTE: idx_items_parent (on items.parent_atm_id) is created in migrateColumns
-- AFTER the parent_atm_id column is ensured present — a CREATE INDEX here would
-- reference a not-yet-added column when an older (pre-v4) items table is opened.

-- ============================================================
-- §11.4.93 — item_history: append-only audit log
-- Covers §11.4.34 Reopened attribution + §11.4.90 Obsolete attribution +
-- §11.4.42 iteration discipline state transitions.
-- ============================================================
CREATE TABLE IF NOT EXISTS item_history (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    atm_id           TEXT NOT NULL,

    -- Event type — closed-set
    event_type       TEXT NOT NULL CHECK (event_type IN (
                         'Opened', 'Updated', 'Reopened',
                         'Fixed', 'Implemented', 'Completed', 'Obsolete'
                     )),

    -- §11.4.34 source attribution
    by               TEXT CHECK (by IN ('AI', 'User', NULL)),

    -- ISO date
    on_date          TEXT NOT NULL,

    -- §11.4.34 / §11.4.90 closed-set Reason vocabulary
    reason           TEXT,

    -- Captured-evidence per §11.4.5 — path to artefact under qa-results/ etc.
    evidence_path    TEXT,

    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_item_history_atm_id ON item_history(atm_id);
CREATE INDEX IF NOT EXISTS idx_item_history_event_type ON item_history(event_type);

-- ============================================================
-- §11.4.90 — obsolete_details: triple-check evidence for Obsolete items
-- ============================================================
CREATE TABLE IF NOT EXISTS obsolete_details (
    atm_id                  TEXT PRIMARY KEY,

    -- ISO date of obsolescence determination
    since                   TEXT NOT NULL,

    -- §11.4.90 closed-set Reason vocabulary
    -- 'not-reproducible' = a reported defect that does NOT reproduce on the
    -- canonical tree/baseline (environment / isolated-worktree artifact), not a
    -- real product defect; triple_check_evidence captures the non-reproduction.
    reason                  TEXT NOT NULL CHECK (reason IN (
                                'superseded-by-design-change',
                                'superseded-by-later-mandate',
                                'feature-removed',
                                'duplicate-of',
                                'unsupported-topology',
                                'not-reproducible'
                            )),

    -- §-letter / ATM-NNN reference of the work that obsoleted this item
    superseding_item        TEXT NOT NULL,

    -- §11.4.90 triple-check: positive captured evidence (NOT bare assertion)
    triple_check_evidence   TEXT NOT NULL
);

-- ============================================================
-- §11.4.21 — operator_block_details: when Status=Operator-blocked
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_block_details (
    atm_id                       TEXT PRIMARY KEY,
    what                         TEXT NOT NULL,
    why_exhausted_alternatives   TEXT NOT NULL,
    unblock_condition            TEXT NOT NULL,
    who                          TEXT
);

-- ============================================================
-- §11.4.47 — firebase_metadata: per-item Firebase-sourced telemetry
-- ============================================================
CREATE TABLE IF NOT EXISTS firebase_metadata (
    atm_id                 TEXT PRIMARY KEY,
    firebase_issue_ids     TEXT,           -- JSON array
    firebase_url           TEXT,
    stacktrace_cluster_hash TEXT,
    kpi                    TEXT,           -- Performance KPI ref
    funnel                 TEXT            -- Analytics funnel ref
);

-- ============================================================
-- §11.4.93 — doc_segments: ordered byte-identical-round-trip ledger
--
-- Each source document (Issues.md / Fixed.md) is decomposed into an
-- ordered sequence of segments. A segment is either:
--   kind='item' — a parsed workable item; raw text lives in items.body_md,
--                 referenced by atm_id. (Queryable + validatable.)
--   kind='raw'  — verbatim prose (preamble, prefix-convention section,
--                 inter-item separators, table header/footer) that is NOT
--                 a workable item; raw text lives in `raw`.
--
-- db→md walks this table in (document, seq) order, emitting raw segments
-- verbatim and item segments from items.body_md — reproducing the source
-- byte-for-byte (modulo trailing whitespace tolerance).
-- ============================================================
CREATE TABLE IF NOT EXISTS doc_segments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    document    TEXT NOT NULL CHECK (document IN ('Issues', 'Fixed')),
    seq         INTEGER NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('item', 'raw')),
    atm_id      TEXT,          -- set when kind='item' (FK-ish to items.atm_id)
    -- Which item REPRESENTATION this segment points to (GAP A): a 'table' segment
    -- references the pipe-table row, a 'section' segment the H2 block, so the
    -- renderer disambiguates when the SAME atm_id has both in one document.
    -- Default 'section' (raw segments + legacy DBs); raw segments ignore it.
    representation TEXT NOT NULL DEFAULT 'section',
    raw         TEXT,          -- set when kind='raw'
    UNIQUE(document, seq)
);

CREATE INDEX IF NOT EXISTS idx_doc_segments_document ON doc_segments(document);

-- ============================================================
-- §11.4.149 — test_diary: append-only per-item testing diary.
--
-- One row per TEST RUN against an item / ATM-NNN-SSS sub-task. Distinct from
-- item_history (lifecycle STATE transitions): the diary records test EXECUTIONS
-- (which may or may not change status). The diary is the in-depth forensic
-- record; test_diary_summary is the DERIVED at-a-glance rollup (never a second
-- source of truth — §11.4.93).
--
-- §11.4.149 PASS-requires-evidence: the CHECK makes a PASS row with an empty /
-- NULL evidence_path IMPOSSIBLE at the storage layer — a PASS-bluff is rejected
-- by the schema itself, independent of any CLI guard.
-- ============================================================
CREATE TABLE IF NOT EXISTS test_diary (
    entry_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    atm_id         TEXT NOT NULL,
    date_time      TEXT NOT NULL,            -- ISO-8601 UTC
    tested_by      TEXT NOT NULL CHECK (tested_by IN ('User', 'Operator', 'AI-agent', 'HelixQA')),
    result         TEXT NOT NULL CHECK (result IN ('PASS', 'FAIL', 'SKIP')),
    result_detail  TEXT,
    observations   TEXT NOT NULL,
    action_taken   TEXT NOT NULL,
    status_changed INTEGER NOT NULL DEFAULT 0,
    status_from    TEXT,
    status_to      TEXT,
    evidence_path  TEXT,                     -- §11.4.69 captured-evidence path
    feature_class  TEXT,                     -- §11.4.69 sink-side feature class
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    -- §11.4.149: a PASS run MUST cite captured evidence.
    CHECK (result <> 'PASS' OR (evidence_path IS NOT NULL AND evidence_path <> ''))
);

CREATE INDEX IF NOT EXISTS idx_test_diary_atm_id ON test_diary(atm_id);

-- Derived at-a-glance rollup per item (§11.4.149(b)). last_result is the result
-- of the newest run (by date_time, then entry_id).
CREATE VIEW IF NOT EXISTS test_diary_summary AS
SELECT
    d.atm_id                                                   AS atm_id,
    COUNT(*)                                                   AS total_runs,
    SUM(CASE WHEN d.result = 'PASS' THEN 1 ELSE 0 END)         AS pass_runs,
    SUM(CASE WHEN d.result = 'FAIL' THEN 1 ELSE 0 END)         AS fail_runs,
    SUM(CASE WHEN d.result = 'SKIP' THEN 1 ELSE 0 END)         AS skip_runs,
    MAX(d.date_time)                                           AS last_run,
    (SELECT l.result FROM test_diary l WHERE l.atm_id = d.atm_id
        ORDER BY l.date_time DESC, l.entry_id DESC LIMIT 1)    AS last_result,
    SUM(d.status_changed)                                      AS status_changes,
    (SELECT GROUP_CONCAT(t) FROM (SELECT DISTINCT tested_by AS t
        FROM test_diary WHERE atm_id = d.atm_id ORDER BY t))   AS testers,
    (SELECT GROUP_CONCAT(c) FROM (SELECT DISTINCT feature_class AS c
        FROM test_diary WHERE atm_id = d.atm_id AND feature_class IS NOT NULL
        AND feature_class <> '' ORDER BY c))                   AS feature_classes
FROM test_diary d
GROUP BY d.atm_id;

-- ============================================================
-- meta: schema version + sync state
-- ============================================================
CREATE TABLE IF NOT EXISTS meta (
    key                  TEXT PRIMARY KEY,
    value                TEXT NOT NULL,
    last_modified        TEXT NOT NULL DEFAULT (datetime('now'))
);

-- INSERT OR IGNORE (NOT OR REPLACE): the schema is re-exec'd on every openDB, so
-- OR REPLACE would clobber live sync state ('last_sync_direction' etc.) back to
-- the seed values on every re-open. OR IGNORE seeds these keys ONLY when absent
-- (first materialisation), preserving subsequent sync updates. migrateColumns
-- advances 'schema_version' to '5' on an older DB; a fresh DB is seeded '5' here.
INSERT OR IGNORE INTO meta(key, value) VALUES
    ('schema_version', '5'),
    ('last_sync_direction', 'none'),
    ('last_sync_timestamp', ''),
    ('integrity_hash', '');
