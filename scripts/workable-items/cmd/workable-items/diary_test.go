// diary_test.go — §11.4.149 testing-diary unit tests.
//
// Covers: diary-add inserts one row keyed to a sub-task, PASS-without-evidence
// rejected (CLI guard AND schema CHECK), bad tested_by/result rejected, the
// derived summary VIEW, and the summary < description size invariant. Anti-bluff
// per §11.4.27(A): real SQLite DB.
package main

import (
	"os"
	"path/filepath"
	"testing"
)

func newTestDBWithSubtask(t *testing.T) (dbPath, child string) {
	t.Helper()
	dbPath = newTestDBWithParent(t, "ATM-300")
	if code := subtaskAddCmd([]string{"ATM-300", "--db", dbPath, "--session", "diary-session",
		"--description", "a session with a deliberately long description so the summary stays strictly shorter than it for the size-invariant test"}); code != exitOK {
		t.Fatalf("subtask-add: %d", code)
	}
	return dbPath, "ATM-300-001"
}

func TestDiaryAddInsertsRow(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	if code := diaryAddCmd([]string{"--subtask", child, "--db", dbPath,
		"--tested-by", "AI-agent", "--result", "FAIL",
		"--observations", "RED reproduced on artifact b01bef8 — codec rejected EAC3",
		"--action", "status: In testing -> Reopened"}); code != exitOK {
		t.Fatalf("diary-add FAIL row: exit %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM test_diary WHERE atm_id=?`, child).Scan(&n)
	if n != 1 {
		t.Fatalf("diary rows = %d, want 1", n)
	}
}

func TestDiaryAddPassRequiresEvidence(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	// PASS without --evidence MUST be rejected by the CLI guard.
	if code := diaryAddCmd([]string{"--subtask", child, "--db", dbPath,
		"--tested-by", "AI-agent", "--result", "PASS",
		"--observations", "looked green"}); code == exitOK {
		t.Fatalf("PASS without evidence must FAIL (CLI guard)")
	}
	// PASS WITH evidence must succeed.
	if code := diaryAddCmd([]string{"--subtask", child, "--db", dbPath,
		"--tested-by", "AI-agent", "--result", "PASS", "--evidence", "qa-results/run/wav.json",
		"--observations", "5.1 EAC3 GREEN N=3, ffprobe 6ch"}); code != exitOK {
		t.Fatalf("PASS with evidence: exit %d", code)
	}
}

func TestDiarySchemaCheckRejectsPassNoEvidence(t *testing.T) {
	// Belt-and-suspenders: the schema CHECK must independently reject a PASS row
	// with an empty evidence_path even if a future caller bypassed the CLI guard.
	dbPath, child := newTestDBWithSubtask(t)
	db, _ := openDB(dbPath)
	defer db.Close()
	_, err := db.Exec(`INSERT INTO test_diary(atm_id,date_time,tested_by,result,observations,action_taken)
		VALUES(?,?,?,?,?,?)`, child, "2026-06-10T00:00:00Z", "AI-agent", "PASS", "x", "y")
	if err == nil {
		t.Fatalf("schema CHECK must reject a PASS row with no evidence_path")
	}
}

func TestDiaryAddRejectsBadEnums(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	if code := diaryAddCmd([]string{"--subtask", child, "--db", dbPath,
		"--tested-by", "Robot", "--result", "FAIL", "--observations", "x"}); code == exitOK {
		t.Fatalf("bad --tested-by must FAIL")
	}
	if code := diaryAddCmd([]string{"--subtask", child, "--db", dbPath,
		"--tested-by", "AI-agent", "--result", "MAYBE", "--observations", "x"}); code == exitOK {
		t.Fatalf("bad --result must FAIL")
	}
}

func TestDiarySummaryView(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	// 1 FAIL + 1 PASS + 1 SKIP.
	_ = diaryAddCmd([]string{"--subtask", child, "--db", dbPath, "--tested-by", "AI-agent",
		"--result", "FAIL", "--observations", "first run failed", "--date-time", "2026-06-10T01:00:00Z"})
	_ = diaryAddCmd([]string{"--subtask", child, "--db", dbPath, "--tested-by", "HelixQA",
		"--result", "PASS", "--evidence", "qa/x.json", "--feature-class", "audio_output",
		"--observations", "second run green", "--date-time", "2026-06-10T02:00:00Z"})
	_ = diaryAddCmd([]string{"--subtask", child, "--db", dbPath, "--tested-by", "AI-agent",
		"--result", "SKIP", "--result-detail", "geo_restricted",
		"--observations", "third skipped", "--date-time", "2026-06-10T03:00:00Z"})

	db, _ := openDB(dbPath)
	defer db.Close()
	s, err := loadSummary(db, child)
	if err != nil {
		t.Fatalf("loadSummary: %v", err)
	}
	if s.TotalRuns != 3 || s.PassRuns != 1 || s.FailRuns != 1 || s.SkipRuns != 1 {
		t.Fatalf("summary counts = %+v, want total3 pass1 fail1 skip1", s)
	}
	if s.LastResult != "SKIP" {
		t.Errorf("last_result = %q, want SKIP (newest by date_time)", s.LastResult)
	}
}

func TestSummaryGenSizeInvariant(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	_ = diaryAddCmd([]string{"--subtask", child, "--db", dbPath, "--tested-by", "AI-agent",
		"--result", "FAIL", "--result-detail", "a fairly long result detail string that could otherwise blow past the description length", "--observations", "x"})
	db, _ := openDB(dbPath)
	defer db.Close()
	s, _ := loadSummary(db, child)
	desc, _ := itemDescription(db, child)
	essence := buildSummaryEssence(s, mostRecentDetail(db, child), desc)
	if len(essence) >= len(desc) {
		t.Fatalf("summary essence (%d chars) must be STRICTLY shorter than description (%d chars)", len(essence), len(desc))
	}
}

func TestSubtaskExportWritesThreeMarkdownDocs(t *testing.T) {
	dbPath, child := newTestDBWithSubtask(t)
	_ = diaryAddCmd([]string{"--subtask", child, "--db", dbPath, "--tested-by", "AI-agent",
		"--result", "FAIL", "--observations", "diary content for export"})
	out := filepath.Join(t.TempDir(), "issues")
	// --no-formats: assert the three .md files exist without requiring pandoc.
	if code := subtaskExportCmd([]string{"--subtask", child, "--db", dbPath, "--out-dir", out, "--no-formats"}); code != exitOK {
		t.Fatalf("subtask-export: exit %d", code)
	}
	dir := filepath.Join(out, "ATM-300", "sessions", "001")
	for _, f := range []string{"Session.md", "Diary.md", "Summary.md"} {
		p := filepath.Join(dir, f)
		if _, err := os.Stat(p); err != nil {
			t.Errorf("expected %s to exist: %v", p, err)
		}
	}
}
