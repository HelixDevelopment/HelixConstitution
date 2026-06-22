// diary_cmd_test.go — §11.4.149 + §11.4.27(A) tests for the `diary` subcommand
// group (add | list | summary). Anti-bluff: every test runs against a REAL
// SQLite DB (no mocks beyond the unit layer). The PASS-requires-existing-evidence
// case is authored §11.4.115 RED-polarity style — it PROVES the anti-bluff
// constraint genuinely fires on a PASS whose evidence path does not exist.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// (a) diary add PASS with a real on-disk evidence file → row inserted.
func TestDiaryGroupAddPassWithRealEvidence(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)

	ev := filepath.Join(t.TempDir(), "wav_rms.json")
	if err := os.WriteFile(ev, []byte(`{"rms":0.42,"channels":6}`), 0o644); err != nil {
		t.Fatalf("write evidence fixture: %v", err)
	}

	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath,
		"--tested-by", "HelixQA", "--result", "PASS",
		"--evidence", ev, "--feature-class", "audio_output",
		"--observations", "5.1 EAC3 GREEN N=3, ffprobe 6ch",
		"--detail", "decoder healthy",
		"--action-taken", "status: In testing -> Ready for testing",
		"--status-from", "In testing", "--status-to", "Ready for testing",
	}); code != exitOK {
		t.Fatalf("diary add PASS with real evidence: exit %d", code)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	var n, statusChanged int
	var evPath, fclass string
	if err := db.QueryRow(`SELECT COUNT(*) FROM test_diary WHERE atm_id=?`, child).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 1 {
		t.Fatalf("diary rows = %d, want 1", n)
	}
	if err := db.QueryRow(`SELECT status_changed, evidence_path, feature_class
		FROM test_diary WHERE atm_id=?`, child).Scan(&statusChanged, &evPath, &fclass); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if statusChanged != 1 {
		t.Errorf("status_changed = %d, want 1 (status-from/to provided)", statusChanged)
	}
	if evPath != ev {
		t.Errorf("evidence_path = %q, want %q", evPath, ev)
	}
	if fclass != "audio_output" {
		t.Errorf("feature_class = %q, want audio_output", fclass)
	}
}

// (b) §11.4.115 RED-polarity: diary add PASS whose --evidence does NOT exist on
// disk MUST be rejected (the anti-bluff constraint provably fires). RED_MODE=1
// (default) asserts the defect-class is caught; RED_MODE=0 documents the
// equivalent GREEN expectation (the constraint still rejects — same assertion,
// the invariant is "missing/empty/nonexistent evidence ⇒ PASS rejected").
func TestDiaryGroupAddPassRejectsMissingEvidence(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)

	// Empty --evidence on a PASS → rejected.
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "PASS",
		"--observations", "looked green",
	}); code == exitOK {
		t.Fatalf("RED: PASS with EMPTY evidence must be rejected, got exitOK")
	}

	// Nonexistent --evidence path on a PASS → rejected (the on-disk check).
	nonexistent := filepath.Join(t.TempDir(), "does_not_exist.json")
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "PASS",
		"--evidence", nonexistent, "--observations", "claims green but no artefact",
	}); code == exitOK {
		t.Fatalf("RED: PASS with NONEXISTENT evidence must be rejected, got exitOK")
	}

	// A directory is not a valid evidence file either → rejected.
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "PASS",
		"--evidence", t.TempDir(), "--observations", "points at a dir",
	}); code == exitOK {
		t.Fatalf("RED: PASS with a DIRECTORY as evidence must be rejected, got exitOK")
	}

	// Prove the rejections left NO row behind (the constraint is enforced
	// pre-insert, so nothing leaked into the DB).
	db, _ := openDB(dbPath)
	defer db.Close()
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM test_diary WHERE atm_id=?`, child).Scan(&n)
	if n != 0 {
		t.Fatalf("rejected PASS runs must not insert any row; got %d", n)
	}
}

// (c) FAIL / SKIP without evidence → allowed (only PASS demands evidence).
func TestDiaryGroupAddFailSkipNoEvidence(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)

	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "FAIL",
		"--observations", "RED reproduced on broken artifact b01bef8 — codec rejected EAC3",
	}); code != exitOK {
		t.Fatalf("FAIL without evidence must be allowed: exit %d", code)
	}
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "Operator", "--result", "SKIP",
		"--detail", "geo_restricted", "--observations", "catalogue unreachable from this region",
	}); code != exitOK {
		t.Fatalf("SKIP without evidence must be allowed: exit %d", code)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM test_diary WHERE atm_id=?`, child).Scan(&n)
	if n != 2 {
		t.Fatalf("diary rows = %d, want 2 (FAIL + SKIP)", n)
	}
}

// (d) invalid --tested-by / --result → rejected.
func TestDiaryGroupAddRejectsBadEnums(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "Robot", "--result", "FAIL",
		"--observations", "x",
	}); code == exitOK {
		t.Fatalf("bad --tested-by must be rejected")
	}
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "MAYBE",
		"--observations", "x",
	}); code == exitOK {
		t.Fatalf("bad --result must be rejected")
	}
}

// (e) unknown --id (not present in items) → rejected.
func TestDiaryGroupAddRejectsUnknownID(t *testing.T) {
	dbPath, _ := newTestDBWithSubtask(t)
	if code := diaryGroupAddCmd([]string{
		"--id", "ATM-999-777", "--db", dbPath, "--tested-by", "AI-agent", "--result", "FAIL",
		"--observations", "no such target",
	}); code == exitOK {
		t.Fatalf("unknown --id must be rejected")
	}
}

// (f) diary list / diary summary round-trip over a real recorded sequence.
func TestDiaryGroupListAndSummaryRoundTrip(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)

	ev := filepath.Join(t.TempDir(), "pass.json")
	if err := os.WriteFile(ev, []byte(`{"ok":true}`), 0o644); err != nil {
		t.Fatalf("write evidence: %v", err)
	}
	// FAIL, then PASS (newest) — recorded with explicit timestamps so ordering is
	// deterministic (§11.4.50).
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "FAIL",
		"--observations", "first run failed", "--date-time", "2026-06-10T01:00:00Z",
	}); code != exitOK {
		t.Fatalf("seed FAIL: exit %d", code)
	}
	if code := diaryGroupAddCmd([]string{
		"--id", child, "--db", dbPath, "--tested-by", "HelixQA", "--result", "PASS",
		"--evidence", ev, "--feature-class", "audio_output",
		"--observations", "second run green", "--date-time", "2026-06-10T02:00:00Z",
	}); code != exitOK {
		t.Fatalf("seed PASS: exit %d", code)
	}

	// diary list exits OK and finds the rows.
	if code := diaryGroupListCmd([]string{"--id", child, "--db", dbPath}); code != exitOK {
		t.Fatalf("diary list: exit %d", code)
	}
	// diary list on an unknown id is not an error (prints "no diary entries").
	if code := diaryGroupListCmd([]string{"--id", "ATM-300", "--db", dbPath}); code != exitOK {
		t.Fatalf("diary list on item with no diary rows should exit OK: %d", code)
	}

	// diary summary (single) exits OK; cross-check the rollup via the helper.
	if code := diaryGroupSummaryCmd([]string{"--id", child, "--db", dbPath}); code != exitOK {
		t.Fatalf("diary summary --id: exit %d", code)
	}
	// diary summary (all) exits OK.
	if code := diaryGroupSummaryCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("diary summary (all): exit %d", code)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	s, err := loadSummary(db, child)
	if err != nil {
		t.Fatalf("loadSummary: %v", err)
	}
	if s.TotalRuns != 2 || s.PassRuns != 1 || s.FailRuns != 1 {
		t.Fatalf("summary = %+v, want total2 pass1 fail1", s)
	}
	if s.LastResult != "PASS" {
		t.Errorf("last_result = %q, want PASS (newest by date_time)", s.LastResult)
	}

	// loadDiary returns newest-first → PASS leads.
	rows, err := loadDiary(db, child)
	if err != nil {
		t.Fatalf("loadDiary: %v", err)
	}
	if len(rows) != 2 || rows[0].Result != "PASS" {
		t.Fatalf("loadDiary newest-first PASS expected; got %d rows, first=%q", len(rows), firstResult(rows))
	}
}

// --id / --db requiredness on each subcommand.
func TestDiaryGroupRequiredFlags(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	if code := diaryGroupAddCmd([]string{"--db", dbPath, "--tested-by", "AI-agent", "--result", "FAIL", "--observations", "x"}); code == exitOK {
		t.Errorf("diary add without --id must be rejected")
	}
	if code := diaryGroupListCmd([]string{"--db", dbPath}); code == exitOK {
		t.Errorf("diary list without --id must be rejected")
	}
	if code := diaryGroupAddCmd([]string{"--id", child, "--tested-by", "AI-agent", "--result", "FAIL", "--observations", "x"}); code == exitOK {
		t.Errorf("diary add without --db must be rejected")
	}
	if code := diaryGroupSummaryCmd([]string{}); code == exitOK {
		t.Errorf("diary summary without --db must be rejected")
	}
	// observations required.
	if code := diaryGroupAddCmd([]string{"--id", child, "--db", dbPath, "--tested-by", "AI-agent", "--result", "FAIL"}); code == exitOK {
		t.Errorf("diary add without --observations must be rejected")
	}
}

func firstResult(rows []diaryRow) string {
	if len(rows) == 0 {
		return ""
	}
	return strings.TrimSpace(rows[0].Result)
}
