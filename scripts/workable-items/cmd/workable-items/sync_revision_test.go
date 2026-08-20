// sync_revision_test.go — §11.4.44 monotonic-revision anti-regression
// coverage for `sync db-to-md`.
//
// Forensic anchor (task #86, filed by task-incident-3-writeup subagent
// aebfe202, 2026-08-18/19): BOB-108 (task #68) fixed the §11.4.44
// Revision-regression defect for the `export` subcommand only
// (reconcileRevisionHeader wired into exportCmd, export_revision.go). The
// SIBLING subcommand `sync db-to-md` (syncDBToMD, sync.go) shares the exact
// same regeneration mechanism — renderDocument(db, doc) replaying the
// doc_segments "raw" header segment VERBATIM — but was never patched: it
// writes the rendered text straight to disk with plain os.WriteFile, with NO
// call to reconcileRevisionHeader anywhere in its body. `sync db-to-md` is a
// documented, first-class entry point (constitution/scripts/workable-items/
// README.md "Phase 4 — `sync db-to-md` lands + byte-identical round-trip CI
// gate"), reachable by any script or agent that follows that documentation,
// so it carries the identical regression risk export.go was patched for.
//
// Reproduced LIVE against the real repo tree 2026-08-19: with docs/Fixed.md
// already committed at **Revision:** 22, running the real binary via
// `sync db-to-md --db docs/workable_items.db --out-fixed docs/Fixed.md`
// turned docs/Fixed.md **Revision:** 22 -> 15 (verbatim replay of the DB's
// stale doc_segments raw-segment header) — the exact BOB-108 defect class,
// on the sibling subcommand. Immediately reverted via file restore before
// this fix landed; nothing was left committed from that reproduction.
//
// RED before the fix: TestSyncDBToMD_NeverRegressesRevisionBelowCommittedFile
// fails with "**Revision:** 6" present in the output (syncDBToMD wrote the
// DB's stale header verbatim, exactly mirroring
// TestExportCmd_NeverRegressesRevisionBelowCommittedFile in
// export_revision_test.go). GREEN after wiring reconcileRevisionHeader into
// syncDBToMD's write paths for both --out-issues and --out-fixed.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestSyncDBToMD_NeverRegressesRevisionBelowCommittedFile reproduces the
// BOB-108-class defect end-to-end through the REAL syncDBToMD entry point
// (no mocks, real SQLite, real file IO) — the sibling of
// TestExportCmd_NeverRegressesRevisionBelowCommittedFile in
// export_revision_test.go, but exercising `sync db-to-md` instead of
// `export`. A DB whose stored §11.4.44 header is stale (Revision 6) relative
// to an already-committed on-disk file (Revision 8) MUST NOT regress the
// emitted Revision below 8 — and since a new item's body genuinely changes
// the regenerated content, the earned bump lands at 9, never at the DB's
// stale 6.
func TestSyncDBToMD_NeverRegressesRevisionBelowCommittedFile(t *testing.T) {
	dbPath := newTestDB(t)

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
	// `sync db-to-md` runs.
	committed := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 8\n" +
		"**Last modified:** 2026-08-18T16:50:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if err := os.WriteFile(issuesPath, []byte(committed), 0o644); err != nil {
		t.Fatalf("seed committed file: %v", err)
	}

	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", issuesPath}); code != exitOK {
		t.Fatalf("syncDBToMD exit = %d, want %d", code, exitOK)
	}

	got := readFile(t, issuesPath)
	if strings.Contains(got, "**Revision:** 6") {
		t.Fatalf("sync db-to-md REGRESSED the committed §11.4.44 Revision (8 -> 6) — the BOB-108 defect class, unpatched on this sibling subcommand:\n%s", got)
	}
	if !strings.Contains(got, "**Revision:** 9") {
		t.Errorf("sync db-to-md must bump PAST the already-committed Revision (8) since content genuinely changed (a new item was added) — want **Revision:** 9, got:\n%s", got)
	}
}

// TestSyncDBToMD_FixedRevisionNeverRegresses is the docs/Fixed.md-specific
// instance — the exact document + exact regression direction the task-86
// forensic anchor captured live (22 -> 15). Proves --out-fixed is covered
// identically to --out-issues (both write paths in syncDBToMD must be
// patched, not just one).
func TestSyncDBToMD_FixedRevisionNeverRegresses(t *testing.T) {
	dbPath := newTestDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	staleHeader := "# Fixed — Closed Workable Items\n\n" +
		"**Revision:** 15\n" +
		"**Last modified:** 2026-07-01T00:00:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if _, err := db.Exec(`INSERT INTO doc_segments (document, seq, kind, atm_id, raw) VALUES (?,?,?,?,?)`,
		"Fixed", 0, "raw", "", staleHeader); err != nil {
		db.Close()
		t.Fatalf("seed stale header segment: %v", err)
	}
	db.Close()

	outDir := t.TempDir()
	fixedPath := filepath.Join(outDir, "Fixed.md")

	// The already-committed on-disk file at Revision 22 — the exact live
	// value docs/Fixed.md carried when this defect was reproduced 2026-08-19.
	committed := "# Fixed — Closed Workable Items\n\n" +
		"**Revision:** 22\n" +
		"**Last modified:** 2026-08-18T22:14:38Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if err := os.WriteFile(fixedPath, []byte(committed), 0o644); err != nil {
		t.Fatalf("seed committed file: %v", err)
	}

	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", fixedPath}); code != exitOK {
		t.Fatalf("syncDBToMD exit = %d, want %d", code, exitOK)
	}

	got := readFile(t, fixedPath)
	if strings.Contains(got, "**Revision:** 15") {
		t.Fatalf("sync db-to-md REGRESSED docs/Fixed.md's committed §11.4.44 Revision (22 -> 15) — the LIVE task-86 forensic reproduction, replayed as a test:\n%s", got)
	}
	// No items in either the DB or on disk beyond the header — content is
	// byte-identical once the two volatile header lines are stripped, so
	// the no-op-regeneration half of the contract applies: preserve the
	// committed Revision + Last-modified verbatim, never regress and never
	// gratuitously bump.
	if got != committed {
		t.Errorf("no-op regeneration must reproduce the committed file byte-for-byte (preserve Revision 22 + its Last-modified, never touch either):\nwant:\n%s\ngot:\n%s", committed, got)
	}
}

// TestSyncDBToMD_IdempotentOnRepeatedInvocation proves running `sync
// db-to-md` TWICE in a row against an unchanged DB produces an IDENTICAL
// Revision header both times (§11.4.6 anti-bluff requirement for this fix:
// the reconciled write path must not itself introduce a gratuitous bump on
// every invocation).
func TestSyncDBToMD_IdempotentOnRepeatedInvocation(t *testing.T) {
	dbPath := newTestDB(t)

	outDir := t.TempDir()
	issuesPath := filepath.Join(outDir, "Issues.md")
	committed := "# Issues — Open Workable Items\n\n" +
		"**Revision:** 3\n" +
		"**Last modified:** 2026-08-18T16:50:00Z\n" +
		"**Ticket prefix:** `BOB`\n\n"
	if err := os.WriteFile(issuesPath, []byte(committed), 0o644); err != nil {
		t.Fatalf("seed committed file: %v", err)
	}

	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", issuesPath}); code != exitOK {
		t.Fatalf("first syncDBToMD exit = %d, want %d", code, exitOK)
	}
	first := readFile(t, issuesPath)

	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", issuesPath}); code != exitOK {
		t.Fatalf("second syncDBToMD exit = %d, want %d", code, exitOK)
	}
	second := readFile(t, issuesPath)

	if first != second {
		t.Errorf("sync db-to-md is not idempotent — two consecutive runs against an unchanged DB produced different output:\nfirst:\n%s\nsecond:\n%s", first, second)
	}
}
