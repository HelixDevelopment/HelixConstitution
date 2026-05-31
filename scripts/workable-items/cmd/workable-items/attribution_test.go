// attribution_test.go — §11.4.104 anti-bluff coverage for the participant
// attribution columns (created_by + assigned_to).
//
// Every test exercises the REAL SQLite driver + real parser + real renderer
// (no mocks). The decisive anti-bluff assertions:
//   (1) a fixture WITH the attribution fields round-trips BYTE-IDENTICAL through
//       md→db→md AND the parsed columns carry the exact handles;
//   (2) a LEGACY fixture WITHOUT the fields round-trips BYTE-IDENTICAL — no empty
//       Created-By/Assigned-To lines are ever injected, and the columns are "";
//   (3) add --created-by/--assigned-to persists the columns + emits the MD lines;
//   (4) close preserves the columns across the Issues→Fixed atomic move;
//   (5) validate accepts empty attribution (legacy) AND populated attribution;
//   (6) report --by-assigned / --by-creator reflect real DB state;
//   (7) an OLD (pre-§11.4.104) DB is migrated forward losslessly by openDB.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// roundTripFixture writes fixture content into a temp Issues.md, syncs md→db,
// regenerates db→md, and returns (orig, regen) for byte comparison plus the DB
// path so the caller can assert parsed column values.
func roundTripFixture(t *testing.T, fixture string) (orig, regen, dbPath string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("testdata", fixture))
	if err != nil {
		t.Fatalf("read fixture %s: %v", fixture, err)
	}
	tmp := t.TempDir()
	inIssues := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(inIssues, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath = filepath.Join(tmp, "workable_items.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", inIssues}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}
	outIssues := filepath.Join(tmp, "Issues.regen.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outIssues}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	regenBytes, err := os.ReadFile(outIssues)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw), string(regenBytes), dbPath
}

// TestAttribution_FixtureWithFields_RoundTripsByteIdentical proves a fixture that
// DOES carry Created-By/Assigned-To round-trips byte-identical AND the columns
// are parsed with the exact handles (no metadata-only bluff).
func TestAttribution_FixtureWithFields_RoundTripsByteIdentical(t *testing.T) {
	orig, regen, dbPath := roundTripFixture(t, "fx_attrib_with.md")

	if orig != regen {
		t.Errorf("fx_attrib_with.md NOT byte-identical after round-trip (orig=%d regen=%d bytes); %s",
			len(orig), len(regen), firstDiff(orig, regen))
	} else {
		t.Logf("fx_attrib_with.md round-trip: BYTE-IDENTICAL (%d bytes)", len(orig))
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	it, err := loadItem(db, "WIT-501", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-501 absent (err=%v)", err)
	}
	if it.CreatedBy != "@milos85vasic" {
		t.Errorf("WIT-501 created_by = %q, want @milos85vasic", it.CreatedBy)
	}
	if it.AssignedTo != "@someoneelse" {
		t.Errorf("WIT-501 assigned_to = %q, want @someoneelse", it.AssignedTo)
	}

	it2, err := loadItem(db, "WIT-502", "Issues")
	if err != nil || it2 == nil {
		t.Fatalf("WIT-502 absent (err=%v)", err)
	}
	if it2.CreatedBy != "Claude" {
		t.Errorf("WIT-502 created_by = %q, want Claude", it2.CreatedBy)
	}
	if it2.AssignedTo != "@milos85vasic" {
		t.Errorf("WIT-502 assigned_to = %q, want @milos85vasic", it2.AssignedTo)
	}
}

// TestAttribution_LegacyFixture_RoundTripsByteIdentical proves a legacy fixture
// WITHOUT the fields round-trips byte-identical AND the columns are empty — the
// renderer must NOT inject empty Created-By/Assigned-To lines that were not there.
func TestAttribution_LegacyFixture_RoundTripsByteIdentical(t *testing.T) {
	orig, regen, dbPath := roundTripFixture(t, "fx_attrib_legacy.md")

	if orig != regen {
		t.Errorf("fx_attrib_legacy.md NOT byte-identical after round-trip (orig=%d regen=%d bytes); %s",
			len(orig), len(regen), firstDiff(orig, regen))
	} else {
		t.Logf("fx_attrib_legacy.md round-trip: BYTE-IDENTICAL (%d bytes)", len(orig))
	}
	// No empty attribution lines may appear in the regenerated MD.
	if strings.Contains(regen, "**Created-By:**") {
		t.Error("legacy round-trip INJECTED a **Created-By:** line that did not exist in the source")
	}
	if strings.Contains(regen, "**Assigned-To:**") {
		t.Error("legacy round-trip INJECTED an **Assigned-To:** line that did not exist in the source")
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	for _, id := range []string{"WIT-601", "WIT-602"} {
		it, err := loadItem(db, id, "Issues")
		if err != nil || it == nil {
			t.Fatalf("%s absent (err=%v)", id, err)
		}
		if it.CreatedBy != "" || it.AssignedTo != "" {
			t.Errorf("%s legacy attribution non-empty: created_by=%q assigned_to=%q (want both empty)",
				id, it.CreatedBy, it.AssignedTo)
		}
	}

	// validate must accept empty (legacy) attribution.
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate REJECTED legacy empty-attribution DB (exit %d) — false positive", code)
	}
}

// TestAttribution_AddPersistsColumns proves `add --created-by/--assigned-to`
// writes the columns AND emits the canonical MD lines, and validate accepts it.
func TestAttribution_AddPersistsColumns(t *testing.T) {
	dbPath := newTestDB(t)
	code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-700",
		"--title", "item opened with explicit attribution",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the attribution add",
		"--created-by", "@reporter",
		"--assigned-to", "@milos85vasic",
		"Bug", "High",
	})
	if code != exitOK {
		t.Fatalf("add exited %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	it, err := loadItem(db, "WIT-700", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-700 absent (err=%v)", err)
	}
	if it.CreatedBy != "@reporter" {
		t.Errorf("created_by = %q, want @reporter", it.CreatedBy)
	}
	if it.AssignedTo != "@milos85vasic" {
		t.Errorf("assigned_to = %q, want @milos85vasic", it.AssignedTo)
	}
	if !strings.Contains(it.BodyMD, "**Created-By:** @reporter") {
		t.Errorf("body_md missing Created-By line:\n%s", it.BodyMD)
	}
	if !strings.Contains(it.BodyMD, "**Assigned-To:** @milos85vasic") {
		t.Errorf("body_md missing Assigned-To line:\n%s", it.BodyMD)
	}

	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate after attributed add exited %d (expected OK)", code)
	}
}

// TestAttribution_AddOmitsEmptyFields proves `add` with NO attribution flags
// emits NO Created-By/Assigned-To lines (back-compat: the default add path is
// byte-stable with the legacy renderer).
func TestAttribution_AddOmitsEmptyFields(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-701",
		"--title", "item opened without attribution flags",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the no-attribution add",
		"Task", "Low",
	}); code != exitOK {
		t.Fatalf("add exited %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	it, _ := loadItem(db, "WIT-701", "Issues")
	if it == nil {
		t.Fatal("WIT-701 absent")
	}
	if it.CreatedBy != "" || it.AssignedTo != "" {
		t.Errorf("unattributed add stored non-empty columns: created_by=%q assigned_to=%q", it.CreatedBy, it.AssignedTo)
	}
	if strings.Contains(it.BodyMD, "**Created-By:**") || strings.Contains(it.BodyMD, "**Assigned-To:**") {
		t.Errorf("unattributed add INJECTED empty attribution lines:\n%s", it.BodyMD)
	}
}

// TestAttribution_ClosePreservesColumns proves the Issues→Fixed atomic close
// carries created_by/assigned_to through unchanged, in both the columns and the
// regenerated Fixed body.
func TestAttribution_ClosePreservesColumns(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-800",
		"--title", "attributed item to be closed",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the attributed close",
		"--created-by", "@opener",
		"--assigned-to", "@assignee",
		"Bug", "Critical",
	}); code != exitOK {
		t.Fatalf("add exited %d", code)
	}
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "fixed",
		"--evidence", "docs/qa/WIT-800/run.md", "WIT-800",
	}); code != exitOK {
		t.Fatalf("close exited %d", code)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	fx, err := loadItem(db, "WIT-800", "Fixed")
	if err != nil || fx == nil {
		t.Fatalf("WIT-800 absent from Fixed (err=%v)", err)
	}
	if fx.CreatedBy != "@opener" {
		t.Errorf("after close created_by = %q, want @opener (attribution lost in move)", fx.CreatedBy)
	}
	if fx.AssignedTo != "@assignee" {
		t.Errorf("after close assigned_to = %q, want @assignee (attribution lost in move)", fx.AssignedTo)
	}
	if !strings.Contains(fx.BodyMD, "**Created-By:** @opener") {
		t.Errorf("closed body_md missing Created-By line:\n%s", fx.BodyMD)
	}
	if !strings.Contains(fx.BodyMD, "**Assigned-To:** @assignee") {
		t.Errorf("closed body_md missing Assigned-To line:\n%s", fx.BodyMD)
	}
}

// TestAttribution_ReportByAssignedAndCreator proves the new grouping views run
// against real data and the underlying group state is faithful.
func TestAttribution_ReportByAssignedAndCreator(t *testing.T) {
	dbPath := newTestDB(t)
	specs := []struct{ id, cb, at string }{
		{"WIT-901", "@alice", "@milos85vasic"},
		{"WIT-902", "@alice", "@bob"},
		{"WIT-903", "Claude", "@bob"},
	}
	for _, s := range specs {
		if code := addCmd([]string{
			"--db", dbPath, "--id", s.id,
			"--title", "report attribution seed item",
			"--description", "a sufficiently long description that clears the §11.4.91 floor for report attribution",
			"--created-by", s.cb, "--assigned-to", s.at,
			"Task", "Low",
		}); code != exitOK {
			t.Fatalf("seed %s exited %d", s.id, code)
		}
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	check := func(col, val string, want int) {
		var got int
		if err := db.QueryRow(`SELECT COUNT(1) FROM items WHERE `+col+`=?`, val).Scan(&got); err != nil {
			t.Fatalf("count %s=%s: %v", col, val, err)
		}
		if got != want {
			t.Errorf("%s=%s count = %d, want %d", col, val, got, want)
		}
	}
	check("created_by", "@alice", 2)
	check("created_by", "Claude", 1)
	check("assigned_to", "@bob", 2)
	check("assigned_to", "@milos85vasic", 1)

	for _, flag := range []string{"--by-assigned", "--by-creator"} {
		if code := reportCmd([]string{"--db", dbPath, flag}); code != exitOK {
			t.Errorf("report %s exited %d", flag, code)
		}
	}
}

// TestAttribution_MigratesOldDB proves an existing DB created WITHOUT the
// attribution columns (schema_version 2 shape) is migrated forward by openDB —
// the columns are ADDed, existing rows survive with empty defaults, and the
// attribution INSERT/SELECT paths then work. This is the forward-compatible
// ALTER path required by PART A item 1.
func TestAttribution_MigratesOldDB(t *testing.T) {
	tmp := t.TempDir()
	dbPath := filepath.Join(tmp, "old.db")

	// Build an OLD items table WITHOUT created_by/assigned_to, seed a row, close.
	old, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if _, err := old.Exec(`DROP TABLE items`); err != nil {
		t.Fatalf("drop: %v", err)
	}
	// Recreate the pre-§11.4.104 column set (no created_by/assigned_to).
	if _, err := old.Exec(`CREATE TABLE items (
		atm_id TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL,
		severity TEXT, title TEXT NOT NULL, description TEXT NOT NULL,
		forensic_anchor TEXT, closure_criteria TEXT, composes_with TEXT,
		current_location TEXT NOT NULL DEFAULT 'Issues', body_md TEXT,
		created_at TEXT NOT NULL DEFAULT (datetime('now')),
		last_modified TEXT NOT NULL DEFAULT (datetime('now')),
		PRIMARY KEY (atm_id, current_location))`); err != nil {
		t.Fatalf("recreate old items: %v", err)
	}
	if _, err := old.Exec(`INSERT INTO items
		(atm_id,type,status,title,description,current_location,body_md)
		VALUES ('OLD-001','Bug','Queued',
		'a legacy row predating the attribution columns entirely',
		'a legacy row predating the attribution columns entirely','Issues','## OLD-001 — x\n')`); err != nil {
		t.Fatalf("seed legacy row: %v", err)
	}
	old.Close()

	// Re-open: migrateColumns MUST add the two columns without data loss.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("re-open (migration) failed: %v", err)
	}
	defer db.Close()

	cols, err := itemColumns(db)
	if err != nil {
		t.Fatalf("itemColumns: %v", err)
	}
	if !cols["created_by"] || !cols["assigned_to"] {
		t.Fatalf("migration did NOT add attribution columns: %v", cols)
	}

	// Legacy row survived with empty attribution.
	it, err := loadItem(db, "OLD-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("OLD-001 lost across migration (err=%v)", err)
	}
	if it.CreatedBy != "" || it.AssignedTo != "" {
		t.Errorf("migrated legacy row has non-empty attribution: created_by=%q assigned_to=%q", it.CreatedBy, it.AssignedTo)
	}

	// The migrated DB now accepts an attributed add.
	if code := addCmd([]string{
		"--db", dbPath, "--id", "OLD-002",
		"--title", "attributed item added to a migrated DB",
		"--description", "a sufficiently long description that clears the §11.4.91 floor on the migrated DB",
		"--created-by", "@late", "--assigned-to", "@op",
		"Feature", "Medium",
	}); code != exitOK {
		t.Fatalf("attributed add on migrated DB exited %d", code)
	}
	a2, _ := loadItem(db, "OLD-002", "Issues")
	if a2 == nil || a2.CreatedBy != "@late" || a2.AssignedTo != "@op" {
		t.Fatalf("attributed add on migrated DB did not persist columns: %+v", a2)
	}
}
