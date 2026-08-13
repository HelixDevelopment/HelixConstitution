// move_test.go — guards for the `move` subcommand: the general REVERSE-OF-CLOSE
// relocation between the Issues and Fixed trackers.
//
// WHY `move` EXISTS (and is not `reopen --status`): `reopen` carries §11.4.34
// semantics — it forces status='Reopened', writes a `**Reopened-Details:**` block,
// and mints a `Reopened` item_history event that feeds the §11.4.55 reopens_count
// signal §11.4.132(d) + §11.4.189 use to rank the most-fragile work for the deepest
// live scrutiny. A transition that is NOT a demotion-from-closure (e.g. a fix that
// landed and is wired but whose runtime GREEN is still owed — §11.4.69
// `artifact_not_yet_built` — belonging at `Ready for testing` in Issues) must NOT
// mint a reopen event: doing so asserts a defect the fix does not have AND inflates
// the counter, corrupting exactly the signal §11.4.214 exists to keep true.
//
// §11.4.201: the location↔status guard asserts the REAL condition from the
// AUTHORITATIVE source — terminalStatuses(), the same closed set the
// fixedLocationNonTerminalStatus detective gate (sync.go) checks — so the preventive
// guard and the detective gate can never drift apart. Both a golden-TRUE (the guard
// fires on a genuinely bad combination) and a golden-FALSE (it does NOT fire on a
// legitimate move) case are covered, so a false-positive refusal — a §11.4.1
// FAIL-bluff — is caught too.
//
// §1.1 PAIRED MUTATION (documented): delete the two invariant checks in moveCmd
// (mutate.go) → TestMoveCmd_RefusesInvariantViolatingCombinations FAILs; replace
// the body-preserving line with a renderItemBody regeneration →
// TestMoveCmd_PreservesAuthoredBody FAILs. Restore → GREEN.
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches docs/workable_items.db.
package main

import (
	"strings"
	"testing"
)

// TestMoveCmd_RelocatesFixedToIssuesWithStatus is the primary path: a closed item
// moves back to Issues carrying a non-terminal status, row AND doc_segment.
func TestMoveCmd_RelocatesFixedToIssuesWithStatus(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-500")

	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-500", "--to", "Issues",
		"--status", "Ready for testing",
		"--why", "fix landed and wired; only the runtime GREEN is owed (§11.4.69 artifact_not_yet_built)",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "docs/evidence/WIT-500.md")}); code != exitOK {
		t.Fatalf("moveCmd: exit %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	inFixed, _ := loadItem(db, "WIT-500", "Fixed")
	inIssues, _ := loadItem(db, "WIT-500", "Issues")
	if inFixed != nil {
		t.Fatalf("WIT-500 still in Fixed after move (status=%q)", inFixed.Status)
	}
	if inIssues == nil {
		t.Fatal("WIT-500 not relocated to Issues")
	}
	if inIssues.Status != "Ready for testing" {
		t.Errorf("status = %q, want %q", inIssues.Status, "Ready for testing")
	}
	// The doc_segment moved with the row — otherwise db-to-md renders it under the
	// OLD document (the ATM-627 dangling-segment class).
	if s := segCount(t, dbPath, "Fixed", "WIT-500"); s != 0 {
		t.Errorf("Fixed doc_segment not removed (%d)", s)
	}
	if s := segCount(t, dbPath, "Issues", "WIT-500"); s != 1 {
		t.Errorf("Issues doc_segment count = %d, want 1", s)
	}
}

// TestMoveCmd_MintsNoReopenEvent is the load-bearing distinction from `reopen`:
// a relocation must NOT inflate the §11.4.55 reopens_count.
func TestMoveCmd_MintsNoReopenEvent(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-501")

	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-501", "--to", "Issues",
		"--status", "Ready for testing", "--why", "runtime GREEN owed, not a defect"}); code != exitOK {
		t.Fatalf("moveCmd: exit %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	if n := historyCount(t, db, "WIT-501", "Reopened"); n != 0 {
		t.Fatalf("move minted %d Reopened history event(s), want 0 — a non-demotion "+
			"relocation must never inflate the §11.4.55 reopens_count signal", n)
	}
	if n := historyCount(t, db, "WIT-501", "Updated"); n != 1 {
		t.Errorf("Updated audit rows = %d, want 1 (the relocation must still be audited)", n)
	}

	it, _ := loadItem(db, "WIT-501", "Issues")
	if it != nil && strings.Contains(it.BodyMD, "**Reopened-Details:**") {
		t.Error("move injected a §11.4.34 **Reopened-Details:** block — that is reopen's semantics, not move's")
	}
}

// TestMoveCmd_PreservesAuthoredBody: a relocation may change EXACTLY the
// `**Status:**` line; every other authored byte survives.
func TestMoveCmd_PreservesAuthoredBody(t *testing.T) {
	dbPath := newTestDB(t)
	rich := seedRichFixedItem(t, dbPath, "WIT-502")

	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-502", "--to", "Issues",
		"--status", "Ready for testing", "--why", "runtime GREEN owed"}); code != exitOK {
		t.Fatalf("moveCmd: exit %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, _ := loadItem(db, "WIT-502", "Issues")
	if it == nil {
		t.Fatal("WIT-502 not found in Issues")
	}

	want := strings.ReplaceAll(rich, "**Status:** Fixed (→ Fixed.md)", "**Status:** Ready for testing")
	if it.BodyMD != want {
		t.Fatalf("body not preserved: got %d bytes, want %d — a relocation may change "+
			"ONLY the **Status:** line", len(it.BodyMD), len(want))
	}
}

// TestMoveCmd_PureRelocationIsByteIdentical: with no --status, the body must come
// through byte-for-byte (canonicalizeBodyStatusLine is a STRICT no-op).
func TestMoveCmd_PureRelocationIsByteIdentical(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "High",
		"an open item relocated without a status change",
		"a sufficiently long description that clears the §11.4.91 floor for the move test")

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	before, _ := loadItem(db, "WIT-001", "Issues")
	db.Close()
	if before == nil {
		t.Fatal("seed did not land WIT-001 in Issues")
	}

	// Issues→Issues: no location change, no status change — a strict no-op on body.
	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-001", "--to", "Issues",
		"--why", "no-op relocation exercising the byte-identical path"}); code != exitOK {
		t.Fatalf("moveCmd: exit %d", code)
	}

	db, err = openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	after, _ := loadItem(db, "WIT-001", "Issues")
	if after == nil {
		t.Fatal("WIT-001 vanished")
	}
	if after.BodyMD != before.BodyMD {
		t.Fatalf("pure relocation mutated body_md (%d → %d bytes)", len(before.BodyMD), len(after.BodyMD))
	}
}

// TestMoveCmd_RefusesInvariantViolatingCombinations is the §11.4.201 golden-TRUE
// half: move must REFUSE any destination/status pair that would CREATE the INTEG-03
// location↔status desync `validate` catches.
func TestMoveCmd_RefusesInvariantViolatingCombinations(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssue(t, dbPath, "Bug", "High",
		"an open item that must not be moved to Fixed while non-terminal",
		"a sufficiently long description that clears the §11.4.91 floor for the guard test")
	seedFixedItem(t, dbPath, "WIT-510")

	// (a) non-terminal status → Fixed: forbidden (this IS INTEG-03).
	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-001", "--to", "Fixed",
		"--why", "should be refused"}); code == exitOK {
		t.Error("move accepted a NON-terminal status at Fixed — it created the INTEG-03 desync it must prevent")
	}
	// (b) terminal status → Issues: forbidden (the mirror desync).
	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-510", "--to", "Issues",
		"--why", "should be refused"}); code == exitOK {
		t.Error("move accepted a TERMINAL status at Issues without a --status override")
	}

	// Neither refusal may have mutated anything.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if it, _ := loadItem(db, "WIT-001", "Issues"); it == nil {
		t.Error("refused move relocated WIT-001 anyway")
	}
	if it, _ := loadItem(db, "WIT-510", "Fixed"); it == nil {
		t.Error("refused move relocated WIT-510 anyway")
	}
}

// TestMoveCmd_DoesNotRefuseLegitimateMoves is the §11.4.201 golden-FALSE half — the
// false-positive guard. A guard that refuses everything is a FAIL-bluff (§11.4.1),
// indistinguishable from a correct guard if only the refusal case is tested.
func TestMoveCmd_DoesNotRefuseLegitimateMoves(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-520")

	// Fixed → Issues WITH a non-terminal --status: legitimate, must be accepted.
	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-520", "--to", "Issues",
		"--status", "In testing", "--why", "legitimate reverse-of-close"}); code != exitOK {
		t.Fatalf("move REFUSED a legitimate Fixed→Issues relocation (exit %d) — §11.4.201 false-positive refusal", code)
	}
	// Issues → Fixed WITH a terminal --status: legitimate, must be accepted.
	if code := moveCmd([]string{"--db", dbPath, "--id", "WIT-520", "--to", "Fixed",
		"--status", "Fixed (→ Fixed.md)", "--why", "legitimate re-close"}); code != exitOK {
		t.Fatalf("move REFUSED a legitimate Issues→Fixed relocation (exit %d) — §11.4.201 false-positive refusal", code)
	}
}

// TestMoveCmd_RejectsIncompleteInvocation: --to and --why are mandatory; an
// unexplained relocation is a §11.4.6 gap.
func TestMoveCmd_RejectsIncompleteInvocation(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-530")

	cases := []struct {
		name string
		args []string
	}{
		{"missing --to", []string{"--db", dbPath, "--id", "WIT-530", "--why", "x"}},
		{"bad --to", []string{"--db", dbPath, "--id", "WIT-530", "--to", "Archive", "--why", "x"}},
		{"missing --why", []string{"--db", dbPath, "--id", "WIT-530", "--to", "Issues", "--status", "Ready for testing"}},
		{"missing --id", []string{"--db", dbPath, "--to", "Issues", "--why", "x"}},
		{"unknown id", []string{"--db", dbPath, "--id", "WIT-999", "--to", "Issues", "--why", "x"}},
	}
	for _, tc := range cases {
		if code := moveCmd(tc.args); code == exitOK {
			t.Errorf("%s: moveCmd returned exitOK, want a usage refusal", tc.name)
		}
	}
}
