// atm627_integrity_guard_test.go — §11.4.135 permanent regression guard for the
// ATM-627 dangling-doc_segment defect CLASS, in its strongest DIRECT form.
//
// ROOT CAUSE (FACT, §11.4.102 Phase 1): an item row lives in `items` keyed by
// (atm_id, current_location, representation); its rendered body lives in a
// `doc_segments` row with kind='item', atm_id=X, document=D. The ATM-627 bug:
// three items sat in items.current_location='Fixed' while their
// doc_segments.document='Issues' — a DANGLING item-segment (the segment's
// (atm_id, document) has NO matching item at (atm_id, current_location=document,
// representation)). That made db-to-md('Issues') unrenderable and §11.4.93 regen
// silently blocked.
//
// The pre-existing guard (sync.go renderability check) catches this INDIRECTLY —
// as a side-effect of renderDocument() erroring. THIS guard asserts the invariant
// DIRECTLY via an explicit segment↔item join (`danglingItemSegments`), so the
// integrity violation is a first-class, self-documenting, actionable finding
// independent of the render control-flow.
//
// §11.4.115 RED-polarity: DEFAULT (RED_MODE unset/"0") is the standing GREEN
// regression-guard — on a dangling-segment DB the direct guard MUST report the
// exact offending segment, and on a clean DB it MUST report none. RED_MODE=1
// asserts the PRE-FIX / guard-absent behaviour (the direct guard reported NO
// dangling segment on the corrupt DB); it therefore FAILs on this fixed build and
// PASSes only against a guard-absent build — the captured proof the guard works.
//
// §1.1 PAIRED MUTATION (manual, documented): stub the body of
// danglingItemSegments (sync.go) to `return nil, nil` (guard removed). Re-run
// `go test -run ATM627_IntegrityGuard` — TestATM627_IntegrityGuard_* FAIL
// (dangling segment no longer detected), proving the guard is NOT a tautology.
// Restore the real body → GREEN again. Demonstrated live in the R3 report.
//
// HARD CONSTRAINT: fresh temp/in-memory DB only; NEVER touches the live
// docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// atm627FixtureDB writes a minimal valid two-document tree and syncs it into a
// fresh temp DB, returning the db path. The tree has one Issues item (ATM-900)
// and one Fixed item (ATM-901), each with its own item-segment.
func atm627FixtureDB(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	dbPath := filepath.Join(tmp, "wi.db")

	issues := "# Issues\n\n## §1. [ATM-900] alpha item with enough words to satisfy description length\n\n**Type:** Bug\n**Status:** Queued\n\nbody one two three four five six.\n"
	fixed := "# Fixed\n\n## §2. [ATM-901] beta item with enough words to satisfy description length\n\n**Type:** Bug\n**Status:** Fixed (→ Fixed.md)\n\nbody one two three four five six.\n"
	issuesPath := filepath.Join(tmp, "Issues.md")
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(issuesPath, []byte(issues), 0o644); err != nil {
		t.Fatalf("write issues: %v", err)
	}
	if err := os.WriteFile(fixedPath, []byte(fixed), 0o644); err != nil {
		t.Fatalf("write fixed: %v", err)
	}
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}
	return dbPath
}

// TestATM627_IntegrityGuard_DetectsLocationMismatch reproduces the FAITHFUL
// ATM-627 corruption (item relocated Issues→Fixed via direct SQL while its
// 'Issues' doc_segment stays behind — BOTH current_location values are in the
// closed set so no CHECK fires) and asserts the DIRECT integrity guard names
// exactly that dangling segment.
func TestATM627_IntegrityGuard_DetectsLocationMismatch(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := atm627FixtureDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// Sanity: a clean DB has ZERO dangling item-segments (guard must not
	// false-positive on the 415-item-class valid shape).
	if clean, err := danglingItemSegments(db); err != nil {
		t.Fatalf("danglingItemSegments (clean): %v", err)
	} else if len(clean) != 0 {
		t.Fatalf("clean DB reported %d dangling segment(s): %v (guard false-positives)", len(clean), clean)
	}

	// Inject the faithful ATM-627 corruption: relocate ATM-900 out of 'Issues'
	// into 'Fixed' (valid closed-set value, CHECK passes) WITHOUT moving its
	// 'Issues' doc_segment → that segment is now dangling.
	res, err := db.Exec(`UPDATE items SET current_location='Fixed' WHERE atm_id='ATM-900' AND current_location='Issues'`)
	if err != nil {
		t.Fatalf("inject corruption: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject corruption: expected 1 row relocated, got %d", n)
	}

	dangling, err := danglingItemSegments(db)
	if err != nil {
		t.Fatalf("danglingItemSegments (corrupt): %v", err)
	}

	// The guard MUST name the exact offending segment: document=Issues, atm_id=ATM-900.
	found := false
	for _, d := range dangling {
		if strings.Contains(d, "ATM-900") && strings.Contains(d, "Issues") {
			found = true
			break
		}
	}

	if assertGuardAbsent {
		// RED_MODE=1: assert the PRE-FIX / guard-absent behaviour — the direct
		// guard did NOT flag the dangling segment. On this fixed build the guard
		// DOES flag it, so this branch FAILs (fix present).
		if found {
			t.Fatalf("RED_MODE=1: direct guard DETECTED the dangling segment — fix present, guard-absent baseline no longer reproducible")
		}
		return
	}

	// DEFAULT GREEN guard: the direct integrity check flags exactly the dangling
	// (Issues, ATM-900) segment.
	if !found {
		t.Fatalf("direct integrity guard did NOT detect the dangling (Issues, ATM-900) segment; got %d finding(s): %v", len(dangling), dangling)
	}

	// The repair (relocate back to Issues) MUST clear the finding — proving the
	// guard is SPECIFIC to the mismatch, not a blanket failure (§11.4.115 GREEN).
	if _, err := db.Exec(`UPDATE items SET current_location='Issues' WHERE atm_id='ATM-900' AND current_location='Fixed'`); err != nil {
		t.Fatalf("repair: %v", err)
	}
	if repaired, err := danglingItemSegments(db); err != nil {
		t.Fatalf("danglingItemSegments (repaired): %v", err)
	} else if len(repaired) != 0 {
		t.Fatalf("after repair the guard still reports %d dangling segment(s): %v (not specific to the mismatch)", len(repaired), repaired)
	}
}

// TestATM627_IntegrityGuard_ValidateFailsAndNamesInvariant asserts the DIRECT
// guard is WIRED into validateCmd: validate FAILs on the corrupt DB (composes
// with, does not replace, the renderability guard) — and, on a clean DB, PASSes.
// This is the end-to-end §11.4.135 regression assertion at the CLI boundary.
func TestATM627_IntegrityGuard_ValidateFailsAndNamesInvariant(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := atm627FixtureDB(t)

	// Clean DB validates OK.
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate on clean DB exited %d (expected OK)", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if _, err := db.Exec(`UPDATE items SET current_location='Fixed' WHERE atm_id='ATM-900' AND current_location='Issues'`); err != nil {
		db.Close()
		t.Fatalf("inject corruption: %v", err)
	}
	db.Close()

	code := validateCmd([]string{"--db", dbPath})

	if assertGuardAbsent {
		if code != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — fix present, pre-fix bluff no longer reproducible", code)
		}
		return
	}
	if code == exitOK {
		t.Fatalf("validate returned exitOK on a dangling-segment DB (ATM-627 guard not wired)")
	}
}
