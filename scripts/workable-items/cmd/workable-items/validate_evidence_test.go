// validate_evidence_test.go — HXC-217 permanent regression guard (§11.4.135)
// for the UNRESOLVABLE-CLOSURE-EVIDENCE defect CLASS.
//
// ROOT CAUSE (FACT, HXC-217): a closed item's `item_history.evidence_path` is
// the pointer to the captured proof that IS the closure's warrant
// (§11.4.5 / §11.4.69 / §11.4.123). Nothing ever asserted that pointer
// RESOLVES, so a closure could record either (a) a narrative paragraph pasted
// into the single-path field, or (b) a well-formed path to a file that was
// never committed — and still read as evidence-backed everywhere downstream.
// That is the §11.4.226(2) "class proven by a LABEL, not by machine fields"
// bluff: the closure claims captured proof that cannot be produced on demand.
//
// Every test drives the REAL SQLite driver + the REAL add/close subcommands +
// the REAL validateCmd (no mocks), against a fresh temp DB only — it NEVER
// touches the live docs/workable_items.db.
//
// The decisive anti-bluff assertions:
//   (a) a closure whose evidence_path EXISTS produces NO violation (the
//       §11.4.201(1) false-positive guard — a guard that refuses a clean state
//       is a FAIL-bluff exactly as a false pass is a PASS-bluff);
//   (b) a closure whose evidence_path is a well-formed path to a NONEXISTENT
//       file DOES produce a violation, and the message names that sub-class;
//   (c) a closure whose evidence_path holds NARRATIVE text (whitespace) DOES
//       produce a violation, and the message names the OTHER sub-class;
//   (d) an OPEN (non-closed-status) item with an unresolvable evidence_path
//       produces NO violation — the guard is deliberately scoped to CLOSURES
//       (an in-progress note is not a closure claim), the §11.4.201(1)
//       assert-the-REAL-condition-and-refuse-nothing-else guard-rail;
//   (e) the guard is WIRED into validateCmd — validate FAILs on the
//       unresolvable-evidence DB and PASSes once the evidence really exists
//       (so DELETING the call site is caught, not only gutting the function).
//
// §1.1 PAIRED MUTATION (manual, documented): replace the body of
// unresolvableClosureEvidence (sync.go) with `return nil, nil` (guard removed),
// then re-run `go test -run ClosureEvidence ./cmd/workable-items/` — cases
// (b), (c) and (e) FAIL, proving the guard is NOT a tautology. Restore the real
// body → GREEN again. Captured live in
// docs/qa/hxc217_evidence_path_resolve_20260805T082033Z/validator_mutation_proof.log.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// seedClosedWithEvidence adds a fresh Issues item and closes it through the
// REAL close subcommand with the supplied evidence value, returning the db
// path. Using the real close path (not a hand-written INSERT) means the fixture
// exercises exactly the seam that records evidence_path in production.
func seedClosedWithEvidence(t *testing.T, id, evidence string) string {
	t.Helper()
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "closure evidence probe item " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}
	// HXC-224 §11.4.120 RECONCILIATION — read this before "simplifying" it.
	//
	// close now REFUSES an evidence path that does not resolve (the record-time
	// half of this same invariant), so the unresolvable values these tests need
	// can no longer be introduced THROUGH close. That is the guard working, and
	// the fixture is rebuilt rather than the guard weakened.
	//
	// The two-step below is not a workaround, it is the honest model of the rows
	// this DETECTIVE validator still exists to catch, which the preventive guard
	// provably cannot: (i) LEGACY rows recorded before the record-time guard
	// landed, and (ii) rows whose artefact was REAL at closure time and was
	// later deleted, moved, or never committed. Both are "closed item, evidence
	// that no longer resolves" — reached here by closing with a real artefact
	// and then rewriting item_history.evidence_path directly.
	real := filepath.Join(t.TempDir(), "closure-artefact.log")
	if err := os.WriteFile(real, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write seed artefact: %v", err)
	}
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "fixed", "--evidence", real, id,
	}); code != exitOK {
		t.Fatalf("close %s exited %d, want %d", id, code, exitOK)
	}
	if evidence != real {
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB: %v", err)
		}
		if _, err := db.Exec(
			`UPDATE item_history SET evidence_path=? WHERE atm_id=? AND event_type='Fixed'`,
			evidence, id); err != nil {
			db.Close()
			t.Fatalf("rewrite evidence_path: %v", err)
		}
		db.Close()
	}
	return dbPath
}

// findingsFor opens the DB and returns the guard's findings.
func findingsFor(t *testing.T, dbPath string) []string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	out, err := unresolvableClosureEvidence(db)
	if err != nil {
		t.Fatalf("unresolvableClosureEvidence: %v", err)
	}
	return out
}

// (a) A closure whose evidence_path RESOLVES to a real file is clean. Without
// this case the guard could be a blanket "every closure is a violation"
// tautology — the §11.4.201(1) false-positive FAIL-bluff.
func TestClosureEvidence_ResolvableAbsolutePath_NoViolation(t *testing.T) {
	dir := t.TempDir()
	evidence := filepath.Join(dir, "capture.log")
	if err := os.WriteFile(evidence, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write evidence: %v", err)
	}

	dbPath := seedClosedWithEvidence(t, "WIT-701", evidence)

	if got := findingsFor(t, dbPath); len(got) != 0 {
		t.Fatalf("guard reported %d violation(s) for an EXISTING evidence file (false positive, §11.4.201(1)): %v", len(got), got)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate exited %d on a closure with resolvable evidence (expected OK)", code)
	}
}

// (a') The same clean verdict for a REPO-RELATIVE evidence path — the real-world
// shape (`docs/qa/<run-id>/…`). Proves the guard anchors relative paths through
// resolveInvocationRelative ($PWD, the HXC-201 mechanism) instead of the
// process cwd, so an ordinary relative evidence path is never a false positive.
func TestClosureEvidence_ResolvableRelativePath_AnchoredAtPWD_NoViolation(t *testing.T) {
	root := t.TempDir()
	rel := filepath.Join("docs", "qa", "run-1", "capture.log")
	abs := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		t.Fatalf("mkdir evidence dir: %v", err)
	}
	if err := os.WriteFile(abs, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write evidence: %v", err)
	}
	t.Setenv("PWD", root)

	dbPath := seedClosedWithEvidence(t, "WIT-702", rel)

	if got := findingsFor(t, dbPath); len(got) != 0 {
		t.Fatalf("guard reported %d violation(s) for a RESOLVABLE relative evidence path (false positive, §11.4.201(1)): %v", len(got), got)
	}
}

// (b) A well-formed path to a file that does not exist IS a violation, and the
// message distinguishes that sub-class so the finding is actionable in one read.
func TestClosureEvidence_WellFormedPathButMissingFile_Violation(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "docs", "qa", "never-committed", "capture.log")

	dbPath := seedClosedWithEvidence(t, "WIT-703", missing)

	got := findingsFor(t, dbPath)
	if len(got) != 1 {
		t.Fatalf("guard reported %d violation(s) for a NONEXISTENT evidence path, want exactly 1: %v", len(got), got)
	}
	msg := got[0]
	if !strings.Contains(msg, "WIT-703") {
		t.Errorf("violation does not name the offending item: %s", msg)
	}
	if !strings.Contains(msg, "well-formed path, but nothing exists there") {
		t.Errorf("violation does not carry the missing-file sub-class wording: %s", msg)
	}
	if strings.Contains(msg, "narrative") {
		t.Errorf("violation mis-classified a clean path token as narrative: %s", msg)
	}
}

// (c) Narrative prose pasted into the single-path field IS a violation, carrying
// the OTHER sub-class wording — the two sub-classes must stay distinguishable
// (they have different remediations: locate the artefact vs. capture one).
func TestClosureEvidence_NarrativeText_Violation(t *testing.T) {
	narrative := "closure confirmed by manual QA during the 2026-08-05 session"

	dbPath := seedClosedWithEvidence(t, "WIT-704", narrative)

	got := findingsFor(t, dbPath)
	if len(got) != 1 {
		t.Fatalf("guard reported %d violation(s) for NARRATIVE evidence text, want exactly 1: %v", len(got), got)
	}
	msg := got[0]
	if !strings.Contains(msg, "WIT-704") {
		t.Errorf("violation does not name the offending item: %s", msg)
	}
	if !strings.Contains(msg, "narrative or multi-value text in a single-path field") {
		t.Errorf("violation does not carry the narrative sub-class wording: %s", msg)
	}
}

// (d) THE FALSE-POSITIVE GUARD-RAIL (§11.4.201(1)): an OPEN item whose history
// carries an unresolvable evidence_path is NOT a violation. The mandate is that
// a CLOSURE's captured proof resolves; an in-progress note is not a closure
// claim, and refusing it would be a FAIL-bluff.
func TestClosureEvidence_OpenItemUnresolvableEvidence_NoViolation(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-705",
		"--title", "open item with an in-progress note",
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add exited %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// An 'Updated' event on a still-OPEN item, whose evidence_path resolves to
	// nothing at all — exactly the shape the guard MUST NOT refuse.
	if _, err := db.Exec(
		`INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path)
		 VALUES (?,?,?,?,?,?)`,
		"WIT-705", "Updated", "AI", "2026-08-05", "",
		filepath.Join(t.TempDir(), "no", "such", "in-progress-note.log")); err != nil {
		db.Close()
		t.Fatalf("insert open-item history: %v", err)
	}
	db.Close()

	if got := findingsFor(t, dbPath); len(got) != 0 {
		t.Fatalf("guard refused an OPEN item's unresolvable note (%d finding(s)) — §11.4.201(1) false-positive refusal: %v", len(got), got)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate exited %d on an OPEN item with an unresolvable note (expected OK)", code)
	}
}

// (e) WIRING: the guard is reached through validateCmd. validate MUST FAIL on
// the unresolvable-evidence DB and MUST PASS once the evidence artefact really
// exists at the recorded path — so removing the call site (not merely gutting
// the function) is caught too.
func TestValidate_UnresolvableClosureEvidence_FailsThenPassesWhenEvidenceLands(t *testing.T) {
	dir := t.TempDir()
	evidence := filepath.Join(dir, "qa", "run-7", "capture.log")

	dbPath := seedClosedWithEvidence(t, "WIT-706", evidence)

	if code := validateCmd([]string{"--db", dbPath}); code == exitOK {
		t.Fatal("validate returned exitOK on a closure whose evidence_path does not resolve — the HXC-217 guard is not wired into validateCmd")
	}

	// Land the artefact at exactly the recorded path; the SAME DB must now pass
	// (proving the guard is SPECIFIC to the unresolvable pointer, not a blanket
	// failure on any closed item).
	if err := os.MkdirAll(filepath.Dir(evidence), 0o755); err != nil {
		t.Fatalf("mkdir evidence dir: %v", err)
	}
	if err := os.WriteFile(evidence, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write evidence: %v", err)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate exited %d after the evidence artefact landed (expected OK — guard is not specific to the unresolvable pointer)", code)
	}
}

// (f) TASK-54 / BOB-010 id=64 — the OVER-SCOPING regression: a CLOSED item's
// NON-closure history rows (Updated/Reopened/Opened) MUST NOT be checked for
// evidence-path resolvability, even though the item's CURRENT status is
// terminal. Only a CLOSURE event (Fixed/Implemented/Completed/Obsolete) is a
// closure's captured-proof claim (§11.4.5/§11.4.69/§11.4.123/§11.4.226); an
// `Updated` row is ordinary history-trail narrative, not a re-assertion of the
// closure's evidence.
//
// ROOT CAUSE (FACT, live DB, 2026-08-18): BOB-010's real closure (history
// id=4, event=Completed) recorded evidence_path="scripts/workable-items-export.sh",
// which resolves. A LATER `Updated` row (history id=64, on=2026-08-10) recorded
// evidence_path="scripts/docs_chain.sh" — the file's PRE-rename name, git-mv'd
// away by commit 0558399/d9d512d before this fixture's date. The query in
// unresolvableClosureEvidence (sync.go) filtered ONLY on
// `items.status IN (terminal set)`, never on `item_history.event_type`, so it
// flagged the Updated row as an "unresolvable closure evidence_path" even
// though it is not a closure claim at all — blocking every commit with
// `workable-items validate` exit 1 on a healthy tracker.
//
// This test reproduces the EXACT shape: seed a closure with a RESOLVABLE
// evidence path (so the real closure claim is provably clean), then append an
// Updated event on the SAME now-closed item with an UNRESOLVABLE evidence_path
// — the guard MUST report zero violations and `validate` MUST exit OK.
//
// §1.1 PAIRED MUTATION: reverting the `h.event_type IN (...)` clause this test
// drove into unresolvableClosureEvidence's SQL (sync.go) makes this test FAIL
// again with exactly the BOB-010 message shape — proving the scope-narrowing
// fix is load-bearing, not decorative.
func TestClosureEvidence_UpdatedEventOnClosedItem_UnresolvablePath_NoViolation(t *testing.T) {
	dir := t.TempDir()
	closureEvidence := filepath.Join(dir, "closure-capture.log")
	if err := os.WriteFile(closureEvidence, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write closure evidence: %v", err)
	}

	dbPath := seedClosedWithEvidence(t, "WIT-707", closureEvidence)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// The BOB-010 shape: an `Updated` event landed AFTER closure, on the SAME
	// closed item, whose evidence_path names a file that was since renamed away
	// (a well-formed path to nothing) — never a closure re-assertion.
	if _, err := db.Exec(
		`INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path)
		 VALUES (?,?,?,?,?,?)`,
		"WIT-707", "Updated", "AI", "2026-08-10", "rename cross-reference note",
		filepath.Join(dir, "renamed-away-before-this-fixture.sh")); err != nil {
		db.Close()
		t.Fatalf("insert post-closure Updated history: %v", err)
	}
	db.Close()

	got := findingsFor(t, dbPath)
	if len(got) != 0 {
		t.Fatalf("guard flagged %d violation(s) for an Updated-event evidence_path on a closed item (§11.4.201(1) over-scoping — Updated is not a closure event): %v", len(got), got)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate exited %d on a closed item whose ONLY unresolvable evidence_path belongs to a non-closure Updated event (expected OK — the BOB-010 id=64 over-scoping bug)", code)
	}
}

// TestFirstLine keeps the message-bounding helper honest: one multi-line or
// over-long evidence value must never flood the validator's output and hide its
// siblings.
func TestFirstLine(t *testing.T) {
	long := strings.Repeat("x", 200)
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"short single line is unchanged", "docs/qa/run-1/capture.log", "docs/qa/run-1/capture.log"},
		{"empty is unchanged", "", ""},
		{"newline truncates at the first line", "first line\nsecond line", "first line …"},
		{"carriage return truncates too", "first line\r\nsecond", "first line …"},
		{"over-long single line is capped at 120 chars", long, long[:120] + " …"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := firstLine(c.in); got != c.want {
				t.Errorf("firstLine(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}
