// correct_evidence_test.go — anti-bluff coverage for the
// `correct-history-evidence` subcommand.
//
// §11.4.115 RED-first: authored BEFORE the subcommand's decisions were wired.
// The three cases below assert:
//
//   (1) golden-BAD — attempt correction with a NON-existent evidence path →
//       tool exits non-zero, the target item_history row is UNCHANGED, and
//       no `Updated` audit row is appended. (Fails on a stub that skips the
//       checkEvidencePath call.)
//   (2) golden-GOOD — a valid correction against a real file → tool exits 0,
//       the target row's evidence_path is the new value, an audit row is
//       appended recording old→new, and `workable-items validate` now reports
//       ZERO violations for the item's closure-evidence class.
//   (3) golden-BAD — attempt correction on a NON-terminal item → tool refuses
//       with a clear error. §11.4.226 evidence-class-at-closure applies to
//       CLOSED items; retro-editing an open item's audit trail is out of scope.
//
// All three drive the REAL subcommands + REAL SQLite driver against a fresh
// temp DB; never touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// seedClosedItem opens a fresh temp DB with one Completed Task item and
// returns (dbPath, atmID, closureHistoryID). The closure history row cites
// a real evidence file so validate is clean at the starting line.
func seedClosedItem(t *testing.T) (string, string, int64, string) {
	t.Helper()
	dbPath := newTestDB(t)
	const id = "WIT-901"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "correct-history-evidence seed item",
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Task", "Low",
	}); code != exitOK {
		t.Fatalf("seed add exited %d", code)
	}
	realFile := filepath.Join(t.TempDir(), "SEED_EVIDENCE.md")
	if err := os.WriteFile(realFile, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write seed evidence: %v", err)
	}
	if code := closeCmd([]string{"--db", dbPath, "--status", "completed", "--evidence", realFile, id}); code != exitOK {
		t.Fatalf("seed close exited %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	var hid int64
	if err := db.QueryRow(
		`SELECT id FROM item_history WHERE atm_id=? AND event_type='Completed' ORDER BY id DESC LIMIT 1`,
		id,
	).Scan(&hid); err != nil {
		t.Fatalf("query closure history id: %v", err)
	}
	return dbPath, id, hid, realFile
}

// forceEvidenceNarrative rewrites the closure row's evidence_path to a
// narrative sentence (the exact BOB-009/BOB-010 defect shape) so the
// correction subcommand has something real to repair.
func forceEvidenceNarrative(t *testing.T, dbPath, atmID string, hid int64, narrative string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(
		`UPDATE item_history SET evidence_path=? WHERE id=? AND atm_id=?`,
		narrative, hid, atmID,
	); err != nil {
		t.Fatalf("force narrative evidence: %v", err)
	}
}

// historyEvidence returns the evidence_path of one item_history row.
func historyEvidence(t *testing.T, dbPath string, hid int64) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var ev string
	if err := db.QueryRow(
		`SELECT COALESCE(evidence_path,'') FROM item_history WHERE id=?`, hid,
	).Scan(&ev); err != nil {
		t.Fatalf("read history evidence: %v", err)
	}
	return ev
}

// countHistory returns the number of rows for an item.
func countHistory(t *testing.T, dbPath, atmID string) int {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM item_history WHERE atm_id=?`, atmID).Scan(&n); err != nil {
		t.Fatalf("count history: %v", err)
	}
	return n
}

// TestCorrectHistoryEvidence_RefusesNonExistentPath — golden-BAD (1):
// a non-existent evidence path is refused BEFORE any DB write, and the
// row + audit trail are byte-identical afterwards.
func TestCorrectHistoryEvidence_RefusesNonExistentPath(t *testing.T) {
	dbPath, id, hid, _ := seedClosedItem(t)
	narrative := "boba-ctl is now default for start/stop; --no-boba-ctl falls back to raw compose"
	forceEvidenceNarrative(t, dbPath, id, hid, narrative)
	evBefore := historyEvidence(t, dbPath, hid)
	countBefore := countHistory(t, dbPath, id)

	fabricated := filepath.Join(t.TempDir(), "DEFINITELY_NOT_A_REAL_PATH", "x.log")
	code := correctHistoryEvidenceCmd([]string{
		"--db", dbPath, "--atm-id", id,
		"--history-id", itoaInt64(hid),
		"--evidence-path", fabricated,
		"--reason", "attempt with fabricated path",
	})
	if code == exitOK {
		t.Fatalf("correct-history-evidence ACCEPTED a fabricated path %q (exit %d) — the record-time guard is not wired", fabricated, code)
	}
	if got := historyEvidence(t, dbPath, hid); got != evBefore {
		t.Fatalf("refused but MUTATED evidence_path anyway: %q -> %q", evBefore, got)
	}
	if got := countHistory(t, dbPath, id); got != countBefore {
		t.Fatalf("refused but wrote %d new audit row(s); a refused correction must leave no audit trace", got-countBefore)
	}
}

// TestCorrectHistoryEvidence_GreenApplyAndAudit — golden-GOOD (2):
// a real evidence path is accepted, the row's evidence_path becomes the new
// value, and a new `Updated` audit row records the correction with old→new
// visible in the reason field. Post-fix, validate reports ZERO violations
// for this item's closure-evidence class.
func TestCorrectHistoryEvidence_GreenApplyAndAudit(t *testing.T) {
	dbPath, id, hid, _ := seedClosedItem(t)
	narrative := "SQLite DB integrated with pre-build gate; 20 items tracked; docs_chain validation wired"
	forceEvidenceNarrative(t, dbPath, id, hid, narrative)
	countBefore := countHistory(t, dbPath, id)

	newEv := filepath.Join(t.TempDir(), "CORRECTED_EVIDENCE.md")
	if err := os.WriteFile(newEv, []byte("real captured evidence pointing to the shipped fix\n"), 0o644); err != nil {
		t.Fatalf("write new evidence: %v", err)
	}
	code := correctHistoryEvidenceCmd([]string{
		"--db", dbPath, "--atm-id", id,
		"--history-id", itoaInt64(hid),
		"--evidence-path", newEv,
		"--reason", "commit 0558399: the shipped script backing this closure",
	})
	if code != exitOK {
		t.Fatalf("correct-history-evidence REFUSED a valid correction (exit %d)", code)
	}

	if got := historyEvidence(t, dbPath, hid); got != newEv {
		t.Fatalf("evidence_path not updated: got %q, want %q", got, newEv)
	}
	if got := countHistory(t, dbPath, id); got != countBefore+1 {
		t.Fatalf("expected exactly one new audit row, got delta %d", got-countBefore)
	}

	// Newest audit row is our correction event with old→new + reason.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var evt, by, reason, ev string
	if err := db.QueryRow(
		`SELECT event_type, COALESCE(by,''), COALESCE(reason,''), COALESCE(evidence_path,'')
		 FROM item_history WHERE atm_id=? ORDER BY id DESC LIMIT 1`, id,
	).Scan(&evt, &by, &reason, &ev); err != nil {
		t.Fatalf("query newest audit row: %v", err)
	}
	if evt != "Updated" {
		t.Fatalf("audit event_type = %q, want Updated (closed-set CHECK forbids EvidenceCorrected)", evt)
	}
	if by != "AI" {
		t.Fatalf("audit by = %q, want AI", by)
	}
	if !strings.Contains(reason, "evidence-corrected") {
		t.Errorf("audit reason lacks 'evidence-corrected' marker: %q", reason)
	}
	if !strings.Contains(reason, "commit 0558399") {
		t.Errorf("audit reason lacks operator's --reason text: %q", reason)
	}
	if ev != newEv {
		t.Errorf("audit evidence_path = %q, want %q", ev, newEv)
	}

	// validate now reports ZERO closure-evidence violations for this item.
	// validateCmd writes to stdout; capture and grep.
	stdout := captureValidateOutput(t, func() int {
		return validateCmd([]string{"--db", dbPath})
	})
	if strings.Contains(stdout, id+":") && strings.Contains(stdout, "closure evidence_path does not resolve") {
		t.Fatalf("validate still reports closure-evidence violation for %s after correction:\n%s", id, stdout)
	}
}

// TestCorrectHistoryEvidence_RefusesNonTerminalItem — golden-BAD (3):
// the subcommand refuses when the item's Status is NON-terminal.
func TestCorrectHistoryEvidence_RefusesNonTerminalItem(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "WIT-902"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "non-terminal item probe",
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "Low",
	}); code != exitOK {
		t.Fatalf("seed add exited %d", code)
	}
	// Grab the Opened history id (there is always at least one row per add).
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	var hid int64
	if err := db.QueryRow(
		`SELECT id FROM item_history WHERE atm_id=? ORDER BY id ASC LIMIT 1`, id,
	).Scan(&hid); err != nil {
		t.Fatalf("query opened history id: %v", err)
	}
	db.Close()

	realFile := filepath.Join(t.TempDir(), "IRRELEVANT.md")
	if err := os.WriteFile(realFile, []byte("does not matter\n"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	code := correctHistoryEvidenceCmd([]string{
		"--db", dbPath, "--atm-id", id,
		"--history-id", itoaInt64(hid),
		"--evidence-path", realFile,
		"--reason", "should be refused — item is open",
	})
	if code == exitOK {
		t.Fatalf("correct-history-evidence ACCEPTED correction on a NON-terminal item (exit %d) — §11.4.226 scope violation", code)
	}
}

// itoaInt64 avoids pulling strconv into a test-only helper block.
func itoaInt64(n int64) string {
	// small positive numbers, path only sees history ids
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	neg := false
	if n < 0 {
		neg = true
		n = -n
	}
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// captureValidateOutput redirects os.Stdout for the duration of fn and returns
// the captured bytes, ignoring fn's exit code (validateCmd may return exitUsage
// on violations, but we grep for a specific item — a distinct helper avoids the
// version_tags_test.go captureStdout's rc==exitOK precondition).
func captureValidateOutput(t *testing.T, fn func() int) string {
	t.Helper()
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	done := make(chan string, 1)
	go func() {
		var b [8192]byte
		var sb strings.Builder
		for {
			n, err := r.Read(b[:])
			if n > 0 {
				sb.Write(b[:n])
			}
			if err != nil {
				done <- sb.String()
				return
			}
		}
	}()
	_ = fn()
	w.Close()
	os.Stdout = orig
	return <-done
}
