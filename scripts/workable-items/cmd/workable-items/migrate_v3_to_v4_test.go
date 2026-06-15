// migrate_v3_to_v4_test.go — §11.4.149 schema v3→v4 migration unit tests.
//
// Proves the migration is NON-DESTRUCTIVE: a DB materialised under an OLDER
// schema (items table WITHOUT parent_atm_id / session_ref) is brought up to v4
// by openDB→migrateColumns with every pre-existing row preserved + backfilled as
// top-level (parent_atm_id IS NULL), schema_version advanced to '4', and the new
// test_diary table + view + indexes present.
package main

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// makeV3LikeDB hand-builds a DB whose `items` table predates the v4 columns
// (the shape an older schema_version produced), seeds rows, and stamps
// schema_version='3'. This is the artifact migrateColumns must upgrade.
func makeV3LikeDB(t *testing.T) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "v3.db")
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open raw: %v", err)
	}
	defer raw.Close()
	ddl := `
CREATE TABLE items (
  atm_id TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  severity TEXT,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  forensic_anchor TEXT,
  closure_criteria TEXT,
  composes_with TEXT,
  created_by TEXT NOT NULL DEFAULT '',
  assigned_to TEXT NOT NULL DEFAULT '',
  current_location TEXT NOT NULL DEFAULT 'Issues',
  body_md TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (atm_id, current_location)
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL, last_modified TEXT NOT NULL DEFAULT (datetime('now')));
INSERT INTO meta(key,value) VALUES ('schema_version','3'),('last_sync_direction','md-to-db'),('last_sync_timestamp','2026-06-09T00:00:00Z'),('integrity_hash','abc');
INSERT INTO items(atm_id,type,status,title,description,current_location) VALUES
  ('ATM-001','Bug','Queued','t1','desc one with enough words here for floor','Issues'),
  ('ATM-002','Task','In progress','t2','desc two with enough words here for floor','Issues'),
  ('ATM-003','Feature','Fixed (→ Fixed.md)','t3','desc three with enough words here floor','Fixed');
`
	if _, err := raw.Exec(ddl); err != nil {
		t.Fatalf("seed v3 DDL: %v", err)
	}
	return dbPath
}

func TestMigrateV3ToV4NonDestructive(t *testing.T) {
	dbPath := makeV3LikeDB(t)

	// Pre-condition: items has no parent_atm_id, schema_version=3.
	if cols := pragmaCols(t, dbPath); cols["parent_atm_id"] {
		t.Fatalf("pre-migration items unexpectedly has parent_atm_id")
	}
	if v := metaVal(t, dbPath, "schema_version"); v != "3" {
		t.Fatalf("pre schema_version = %q, want 3", v)
	}

	// openDB runs the embedded schema (IF NOT EXISTS no-ops) + migrateColumns.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (migrate): %v", err)
	}
	defer db.Close()

	// Rows preserved: still 3, every one backfilled top-level (parent_atm_id NULL).
	var total, topLevel int
	_ = db.QueryRow(`SELECT COUNT(*) FROM items`).Scan(&total)
	_ = db.QueryRow(`SELECT COUNT(*) FROM items WHERE parent_atm_id IS NULL`).Scan(&topLevel)
	if total != 3 {
		t.Fatalf("post-migration item count = %d, want 3 (no rows lost)", total)
	}
	if topLevel != 3 {
		t.Fatalf("top-level (NULL parent) count = %d, want 3 (backfill)", topLevel)
	}

	// schema_version advanced to 4.
	var ver string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
	if ver != "4" {
		t.Fatalf("post schema_version = %q, want 4", ver)
	}

	// Live sync state preserved (INSERT OR IGNORE did NOT clobber it).
	var lastDir string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='last_sync_direction'`).Scan(&lastDir)
	if lastDir != "md-to-db" {
		t.Fatalf("last_sync_direction = %q, want md-to-db (preserved across re-open)", lastDir)
	}

	// New v4 columns present.
	cols := pragmaColsDB(t, db)
	for _, c := range []string{"parent_atm_id", "session_ref"} {
		if !cols[c] {
			t.Errorf("post-migration items missing column %s", c)
		}
	}

	// test_diary table + view + indexes present.
	for _, obj := range []string{"test_diary", "test_diary_summary", "idx_items_parent", "idx_test_diary_atm_id"} {
		var n int
		_ = db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name=?`, obj).Scan(&n)
		if n != 1 {
			t.Errorf("expected schema object %q present after migration", obj)
		}
	}

	// integrity_check ok.
	var ic string
	_ = db.QueryRow(`PRAGMA integrity_check`).Scan(&ic)
	if ic != "ok" {
		t.Fatalf("integrity_check = %q, want ok", ic)
	}
}

func TestMigrateIdempotent(t *testing.T) {
	dbPath := makeV3LikeDB(t)
	for i := 0; i < 3; i++ {
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB #%d: %v", i, err)
		}
		var ver string
		_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
		if ver != "4" {
			t.Fatalf("re-open #%d schema_version = %q, want 4", i, ver)
		}
		var total int
		_ = db.QueryRow(`SELECT COUNT(*) FROM items`).Scan(&total)
		if total != 3 {
			t.Fatalf("re-open #%d item count = %d, want 3", i, total)
		}
		db.Close()
	}
}

// ---- helpers ----

func pragmaCols(t *testing.T, dbPath string) map[string]bool {
	t.Helper()
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer raw.Close()
	return pragmaColsDB(t, raw)
}

func pragmaColsDB(t *testing.T, db *sql.DB) map[string]bool {
	t.Helper()
	rows, err := db.Query(`PRAGMA table_info(items)`)
	if err != nil {
		t.Fatalf("pragma: %v", err)
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var dflt any
		if err := rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk); err != nil {
			t.Fatalf("scan: %v", err)
		}
		cols[name] = true
	}
	return cols
}

func metaVal(t *testing.T, dbPath, key string) string {
	t.Helper()
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer raw.Close()
	var v string
	_ = raw.QueryRow(`SELECT value FROM meta WHERE key=?`, key).Scan(&v)
	return v
}
