// reopen_relocate_test.go — §11.4.115 RED-polarity regression guard for the
// ATM-627 INTEG-03 (location↔status) defect: `reopen` flipped status→Reopened but
// NEVER migrated current_location Fixed→Issues, leaving a reopened item stranded in
// Fixed with a NON-terminal status (a §11.4.15/§11.4.148 location↔status desync).
//
// DEFECT CLASS (FACT): the pre-fix reopenCmd did an in-place
// `UPDATE items SET status='Reopened', body_md=… WHERE atm_id=? AND current_location=?`
// with NO current_location change and NO doc_segment move — so reopening an item that
// lived in Fixed left it in Fixed (status=Reopened), its Fixed doc_segment intact, and
// `validate`'s new location↔status invariant would flag it. The keystone reconciliation
// (docs/research/atm627_db_docs_roundtrip_20260703/RECONCILIATION_PLAN.md) had to
// RELOCATE reopened items (ATM-393/398) to Issues by hand — this fix makes reopen do it.
//
// §11.4.115 polarity: DEFAULT (RED_MODE unset/"0") = standing GREEN guard (reopen of a
// Fixed item migrates it to Issues + moves its doc_segment + leaves validate clean).
// RED_MODE=1 asserts the PRE-FIX bluff (the reopened item STAYED in Fixed) — it FAILs on
// this fixed binary and PASSes only against a migration-absent build (the captured RED).
//
// §1.1 PAIRED MUTATION (meta_test_false_positive_proof.sh): revert the migration in
// mutate.go (force the reopen destination back to the source location) → this test +
// TestValidate_CatchesReopenedInFixed FAIL; restore → GREEN. Proves the fix + guard are
// not tautologies.
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"testing"
)

// seedFixedItem adds a fresh Issues item then closes it to Fixed via the REAL
// add + close paths, returning the item id. The resulting item lives at
// current_location='Fixed' with a Fixed doc_segment and a terminal status —
// exactly the shape a reopen must relocate.
func seedFixedItem(t *testing.T, dbPath, id string) {
	t.Helper()
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "a closed item that will be reopened later",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for reopen relocate",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("seed add %s: exit %d", id, code)
	}
	// HXC-217 (§11.4.120 reconciliation): the closure-evidence RESOLVABILITY
	// guard (unresolvableClosureEvidence, sync.go) now requires a closed item's
	// item_history.evidence_path to point at an artefact that actually EXISTS —
	// a closure claiming captured proof that cannot be produced on demand is a
	// §11.4.226(2) bluff. This seed previously passed a fabricated
	// `docs/qa/<id>/close.md`, which validate correctly rejects. The fixture is
	// reconciled to the NEW mechanism (land a real artefact, cite its path), NOT
	// by weakening the guard — the tests below assert the location↔status and
	// segment invariants, which are unaffected by which real path is cited.
	evidence := filepath.Join(t.TempDir(), "close.md")
	if err := os.WriteFile(evidence, []byte("captured closure evidence for "+id+"\n"), 0o644); err != nil {
		t.Fatalf("seed evidence for %s: %v", id, err)
	}
	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed",
		"--evidence", evidence, id}); code != exitOK {
		t.Fatalf("seed close %s: exit %d", id, code)
	}
}

// segCount returns the number of kind='item' doc_segments for id in document.
func segCount(t *testing.T, dbPath, document, id string) int {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var n int
	if err := db.QueryRow(`SELECT COUNT(1) FROM doc_segments WHERE document=? AND kind='item' AND atm_id=?`, document, id).Scan(&n); err != nil {
		t.Fatalf("segCount(%s,%s): %v", document, id, err)
	}
	return n
}

// TestReopenCmd_MigratesFixedItemToIssues is the KEYSTONE RED-polarity guard for
// INTEG-03: reopening a Fixed item MUST relocate it to Issues (row + doc_segment)
// because Reopened is non-terminal and non-terminal items belong in Issues.
func TestReopenCmd_MigratesFixedItemToIssues(t *testing.T) {
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-300")

	// Sanity: the item really is in Fixed before reopen.
	{
		db, _ := openDB(dbPath)
		fx, _ := loadItem(db, "WIT-300", "Fixed")
		db.Close()
		if fx == nil {
			t.Fatal("seed did not land WIT-300 in Fixed")
		}
	}

	// Pre-fix code returns exitUsage here: its reopen looks ONLY at the --location
	// source (default Issues) and cannot find the Fixed item at all. The fixed code
	// auto-detects the source, returns exitOK, and migrates Fixed→Issues. Both
	// outcomes are captured (never Fatal on the exit code) so the RED_MODE polarity
	// switch is robust across the pre-fix / fixed binaries.
	code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-300",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-07-11", "--incident", "qa-results/2026-07-11/wit-300-fail.log"})

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	inFixed, _ := loadItem(db, "WIT-300", "Fixed")
	inIssues, _ := loadItem(db, "WIT-300", "Issues")
	db.Close()

	migrated := code == exitOK && inFixed == nil && inIssues != nil && inIssues.Status == "Reopened"

	if assertPreFixBluff {
		// RED_MODE=1: assert the PRE-FIX behaviour — the default reopen did NOT
		// migrate the Fixed item to Issues (it errored out / stranded it). On the
		// fixed binary the item migrated, so this Fatal fires — the captured RED proof.
		if migrated {
			t.Fatalf("RED_MODE=1: WIT-300 migrated Fixed→Issues (code=%d) — fix present, pre-fix bluff no longer reproducible", code)
		}
		return
	}

	// GREEN guard: the reopened item migrated Fixed→Issues.
	if code != exitOK {
		t.Fatalf("reopenCmd exit = %d, want %d (default reopen must find + relocate a Fixed item)", code, exitOK)
	}
	if inFixed != nil {
		t.Fatalf("INTEG-03: WIT-300 still in Fixed after reopen (status=%q) — a non-terminal Reopened item stranded in Fixed", inFixed.Status)
	}
	if inIssues == nil {
		t.Fatal("INTEG-03: WIT-300 not migrated to Issues after reopen")
	}
	if inIssues.Status != "Reopened" {
		t.Errorf("migrated item status = %q, want Reopened", inIssues.Status)
	}
	// The doc_segment moved with the row (mirrors close, reversed).
	if s := segCount(t, dbPath, "Fixed", "WIT-300"); s != 0 {
		t.Errorf("Fixed doc_segment for WIT-300 not removed after reopen (%d)", s)
	}
	if s := segCount(t, dbPath, "Issues", "WIT-300"); s != 1 {
		t.Errorf("Issues doc_segment for WIT-300 missing after reopen (%d)", s)
	}
	// §11.4.34 attribution survived the relocation.
	db2, _ := openDB(dbPath)
	var n int
	db2.QueryRow(`SELECT COUNT(1) FROM item_history WHERE atm_id='WIT-300' AND event_type='Reopened' AND evidence_path='qa-results/2026-07-11/wit-300-fail.log'`).Scan(&n)
	db2.Close()
	if n != 1 {
		t.Errorf("Reopened history row absent after relocation (%d)", n)
	}
	// The migrated DB is location↔status consistent → validate PASSes.
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) on a correctly-relocated DB — relocation left a desync", code)
	}
}

// TestReopenCmd_IssuesItemStaysInIssues is the regression guard: reopening an item
// already in Issues (the common case) MUST leave it in Issues (no spurious move).
func TestReopenCmd_IssuesItemStaysInIssues(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "High",
		"an issues item to reopen in place",
		"a sufficiently long description that clears the §11.4.91 floor for the in-place reopen")

	if code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-001",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-07-11", "--incident", "qa-results/x.log"}); code != exitOK {
		t.Fatalf("reopenCmd exit %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	it, _ := loadItem(db, "WIT-001", "Issues")
	if it == nil || it.Status != "Reopened" {
		t.Fatalf("WIT-001 not Reopened-in-Issues after reopen (it=%v)", it)
	}
	if fx, _ := loadItem(db, "WIT-001", "Fixed"); fx != nil {
		t.Error("WIT-001 spuriously appeared in Fixed after an in-place reopen")
	}
	if s := segCount(t, dbPath, "Issues", "WIT-001"); s != 1 {
		t.Errorf("Issues doc_segment for WIT-001 = %d, want 1 (in-place reopen must not drop it)", s)
	}
}

// TestReopenCmd_LocationFixedOverrideKeepsInFixed proves the explicit
// `--location Fixed` operator override is still honored (the flag is not removed):
// the reopened item is kept in Fixed. This produces a location↔status state that
// `validate` will (correctly) flag — it is a deliberate operator escape hatch, not
// the default path.
func TestReopenCmd_LocationFixedOverrideKeepsInFixed(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-301")

	if code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-301",
		"--location", "Fixed",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-07-11", "--incident", "qa-results/y.log"}); code != exitOK {
		t.Fatalf("reopenCmd (--location Fixed) exit %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	fx, _ := loadItem(db, "WIT-301", "Fixed")
	if fx == nil {
		t.Fatal("--location Fixed override NOT honored — WIT-301 left Fixed")
	}
	if fx.Status != "Reopened" {
		t.Errorf("override item status = %q, want Reopened", fx.Status)
	}
	if it, _ := loadItem(db, "WIT-301", "Issues"); it != nil {
		t.Error("--location Fixed override still leaked WIT-301 into Issues")
	}
}

// TestValidate_CatchesReopenedInFixed is the INTEG-03 detective gate (§11.4.186
// INTEGRITY / location↔status family): a Fixed-location item with a NON-terminal
// status is a violation. A synced DB validates OK; injecting a non-terminal status
// at Fixed makes validate FAIL; restoring a terminal status clears it (specificity).
func TestValidate_CatchesReopenedInFixed(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-302") // Fixed + terminal status → clean.

	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate on a clean DB exited %d (want OK)", code)
	}

	// Inject a PURE location↔status desync, bypassing reopenCmd so the new guard is
	// exercised in isolation. Crucially the body_md `**Status:**` line is
	// canonicalized to the SAME non-terminal value as the column, so this does NOT
	// trip the pre-existing column↔body Status guard (check (e)) — ONLY the new
	// location↔status invariant (Fixed ⇒ terminal status) can catch it.
	db, _ := openDB(dbPath)
	var body string
	if err := db.QueryRow(`SELECT COALESCE(body_md,'') FROM items WHERE atm_id='WIT-302' AND current_location='Fixed'`).Scan(&body); err != nil {
		db.Close()
		t.Fatalf("read body: %v", err)
	}
	syncedBody := canonicalizeBodyStatusLine(body, "Reopened")
	res, err := db.Exec(`UPDATE items SET status='Reopened', body_md=? WHERE atm_id='WIT-302' AND current_location='Fixed'`, syncedBody)
	if err != nil {
		db.Close()
		t.Fatalf("inject desync: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		db.Close()
		t.Fatalf("inject desync affected %d rows, want 1", n)
	}
	// Guard the isolation itself: the column↔body Status guard must find NOTHING here
	// (otherwise this test would pass for the wrong reason, a §11.4.107(10) analyzer bluff).
	items, _ := loadItems(db)
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		db.Close()
		t.Fatalf("test setup not isolated: column↔body guard fired (%v) — location↔status guard is not being exercised alone", d)
	}
	db.Close()

	code := validateCmd([]string{"--db", dbPath})
	if assertGuardAbsent {
		// RED_MODE=1: assert the guard-absent baseline — validate returned OK on the
		// Fixed+non-terminal desync. On the fixed binary this FAILs (guard now fires).
		if code != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — location↔status guard present, guard-absent baseline no longer reproducible", code)
		}
		return
	}
	if code == exitOK {
		t.Fatal("validate returned OK on a Fixed-location item with a non-terminal (Reopened) status — INTEG-03 location↔status guard not wired")
	}

	// Specificity: restoring a terminal status (column AND body, kept consistent so
	// the column↔body guard stays quiet) clears ONLY this finding.
	repair, _ := openDB(dbPath)
	var rbody string
	if err := repair.QueryRow(`SELECT COALESCE(body_md,'') FROM items WHERE atm_id='WIT-302' AND current_location='Fixed'`).Scan(&rbody); err != nil {
		repair.Close()
		t.Fatalf("repair read body: %v", err)
	}
	if _, err := repair.Exec(`UPDATE items SET status='Fixed (→ Fixed.md)', body_md=? WHERE atm_id='WIT-302' AND current_location='Fixed'`,
		canonicalizeBodyStatusLine(rbody, "Fixed (→ Fixed.md)")); err != nil {
		repair.Close()
		t.Fatalf("repair: %v", err)
	}
	repair.Close()
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after restoring a terminal status — guard not specific to the desync", code)
	}
}
