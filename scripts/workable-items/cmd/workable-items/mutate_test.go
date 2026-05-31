// mutate_test.go — real-SQLite behavioural tests for update / reopen / block.
//
// §11.4.93 + §11.4.27 anti-bluff: these drive the actual updateCmd / reopenCmd /
// blockCmd entry points against a REAL on-disk SQLite DB (no mock), then read
// the rows + item_history + operator_block_details back to assert the
// user-visible outcome. Each is falsifiability-rehearsed in the commit body
// (see UPSTREAM-EXTENSION-EVIDENCE.md) per §1.1.
package main

import (
	"database/sql"
	"strings"
	"testing"
)

// seedIssue adds a single Issues item via the real add path.
func seedIssue(t *testing.T, dbPath, typ, severity, title, desc string) {
	t.Helper()
	if code := addCmd([]string{typ, severity, "--db", dbPath,
		"--title", title, "--description", desc}); code != exitOK {
		t.Fatalf("seed addCmd: exit %d", code)
	}
}

// historyCount returns the number of item_history rows for id with the given
// event_type.
func historyCount(t *testing.T, db *sql.DB, id, event string) int {
	t.Helper()
	var n int
	if err := db.QueryRow(`SELECT COUNT(1) FROM item_history WHERE atm_id=? AND event_type=?`, id, event).Scan(&n); err != nil {
		t.Fatalf("historyCount: %v", err)
	}
	return n
}

// ---- update ----

func TestUpdateCmd_MutatesFieldsAndRecordsHistory(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "Low",
		"Original title for the update test",
		"Original description with enough words to clear the floor here")

	code := updateCmd([]string{"--db", dbPath, "--id", "WIT-001",
		"--title", "Updated title after the change",
		"--severity", "Critical",
		"--status", "In progress"})
	if code != exitOK {
		t.Fatalf("updateCmd exit = %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-001 absent (err=%v)", err)
	}
	if it.Status != "In progress" {
		t.Errorf("status = %q, want In progress", it.Status)
	}
	if it.Severity != "Critical" {
		t.Errorf("severity = %q, want Critical", it.Severity)
	}
	if it.Title != "Updated title after the change" {
		t.Errorf("title = %q, want updated", it.Title)
	}
	// body_md regenerated so the round-trip carries the new state.
	if !strings.Contains(it.BodyMD, "Updated title after the change") {
		t.Errorf("body_md not regenerated with new title: %q", it.BodyMD)
	}
	if !strings.Contains(it.BodyMD, "**Status:** In progress") {
		t.Errorf("body_md missing new status: %q", it.BodyMD)
	}
	// §11.4.34 audit: an 'Updated' history row was appended.
	if n := historyCount(t, db, "WIT-001", "Updated"); n != 1 {
		t.Errorf("Updated history rows = %d, want 1", n)
	}
}

// §11.4.91: a too-short --description is rejected.
func TestUpdateCmd_RejectsShortDescription(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Task", "Low",
		"A task heading for the short-desc test",
		"A sufficiently long original description goes right here now")

	code := updateCmd([]string{"--db", dbPath, "--id", "WIT-001", "--description", "too short"})
	if code == exitOK {
		t.Fatal("updateCmd with short --description succeeded; want failure (§11.4.91)")
	}
}

// Unknown ids are rejected.
func TestUpdateCmd_RejectsUnknownID(t *testing.T) {
	dbPath := newTestDB(t)
	code := updateCmd([]string{"--db", dbPath, "--id", "WIT-999", "--severity", "High"})
	if code == exitOK {
		t.Fatal("updateCmd on unknown id succeeded; want failure")
	}
}

// At least one mutable field is required.
func TestUpdateCmd_RequiresAField(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "Low", "A heading here for no-field test",
		"A description long enough to clear the description floor here")
	code := updateCmd([]string{"--db", dbPath, "--id", "WIT-001"})
	if code == exitOK {
		t.Fatal("updateCmd with no field flags succeeded; want failure")
	}
}

// ---- reopen ----

func TestReopenCmd_SetsReopenedWithFullAttribution(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "High",
		"A bug to be reopened later on",
		"A description of the bug long enough to clear the floor here")

	code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-001",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-05-31", "--incident", "qa-results/2026-05-31/wit-001-fail.log"})
	if code != exitOK {
		t.Fatalf("reopenCmd exit = %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-001 absent (err=%v)", err)
	}
	if it.Status != "Reopened" {
		t.Errorf("status = %q, want Reopened", it.Status)
	}
	// §11.4.34 attribution embedded in the regenerated body.
	if !strings.Contains(it.BodyMD, "**Reopened-Details:**") {
		t.Errorf("body missing Reopened-Details line: %q", it.BodyMD)
	}
	for _, want := range []string{"By: AI", "On: 2026-05-31", "Reason: test-failed", "Evidence: qa-results/2026-05-31/wit-001-fail.log"} {
		if !strings.Contains(it.BodyMD, want) {
			t.Errorf("body missing %q: %q", want, it.BodyMD)
		}
	}
	// §11.4.34 audit: a Reopened history row with all four facts.
	var by, on, reason, ev string
	row := db.QueryRow(`SELECT by, on_date, reason, evidence_path FROM item_history WHERE atm_id='WIT-001' AND event_type='Reopened'`)
	if err := row.Scan(&by, &on, &reason, &ev); err != nil {
		t.Fatalf("scan reopen history: %v", err)
	}
	if by != "AI" || on != "2026-05-31" || reason != "test-failed" || ev != "qa-results/2026-05-31/wit-001-fail.log" {
		t.Errorf("history attribution = (%q,%q,%q,%q)", by, on, reason, ev)
	}
}

// §11.4.34: partial attribution is rejected — each missing fact independently.
func TestReopenCmd_RejectsPartialAttribution(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "High", "A bug heading for partial-attribution",
		"A description long enough to clear the description floor here")

	cases := map[string][]string{
		"missing why":      {"--db", dbPath, "--id", "WIT-001", "--who", "AI", "--when", "2026-05-31", "--incident", "x.log"},
		"missing who":      {"--db", dbPath, "--id", "WIT-001", "--why", "test-failed", "--when", "2026-05-31", "--incident", "x.log"},
		"missing when":     {"--db", dbPath, "--id", "WIT-001", "--why", "test-failed", "--who", "AI", "--incident", "x.log"},
		"missing incident": {"--db", dbPath, "--id", "WIT-001", "--why", "test-failed", "--who", "AI", "--when", "2026-05-31"},
		"bad why vocab":    {"--db", dbPath, "--id", "WIT-001", "--why", "i-felt-like-it", "--who", "AI", "--when", "2026-05-31", "--incident", "x.log"},
		"bad who value":    {"--db", dbPath, "--id", "WIT-001", "--why", "test-failed", "--who", "Robot", "--when", "2026-05-31", "--incident", "x.log"},
	}
	for name, args := range cases {
		if code := reopenCmd(args); code == exitOK {
			t.Errorf("%s: reopenCmd succeeded; want failure (§11.4.34)", name)
		}
	}
}

// ---- block ----

func TestBlockCmd_SetsOperatorBlockedWithDetails(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Task", "Medium",
		"A task that becomes operator-blocked",
		"A description of the task long enough to clear the floor here")

	code := blockCmd([]string{"--db", dbPath, "--id", "WIT-001",
		"--details", "Needs operator to provision a Linux x86_64 gate host",
		"--why", "no host-direct emulator on this darwin host",
		"--unblock", "Linux runner provisioned",
		"--who", "@operator"})
	if code != exitOK {
		t.Fatalf("blockCmd exit = %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-001 absent (err=%v)", err)
	}
	if it.Status != "Operator-blocked" {
		t.Errorf("status = %q, want Operator-blocked", it.Status)
	}
	if !strings.Contains(it.BodyMD, "**Operator-Block-Details:**") {
		t.Errorf("body missing Operator-Block-Details line: %q", it.BodyMD)
	}
	if !strings.Contains(it.BodyMD, "WHAT: Needs operator to provision a Linux x86_64 gate host") {
		t.Errorf("body missing WHAT detail: %q", it.BodyMD)
	}
	// §11.4.21 operator_block_details row persisted.
	var what, why, unblock string
	row := db.QueryRow(`SELECT what, why_exhausted_alternatives, unblock_condition FROM operator_block_details WHERE atm_id='WIT-001'`)
	if err := row.Scan(&what, &why, &unblock); err != nil {
		t.Fatalf("scan operator_block_details: %v", err)
	}
	if what != "Needs operator to provision a Linux x86_64 gate host" {
		t.Errorf("what = %q", what)
	}
	if unblock != "Linux runner provisioned" {
		t.Errorf("unblock_condition = %q", unblock)
	}
}

// §11.4.21: empty --details is rejected.
func TestBlockCmd_RejectsEmptyDetails(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Task", "Low", "A task heading for empty-details test",
		"A description long enough to clear the description floor here")

	if code := blockCmd([]string{"--db", dbPath, "--id", "WIT-001", "--details", "   "}); code == exitOK {
		t.Fatal("blockCmd with blank --details succeeded; want failure (§11.4.21)")
	}
	if code := blockCmd([]string{"--db", dbPath, "--id", "WIT-001"}); code == exitOK {
		t.Fatal("blockCmd with no --details succeeded; want failure (§11.4.21)")
	}
}
