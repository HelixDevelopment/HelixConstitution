// sync_diff_partial_scope_test.go — §11.4.201(6) false-null guard for diffCmd's
// PARTIAL-Markdown invocation shape.
//
// Defect (BOB-186, measured 2026-08-25). BOB-155 closed the NO-path false-null
// (`diff --db <p>` with neither --issues nor --fixed now REFUSES). It left the
// PARTIAL-path shape open:
//
//	$ workable-items diff --db docs/workable_items.db --issues docs/Issues.md
//	diff: DB and Markdown are in sync (compared 77 Markdown item(s)
//	                                   against 185 DB item(s); read docs/Issues.md)
//	exit 0
//
// 77 against 185. The verdict prints BOTH numbers and still says "in sync".
// The 107 DB rows whose current_location is 'Fixed' were never compared against
// anything: the terminal "absent in Markdown" pass deliberately (and correctly)
// skips them — `if d.CurrentLocation == "Fixed" && *fixedPath == "" { continue }`
// — to avoid manufacturing false positives against a tracker the caller never
// supplied, but the VERDICT then claims a full DB-vs-Markdown sync it did not
// perform. A partially blind instrument returns the same quiet green a genuinely
// synced corpus returns, which is the §11.4.201(6) FALSE-NULL in its exact
// canonical shape — inside the very tool whose job is to verify that sync.
//
// Load-bearing, not cosmetic: this verdict is consumed by the §11.4.106(F)
// commit-seam check in consuming projects. A caller passing only --issues was
// told the docs chain was clean while the Fixed tracker had diverged silently.
//
// PROVENANCE CORRECTION (§11.4.6): an earlier report located this false-null in
// the NO-paths form. That form REFUSES correctly (BOB-155) and is asserted here
// as a preserved invariant. The defect is the PARTIAL read, and only that.
//
// THE FIX'S DESIGN RULE, asserted by this file:
//
//	diff REFUSES to emit a DB-vs-Markdown verdict whenever the supplied Markdown
//	paths do not account for every DB item's current_location. The narrower
//	per-tracker comparison is a REAL, documented capability and is therefore NOT
//	deleted (§11.4.122) — it survives, but must be asked for BY NAME
//	(--partial-scope), exactly as BOB-155 preserved the no-Markdown shape behind
//	--db-only. When the scope really is partial, the verdict NEVER says
//	"in sync": it names the locations it did not cover and how many rows they hold.
//
// The refusal is keyed on MEASURED DB CONTENT, never on "were both flags given".
// A DB holding zero Fixed rows IS fully accounted for by --issues alone, and
// must still pass — that is the §11.4.201(1) false-positive guard, asserted by
// TestDiffCmd_IssuesOnlyIsCompleteWhenDBHasNoFixedRows below. Without it this
// fix would trade a false-null for a false-positive refusal, which §11.4.201
// forbids in the same breath.
//
// No polarity switch (§11.4.115), following the precedent this package already
// set in sync_diff_nopaths_test.go: a RED branch that reproduces an
// already-fixed defect FAILs on every default `go test` run, so it gets muted
// and stops guarding. The RED-on-the-broken-artifact evidence for BOB-186 is the
// captured pre-fix run of these tests against unmodified sync.go, and the
// standing §1.1 mutation is the fix commit's own revert.
package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// captureDiffBoth runs diffCmd(args) capturing BOTH streams. The sibling helper
// captureDiff (sync_diff_test.go) takes stdout only, but a refusal is written to
// stderr, so asserting on refusals needs both. Returns (exitCode, stdout, stderr).
func captureDiffBoth(t *testing.T, args []string) (int, string, string) {
	t.Helper()
	origOut, origErr := os.Stdout, os.Stderr
	rOut, wOut, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe (stdout): %v", err)
	}
	rErr, wErr, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe (stderr): %v", err)
	}
	os.Stdout, os.Stderr = wOut, wErr

	// Drain concurrently: a refusal plus a large item list can exceed the pipe
	// buffer, and a blocked write inside diffCmd would deadlock the test rather
	// than fail it (a §11.4.201(12)-class instrument footgun).
	outCh, errCh := make(chan []byte, 1), make(chan []byte, 1)
	go func() { b, _ := io.ReadAll(rOut); outCh <- b }()
	go func() { b, _ := io.ReadAll(rErr); errCh <- b }()

	rc := diffCmd(args)

	wOut.Close()
	wErr.Close()
	os.Stdout, os.Stderr = origOut, origErr
	return rc, string(<-outCh), string(<-errCh)
}

// buildMixedLocationDB writes BOTH tracker fixtures and syncs them into ONE
// fresh temp DB, so the DB provably holds rows in BOTH current_locations. The
// DB is DEFINITIONALLY in sync with those two files, having just been derived
// from them — so any divergence a later diff reports is diff's own invention,
// and any "in sync" claim it makes about a tracker it never read is a bluff.
// Returns (dbPath, issuesPath, fixedPath).
func buildMixedLocationDB(t *testing.T) (string, string, string) {
	t.Helper()
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatalf("write fixed fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on mixed-location fixtures exited %d", code)
	}

	// Control needle (§11.4.201(7)(b)): prove the SETUP actually produced rows in
	// BOTH locations before any test concludes anything from their presence or
	// absence. A silently issues-only DB would make the whole file vacuous while
	// still going green — the exact shape of bluff this file exists to forbid.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	items, err := loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	nIssues, nFixed := 0, 0
	for _, it := range items {
		switch it.CurrentLocation {
		case "Issues":
			nIssues++
		case "Fixed":
			nFixed++
		}
	}
	if nIssues == 0 || nFixed == 0 {
		t.Fatalf("setup did not produce a mixed-location DB (Issues=%d Fixed=%d); "+
			"every assertion below would be vacuous", nIssues, nFixed)
	}
	return dbPath, issuesPath, fixedPath
}

// TestDiffCmd_IssuesOnlyDoesNotClaimSyncWhileFixedRowsUncompared is the BOB-186
// RED capturing the escape. --issues is supplied, --fixed is omitted, and the DB
// provably holds Fixed rows the invocation cannot read. diff MUST NOT return a
// green full-sync verdict, because it did not compare those rows against
// anything.
func TestDiffCmd_IssuesOnlyDoesNotClaimSyncWhileFixedRowsUncompared(t *testing.T) {
	dbPath, issuesPath, _ := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t, []string{"--db", dbPath, "--issues", issuesPath})
	combined := out + errOut

	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("BOB-186 false-null: diff claimed full DB/Markdown sync while every "+
			"Fixed-located DB row went uncompared (--fixed omitted). A partially blind "+
			"instrument returned the same green a genuinely synced corpus returns.\n"+
			"exit=%d\nstdout:\n%s\nstderr:\n%s", rc, out, errOut)
	}
	if rc == exitOK && !strings.Contains(combined, "PARTIAL SCOPE") {
		t.Fatalf("diff exited OK on a partial comparison without declaring the scope it "+
			"actually covered; a reader cannot tell this from a complete verdict.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
	// Whichever shape the fix takes, the unaccounted tracker must be NAMED — a
	// verdict that hides which rows it skipped is not actionable (§11.4.6).
	if !strings.Contains(combined, "Fixed") {
		t.Fatalf("diff neither refused nor named the uncompared 'Fixed' location.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
}

// TestDiffCmd_FixedOnlyDoesNotClaimSyncWhileIssuesRowsUncompared is the mirror
// case. The defect is symmetric, so the guard must be too — fixing only the
// direction that happened to be reported would leave the other half live.
func TestDiffCmd_FixedOnlyDoesNotClaimSyncWhileIssuesRowsUncompared(t *testing.T) {
	dbPath, _, fixedPath := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t, []string{"--db", dbPath, "--fixed", fixedPath})
	combined := out + errOut

	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("BOB-186 false-null (mirror): diff claimed full DB/Markdown sync while "+
			"every Issues-located DB row went uncompared (--issues omitted).\n"+
			"exit=%d\nstdout:\n%s\nstderr:\n%s", rc, out, errOut)
	}
	if !strings.Contains(combined, "Issues") {
		t.Fatalf("diff neither refused nor named the uncompared 'Issues' location.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
}

// TestDiffCmd_CompleteComparisonStillReportsInSync is the NEGATIVE CONTROL
// (§11.4.201(1)). Both trackers supplied, both matching, every DB row accounted
// for: this is a genuinely complete comparison and MUST still pass with the
// full-sync verdict. Without this, the fix would be a false-positive refusal
// machine and strictly worse than the defect.
func TestDiffCmd_CompleteComparisonStillReportsInSync(t *testing.T) {
	dbPath, issuesPath, fixedPath := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t,
		[]string{"--db", dbPath, "--issues", issuesPath, "--fixed", fixedPath})

	if rc != exitOK {
		t.Fatalf("complete comparison of a DB derived from these very files exited %d "+
			"(want exitOK %d) — the guard is refusing a legitimate full comparison "+
			"(§11.4.201(1) false positive).\nstdout:\n%s\nstderr:\n%s", rc, exitOK, out, errOut)
	}
	if !strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("complete comparison did not emit the full-sync verdict.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
	if strings.Contains(out, "PARTIAL SCOPE") {
		t.Fatalf("complete comparison mislabelled itself as partial.\nstdout:\n%s", out)
	}
}

// TestDiffCmd_IssuesOnlyIsCompleteWhenDBHasNoFixedRows is the SHARPEST
// false-positive guard. The refusal must key on MEASURED DB CONTENT, not on
// "were both flags given". A DB holding zero Fixed rows is fully accounted for
// by --issues alone, and refusing it would block a legitimate, complete
// comparison — turning this fix into the §11.4.201(1) failure it must avoid.
func TestDiffCmd_IssuesOnlyIsCompleteWhenDBHasNoFixedRows(t *testing.T) {
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("setup: md-to-db exited %d", code)
	}

	rc, out, errOut := captureDiffBoth(t, []string{"--db", dbPath, "--issues", issuesPath})

	if rc != exitOK {
		t.Fatalf("--issues alone was REFUSED against a DB with zero Fixed rows, where it "+
			"is a COMPLETE comparison. The guard is keying on flag presence instead of "+
			"measured DB content (§11.4.201(1) false-positive refusal).\n"+
			"exit=%d\nstdout:\n%s\nstderr:\n%s", rc, out, errOut)
	}
	if !strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("a complete issues-only comparison did not emit the full-sync verdict.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
}

// TestDiffCmd_PartialScopeOptInNeverClaimsSync asserts the preserved capability
// (§11.4.122): the narrower per-tracker comparison still WORKS when asked for by
// name, and its verdict states the scope it actually covered instead of claiming
// a sync it did not verify.
func TestDiffCmd_PartialScopeOptInNeverClaimsSync(t *testing.T) {
	dbPath, issuesPath, _ := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t,
		[]string{"--db", dbPath, "--issues", issuesPath, "--partial-scope"})

	if rc != exitOK {
		t.Fatalf("--partial-scope did not preserve the issues-only comparison capability "+
			"(exit %d); §11.4.122 forbids silently deleting an existing capability.\n"+
			"stdout:\n%s\nstderr:\n%s", rc, out, errOut)
	}
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("--partial-scope claimed full sync while Fixed rows went uncompared — "+
			"the opt-in reintroduced the very false-null it exists to make explicit.\n"+
			"stdout:\n%s", out)
	}
	if !strings.Contains(out, "PARTIAL SCOPE") {
		t.Fatalf("--partial-scope verdict did not declare itself partial.\nstdout:\n%s", out)
	}
	if !strings.Contains(out, "Fixed") {
		t.Fatalf("--partial-scope verdict did not name the uncompared location.\nstdout:\n%s", out)
	}
}

// TestDiffCmd_NoPathsStillRefuses preserves CASE A — the BOB-155 refusal.
// Measured 2026-08-25: this invariant had NO test anywhere in the package, so
// the BOB-155 fix was one careless edit from silent regression. Per §11.4.238
// the coverage gap is itself the finding; this closes it.
func TestDiffCmd_NoPathsStillRefuses(t *testing.T) {
	dbPath, _, _ := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t, []string{"--db", dbPath})

	if rc == exitOK {
		t.Fatalf("BOB-155 regressed: diff with no Markdown paths exited OK.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("BOB-155 regressed: diff claimed sync having read no Markdown.\n"+
			"stdout:\n%s", out)
	}
	if !strings.Contains(errOut, "refusing") {
		t.Fatalf("no-paths form did not emit its refusal on stderr.\nstderr:\n%s", errOut)
	}
}

// TestDiffCmd_DBOnlyStaysHonestAndGreen preserves CASE B. --db-only reads no
// Markdown BY DESIGN, is unaffected by the location-accounting guard, and keeps
// its honest verdict that names what it did NOT do.
func TestDiffCmd_DBOnlyStaysHonestAndGreen(t *testing.T) {
	dbPath, _, _ := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t, []string{"--db", dbPath, "--db-only"})

	if rc != exitOK {
		t.Fatalf("--db-only exited %d (want exitOK %d) on a DB with no internal integrity "+
			"findings — the location-accounting guard leaked into the no-Markdown mode.\n"+
			"stdout:\n%s\nstderr:\n%s", rc, exitOK, out, errOut)
	}
	if !strings.Contains(out, "no Markdown compared (--db-only)") {
		t.Fatalf("--db-only lost its honest no-Markdown-compared verdict.\nstdout:\n%s", out)
	}
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("--db-only claimed DB/Markdown sync without reading Markdown.\nstdout:\n%s", out)
	}
}

// TestDiffCmd_PartialScopeIsRejectedWithDBOnly keeps the flag set from
// misdescribing the run. --db-only compares NO Markdown; --partial-scope asserts
// something about which Markdown trackers were compared. Accepting both would
// silently ignore one, which is how a verdict starts lying about its own inputs —
// the same rationale that already makes --db-only exclusive with --issues/--fixed.
func TestDiffCmd_PartialScopeIsRejectedWithDBOnly(t *testing.T) {
	dbPath, _, _ := buildMixedLocationDB(t)

	rc, out, errOut := captureDiffBoth(t,
		[]string{"--db", dbPath, "--db-only", "--partial-scope"})

	if rc == exitOK {
		t.Fatalf("contradictory --db-only + --partial-scope was accepted.\n"+
			"stdout:\n%s\nstderr:\n%s", out, errOut)
	}
	if !strings.Contains(errOut, "--partial-scope") {
		t.Fatalf("rejection did not name the offending flag.\nstderr:\n%s", errOut)
	}
}

// TestDiffCmd_RefusalNamesTheUnaccountedRowCount asserts the refusal prints its
// RESOLVED EVIDENCE (§11.4.201(5)): which location is unaccounted, how many rows
// it holds, and which flag supplies it. A refusal a reader cannot diagnose in one
// step is itself a defect.
func TestDiffCmd_RefusalNamesTheUnaccountedRowCount(t *testing.T) {
	dbPath, issuesPath, _ := buildMixedLocationDB(t)

	rc, _, errOut := captureDiffBoth(t, []string{"--db", dbPath, "--issues", issuesPath})
	if rc == exitOK {
		return // a partial-scope-verdict implementation is also acceptable; covered above
	}
	for _, want := range []string{"--fixed", "Fixed", "--partial-scope"} {
		if !strings.Contains(errOut, want) {
			t.Fatalf("refusal omitted %q; it must name the missing flag, the unaccounted "+
				"location, and the opt-in that preserves the narrow comparison.\nstderr:\n%s",
				want, errOut)
		}
	}
	if !bytes.ContainsAny([]byte(errOut), "0123456789") {
		t.Fatalf("refusal did not state HOW MANY rows are unaccounted.\nstderr:\n%s", errOut)
	}
}
