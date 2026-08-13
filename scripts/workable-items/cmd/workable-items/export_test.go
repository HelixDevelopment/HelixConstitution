// export_test.go — real-SQLite behavioural tests for the `export` subcommand.
//
// §11.4.93 + §11.4.12 + §11.4.53 anti-bluff: these seed a known DB via the real
// addCmd / closeCmd entry points, run exportCmd, then read the emitted files
// back and assert their CONTENT (summary tallies, per-item rows). No mock — real
// SQLite, real command dispatch, real file IO. The pandoc-gated path is asserted
// honest: with --no-formats the .md docs exist and NO sibling is fabricated.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExportCmd_EmitsDocsAndSummaries(t *testing.T) {
	dbPath := newTestDB(t)

	// Two open issues + one closed item.
	if code := addCmd([]string{"Bug", "High", "--db", dbPath,
		"--title", "An open bug in search",
		"--description", "Search returns no results for a known query to the user"}); code != exitOK {
		t.Fatalf("add bug: %d", code)
	}
	if code := addCmd([]string{"Feature", "Medium", "--db", dbPath,
		"--title", "A pending dark mode feature",
		"--description", "Add a dark mode toggle so users can switch themes here"}); code != exitOK {
		t.Fatalf("add feature: %d", code)
	}
	if code := addCmd([]string{"Task", "Low", "--db", dbPath,
		"--title", "A task to be completed",
		"--description", "Refactor the navigation helper to reduce duplicated route code"}); code != exitOK {
		t.Fatalf("add task: %d", code)
	}
	if code := closeCmd([]string{"WIT-003", "--db", dbPath, "--status", "completed",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "qa-results/2026-05-31/wit-003.log")}); code != exitOK {
		t.Fatalf("close task: %d", code)
	}

	outDir := t.TempDir()
	code := exportCmd([]string{"--db", dbPath, "--out-dir", outDir, "--no-formats"})
	if code != exitOK {
		t.Fatalf("exportCmd exit = %d, want %d", code, exitOK)
	}

	// All four .md docs exist.
	for _, name := range []string{"Issues.md", "Fixed.md", "Issues_Summary.md", "Fixed_Summary.md"} {
		p := filepath.Join(outDir, name)
		if fi, err := os.Stat(p); err != nil || fi.Size() == 0 {
			t.Errorf("%s missing or empty (err=%v)", name, err)
		}
	}

	// §6.J honesty: --no-formats means NO html/pdf/docx siblings fabricated.
	for _, name := range []string{"Issues.html", "Issues.pdf", "Issues.docx",
		"Issues_Summary.html", "Fixed_Summary.pdf"} {
		if _, err := os.Stat(filepath.Join(outDir, name)); err == nil {
			t.Errorf("%s was fabricated under --no-formats (must not exist)", name)
		}
	}

	// Issues_Summary: open-only — contains the two open items, NOT the closed one.
	is := readFile(t, filepath.Join(outDir, "Issues_Summary.md"))
	if !strings.Contains(is, "WIT-001") || !strings.Contains(is, "WIT-002") {
		t.Errorf("Issues_Summary missing open items:\n%s", is)
	}
	if strings.Contains(is, "WIT-003") {
		t.Errorf("Issues_Summary leaked closed item WIT-003:\n%s", is)
	}
	if !strings.Contains(is, "Counts by Type × Status") {
		t.Errorf("Issues_Summary missing tally header:\n%s", is)
	}
	if !strings.Contains(is, "| Bug | Queued | 1 |") {
		t.Errorf("Issues_Summary missing expected Bug/Queued count:\n%s", is)
	}

	// Fixed_Summary: closed-only — contains the closed item with terminal status.
	fs := readFile(t, filepath.Join(outDir, "Fixed_Summary.md"))
	if !strings.Contains(fs, "WIT-003") {
		t.Errorf("Fixed_Summary missing closed item WIT-003:\n%s", fs)
	}
	if strings.Contains(fs, "WIT-001") {
		t.Errorf("Fixed_Summary leaked open item WIT-001:\n%s", fs)
	}
	if !strings.Contains(fs, "Completed (→ Fixed.md)") {
		t.Errorf("Fixed_Summary missing terminal closure status:\n%s", fs)
	}
}

// TestFixedSummary_ColumnAlignedHeader guards the §11.4.19 / §11.4.53
// column-alignment mandate the CM-FIXED-COLUMN-ALIGNMENT pre-build gate enforces:
// the Fixed_Summary items table header MUST be
// `| # | Level | Status | Type | Fixed-In Tag(s) | One-line description |`.
// RED before the renderFixedItemRows fix (the shared renderItemRows emitted
// `| ATM ID | Type | Status | Severity | Description |`), GREEN after. The
// Issues_Summary header MUST stay the open-tracker layout (the fix is scoped to
// the closed archive), and the closed item's stable id MUST remain visible.
func TestFixedSummary_ColumnAlignedHeader(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{"Task", "Low", "--db", dbPath,
		"--title", "A task to be completed",
		"--description", "Refactor the navigation helper to reduce duplicated route code"}); code != exitOK {
		t.Fatalf("add task: %d", code)
	}
	if code := closeCmd([]string{"WIT-001", "--db", dbPath, "--status", "completed",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "qa-results/2026-07-10/wit-001.log")}); code != exitOK {
		t.Fatalf("close task: %d", code)
	}

	outDir := t.TempDir()
	if code := exportCmd([]string{"--db", dbPath, "--out-dir", outDir, "--no-formats"}); code != exitOK {
		t.Fatalf("exportCmd exit = %d, want %d", code, exitOK)
	}

	fs := readFile(t, filepath.Join(outDir, "Fixed_Summary.md"))
	const wantHeader = "| # | Level | Status | Type | Fixed-In Tag(s) | One-line description |"
	if !strings.Contains(fs, wantHeader) {
		t.Errorf("Fixed_Summary missing §11.4.19 column-aligned header %q:\n%s", wantHeader, fs)
	}
	if !strings.Contains(fs, "WIT-001") {
		t.Errorf("Fixed_Summary dropped the stable ATM id (must stay visible in the description cell):\n%s", fs)
	}

	is := readFile(t, filepath.Join(outDir, "Issues_Summary.md"))
	const issuesHeader = "| ATM ID | Type | Status | Severity | Description |"
	if !strings.Contains(is, issuesHeader) {
		t.Errorf("Issues_Summary open-tracker header changed (fix must be scoped to Fixed_Summary): want %q:\n%s", issuesHeader, is)
	}
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("readFile %s: %v", p, err)
	}
	return string(b)
}
