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

    -- Timestamps
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    last_modified    TEXT NOT NULL DEFAULT (datetime('now')),

    -- Composite identity: a ticket may be present in both trackers at once.
    PRIMARY KEY (atm_id, current_location)
);

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
    raw         TEXT,          -- set when kind='raw'
    UNIQUE(document, seq)
);

CREATE INDEX IF NOT EXISTS idx_doc_segments_document ON doc_segments(document);

-- ============================================================
-- meta: schema version + sync state
-- ============================================================
CREATE TABLE IF NOT EXISTS meta (
    key                  TEXT PRIMARY KEY,
    value                TEXT NOT NULL,
    last_modified        TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO meta(key, value) VALUES
    ('schema_version', '3'),
    ('last_sync_direction', 'none'),
    ('last_sync_timestamp', ''),
    ('integrity_hash', '');
