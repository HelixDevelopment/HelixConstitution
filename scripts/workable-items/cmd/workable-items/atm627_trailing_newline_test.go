// atm627_trailing_newline_test.go — anti-bluff coverage for the ATM-627-part-2
// STORE-side trailing-newline defect (residual after the 97d405c db-to-md WRITER
// fix), the STORAGE-side normalization half of the byte-identical round-trip.
//
// FORENSIC ANCHOR (FACT, captured 2026-07-10). On the live tree, 9 items
// (ATM-370 / SPK-512 / MVR-017 / ATM-702 / ATM-707 / ATM-709 / ATM-710 / ATM-711
// / ATM-712) had a stored `items.body_md` that ended WITHOUT a trailing "\n"
// (e.g. `…PROGRESS.md.` — last byte 0x2E). The db-to-md WRITER (renderDocument,
// db.go, fixed in 97d405c) SYNTHESIZES a separator "\n" before the next heading
// so a heading never glues onto the prior body line — but that makes the
// re-parsed body exactly one "\n" longer than the stored body, so
// `workable-items diff` reports `~ <id> body differs (md=N+1 db=N)` and the
// round-trip is NOT byte-identical. Root cause: a STORE-side data-normalization
// defect — the mutation/store paths persisted a body_md that did not end with a
// "\n". Fix: normalize ON STORE (classifyRepair + the `update` write path both
// call ensureTrailingNewline) so body_md always ends with at least one "\n"
// (idempotent + byte-identical for an already-normalized body, incl. the
// renderItemBody "\n\n" convention — 494 live items end "\n\n", 2 end "\n", ONLY
// the 9 broken items ended with no "\n").
//
// §11.4.115 RED-polarity: RED_MODE=1 stops at the captured RED (a no-"\n" body's
// round-trip diff is non-zero — defect reproduced, fix NOT applied). At the
// default polarity the test proves repair-bodies converts it to GREEN (body ends
// "\n", round-trip diff == 0, idempotent).
//
// §1.1 PAIRED MUTATION: stubbing ensureTrailingNewline (parse.go) to
// `return body` — OR removing its call from classifyRepair (repair_bodies.go) —
// leaves the no-"\n" body unrepaired, so this test FAILs (RED assertion after the
// GREEN branch is reached: body does not end "\n" / round-trip diff != 0).
// Restoring the normalization -> GREEN. Proves the normalization is load-bearing,
// not a tautology.
//
// HARD CONSTRAINT: fresh temp DBs only (t.TempDir); NEVER touches the live
// docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// rtInSync regenerates the trackers from the DB (db-to-md) into fresh temp files,
// then re-parses them (diff) — returning true IFF the db->md->db round-trip is
// byte-identical (0 differences). This is the exact user-facing mechanism the
// `workable-items diff` gate uses: diffCmd returns exitOK IFF in-sync.
func rtInSync(t *testing.T, dbPath string) bool {
	t.Helper()
	tmp := t.TempDir()
	outIssues := filepath.Join(tmp, "rt_Issues.md")
	outFixed := filepath.Join(tmp, "rt_Fixed.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outIssues, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	return diffCmd([]string{"--db", dbPath, "--issues", outIssues, "--fixed", outFixed}) == exitOK
}

func TestRepairBodies_NormalizesTrailingNewline_RedPolarity(t *testing.T) {
	redMode := os.Getenv("RED_MODE") == "1"
	dbPath := rbFixtureDB(t)

	// Faithfully reproduce the live 9-item condition: take a REAL synced body
	// (ends "\n\n"), strip ALL trailing newlines so it ends with NO "\n". The
	// only change vs a clean synced item is the missing trailing "\n"; its
	// **Status:** line still matches the column, so canonicalizeBodyStatusLine
	// stays a strict no-op — the trailing-newline defect is the SOLE trigger.
	orig := rbReadBody(t, dbPath, "ATM-970", "Issues")
	if !strings.HasSuffix(orig, "\n") {
		t.Fatalf("precondition: fixture body for ATM-970 does not end with \\n: %q", orig)
	}
	noNL := strings.TrimRight(orig, "\n")
	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET body_md=?
		WHERE atm_id='ATM-970' AND current_location='Issues' AND representation='section'`, noNL)
	db.Close()

	// RED baseline on the BROKEN artifact: the stored body ends with NO "\n" AND
	// the db->md->db round-trip is NOT byte-identical (the md=N+1 db=N symptom).
	if got := rbReadBody(t, dbPath, "ATM-970", "Issues"); strings.HasSuffix(got, "\n") {
		t.Fatalf("RED baseline: injected body already ends with \\n (defect not reproduced): %q", got)
	}
	if rtInSync(t, dbPath) {
		t.Fatalf("RED baseline: db->md->db round-trip is in-sync on a no-\\n body (defect not reproduced)")
	}
	if redMode {
		// RED_MODE=1: assert ONLY that the defect reproduces; do NOT apply the fix.
		return
	}

	// GREEN: repair-bodies normalizes the trailing "\n" ON STORE ...
	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("repair-bodies exited %d (expected OK)", code)
	}
	got := rbReadBody(t, dbPath, "ATM-970", "Issues")
	if !strings.HasSuffix(got, "\n") {
		t.Fatalf("post-repair body_md does NOT end with \\n: %q", got)
	}
	// ... and the db->md->db round-trip is now byte-identical (diff == 0).
	if !rtInSync(t, dbPath) {
		t.Fatalf("post-repair round-trip is NOT in-sync (trailing-newline residual not cleared)")
	}

	// Idempotence: a SECOND repair-bodies run is a byte-identical no-op.
	before := rbReadBody(t, dbPath, "ATM-970", "Issues")
	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("second repair-bodies exited %d", code)
	}
	if after := rbReadBody(t, dbPath, "ATM-970", "Issues"); after != before {
		t.Fatalf("repair-bodies NOT idempotent on trailing-newline fix:\n--- before ---\n%q\n--- after ---\n%q", before, after)
	}
}

// TestUpdate_NormalizesTrailingNewline — defense-in-depth: the `update` write path
// (mutate.go) propagates the EXISTING cur.BodyMD for a field-only update, so a
// pre-existing no-"\n" body would be re-stored no-"\n" without normalization. The
// store-side ensureTrailingNewline on the update path self-heals it: after a
// benign field-only update, the stored body ends with "\n".
//
// §1.1 PAIRED MUTATION: removing ensureTrailingNewline from the update path
// (mutate.go) makes this test FAIL (the re-stored body stays no-"\n").
func TestUpdate_NormalizesTrailingNewline(t *testing.T) {
	dbPath := rbFixtureDB(t)

	orig := rbReadBody(t, dbPath, "ATM-970", "Issues")
	noNL := strings.TrimRight(orig, "\n")
	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET body_md=?
		WHERE atm_id='ATM-970' AND current_location='Issues' AND representation='section'`, noNL)
	db.Close()

	// A benign field-only update (severity) MUST NOT regenerate the freeform body
	// (SPK-481 preservation) but MUST self-heal the trailing "\n" on store.
	if code := updateCmd([]string{"--db", dbPath, "--id", "ATM-970", "--severity", "Medium"}); code != exitOK {
		t.Fatalf("update exited %d (expected OK)", code)
	}
	got := rbReadBody(t, dbPath, "ATM-970", "Issues")
	if !strings.HasSuffix(got, "\n") {
		t.Fatalf("post-update body_md does NOT end with \\n (update path did not normalize): %q", got)
	}
	// The authored freeform content is preserved (only the trailing "\n" added).
	if !strings.Contains(got, "body one two three four five six.") {
		t.Fatalf("post-update body_md lost its authored freeform content: %q", got)
	}
}
