// obsolete_test.go — anti-bluff coverage for the §11.4.90 obsolete_details
// write-path + the `not-reproducible` closed-set reason extension.
//
// Every test drives the REAL SQLite driver + real subcommands (no mocks). The
// decisive anti-bluff assertions:
//   (1) the schema CHECK now ACCEPTS `not-reproducible` via obsoleteDetailsCmd —
//       the row is written and reads back exactly (proving the value is live);
//   (2) a GARBAGE reason is REJECTED by the Go closed-set guard AND, going
//       straight to SQL, by the CHECK constraint itself (the paired §1.1 check —
//       proving the constraint is not a no-op that accepts anything);
//   (3) obsolete-details on a non-Obsolete item FAILs (the row is meaningless
//       without the terminal status);
//   (4) a DB carrying the OLD 5-value CHECK is rebuilt by openDB so the new value
//       becomes insertable (the migration is real, not assumed).
package main

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
)

// addThenObsolete adds an Issues item and closes it Obsolete, returning once the
// item is in Fixed with status `Obsolete (→ Fixed.md)`.
//
// It returns the evidence root it created (HXC-224): the caller materialises
// its OWN obsolete-details evidence literals under the SAME root, so a single
// $PWD anchor resolves every artefact this test records.
func addThenObsolete(t *testing.T, dbPath, id string) string {
	t.Helper()
	evRoot := newEvidenceRoot(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "obsoletable item " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "Medium",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}
	if code := closeCmd([]string{
		id, "--db", dbPath, "--status", "obsolete",
		"--evidence", materialiseEvidence(t, evRoot, "docs/qa/"+id+"/evidence.md"),
	}); code != exitOK {
		t.Fatalf("close %s --status obsolete exited %d, want %d", id, code, exitOK)
	}
	return evRoot
}

// TestObsoleteDetails_NotReproducible_Accepted is the headline anti-bluff proof:
// the CHECK now accepts `not-reproducible` and the row round-trips.
func TestObsoleteDetails_NotReproducible_Accepted(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	evRoot := addThenObsolete(t, dbPath, "ATM-901")

	if code := obsoleteDetailsCmd([]string{
		"ATM-901", "--db", dbPath,
		"--since", "2026-06-09",
		"--reason", "not-reproducible",
		"--superseding", "none",
		"--evidence", materialiseEvidence(t, evRoot, "docs/qa/ATM-901/evidence.md"),
	}); code != exitOK {
		t.Fatalf("obsolete-details exited %d, want %d (CHECK rejected not-reproducible?)", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("reopen db: %v", err)
	}
	defer db.Close()
	var since, reason, sup, ev string
	if err := db.QueryRow(`SELECT since, reason, superseding_item, triple_check_evidence
		FROM obsolete_details WHERE atm_id='ATM-901'`).Scan(&since, &reason, &sup, &ev); err != nil {
		t.Fatalf("read back obsolete_details row: %v", err)
	}
	if reason != "not-reproducible" {
		t.Fatalf("reason=%q, want not-reproducible", reason)
	}
	if since != "2026-06-09" || sup != "none" || ev != "docs/qa/ATM-901/evidence.md" {
		t.Fatalf("row mismatch: since=%q sup=%q ev=%q", since, sup, ev)
	}

	// §11.4.90: the rendered body MUST carry the **Obsolete-Details:** line within
	// the heading meta block, so a db-to-md regen surfaces it.
	var body string
	if err := db.QueryRow(`SELECT body_md FROM items WHERE atm_id='ATM-901'`).Scan(&body); err != nil {
		t.Fatalf("read body_md: %v", err)
	}
	if !strings.Contains(body, "**Obsolete-Details:**") || !strings.Contains(body, "Reason: not-reproducible") {
		t.Fatalf("body_md missing §11.4.90 Obsolete-Details line:\n%s", body)
	}
	// Idempotent: a second run must not duplicate the line.
	if code := obsoleteDetailsCmd([]string{
		"ATM-901", "--db", dbPath, "--since", "2026-06-09",
		"--reason", "not-reproducible", "--superseding", "none",
		"--evidence", materialiseEvidence(t, evRoot, "docs/qa/ATM-901/evidence.md"),
	}); code != exitOK {
		t.Fatalf("second obsolete-details exited %d", code)
	}
	if err := db.QueryRow(`SELECT body_md FROM items WHERE atm_id='ATM-901'`).Scan(&body); err != nil {
		t.Fatalf("re-read body_md: %v", err)
	}
	if n := strings.Count(body, "**Obsolete-Details:**"); n != 1 {
		t.Fatalf("Obsolete-Details line count = %d, want 1 (idempotency broken)", n)
	}
}

// TestObsoleteDetails_GarbageReason_Rejected is the paired §1.1 check: a reason
// outside the closed-set is rejected by the Go guard...
func TestObsoleteDetails_GarbageReason_Rejected(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	evRoot := addThenObsolete(t, dbPath, "ATM-902")

	if code := obsoleteDetailsCmd([]string{
		"ATM-902", "--db", dbPath,
		"--since", "2026-06-09",
		"--reason", "totally-made-up-reason",
		"--superseding", "none",
		// HXC-224: a REAL artefact, so the refusal below is the closed-set reason
		// guard firing — not the record-time evidence guard masking it.
		"--evidence", materialiseEvidence(t, evRoot, "docs/qa/ATM-902/evidence.md"),
	}); code == exitOK {
		t.Fatalf("obsolete-details accepted a garbage reason (want non-zero exit)")
	}
}

// TestObsoleteDetailsCheck_RejectsGarbage_AtSQLLayer proves the CHECK constraint
// itself (not only the Go guard) rejects a non-closed-set reason — so a direct
// INSERT cannot bypass the vocabulary. This is the constraint-is-not-a-no-op half.
func TestObsoleteDetailsCheck_RejectsGarbage_AtSQLLayer(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()

	// not-reproducible MUST insert (the new value is live).
	if _, err := db.Exec(`INSERT INTO obsolete_details
		(atm_id, since, reason, superseding_item, triple_check_evidence)
		VALUES ('ATM-903','2026-06-09','not-reproducible','none','e.md')`); err != nil {
		t.Fatalf("CHECK rejected not-reproducible: %v", err)
	}
	// A garbage reason MUST be rejected by the CHECK.
	if _, err := db.Exec(`INSERT INTO obsolete_details
		(atm_id, since, reason, superseding_item, triple_check_evidence)
		VALUES ('ATM-904','2026-06-09','garbage-value','none','e.md')`); err == nil {
		t.Fatalf("CHECK accepted a garbage reason (want constraint violation)")
	}
}

// TestObsoleteDetails_NonObsoleteItem_Rejected proves the write-path refuses an
// item that is not in the terminal Obsolete status.
func TestObsoleteDetails_NonObsoleteItem_Rejected(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	if code := addCmd([]string{
		"--db", dbPath, "--id", "ATM-905",
		"--title", "open bug",
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "Medium",
	}); code != exitOK {
		t.Fatalf("add exited %d", code)
	}
	if code := obsoleteDetailsCmd([]string{
		"ATM-905", "--db", dbPath,
		"--since", "2026-06-09", "--reason", "not-reproducible",
		// HXC-224: a REAL artefact, so the refusal below is the non-Obsolete-item
		// guard firing — not the record-time evidence guard masking it.
		"--superseding", "none", "--evidence", materialiseEvidence(t, newEvidenceRoot(t), "e.md"),
	}); code == exitOK {
		t.Fatalf("obsolete-details accepted a non-Obsolete item (want non-zero exit)")
	}
}

// TestMigrateObsoleteReasonCheck_UpgradesOldDB materialises a DB with the OLD
// 5-value CHECK (no not-reproducible), then proves openDB rebuilds it so the new
// value becomes insertable while existing rows are preserved.
func TestMigrateObsoleteReasonCheck_UpgradesOldDB(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "old.db")

	// Hand-create a legacy obsolete_details table carrying the OLD CHECK + one row.
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open raw: %v", err)
	}
	if _, err := raw.Exec(`CREATE TABLE obsolete_details (
		atm_id TEXT PRIMARY KEY,
		since TEXT NOT NULL,
		reason TEXT NOT NULL CHECK (reason IN (
			'superseded-by-design-change','superseded-by-later-mandate',
			'feature-removed','duplicate-of','unsupported-topology')),
		superseding_item TEXT NOT NULL,
		triple_check_evidence TEXT NOT NULL)`); err != nil {
		t.Fatalf("create legacy table: %v", err)
	}
	if _, err := raw.Exec(`INSERT INTO obsolete_details VALUES
		('ATM-OLD','2026-01-01','feature-removed','§X','legacy.md')`); err != nil {
		t.Fatalf("seed legacy row: %v", err)
	}
	// Sanity: the legacy CHECK must reject not-reproducible BEFORE migration.
	if _, err := raw.Exec(`INSERT INTO obsolete_details VALUES
		('ATM-PRE','2026-06-09','not-reproducible','none','e.md')`); err == nil {
		t.Fatalf("legacy CHECK unexpectedly accepted not-reproducible (test premise broken)")
	}
	raw.Close()

	// openDB MUST detect the old CHECK and rebuild the table.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB migrate: %v", err)
	}
	defer db.Close()

	// Legacy row preserved.
	var reason string
	if err := db.QueryRow(`SELECT reason FROM obsolete_details WHERE atm_id='ATM-OLD'`).Scan(&reason); err != nil {
		t.Fatalf("legacy row lost after migration: %v", err)
	}
	if reason != "feature-removed" {
		t.Fatalf("legacy reason=%q, want feature-removed", reason)
	}
	// New value now insertable post-migration.
	if _, err := db.Exec(`INSERT INTO obsolete_details VALUES
		('ATM-NEW','2026-06-09','not-reproducible','none','e.md')`); err != nil {
		t.Fatalf("post-migration CHECK still rejects not-reproducible: %v", err)
	}
}
