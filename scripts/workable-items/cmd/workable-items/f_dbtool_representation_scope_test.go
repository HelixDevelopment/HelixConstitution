// f_dbtool_representation_scope_test.go — §11.4.115/§11.4.135 permanent
// regression guard for the F-DBTOOL representation-scoping fix.
//
// Forensic anchor (2026-07-12, docs/research/f_dbtool_20260712/ROOTCAUSE.md):
// the workable-items schema's PRIMARY KEY is the 3-tuple
// (atm_id, current_location, representation) — GAP A lets the SAME atm_id
// carry BOTH a 'section' (H2 narrative) row AND a 'table' (pipe-summary) row
// in the SAME tracker (the HXC-044 shape). loadItem's WHERE clause used to
// constrain ONLY (atm_id, current_location); on a dual-representation item
// this made `it.Representation` always report the Go zero-value default
// ("section"), and every write-path caller (update/reopen/block/
// obsolete-details) then issued its UPDATE with a WHERE clause ALSO missing
// `representation` — so a SINGLE edit silently clobbered BOTH rows with the
// SAME body, destroying the sibling representation's content. A downstream
// newline/glue bug in renderDocument then corrupted parseFixed's view of
// ~188 LATER items in the tracker (`wi diff` reported 176-190 DB<->MD
// differences). The fix (crud.go/db.go/mutate.go/obsolete.go) scopes every
// item WHERE clause by (atm_id, current_location, representation).
//
// This file is the PERMANENT regression guard for that fix (§11.4.135): it
// reproduces the HXC-044 dual-representation shape via the SAME
// dualRepFixedFixture used by gap_dual_representation_test.go, applies real
// mutations through the obsolete-details and update subcommands, and asserts
// the OTHER representation's row is untouched.
// TestRepresentationScopeIsLoadBearing additionally proves — via a scoped,
// in-test-only reproduction of the PRE-FIX representation-BLIND WHERE clause
// — that omitting the `representation` predicate DOES corrupt the sibling row
// on this exact fixture, satisfying the §11.4.115 reproduce-first guarantee:
// this suite would fail to catch a regression only if the representation
// predicate were dropped from the real code, and THAT scenario is exactly
// what TestRepresentationScopeIsLoadBearing demonstrates would corrupt data.
//
// No mocks: real SQLite driver + real parser + real subcommands throughout.
// Every DB path is a fresh t.TempDir() file — the live docs/workable_items.db
// is never opened, read, or written by this file.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// setupDualRepFixedDB writes dualRepFixedFixture (the HXC-044 dual-
// representation Fixed.md fragment defined in gap_dual_representation_test.go)
// to a fresh temp file and md-to-db's it into a fresh temp SQLite DB, returning
// both paths. Never touches the live docs/workable_items.db.
func setupDualRepFixedDB(t *testing.T) (dbPath, fixedPath string) {
	t.Helper()
	tmp := t.TempDir()
	fixedPath = filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	dbPath = filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on dual-rep fixture exited %d, want %d", code, exitOK)
	}
	return dbPath, fixedPath
}

// repBody reads the body_md of the (id, location, representation) row
// directly, bypassing loadItem's ORDER BY tie-break, so the test can
// independently observe EXACTLY the row the fix's WHERE-clause scoping is
// meant to protect.
func repBody(t *testing.T, dbPath, id, location, representation string) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var body string
	if err := db.QueryRow(`SELECT COALESCE(body_md,'') FROM items
		WHERE atm_id=? AND current_location=? AND representation=?`,
		id, location, representation).Scan(&body); err != nil {
		t.Fatalf("read body_md for %s [%s/%s]: %v", id, location, representation, err)
	}
	return body
}

// repSeverity reads the severity column of the (id, location, representation)
// row directly.
func repSeverity(t *testing.T, dbPath, id, location, representation string) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var sev string
	if err := db.QueryRow(`SELECT COALESCE(severity,'') FROM items
		WHERE atm_id=? AND current_location=? AND representation=?`,
		id, location, representation).Scan(&sev); err != nil {
		t.Fatalf("read severity for %s [%s/%s]: %v", id, location, representation, err)
	}
	return sev
}

// TestObsoleteDetails_DualRepresentation_NoSiblingClobber is the headline
// regression guard: `obsolete-details HXC-044` (the exact command that
// reproduced the live corruption) MUST touch ONLY the 'section' representation
// row it read, leaving the 'table' (pipe-summary) row's body_md byte-for-byte
// unchanged. It then proves the resulting DB state is genuinely self-consistent
// by regenerating Fixed.md from the DB and diffing the DB against that
// regenerated Markdown — a clean round-trip (in-sync, zero divergence lines).
func TestObsoleteDetails_DualRepresentation_NoSiblingClobber(t *testing.T) {
	dbPath, _ := setupDualRepFixedDB(t)

	tableBodyBefore := repBody(t, dbPath, "HXC-044", "Fixed", "table")
	sectionBodyBefore := repBody(t, dbPath, "HXC-044", "Fixed", "section")
	if !strings.HasPrefix(strings.TrimSpace(tableBodyBefore), "|") {
		t.Fatalf("test premise broken: HXC-044 'table' body does not look like a pipe row:\n%s", tableBodyBefore)
	}
	if !strings.Contains(sectionBodyBefore, "## HXC-044") {
		t.Fatalf("test premise broken: HXC-044 'section' body does not carry its H2 heading:\n%s", sectionBodyBefore)
	}

	if code := obsoleteDetailsCmd([]string{
		"HXC-044", "--db", dbPath,
		"--since", "2026-07-12",
		"--reason", "not-reproducible",
		"--superseding", "none",
		"--evidence", "docs/qa/HXC-044/f_dbtool_evidence.md",
	}); code != exitOK {
		t.Fatalf("obsolete-details HXC-044 exited %d, want %d", code, exitOK)
	}

	// The mutated representation (section) MUST carry the new detail line.
	sectionBodyAfter := repBody(t, dbPath, "HXC-044", "Fixed", "section")
	if !strings.Contains(sectionBodyAfter, "**Obsolete-Details:**") ||
		!strings.Contains(sectionBodyAfter, "Reason: not-reproducible") {
		t.Fatalf("GREEN: 'section' body missing the injected Obsolete-Details line:\n%s", sectionBodyAfter)
	}

	// THE CORE INVARIANT: the sibling ('table') representation's row MUST be
	// completely untouched by an edit that only read + rewrote the 'section' row.
	tableBodyAfter := repBody(t, dbPath, "HXC-044", "Fixed", "table")
	if tableBodyAfter != tableBodyBefore {
		t.Fatalf("REGRESSION: obsolete-details on the 'section' representation clobbered the "+
			"sibling 'table' row's body_md (representation-scoping WHERE clause regressed):\n"+
			"before:\n%s\nafter:\n%s", tableBodyBefore, tableBodyAfter)
	}
	if strings.Contains(tableBodyAfter, "**Obsolete-Details:**") {
		t.Fatalf("REGRESSION: the 'table' pipe-row body now carries the 'section' row's "+
			"injected Obsolete-Details line — the two representations were clobbered together:\n%s",
			tableBodyAfter)
	}

	// Round-trip clean: regenerate Fixed.md from the now-mutated DB, then diff
	// the DB against that regenerated Markdown. A representation-scoped, fully
	// self-consistent DB state MUST diff clean (in sync, zero divergences) —
	// exactly the property that was broken live (the glue-corrupted regen made
	// `wi diff` report 176-190 differences downstream of a single clobbered item).
	tmp := t.TempDir()
	outFixed := filepath.Join(tmp, "Fixed.regen.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("db-to-md exited %d, want %d", code, exitOK)
	}
	rc, out := captureDiff(t, []string{"--db", dbPath, "--fixed", outFixed})
	if rc != exitOK {
		t.Fatalf("diff against the freshly-regenerated Fixed.md exited %d (want in-sync %d):\n%s", rc, exitOK, out)
	}
	if !strings.Contains(out, "in sync") {
		t.Fatalf("diff did not report in-sync after a representation-scoped mutation; stdout=%q", out)
	}
	if strings.Contains(out, "differs") {
		t.Fatalf("diff reported a divergence after a representation-scoped mutation "+
			"(round-trip not clean):\n%s", out)
	}
	t.Logf("GREEN: obsolete-details left the sibling 'table' row byte-identical, and the "+
		"resulting DB<->regenerated-Markdown round-trip is clean:\n%s", out)
}

// TestUpdate_DualRepresentation_NoSiblingClobber covers the sibling mutate.go
// write-path (`update --severity`): the same dual-representation invariant
// MUST hold for a field-only update, not only for obsolete-details.
func TestUpdate_DualRepresentation_NoSiblingClobber(t *testing.T) {
	dbPath, _ := setupDualRepFixedDB(t)

	tableBodyBefore := repBody(t, dbPath, "HXC-044", "Fixed", "table")
	tableSeverityBefore := repSeverity(t, dbPath, "HXC-044", "Fixed", "table")

	if code := updateCmd([]string{
		"--db", dbPath, "--id", "HXC-044", "--location", "Fixed", "--severity", "Critical",
	}); code != exitOK {
		t.Fatalf("update --severity exited %d, want %d", code, exitOK)
	}

	// The mutated ('section') representation picks up the new severity.
	sectionSeverityAfter := repSeverity(t, dbPath, "HXC-044", "Fixed", "section")
	if sectionSeverityAfter != "Critical" {
		t.Fatalf("GREEN: 'section' severity=%q, want Critical", sectionSeverityAfter)
	}

	// THE CORE INVARIANT: the sibling 'table' row's severity + body_md MUST be
	// untouched by an update that only read + rewrote the 'section' row.
	tableSeverityAfter := repSeverity(t, dbPath, "HXC-044", "Fixed", "table")
	if tableSeverityAfter != tableSeverityBefore {
		t.Fatalf("REGRESSION: update --severity on the 'section' representation changed the "+
			"sibling 'table' row's severity (%q -> %q); representation-scoping regressed",
			tableSeverityBefore, tableSeverityAfter)
	}
	tableBodyAfter := repBody(t, dbPath, "HXC-044", "Fixed", "table")
	if tableBodyAfter != tableBodyBefore {
		t.Fatalf("REGRESSION: update --severity on the 'section' representation clobbered the "+
			"sibling 'table' row's body_md:\nbefore:\n%s\nafter:\n%s", tableBodyBefore, tableBodyAfter)
	}
	t.Logf("GREEN: update --severity left the sibling 'table' row's severity + body byte-identical")
}

// TestRepresentationScopeIsLoadBearing is the §11.4.115 reproduce-first
// confirmation. It does NOT call any (fixed) subcommand. Instead it issues,
// against the SAME dual-representation fixture, the EXACT pre-fix
// representation-BLIND UPDATE (`WHERE atm_id=? AND current_location=?`, with
// no `representation` predicate) using the identical newBody obsolete-details
// would compute for the 'section' row, and asserts that this DOES corrupt the
// sibling 'table' row. This proves — independent of whether crud.go/mutate.go/
// obsolete.go still carry the representation-scoped WHERE clause — that the
// defect class this test suite guards against is real, and that scoping by
// representation is the load-bearing invariant, not a tautology: a future
// regression that dropped the `representation` predicate from the real code
// would be caught by TestObsoleteDetails_DualRepresentation_NoSiblingClobber /
// TestUpdate_DualRepresentation_NoSiblingClobber above, exactly because THIS
// test demonstrates the representation-blind form genuinely corrupts data on
// this fixture.
func TestRepresentationScopeIsLoadBearing(t *testing.T) {
	dbPath, _ := setupDualRepFixedDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	cur, err := loadItem(db, "HXC-044", "Fixed")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if cur == nil {
		t.Fatalf("test premise broken: HXC-044 not found in Fixed")
	}
	if cur.repOrDefault() != "section" {
		t.Fatalf("test premise broken: loadItem's tie-break did not prefer 'section' (got %q) — "+
			"the mutation below would not reproduce the historical bug shape", cur.repOrDefault())
	}
	tableBodyBefore := repBody(t, dbPath, "HXC-044", "Fixed", "table")

	// Compute EXACTLY the body obsoleteDetailsCmd would write for the 'section'
	// row (same helper, same inputs), then apply it via the PRE-FIX,
	// representation-BLIND WHERE clause — the historical bug, reproduced.
	newBody := injectObsoleteDetails(cur.BodyMD, "2026-07-12", "not-reproducible", "none", "e.md")
	if _, err := db.Exec(`UPDATE items SET body_md=? WHERE atm_id=? AND current_location=?`,
		newBody, "HXC-044", "Fixed"); err != nil {
		t.Fatalf("simulate pre-fix representation-blind UPDATE: %v", err)
	}

	tableBodyAfter := repBody(t, dbPath, "HXC-044", "Fixed", "table")
	if tableBodyAfter == tableBodyBefore {
		t.Fatalf("RED: the representation-blind UPDATE did NOT corrupt the sibling 'table' row — " +
			"the defect this suite guards against is not reproduced on this fixture (test invalid)")
	}
	if tableBodyAfter != newBody {
		t.Fatalf("RED: expected the representation-blind UPDATE to overwrite the 'table' row with "+
			"the 'section' row's new body, got a different (still-wrong) value:\n%s", tableBodyAfter)
	}
	t.Logf("RED reproduced: a representation-blind UPDATE (WHERE atm_id=? AND current_location=? "+
		"only) clobbers the sibling 'table' representation's body_md with the 'section' row's "+
		"content — proving representation-scoping is load-bearing, not a tautology")
}
