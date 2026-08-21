// sync_diff_nopaths_test.go — guard against diffCmd inventing false-positive
// "absent in Markdown" divergences on an invocation that parsed no Markdown.
//
// Defect (2026-08-10): `workable-items diff --db <p>` invoked WITHOUT
// --issues/--fixed left the `parsed []item` slice empty, then ran the terminal
// loop `for _, d := range dbItems { if !parsedSeen[key] { print "- <id> present
// in DB, absent in Markdown" } }` — reporting EVERY DB row as absent from
// Markdown and manufacturing a false-positive divergence count equal to the DB
// row count (102 in-repo). `sync db-to-md` wrote output byte-identical to the
// on-disk trackers, so DB and Markdown were provably in sync; the divergences
// were entirely diff's own invention.
//
// §11.4.120 RECONCILIATION (BOB-155, 2026-08-21) — this file previously
// asserted that the flagless `diff --db` form returns exitOK with an "in sync"
// verdict. That assertion has been REMOVED because it encoded a defect, not a
// requirement: the 2026-08-10 fix silenced the false POSITIVES by gating the
// compare loops on `haveMarkdown`, but then fell through to the unconditional
// success verdict — so the flagless form printed "DB and Markdown are in sync"
// while having opened zero Markdown files, trading a FAIL-bluff for a
// PASS-bluff (BOB-155, §11.4.201(6) false-null). The gate was rewritten to
// assert the NEW mechanism rather than fake-passed or reverted: the flagless
// form now REFUSES, and the only remaining no-Markdown shape is the explicit
// `--db-only` opt-in, which is where this file's original invariant — never
// invent "absent in Markdown" lines when nothing was parsed — now lives.
//
// No polarity switch: this is an unconditional guard on the current contract.
// The prior RED branch reproduced a defect that has been fixed for months and
// therefore failed on every default `go test` run, which is how it went
// unnoticed that its GREEN branch had begun enshrining BOB-155.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// TestDiffCmd_DBOnlyInventsNoAbsentInMarkdownLines is the surviving invariant of
// the 2026-08-10 false-positive defect, re-seated onto the invocation shape that
// still performs no Markdown comparison. Setup: write dualRepFixedFixture to a
// temp Fixed.md and syncMDToDB it into a temp DB — that DB is DEFINITIONALLY in
// sync with that Fixed.md, having just been derived from it. `--db-only` runs
// the DB-internal integrity checks against it and MUST NOT emit a single
// `- <id> present in DB, absent in Markdown` line, because it parsed no
// Markdown and therefore has no basis to call anything absent from it.
func TestDiffCmd_DBOnlyInventsNoAbsentInMarkdownLines(t *testing.T) {
	tmp := t.TempDir()
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on dual-rep fixture exited %d", code)
	}

	rc, out := captureDiff(t, []string{"--db", dbPath, "--db-only"})

	if strings.Contains(out, "present in DB, absent in Markdown") {
		t.Fatalf("--db-only emitted spurious 'present in DB, absent in Markdown' line(s) "+
			"on a DB it never compared against any Markdown (no-Markdown-comparison "+
			"false-positive regressed):\n%s", out)
	}
	if rc != exitOK {
		t.Fatalf("--db-only exited %d (want exitOK %d) on a DB with no internal "+
			"integrity findings:\n%s", rc, exitOK, out)
	}
	// BOB-155: and it must not claim a Markdown comparison it did not perform.
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("--db-only claimed DB/Markdown sync without reading Markdown:\n%s", out)
	}
}
