// atm627_roundtrip_test.go — §11.4.115 RED-polarity regression guard for ATM-627.
//
// The corruption class: an item half-migrated to a stray current_location
// ("Fixed.md") leaving a dangling doc_segment in the OTHER document → the DB
// cannot be rendered by db-to-md → §11.4.93 regen silently blocked, yet the old
// validate returned exitOK (a §11.4.6 bluff gate). This test reproduces that
// exact corrupt state and, DEFAULT (RED_MODE unset / "0") — the standing GREEN
// regression-guard — asserts validate now FAILs AND that db-to-md genuinely
// cannot render it (the ATM-627 fix). RED_MODE=1 (opt-in) flips polarity to
// assert the PRE-FIX bluff behaviour (validate returned exitOK on the corrupt
// DB); it therefore FAILs on this fixed binary and PASSes only against a pre-fix
// binary — the captured proof the fix changed behaviour (§11.4.115).
package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestATM627_ValidateCatchesUnrenderableDB(t *testing.T) {
	// Default (unset) = GREEN guard asserting the fix. RED_MODE=1 = assert the
	// pre-fix bluff (expected to FAIL on the fixed binary).
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

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

	// Inject the ATM-627 corruption: leave ATM-900's Issues doc_segment in place
	// but remove the item it resolves to (the half-migration signature: the item
	// left the 'Issues' location but its segment stayed) → renderDocument("Issues")
	// hits an unresolvable segment. NOTE: the live schema now CHECK-constrains
	// current_location IN {Issues,Fixed}, so the legacy 'Fixed.md' value cannot be
	// re-inserted; deleting the item reproduces the identical dangling-segment
	// render failure the legacy committed DB exhibited.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if _, err := db.Exec(`DELETE FROM items WHERE atm_id='ATM-900' AND current_location='Issues'`); err != nil {
		db.Close()
		t.Fatalf("inject corruption: %v", err)
	}
	db.Close()

	validateCode := validateCmd([]string{"--db", dbPath})
	renderCode := syncDBToMD([]string{"--db", dbPath, "--out-issues", filepath.Join(tmp, "out.md")})

	if assertPreFixBluff {
		// RED_MODE=1: assert the PRE-FIX behaviour — validate was a bluff (exitOK)
		// on the corrupt DB. On the fixed binary this FAILs (fix changed behaviour).
		if validateCode != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — fix is present, pre-fix bluff no longer reproducible", validateCode)
		}
		return
	}

	// DEFAULT GREEN guard: the fix means validate FAILs AND db-to-md cannot render.
	if validateCode == exitOK {
		t.Fatalf("validate returned exitOK on an UNRENDERABLE DB (ATM-627 bluff not caught)")
	}
	if renderCode == exitOK {
		t.Fatalf("db-to-md succeeded on the corrupt DB (expected render failure)")
	}
}

// TestATM627_ValidateCatchesLocationMismatchDB is the §11.4.115 FAITHFUL-signature
// variant of TestATM627_ValidateCatchesUnrenderableDB. The COMMITTED-DB corruption
// (ATM-627) was NOT a deleted item — it was an item RELOCATED via direct SQL:
// current_location flipped Issues->'Fixed' (BOTH valid closed-set values, so the
// schema CHECK never fires) while its ORIGINAL 'Issues' doc_segment stayed behind,
// leaving that segment dangling -> renderDocument("Issues") cannot resolve it ->
// §11.4.93 regen silently blocked. The sibling test DELETEs the item — a weaker
// proxy the live CHECK forces (a 'Fixed.md' stray can no longer be re-inserted).
// THIS test reproduces the exact location-mismatch signature with the UPDATE the
// corruption actually used, so the value stays IN the closed set and ONLY the
// renderability guard (not the current_location closed-set check) can catch it.
//
// Default (RED_MODE unset / "0") = standing GREEN regression-guard: validate FAILs
// on the mismatch DB AND db-to-md('Issues') cannot render it; the repair
// (UPDATE …='Issues') then restores render exit 0 — proving the guard is specific
// to the mismatch, not a blanket failure. RED_MODE=1 asserts the PRE-FIX bluff
// (validate returned exitOK on the mismatch); it therefore FAILs on this fixed
// binary and PASSes only against a pre-fix binary — the captured §11.4.115 proof.
func TestATM627_ValidateCatchesLocationMismatchDB(t *testing.T) {
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

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

	// Inject the FAITHFUL ATM-627 corruption: relocate ATM-900 out of 'Issues'
	// into the valid closed-set value 'Fixed' (the CHECK passes — that IS the
	// point) WITHOUT moving its 'Issues' doc_segment. renderDocument("Issues")
	// scopes its body lookup to current_location='Issues', so ATM-900 (now
	// 'Fixed') is invisible to it and its dangling segment fails to resolve.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	res, err := db.Exec(`UPDATE items SET current_location='Fixed' WHERE atm_id='ATM-900' AND current_location='Issues'`)
	if err != nil {
		db.Close()
		t.Fatalf("inject corruption: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		db.Close()
		t.Fatalf("inject corruption: expected 1 row relocated, got %d", n)
	}
	db.Close()

	validateCode := validateCmd([]string{"--db", dbPath})
	renderCode := syncDBToMD([]string{"--db", dbPath, "--out-issues", filepath.Join(tmp, "out.md")})

	if assertPreFixBluff {
		// RED_MODE=1: assert the PRE-FIX behaviour — validate was a bluff (exitOK)
		// on the location-mismatch DB. On the fixed binary this FAILs.
		if validateCode != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — fix is present, pre-fix bluff no longer reproducible", validateCode)
		}
		return
	}

	// DEFAULT GREEN guard: the fix means validate FAILs AND db-to-md cannot render.
	if validateCode == exitOK {
		t.Fatalf("validate returned exitOK on a location-mismatch (dangling-segment) DB (ATM-627 bluff not caught)")
	}
	if renderCode == exitOK {
		t.Fatalf("db-to-md succeeded on the location-mismatch DB (expected render failure)")
	}

	// Repair proves the guard is SPECIFIC to the mismatch — restoring ATM-900 to
	// 'Issues' makes the DB renderable again (render exit 0). This is the §11.4.115
	// GREEN side: FAIL on the mismatch AND PASS once the mismatch is repaired.
	repairDB, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (repair): %v", err)
	}
	if _, err := repairDB.Exec(`UPDATE items SET current_location='Issues' WHERE atm_id='ATM-900' AND current_location='Fixed'`); err != nil {
		repairDB.Close()
		t.Fatalf("repair corruption: %v", err)
	}
	repairDB.Close()

	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", filepath.Join(tmp, "out_repaired.md")}); code != exitOK {
		t.Fatalf("db-to-md FAILed (%d) after repair — the guard is not specific to the mismatch", code)
	}
}
