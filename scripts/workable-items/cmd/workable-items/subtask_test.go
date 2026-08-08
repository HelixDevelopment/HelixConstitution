// subtask_test.go — §11.4.149 sub-task allocator + CRUD unit tests.
//
// Covers: per-parent monotonic allocation (never reused/gapped), legacy-parent
// compatibility, child-grammar regex, subtask-add inserts with parent_atm_id +
// session_ref, parent-must-exist guard, status lifecycle, Completed-requires-
// evidence. Anti-bluff per §11.4.27(A): unit tests against a real SQLite DB.
package main

import (
	"path/filepath"
	"testing"
)

// newTestDBWithParent creates a fresh DB and inserts one top-level parent item.
func newTestDBWithParent(t *testing.T, parent string) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	if code := addCmd([]string{"Bug", "Critical", "--db", dbPath, "--id", parent,
		"--title", "parent item", "--description", "a parent workable item with enough words here"}); code != exitOK {
		t.Fatalf("seed parent add: exit %d", code)
	}
	return dbPath
}

func TestIsChildID(t *testing.T) {
	cases := []struct {
		id   string
		want bool
	}{
		{"ATM-025-001", true},
		{"ATM-025-999", true},
		{"BOB-014-002", true},
		{"BG-001", true},   // legacy §-letter parent
		{"WIT-007-001", true},
		{"ATM-025-1", false},   // too few digits
		{"ATM-025", false},     // no suffix
		{"ATM-025-01", false},  // 2 digits
		{"atm-025-001", false}, // lowercase
		{"-001", false},
	}
	for _, c := range cases {
		if got := isChildID(c.id); got != c.want {
			t.Errorf("isChildID(%q) = %v, want %v", c.id, got, c.want)
		}
	}
}

func TestSubtaskAllocMonotonicPerParent(t *testing.T) {
	dbPath := newTestDBWithParent(t, "ATM-025")
	// also seed a second parent so cross-parent independence is exercised.
	if code := addCmd([]string{"Task", "Low", "--db", dbPath, "--id", "ATM-026",
		"--title", "second parent", "--description", "another parent workable item here for test"}); code != exitOK {
		t.Fatalf("seed ATM-026: %d", code)
	}

	// Three sub-tasks of ATM-025 → 001,002,003 ; one of ATM-026 → 001.
	for i := 1; i <= 3; i++ {
		if code := subtaskAddCmd([]string{"ATM-025", "--db", dbPath, "--session", "s"}); code != exitOK {
			t.Fatalf("subtask-add ATM-025 #%d: exit %d", i, code)
		}
	}
	if code := subtaskAddCmd([]string{"ATM-026", "--db", dbPath, "--session", "t"}); code != exitOK {
		t.Fatalf("subtask-add ATM-026: exit %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	got25, err := listSubtasks(db, "ATM-025")
	if err != nil {
		t.Fatalf("listSubtasks ATM-025: %v", err)
	}
	wantIDs := []string{"ATM-025-001", "ATM-025-002", "ATM-025-003"}
	if len(got25) != 3 {
		t.Fatalf("ATM-025 sub-task count = %d, want 3", len(got25))
	}
	for i, r := range got25 {
		if r.ChildID != wantIDs[i] {
			t.Errorf("ATM-025 sub-task[%d] = %q, want %q", i, r.ChildID, wantIDs[i])
		}
		if r.Status != "Queued" {
			t.Errorf("ATM-025 sub-task[%d] status = %q, want Queued", i, r.Status)
		}
	}
	got26, err := listSubtasks(db, "ATM-026")
	if err != nil {
		t.Fatalf("listSubtasks ATM-026: %v", err)
	}
	if len(got26) != 1 || got26[0].ChildID != "ATM-026-001" {
		t.Fatalf("ATM-026 first sub-task = %+v, want [ATM-026-001]", got26)
	}
}

func TestSubtaskAllocLegacyParent(t *testing.T) {
	dbPath := newTestDBWithParent(t, "BG")
	if code := subtaskAddCmd([]string{"BG", "--db", dbPath, "--session", "x"}); code != exitOK {
		t.Fatalf("subtask-add BG: exit %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	got, _ := listSubtasks(db, "BG")
	if len(got) != 1 || got[0].ChildID != "BG-001" {
		t.Fatalf("legacy parent BG sub-task = %+v, want [BG-001]", got)
	}
	if !isChildID(got[0].ChildID) {
		t.Errorf("BG-001 must match child grammar")
	}
}

func TestSubtaskAddRejectsMissingParent(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	// create an empty DB by opening once.
	if db, err := openDB(dbPath); err == nil {
		db.Close()
	}
	if code := subtaskAddCmd([]string{"ATM-999", "--db", dbPath, "--session", "x"}); code == exitOK {
		t.Fatalf("subtask-add against a non-existent parent must FAIL, got exitOK")
	}
}

func TestSubtaskAddPersistsParentAndSession(t *testing.T) {
	dbPath := newTestDBWithParent(t, "ATM-100")
	if code := subtaskAddCmd([]string{"ATM-100", "--db", dbPath, "--session", "D3-post-flash-2026-06-10"}); code != exitOK {
		t.Fatalf("subtask-add: exit %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	var parent, session string
	if err := db.QueryRow(`SELECT parent_atm_id, session_ref FROM items WHERE atm_id='ATM-100-001'`).Scan(&parent, &session); err != nil {
		t.Fatalf("query sub-task: %v", err)
	}
	if parent != "ATM-100" {
		t.Errorf("parent_atm_id = %q, want ATM-100", parent)
	}
	if session != "D3-post-flash-2026-06-10" {
		t.Errorf("session_ref = %q, want D3-post-flash-2026-06-10", session)
	}
}

func TestSubtaskStatusLifecycleAndEvidenceGate(t *testing.T) {
	dbPath := newTestDBWithParent(t, "ATM-200")
	if code := subtaskAddCmd([]string{"ATM-200", "--db", dbPath, "--session", "s"}); code != exitOK {
		t.Fatalf("subtask-add: %d", code)
	}
	// Queued -> In progress (no evidence needed).
	if code := subtaskStatusCmd([]string{"ATM-200-001", "--db", dbPath, "--to", "In progress"}); code != exitOK {
		t.Fatalf("status In progress: %d", code)
	}
	// -> Completed WITHOUT evidence must FAIL (§11.4.69).
	if code := subtaskStatusCmd([]string{"ATM-200-001", "--db", dbPath, "--to", "Completed"}); code == exitOK {
		t.Fatalf("Completed without evidence must FAIL")
	}
	// -> Completed WITH evidence must PASS.
	if code := subtaskStatusCmd([]string{"ATM-200-001", "--db", dbPath, "--to", "Completed",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "qa-results/x.log")}); code != exitOK {
		t.Fatalf("Completed with evidence: %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	var st string
	_ = db.QueryRow(`SELECT status FROM items WHERE atm_id='ATM-200-001'`).Scan(&st)
	if st != "Completed (→ Fixed.md)" {
		t.Errorf("final status = %q, want Completed (→ Fixed.md)", st)
	}
}
