// atm627_status_desync_test.go — §11.4.115 RED-polarity regression guard for the
// ATM-627 (task #20) column↔body Status DESYNC class (the KEYSTONE durable fix).
//
// DEFECT CLASS (FACT): items.status is a column; body_md carries a `**Status:**`
// line. A direct `UPDATE items SET status=…` that bypasses renderItemBody advances
// the column while body_md's Status line stays stale — `sync db-to-md` (renderDocument)
// then replays the stale line, misreporting the item to every tracker reader. The
// pre-task-20 validate checked the status CLOSED-SET only (never column↔body
// agreement), so a desynced item passed exit 0 — a §11.4.6/§11.4.93 bluff gate.
//
// §11.4.115 polarity: DEFAULT (RED_MODE unset/"0") = standing GREEN guard (validate
// FAILs on a desync, PASSes on a synced DB, and the repair clears it). RED_MODE=1
// asserts the PRE-FIX bluff (validate returned exit 0 on the desync) — it FAILs on this
// fixed binary and PASSes only against a guard-absent build (the captured RED proof).
//
// §1.1 PAIRED MUTATION (documented): stub statusColumnBodyDesyncs (sync.go) to
// `return nil` → TestATM627_StatusDesync_DirectGuard + …_ValidateCatchesColumnBodyDrift
// FAIL; restore → GREEN. This proves the guard is not a tautology.
//
// HARD CONSTRAINT: fresh temp DB only; NEVER touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// atm627StatusFixtureDB builds a minimal synced two-document DB (ATM-900 Issues
// Queued, ATM-901 Fixed) — column == body Status for BOTH by construction (buildItem
// derives the column from exactly the body Status line at md→db import).
func atm627StatusFixtureDB(t *testing.T) string {
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

// TestATM627_StatusDesync_ValidateCatchesColumnBodyDrift is the §11.4.115 CLI-boundary
// guard: validate PASSes on the synced DB, then FAILs after a direct column mutation
// (UPDATE items SET status=…) leaves body_md's `**Status:**` line stale; the repair
// (column back to Queued) clears the finding — proving the guard is specific to the
// desync, not a blanket failure.
func TestATM627_StatusDesync_ValidateCatchesColumnBodyDrift(t *testing.T) {
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

	dbPath := atm627StatusFixtureDB(t)

	// Clean/synced DB validates OK.
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate on synced DB exited %d (expected OK)", code)
	}

	// Inject the faithful desync: advance ATM-900's status column to 'In progress'
	// via direct SQL (bypassing renderItemBody), leaving body_md's '**Status:** Queued'
	// line stale. 'In progress' is a valid closed-set value so no CHECK / closed-set
	// guard fires — ONLY the column↔body guard can catch it.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	res, err := db.Exec(`UPDATE items SET status='In progress' WHERE atm_id='ATM-900' AND current_location='Issues'`)
	if err != nil {
		db.Close()
		t.Fatalf("inject desync: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		db.Close()
		t.Fatalf("inject desync: expected 1 row, got %d", n)
	}
	db.Close()

	code := validateCmd([]string{"--db", dbPath})

	if assertPreFixBluff {
		// RED_MODE=1: assert the PRE-FIX behaviour — validate was a bluff (exitOK)
		// on the desync DB. On the fixed binary this FAILs (fix changed behaviour).
		if code != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — fix present, pre-fix bluff no longer reproducible", code)
		}
		return
	}
	if code == exitOK {
		t.Fatalf("validate returned exitOK on a column↔body Status desync DB (ATM-627 task-20 guard not wired)")
	}

	// Specificity: repairing the column back to 'Queued' clears the finding.
	repair, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (repair): %v", err)
	}
	if _, err := repair.Exec(`UPDATE items SET status='Queued' WHERE atm_id='ATM-900' AND current_location='Issues'`); err != nil {
		repair.Close()
		t.Fatalf("repair: %v", err)
	}
	repair.Close()
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after repair — guard not specific to the desync", code)
	}
}

// TestATM627_StatusDesync_DirectGuard exercises statusColumnBodyDesyncs directly:
// none on a synced set, exactly the offending id on a desynced set (naming BOTH the
// stale body value and the mutated column value), none after repair.
func TestATM627_StatusDesync_DirectGuard(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := atm627StatusFixtureDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// Synced set → ZERO desyncs (guard must not false-positive on the 415-item shape).
	items, err := loadItems(db)
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("synced DB reported %d desync(s): %v (guard false-positives)", len(d), d)
	}

	// Desync ATM-900 (column advances, body stays stale).
	if _, err := db.Exec(`UPDATE items SET status='In progress' WHERE atm_id='ATM-900' AND current_location='Issues'`); err != nil {
		t.Fatalf("inject desync: %v", err)
	}
	items, err = loadItems(db)
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	d := statusColumnBodyDesyncs(items)
	found := false
	for _, v := range d {
		if strings.Contains(v, "ATM-900") && strings.Contains(v, "In progress") && strings.Contains(v, "Queued") {
			found = true
		}
	}
	if assertGuardAbsent {
		if found {
			t.Fatalf("RED_MODE=1: direct guard DETECTED the desync — fix present, guard-absent baseline no longer reproducible")
		}
		return
	}
	if !found {
		t.Fatalf("direct guard did NOT flag the ATM-900 desync; got %d finding(s): %v", len(d), d)
	}

	// Repair clears it — proving specificity.
	if _, err := db.Exec(`UPDATE items SET status='Queued' WHERE atm_id='ATM-900' AND current_location='Issues'`); err != nil {
		t.Fatalf("repair: %v", err)
	}
	items, err = loadItems(db)
	if err != nil {
		t.Fatalf("loadItems (repaired): %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("after repair the guard still reports %d desync(s): %v (not specific)", len(d), d)
	}
}

// TestATM627_StatusDesync_FalsePositiveFreeTrailingProse proves the generator-symmetry
// oracle does NOT flag a body whose `**Status:**` line carries trailing prose (the
// false-positive class the reconciliation plan calls out): the line normalises to the
// same closed-set value as the column, so column==derived and there is no violation.
func TestATM627_StatusDesync_FalsePositiveFreeTrailingProse(t *testing.T) {
	body := "## §1. [ATM-902] gamma item with enough words to satisfy the description floor\n\n**Type:** Bug\n**Status:** Fixed (→ Fixed.md) — closed 2026-06-23, see qa-results/x\n\nprose.\n"
	if s, ok := lastBodyStatus(body); !ok || s != "Fixed (→ Fixed.md)" {
		t.Fatalf("lastBodyStatus(trailing prose) = (%q,%v); want (\"Fixed (→ Fixed.md)\", true)", s, ok)
	}
	it := item{AtmID: "ATM-902", CurrentLocation: "Fixed", Status: "Fixed (→ Fixed.md)", BodyMD: body}
	if d := statusColumnBodyDesyncs([]item{it}); len(d) != 0 {
		t.Fatalf("trailing-prose body flagged as desync (false positive): %v", d)
	}

	// A 'section' body with NO `**Status:**` line whose column is the buildItem default
	// "Queued" is CONSISTENT (md→db would derive exactly "Queued") → NOT flagged.
	okDefault := item{AtmID: "ATM-904", CurrentLocation: "Issues", Status: "Queued", BodyMD: "## x — y\n\nno status meta line, column is the default.\n"}
	if d := statusColumnBodyDesyncs([]item{okDefault}); len(d) != 0 {
		t.Fatalf("section body with no **Status:** line + default-Queued column flagged (false positive): %v", d)
	}

	// A 'section' body with NO `**Status:**` line whose column is NON-Queued is a GENUINE
	// desync (the SPK-512/519/609 empty-body class): md→db would reset it to "Queued", so
	// the non-Queued column is not recoverable from body_md → MUST be flagged.
	emptyBody := item{AtmID: "SPK-999", CurrentLocation: "Issues", Status: "In progress", BodyMD: ""}
	d := statusColumnBodyDesyncs([]item{emptyBody})
	if len(d) != 1 || !strings.Contains(d[0], "SPK-999") || !strings.Contains(d[0], "NO **Status:** line") {
		t.Fatalf("empty-body non-Queued section item NOT flagged (under-detection): %v", d)
	}

	// A 'table' representation with no `**Status:**` line is OUT OF SCOPE (Status lives
	// in the pipe cell) → NOT flagged even with a non-Queued column.
	tableRow := item{AtmID: "FIX-2026-06-23", CurrentLocation: "Fixed", Status: "Fixed (→ Fixed.md)", Representation: "table", BodyMD: "| 2026-06-23 | t | Bug | Fixed | R3 | c | e |\n"}
	if d := statusColumnBodyDesyncs([]item{tableRow}); len(d) != 0 {
		t.Fatalf("table-representation row flagged (out of scope, false positive): %v", d)
	}
}

// TestATM627_StatusDesync_CanonicalizePreservesDetailBlocksAndRoundTrip proves the
// generator-symmetry half (b): canonicalizeBodyStatusLine is a byte-identical no-op on
// a synced body (incl. a `**Reopened-Details:**` block), and on a desynced body rewrites
// ONLY the Status line while preserving the detail block + all other content.
func TestATM627_StatusDesync_CanonicalizePreservesDetailBlocksAndRoundTrip(t *testing.T) {
	body := "## §1. [ATM-903] delta item with enough words to satisfy the description floor\n\n**Status:** Reopened\n**Type:** Bug\n**Reopened-Details:** By: AI On: 2026-05-17 Reason: test-failed Evidence: qa/x\n\nprose line.\n"

	// (1) synced (column == body) → STRICT byte-identical no-op.
	if got := canonicalizeBodyStatusLine(body, "Reopened"); got != body {
		t.Fatalf("canonicalize on synced body mutated it:\n--- want ---\n%q\n--- got ---\n%q", body, got)
	}

	// (2) desynced (column advanced to Fixed) → Status line rewritten to the column;
	// the detail block + every other line preserved verbatim.
	got := canonicalizeBodyStatusLine(body, "Fixed (→ Fixed.md)")
	if !strings.Contains(got, "**Status:** Fixed (→ Fixed.md)\n") {
		t.Fatalf("canonicalize did not rewrite the Status line to the column value:\n%q", got)
	}
	if !strings.Contains(got, "**Reopened-Details:** By: AI On: 2026-05-17 Reason: test-failed Evidence: qa/x\n") {
		t.Fatalf("canonicalize DROPPED/ALTERED the **Reopened-Details:** block:\n%q", got)
	}
	if !strings.Contains(got, "**Type:** Bug\n") || !strings.Contains(got, "prose line.\n") ||
		!strings.Contains(got, "## §1. [ATM-903]") {
		t.Fatalf("canonicalize altered non-Status content:\n%q", got)
	}
	// The rewritten body MUST re-derive the column value (self-heal convergence:
	// a subsequent md→db sets the column from this line and gets exactly the column).
	if s, ok := lastBodyStatus(got); !ok || s != "Fixed (→ Fixed.md)" {
		t.Fatalf("rewritten body derives (%q,%v); want (\"Fixed (→ Fixed.md)\", true)", s, ok)
	}
}
