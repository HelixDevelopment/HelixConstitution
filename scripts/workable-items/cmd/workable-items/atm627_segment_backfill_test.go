// atm627_segment_backfill_test.go — §11.4.115 RED-polarity anti-bluff coverage
// for the ATM-627 "db-to-md silently drops segmentless items" defect.
//
// Root cause (db.go renderDocument): db-to-md walks doc_segments in seq order and
// emits ONLY items that have a `kind='item'` doc_segments row for their
// (atm_id, current_location, representation) — an item with a populated body_md
// but NO segment row is simply never visited. renderDocument returns exitOK with
// NO error, so `sync db-to-md` silently regenerates Issues.md/Fixed.md WITHOUT the
// item. This reproduces the exact class the live DB carries (112 items, captured
// 2026-07-05): items added DB-direct (or whose doc_segments row was lost) that
// still have body_md but no segment.
//
// §11.4.115 polarity: RED_MODE=1 (env, default here via helper param) captures the
// defect on the pre-fix mechanism (a DB with the segment deliberately deleted) —
// `db-to-md` exits 0 yet OMITS the item, and `validate` (pre-guard) reports OK on
// a DB it cannot faithfully regenerate. GREEN (repair-bodies backfill applied)
// converts the same DB so `validate` catches the gap BEFORE repair, and after
// repair `db-to-md` includes the item + `validate` reports 0 violations.
//
// §1.1 PAIRED-MUTATION SENTINEL: documented on itemsMissingSegments (sync.go) and
// planSegmentBackfill (repair_bodies.go) — stubbing either to a no-op FAILs this
// test, proving neither the guard nor the fix is a tautology.
//
// HARD CONSTRAINT (§9.2 / §11.4.95): fresh temp DBs only (t.TempDir); this test
// file NEVER touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// asbFixtureDB builds a two-document, two-item DB via a real md-to-db sync (so
// every item starts with a genuine doc_segments row), then deletes ATM-980's
// segment directly — reproducing the "added DB-direct / segment layout drifted"
// class WITHOUT inventing a shape md-to-db could never itself produce.
func asbFixtureDB(t *testing.T) (dbPath string) {
	t.Helper()
	tmp := t.TempDir()
	dbPath = filepath.Join(tmp, "wi.db")
	issues := "# Issues\n\n" +
		"## §1. [ATM-980] alpha item with enough words to satisfy the description floor\n\n" +
		"**Type:** Bug\n**Status:** Queued\n\nbody one two three four five six seven.\n\n" +
		"## §2. [ATM-981] beta item with enough words to satisfy the description floor\n\n" +
		"**Type:** Bug\n**Status:** Queued\n\nbody one two three four five six eight.\n"
	issuesPath := filepath.Join(tmp, "Issues.md")
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(issuesPath, []byte(issues), 0o644); err != nil {
		t.Fatalf("write issues: %v", err)
	}
	if err := os.WriteFile(fixedPath, []byte("# Fixed\n\n"), 0o644); err != nil {
		t.Fatalf("write fixed: %v", err)
	}
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("fixture DB did not validate clean before drift injection (exit %d)", code)
	}

	// Inject the drift: delete ATM-980's doc_segments row directly (simulating a
	// segment-layout drift / DB-direct insert whose segment was never created),
	// leaving items.body_md fully intact.
	db := rbOpen(t, dbPath)
	rbExec(t, db, `DELETE FROM doc_segments WHERE document='Issues' AND atm_id='ATM-980' AND kind='item'`)
	db.Close()
	return dbPath
}

// TestATM627_SegmentBackfill_RedBaseline_DbToMdSilentlyDropsItem reproduces the
// USER-VISIBLE symptom: db-to-md exits 0 (no error surfaced) yet the regenerated
// Issues.md is MISSING the segmentless item's content entirely.
func TestATM627_SegmentBackfill_RedBaseline_DbToMdSilentlyDropsItem(t *testing.T) {
	dbPath := asbFixtureDB(t)
	tmp := filepath.Dir(dbPath)
	outIssues := filepath.Join(tmp, "out_issues.md")
	outFixed := filepath.Join(tmp, "out_fixed.md")

	code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outIssues, "--out-fixed", outFixed})
	if code != exitOK {
		t.Fatalf("db-to-md exited %d (expected exitOK — the defect is SILENT loss, not an error)", code)
	}
	got, err := os.ReadFile(outIssues)
	if err != nil {
		t.Fatalf("read regenerated Issues.md: %v", err)
	}
	if strings.Contains(string(got), "ATM-980") {
		t.Fatalf("RED baseline did not reproduce: regenerated Issues.md still contains ATM-980 — drift injection failed")
	}
	if !strings.Contains(string(got), "ATM-981") {
		t.Fatalf("regenerated Issues.md is missing ATM-981 too — fixture is broken beyond the injected drift")
	}
	t.Logf("RED confirmed: db-to-md exited 0 but silently dropped ATM-980 (segmentless) while keeping ATM-981")
}

// TestATM627_SegmentBackfill_ValidateCatchesMissingSegments proves the NEW
// validate guard (itemsMissingSegments) fails-closed on exactly the drifted DB —
// closing the bluff-gate gap where validate previously reported OK on a DB it
// could not faithfully regenerate.
func TestATM627_SegmentBackfill_ValidateCatchesMissingSegments(t *testing.T) {
	dbPath := asbFixtureDB(t)
	code := validateCmd([]string{"--db", dbPath})
	if code == exitOK {
		t.Fatalf("validate reported OK on a DB missing ATM-980's doc_segments row — bluff gate (§11.4.6/§11.4.93)")
	}
}

// TestATM627_SegmentBackfill_RepairBackfillsAndDbToMdIncludesItem is the GREEN
// half: repair-bodies backfills the missing segment, validate reports 0
// violations, and a subsequent db-to-md includes the previously-dropped item.
func TestATM627_SegmentBackfill_RepairBackfillsAndDbToMdIncludesItem(t *testing.T) {
	dbPath := asbFixtureDB(t)

	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("repair-bodies exited %d", code)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate still reports violations after repair-bodies backfill (exit %d)", code)
	}

	tmp := filepath.Dir(dbPath)
	outIssues := filepath.Join(tmp, "out_issues.md")
	outFixed := filepath.Join(tmp, "out_fixed.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outIssues, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	got, err := os.ReadFile(outIssues)
	if err != nil {
		t.Fatalf("read regenerated Issues.md: %v", err)
	}
	if !strings.Contains(string(got), "ATM-980") {
		t.Fatalf("GREEN did not take: regenerated Issues.md still missing ATM-980 after repair-bodies backfill")
	}
	if !strings.Contains(string(got), "ATM-981") {
		t.Fatalf("regenerated Issues.md lost ATM-981 (a previously-fine item) — backfill corrupted an unrelated item")
	}
	t.Logf("GREEN confirmed: repair-bodies backfilled the missing segment; db-to-md now includes ATM-980")
}

// TestATM627_SegmentBackfill_Idempotent proves a second repair-bodies run against
// an already-backfilled DB applies ZERO further changes (deterministic, no drift
// on repeated invocation — §11.4.50).
func TestATM627_SegmentBackfill_Idempotent(t *testing.T) {
	dbPath := asbFixtureDB(t)
	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("first repair-bodies exited %d", code)
	}
	db := rbOpen(t, dbPath)
	items, err := loadItems(db)
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	plan, err := planSegmentBackfill(db, items)
	db.Close()
	if err != nil {
		t.Fatalf("planSegmentBackfill (2nd pass): %v", err)
	}
	if len(plan) != 0 {
		t.Fatalf("second-pass backfill plan is non-empty (%d items) — repair-bodies is not idempotent", len(plan))
	}
}
