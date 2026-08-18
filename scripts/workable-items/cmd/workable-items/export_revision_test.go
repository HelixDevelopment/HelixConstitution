// export_revision_test.go — §11.4.44 monotonic-revision anti-regression
// coverage for `export`.
//
// Forensic anchor (task #68 / BOB-108, filed by BOB-069 subagent a9876d9b):
// `export` regenerated docs/Issues.md + docs/Fixed.md by replaying the
// §11.4.44 **Revision:**/**Last modified:** header VERBATIM from the
// doc_segments "raw" segment captured at the last `sync md-to-db` import —
// never reconciled against the value already committed to the on-disk
// target file. When the on-disk file's header was bumped forward (manually,
// or by any doc-sync path other than md-to-db) AFTER the last import,
// `export` silently REGRESSED the committed Revision counter downward.
// Reproduced LIVE against the real repo tree 2026-08-18: running the real
// binary via `export --db docs/workable_items.db --out-dir docs/` turned
// docs/Issues.md **Revision:** 8 -> 6 and docs/Fixed.md **Revision:** 17 ->
// 15 (both real regressions below the already-committed HEAD values,
// captured via `git diff` and immediately reverted via `git checkout` —
// nothing was left committed from that reproduction). §11.4.44: "monotonic
// positive integer, never reset, never skipped" — a regression is an
// unconditional violation.
//
// RED before the fix (reconcileRevisionHeader, export_revision.go): the
// pre-fix exportCmd wrote the DB's stale header verbatim, so
// TestExportCmd_NeverRegressesRevisionBelowCommittedFile failed with
// "**Revision:** 6" present in the output. GREEN after the fix.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestExportCmd_NeverRegressesRevisionBelowCommittedFile reproduces the
// BOB-108 defect end-to-end through the REAL exportCmd entry point (no
// mocks, real SQLite, real file IO): a DB whose stored §11.4.44 header is
// stale (Revision 6) relative to an already-committed on-disk file
// (Revision 8) MUST NOT regress the emitted Revision below 8 — and since a
// new item's body genuinely changes the regenerated content, the earned
// bump lands at 9, never at the DB's stale 6.
func TestExportCmd_NeverRegressesRevisionBelowCommittedFile(t *testing.T) {
	dbPath := newTestDB(t)

	// Seed a DB whose stored §11.4.44 header (doc_segments raw segment,
	// seq=0) is STALE relative to what is already committed on disk — the
	// exact shape a real `sync md-to-db` import leaves behind when the
	// on-disk file was bumped forward by a later, out-of-band edit.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	staleHeader := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 6\n" +
		"**Last modified:** 2026-08-15T12:15:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if _, err := db.Exec(`INSERT INTO doc_segments (document, seq, kind, atm_id, raw) VALUES (?,?,?,?,?)`,
		"Issues", 0, "raw", "", staleHeader); err != nil {
		db.Close()
		t.Fatalf("seed stale header segment: %v", err)
	}
	db.Close()

	if code := addCmd([]string{"Bug", "High", "--db", dbPath,
		"--title", "An open bug in search",
		"--description", "Search returns no results for a known query to the user"}); code != exitOK {
		t.Fatalf("add bug: %d", code)
	}

	outDir := t.TempDir()
	issuesPath := filepath.Join(outDir, "Issues.md")

	// The already-committed on-disk file — Revision 8, strictly AHEAD of the
	// DB's stale 6 — is exactly what a real repo checkout has BEFORE
	// `export` runs.
	committed := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 8\n" +
		"**Last modified:** 2026-08-18T16:50:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if err := os.WriteFile(issuesPath, []byte(committed), 0o644); err != nil {
		t.Fatalf("seed committed file: %v", err)
	}

	if code := exportCmd([]string{"--db", dbPath, "--out-dir", outDir, "--no-formats"}); code != exitOK {
		t.Fatalf("exportCmd exit = %d, want %d", code, exitOK)
	}

	got := readFile(t, issuesPath)
	if strings.Contains(got, "**Revision:** 6") {
		t.Fatalf("export REGRESSED the committed §11.4.44 Revision (8 -> 6) — the exact BOB-108 defect:\n%s", got)
	}
	if !strings.Contains(got, "**Revision:** 9") {
		t.Errorf("export must bump PAST the already-committed Revision (8) since content genuinely changed (a new item was added) — want **Revision:** 9, got:\n%s", got)
	}
}

// TestExportCmd_PreservesRevisionWhenContentUnchanged proves the converse
// half of the §11.4.44 discipline the task brief mandates ("bump by 1 or
// PRESERVE if no schema changes made"): when the regenerated content is
// byte-identical to what is already committed (modulo the two volatile
// header lines), export MUST restore the existing, higher Revision +
// Last-modified verbatim — never silently regress to the DB's stale value,
// and never gratuitously bump a no-op regeneration.
func TestExportCmd_PreservesRevisionWhenContentUnchanged(t *testing.T) {
	dbPath := newTestDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// No items — the DB's raw header segment IS the entire rendered
	// document, so the body content is identical to the committed file's
	// body content (both empty) once the two header lines are stripped.
	staleHeader := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 6\n" +
		"**Last modified:** 2026-08-15T12:15:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if _, err := db.Exec(`INSERT INTO doc_segments (document, seq, kind, atm_id, raw) VALUES (?,?,?,?,?)`,
		"Issues", 0, "raw", "", staleHeader); err != nil {
		db.Close()
		t.Fatalf("seed stale header segment: %v", err)
	}
	db.Close()

	outDir := t.TempDir()
	issuesPath := filepath.Join(outDir, "Issues.md")
	committed := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 8\n" +
		"**Last modified:** 2026-08-18T16:50:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if err := os.WriteFile(issuesPath, []byte(committed), 0o644); err != nil {
		t.Fatalf("seed committed file: %v", err)
	}

	if code := exportCmd([]string{"--db", dbPath, "--out-dir", outDir, "--no-formats"}); code != exitOK {
		t.Fatalf("exportCmd exit = %d, want %d", code, exitOK)
	}

	got := readFile(t, issuesPath)
	if got != committed {
		t.Errorf("no-op regeneration must reproduce the committed file byte-for-byte (preserve Revision 8 + its Last-modified, never touch either):\nwant:\n%s\ngot:\n%s", committed, got)
	}
}
