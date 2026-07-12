// f_dbtool2_description_table_representation_test.go — §11.4.115/§11.4.135
// permanent regression guard for the F-DBTOOL-2 fix: `update --description`
// on a 'table'-representation item.
//
// Forensic anchor (2026-07-12, docs/research/f_dbtool2_20260712/ROOTCAUSE.md):
// a 'table'-representation item (a legacy Fixed.md pipe-table closure row —
// parseFixed's emitLegacyTable, parse.go) has NO H2 heading / `**Status:**`
// block — its body_md is the single verbatim
// `| date | title | type | status | round | commit(s) | evidence |` line.
// Before this fix, `update --id <id> --description <d>` called
// renderItemBody(...) UNCONDITIONALLY, replacing that single pipe-row line
// with a multi-line H2 section block. Two cooperating defects then fire:
//
//  1. issueHeadingRe / isATMCandidateHeading (parse.go) never recognise a
//     synthetic "FIX-<date>[#n]" id as ANY heading shape (multiple dashes +
//     a literal "#" fail every pattern), so the injected H2 block is
//     swallowed into raw prose on the next db-to-md + re-parse round-trip —
//     the mutated item is no longer parseable as an item at all.
//  2. emitLegacyTable derives an un-ID'd pipe row's atm_id POSITIONALLY (the
//     Nth same-dated row encountered during the scan — a re-derived index,
//     NOT a stable identifier). Once one row stops matching fixedRowRe, the
//     occurrence counter for every LATER same-dated row silently shifts down
//     by one, so a subsequent row's re-derived id collides with (and
//     visually "replaces") the corrupted row's id on the next diff — the
//     `~ <id> body differs` / `- <id> present in DB, absent in Markdown` /
//     status+type-mismatch cascade observed empirically (a SINGLE
//     `update --description` on one table-representation item produced ~64
//     lines of spurious diff output across every LATER same-dated row).
//
// The fix (mutate.go, updateCmd): renderItemBody is now called ONLY when
// cur.repOrDefault() != "table" — for a table-representation item the
// field-only path (preserve cur.BodyMD verbatim; replaceHeadingTitle /
// canonicalizeBodyStatusLine are both proven no-ops on a pipe-row line, since
// neither a "## " heading nor a "**...**" meta line exists in it) is used
// instead, exactly like the already-safe --severity/--status paths. The
// items.description COLUMN is still updated (already applied earlier in
// updateCmd) — only the regenerated body_md shape is skipped for this
// representation, since a pipe row has no dedicated description cell to
// receive it (Description is DERIVED from Title+Evidence at parse time,
// deriveDescription).
//
// TestUpdateDescription_TableRepresentation_RoundTripsCleanly is the GREEN
// confirmation: it drives the REAL `updateCmd` (--description) on a
// table-representation item through the full db-to-md + diff round-trip
// (the SAME production subcommands the CLI user invokes) and asserts
// diffCmd reports zero differences.
//
// TestUpdateDescription_TableRepresentation_RenderItemBodyCorruptsRoundTrip is
// the RED / load-bearing companion (mirrors
// TestRepresentationScopeIsLoadBearing in
// f_dbtool_representation_scope_test.go): it reproduces the PRE-FIX
// behaviour — renderItemBody called unconditionally, exactly as the old
// updateCmd did — via the SAME fixture, and proves that behaviour DOES
// desync the round-trip (the sibling row's re-derived identity shifts),
// satisfying the §11.4.115 reproduce-first guarantee: this suite would fail
// to catch a regression only if the table-representation guard were removed
// from the real code, and THAT scenario is exactly what this test
// demonstrates would desync the DB<->Markdown round-trip.
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

// fx2LegacyTableSameDate — three legacy pipe-table closure rows sharing ONE
// date, none of whose title cells carry a leading bracketed/canonical ticket
// id, so all three fall to emitLegacyTable's synthetic "FIX-<date>[#n]"
// positional-id path: row 1 -> "FIX-2026-05-19", row 2 -> "FIX-2026-05-19#1",
// row 3 -> "FIX-2026-05-19#2" — the exact shape of the live FIX-2026-05-19
// batch in docs/Fixed.md (docs/research/f_dbtool2_20260712/ROOTCAUSE.md).
const fx2LegacyTableSameDate = `| Date | Item | Type | Status | Round | Commit(s) | Evidence |
|---|---|---|---|---|---|---|
| 2026-05-19 | alpha migration landed | Feature | Implemented | 99a | 1111aaa | alpha evidence text |
| 2026-05-19 | beta migration landed | Feature | Implemented | 99a | 2222bbb | beta evidence text |
| 2026-05-19 | gamma migration landed | Task | Completed | 99a | 3333ccc | gamma evidence text |
`

// setupFx2TableDB writes fx2LegacyTableSameDate to a fresh temp Fixed.md and
// md-to-db's it into a fresh temp SQLite DB, returning both paths. Never
// touches the live docs/workable_items.db.
func setupFx2TableDB(t *testing.T) (dbPath, fixedPath string) {
	t.Helper()
	tmp := t.TempDir()
	fixedPath = filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(fx2LegacyTableSameDate), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	dbPath = filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on fx2LegacyTableSameDate exited %d, want %d", code, exitOK)
	}
	return dbPath, fixedPath
}

// TestUpdateDescription_TableRepresentation_RoundTripsCleanly is the GREEN
// confirmation for the F-DBTOOL-2 fix: `update --description` on a
// 'table'-representation item, driven through the REAL production
// subcommands (update -> sync db-to-md -> diff), MUST round-trip with zero
// differences.
func TestUpdateDescription_TableRepresentation_RoundTripsCleanly(t *testing.T) {
	dbPath, _ := setupFx2TableDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	cur, err := loadItem(db, "FIX-2026-05-19#1", "Fixed")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if cur == nil {
		t.Fatalf("test premise broken: FIX-2026-05-19#1 not found in Fixed")
	}
	if cur.repOrDefault() != "table" {
		t.Fatalf("test premise broken: FIX-2026-05-19#1 representation = %q, want %q — "+
			"the fixture no longer reproduces the table-row shape this guard protects",
			cur.repOrDefault(), "table")
	}
	db.Close()

	newDescription := "This regenerated description text replaces the beta migration's derived " +
		"description with a comprehensive, human-readable explanation of what changed and why, " +
		"long enough to satisfy the §11.4.91 description floor on its own."

	if code := updateCmd([]string{
		"--id", "FIX-2026-05-19#1",
		"--db", dbPath,
		"--location", "Fixed",
		"--description", newDescription,
	}); code != exitOK {
		t.Fatalf("update --description exited %d, want %d", code, exitOK)
	}

	// Confirm the DB column itself was actually updated (the fix must not
	// silently drop the --description mutation for a table-representation
	// item — only the body_md REGENERATION is skipped).
	db2, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("reopen DB: %v", err)
	}
	updated, err := loadItem(db2, "FIX-2026-05-19#1", "Fixed")
	if err != nil {
		t.Fatalf("loadItem after update: %v", err)
	}
	if updated == nil {
		t.Fatalf("FIX-2026-05-19#1 vanished after update")
	}
	if updated.Description != newDescription {
		t.Errorf("items.description not updated: got %q, want %q", updated.Description, newDescription)
	}
	if updated.repOrDefault() != "table" {
		t.Errorf("representation flipped by update: got %q, want %q", updated.repOrDefault(), "table")
	}
	if !strings.HasPrefix(updated.BodyMD, "| 2026-05-19 | beta migration landed |") {
		t.Errorf("body_md was regenerated into a non-pipe-row shape for a table-representation item:\n%s",
			updated.BodyMD)
	}
	db2.Close()

	// The production round-trip: regenerate Fixed.md from the DB, then diff
	// the DB against that freshly-regenerated (and freshly re-parsed) file —
	// EXACTLY the `sync db-to-md` + `diff` sequence a CLI operator runs.
	tmp := filepath.Dir(dbPath)
	outFixed := filepath.Join(tmp, "out_Fixed.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("sync db-to-md exited %d, want %d", code, exitOK)
	}
	if code := diffCmd([]string{"--db", dbPath, "--fixed", outFixed}); code != exitOK {
		outBytes, _ := os.ReadFile(outFixed)
		t.Fatalf("diff reported desync after update --description on a table-representation item "+
			"(exit %d, want %d) — regenerated Fixed.md:\n%s", code, exitOK, string(outBytes))
	}
}

// TestUpdateDescription_TableRepresentation_RenderItemBodyCorruptsRoundTrip
// is the RED / load-bearing companion: it reproduces the PRE-FIX behaviour
// (renderItemBody called unconditionally on a table-representation item,
// exactly as the old updateCmd did) via the SAME fixture, and proves that
// behaviour desyncs the round-trip — the row AFTER the corrupted one gets a
// different re-derived identity once emitLegacyTable re-scans the
// regenerated document, so its content shows up under the WRONG id.
func TestUpdateDescription_TableRepresentation_RenderItemBodyCorruptsRoundTrip(t *testing.T) {
	dbPath, _ := setupFx2TableDB(t)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	cur, err := loadItem(db, "FIX-2026-05-19#1", "Fixed")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if cur == nil {
		t.Fatalf("test premise broken: FIX-2026-05-19#1 not found in Fixed")
	}
	if cur.repOrDefault() != "table" {
		t.Fatalf("test premise broken: FIX-2026-05-19#1 representation = %q, want %q",
			cur.repOrDefault(), "table")
	}

	// Capture the THIRD row's original body_md before any mutation — this is
	// the content that the shift bug relabels under the SECOND row's id.
	gammaBefore, err := loadItem(db, "FIX-2026-05-19#2", "Fixed")
	if err != nil || gammaBefore == nil {
		t.Fatalf("test premise broken: FIX-2026-05-19#2 not found in Fixed (err=%v)", err)
	}

	// Reproduce the PRE-FIX code path EXACTLY: `updateCmd` used to call
	// renderItemBody(...) unconditionally whenever --description was set,
	// regardless of representation. Simulate that here by writing the
	// renderItemBody output directly to the 'table' row's body_md, bypassing
	// the (now-present) representation guard — this is what the production
	// code did before the F-DBTOOL-2 fix.
	badBody := renderItemBody(cur.AtmID, cur.Title, cur.Type, cur.Severity,
		"a regenerated H2-shaped description that does not belong on a pipe-table row",
		cur.Status, cur.CreatedBy, cur.AssignedTo)
	if _, err := db.Exec(`UPDATE items SET body_md=? WHERE atm_id=? AND current_location=? AND representation=?`,
		badBody, cur.AtmID, cur.CurrentLocation, cur.repOrDefault()); err != nil {
		t.Fatalf("simulate pre-fix renderItemBody UPDATE: %v", err)
	}

	tmp := filepath.Dir(dbPath)
	outFixed := filepath.Join(tmp, "out_Fixed_red.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("sync db-to-md exited %d, want %d", code, exitOK)
	}
	regenerated, err := os.ReadFile(outFixed)
	if err != nil {
		t.Fatalf("read regenerated Fixed.md: %v", err)
	}

	// Re-parse the regenerated document exactly as `diff` does.
	parsedItems, _ := parseFixed(string(regenerated))
	parsedByID := map[string]item{}
	for _, p := range parsedItems {
		parsedByID[p.AtmID] = p
	}

	// RED assertion 1: the corrupted row's own id is no longer recognised as
	// an item carrying its intended H2 content — issueHeadingRe/
	// isATMCandidateHeading reject the synthetic "FIX-2026-05-19#1" id, so
	// the injected block is swallowed into raw prose.
	if _, ok := parsedByID["FIX-2026-05-19#1"]; ok {
		p := parsedByID["FIX-2026-05-19#1"]
		if strings.Contains(p.BodyMD, "## FIX-2026-05-19#1 —") {
			t.Fatalf("RED not reproduced: the corrupted H2 body was somehow re-recognised verbatim " +
				"under its own id — the defect this suite guards against did not manifest on this " +
				"fixture (test invalid)")
		}
	}

	// RED assertion 2: the THIRD row's original content ("gamma migration
	// landed") is now parsed back under the id that used to belong to the
	// SECOND (corrupted) row — the positional-id shift.
	shifted, ok := parsedByID["FIX-2026-05-19#1"]
	if !ok {
		t.Fatalf("RED not reproduced: expected id %q to still resolve (to the SHIFTED gamma row) "+
			"after the pre-fix corruption, but it is entirely absent from the re-parsed document:\n%s",
			"FIX-2026-05-19#1", string(regenerated))
	}
	if !strings.Contains(shifted.BodyMD, "gamma migration landed") {
		t.Fatalf("RED not reproduced: expected the shifted id %q to carry the THIRD row's "+
			"('gamma migration landed') content after the pre-fix corruption, got:\n%s",
			"FIX-2026-05-19#1", shifted.BodyMD)
	}
	if shifted.BodyMD == gammaBefore.BodyMD {
		// Exact byte-identical match is the strongest possible confirmation
		// of the shift (the row's raw pipe-line text is carried verbatim).
		t.Logf("RED reproduced: after a pre-fix renderItemBody UPDATE on a table-representation item, "+
			"db-to-md + re-parse relabels the THIRD row's original content under the SECOND row's id "+
			"(%q) — proving the table-representation guard in updateCmd (mutate.go) is load-bearing, "+
			"not a tautology: id=%q now carries body=%q", "FIX-2026-05-19#1", "FIX-2026-05-19#1", shifted.BodyMD)
	} else {
		t.Fatalf("RED reproduced the shift but body_md is not byte-identical to the pre-mutation gamma "+
			"row (got %q, want %q) — investigate before trusting this guard", shifted.BodyMD, gammaBefore.BodyMD)
	}
}
