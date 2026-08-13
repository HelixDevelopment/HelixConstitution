// sync_diff_nopaths_test.go — §11.4.115 RED-baseline-on-the-broken-artifact +
// polarity-switch coverage for the diffCmd no-Markdown-paths false-positive.
//
// Defect (post Agent-E DB backfill, 2026-08-10): `workable-items diff --db <p>`
// invoked WITHOUT --issues/--fixed leaves the `parsed []item` slice empty, then
// the terminal loop `for _, d := range dbItems { if !parsedSeen[key] { print
// "- <id> present in DB, absent in Markdown" } }` reports EVERY DB row as
// absent-from-Markdown, manufacturing a false-positive divergence count equal
// to the DB row count (102 in-repo). The reference sync path — `sync db-to-md`
// — writes output byte-identical to the on-disk Issues.md/Fixed.md, so the DB
// and Markdown are provably in-sync; the false positives are entirely diff's
// own invention. Reference for the symmetric no-paths handling is syncMDToDB
// itself (sync.go:66-69), which errors out cleanly when both --issues and
// --fixed are absent instead of silently proceeding with no comparison basis.
//
// Root cause: when both path flags are empty diff has NO Markdown to compare
// against, but the code still runs the "everything in dbItems not in
// parsedSeen" loop, and `parsedSeen` is empty by construction, so every DB row
// is flagged. The desync-only invocation shape the block comment (sync.go
// lines 618-630) intended is defeated by the same terminal loop.
//
// Polarity switch per §11.4.115: env RED_MODE (default "1" = reproduce the
// defect on the PRE-FIX diffCmd; "0" = GREEN regression-guard asserting the
// FIXED diffCmd does NOT invent 'absent in Markdown' lines when neither path
// flag is passed). One source, two roles — the bug-catcher IS the
// regression-guard. No mocks: real SQLite driver + real md→db parser +
// real diffCmd throughout. redMode() shared with gap_dual_representation_test.go.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// TestDiffCmd_NoPathsSkipsMarkdownComparison is the no-Markdown-paths polarity
// test. Setup (both modes): write dualRepFixedFixture to a temp Fixed.md and
// syncMDToDB it into a temp SQLite DB. That DB is DEFINITIONALLY in-sync with
// that Fixed.md (it was just derived from it). The correct diff answer WHEN
// NEITHER --issues NOR --fixed is passed is either (a) "DB and Markdown are in
// sync" with exitOK, OR (b) a usage error requesting the paths — but NEVER a
// silent stream of `- <id> present in DB, absent in Markdown` false positives
// on a state that is provably in-sync.
func TestDiffCmd_NoPathsSkipsMarkdownComparison(t *testing.T) {
	tmp := t.TempDir()
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on dual-rep fixture exited %d", code)
	}

	if redMode() {
		// PRE-FIX artifact: run the CURRENT diffCmd without --issues/--fixed
		// against the in-sync DB and prove it manufactures at least one
		// false-positive 'present in DB, absent in Markdown' line — the exact
		// defect the real-repo run (102 differences on a byte-identical DB↔MD
		// state) exhibited. §11.4.5 defect-present captured evidence.
		_, out := captureDiff(t, []string{"--db", dbPath})
		if !strings.Contains(out, "present in DB, absent in Markdown") {
			t.Fatalf("RED: expected diff --db without --issues/--fixed to invent "+
				"false-positive 'present in DB, absent in Markdown' lines on an "+
				"in-sync DB, but output has none — defect not reproduced:\n%s", out)
		}
		t.Logf("RED reproduced: diff --db without --issues/--fixed manufactures "+
			"false-positive 'absent in Markdown' line(s) on a genuinely in-sync DB")
		return
	}

	// GREEN guard on the FIXED artifact: no --issues/--fixed given → NO
	// Markdown-vs-DB comparison is meaningful, so diffCmd MUST NOT report DB
	// rows as 'absent in Markdown'. Correct behaviour: in-sync verdict with
	// exitOK (the desync-only invocation still runs its own checks per the
	// sync.go:618-630 comment; those checks are ORTHOGONAL to parsed-vs-DB
	// comparison, which is skipped when there is nothing parsed).
	rc, out := captureDiff(t, []string{"--db", dbPath})

	if strings.Contains(out, "present in DB, absent in Markdown") {
		t.Fatalf("GREEN: diff --db without --issues/--fixed still emits spurious "+
			"'present in DB, absent in Markdown' line(s) on an in-sync DB "+
			"(no-Markdown-comparison defect regressed):\n%s", out)
	}
	if rc != exitOK {
		t.Fatalf("GREEN: diff --db without --issues/--fixed exited %d (want exitOK %d) "+
			"on an in-sync DB:\n%s", rc, exitOK, out)
	}
	if !strings.Contains(out, "in sync") {
		t.Fatalf("GREEN: diff --db without --issues/--fixed did not report in-sync; "+
			"stdout=%q", out)
	}
	t.Logf("GREEN: diff --db without --issues/--fixed correctly skips the parsed-vs-DB "+
		"comparison (nothing to parse) and reports DB and Markdown in-sync")
}
