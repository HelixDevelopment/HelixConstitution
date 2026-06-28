// gap_dual_representation_test.go — §11.4.115 RED-baseline-on-the-broken-artifact
// + polarity-switch coverage for GAP A (dual-representation ingest) and GAP B
// (per-item closure metadata + pipe-row synthesis).
//
// Polarity switch per §11.4.115: env RED_MODE (default "1" = reproduce the
// defect on the PRE-FIX artifact / old shape; "0" = GREEN regression-guard
// asserting the defect is ABSENT on the fixed artifact). One source, two roles —
// the bug-catcher IS the regression-guard. No mocks: real SQLite driver + real
// parser + renderer throughout.
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func redMode() bool { return os.Getenv("RED_MODE") != "0" }

// dualRepFixedFixture is an HXC-044-shaped Fixed.md fragment: the SAME ticket id
// (HXC-044) appears BOTH as a pipe-table closure ROW and as a detailed H2
// SECTION in the SAME tracker — the exact dual-representation that collided on
// the old (atm_id, current_location) PRIMARY KEY (GAP A).
const dualRepFixedFixture = `# Fixed

| Closure | Title | Type | Status | Round | Commit(s) | Evidence |
|---|---|---|---|---|---|---|
| 2026-06-09 | HXC-044: rocm-smi JSON parser returns -1 sentinel instead of parsed value | Bug | Obsolete (→ Fixed.md) | 2026-06-09 session | f27e986c | docs/qa/HXC-044/evidence.md |

## HXC-044 — internal/cognee: rocm-smi JSON parser returns -1 sentinel instead of parsed GPU-use value

**Type:** Bug
**Status:** Obsolete (→ Fixed.md)
**Evidence:** docs/qa/HXC-044/evidence.md

Found by an isolated-worktree full unit sweep. Genuine product defect reproducible deterministically.
`

// TestGapA_DualRepresentationIngest is the GAP-A polarity test.
//
// RED_MODE=1 (default): reproduce the collision on the PRE-FIX shape — an items
// table with the OLD 2-tuple PK (atm_id, current_location). Inserting HXC-044
// twice in Fixed (once per representation) MUST fail with the UNIQUE-constraint
// error the live binary produced ("persist fixed: insert item HXC-044: UNIQUE
// constraint failed: items.atm_id, items.current_location").
//
// RED_MODE=0: the GREEN guard — the CURRENT binary parses the dual-rep fixture
// and round-trips it byte-identically, with BOTH representations stored as
// distinct rows under the 3-tuple PK.
func TestGapA_DualRepresentationIngest(t *testing.T) {
	if redMode() {
		// PRE-FIX artifact: the OLD 2-tuple-PK items table. Prove the collision
		// is genuinely present (defect-present captured evidence per §11.4.5).
		dbPath := filepath.Join(t.TempDir(), "old.db")
		raw, err := sql.Open("sqlite3", dbPath)
		if err != nil {
			t.Fatalf("open: %v", err)
		}
		defer raw.Close()
		if _, err := raw.Exec(`CREATE TABLE items (
			atm_id TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL,
			title TEXT NOT NULL, description TEXT NOT NULL,
			current_location TEXT NOT NULL DEFAULT 'Issues', body_md TEXT,
			PRIMARY KEY (atm_id, current_location))`); err != nil {
			t.Fatalf("create old-shape items: %v", err)
		}
		ins := `INSERT INTO items (atm_id,type,status,title,description,current_location,body_md) VALUES (?,?,?,?,?,?,?)`
		if _, err := raw.Exec(ins, "HXC-044", "Bug", "Obsolete (→ Fixed.md)",
			"table row", "the pipe-table representation row for HXC-044", "Fixed", "| ... |\n"); err != nil {
			t.Fatalf("first (table) insert unexpectedly failed: %v", err)
		}
		// The SECOND representation of the SAME id in the SAME tracker — this is
		// what GAP A could not store on the old PK.
		_, err = raw.Exec(ins, "HXC-044", "Bug", "Obsolete (→ Fixed.md)",
			"section block", "the H2 section representation for HXC-044", "Fixed", "## HXC-044 — ...\n")
		if err == nil {
			t.Fatalf("RED: expected a UNIQUE-constraint collision on the old 2-tuple PK, but the second insert SUCCEEDED — GAP A not reproduced")
		}
		if !strings.Contains(err.Error(), "UNIQUE constraint failed") {
			t.Fatalf("RED: expected UNIQUE constraint error, got: %v", err)
		}
		t.Logf("RED reproduced: dual-representation collision on old 2-tuple PK: %v", err)
		return
	}

	// GREEN guard on the FIXED artifact: the current schema's 3-tuple PK +
	// representation discriminator lets both representations coexist, and the
	// dual-rep fixture round-trips byte-identically.
	tmp := t.TempDir()
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("GREEN: md-to-db on dual-rep fixture exited %d (GAP A regressed)", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// BOTH representations stored as distinct rows.
	var nSection, nTable int
	_ = db.QueryRow(`SELECT COUNT(*) FROM items WHERE atm_id='HXC-044' AND current_location='Fixed' AND representation='section'`).Scan(&nSection)
	_ = db.QueryRow(`SELECT COUNT(*) FROM items WHERE atm_id='HXC-044' AND current_location='Fixed' AND representation='table'`).Scan(&nTable)
	db.Close()
	if nSection != 1 || nTable != 1 {
		t.Fatalf("GREEN: expected 1 section + 1 table row for HXC-044, got section=%d table=%d", nSection, nTable)
	}

	outFixed := filepath.Join(tmp, "Fixed.regen.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("GREEN: db-to-md exited %d", code)
	}
	regen, err := os.ReadFile(outFixed)
	if err != nil {
		t.Fatal(err)
	}
	if string(regen) != dualRepFixedFixture {
		t.Fatalf("GREEN: dual-rep fixture NOT byte-identical after round-trip:\n%s", firstDiff(dualRepFixedFixture, string(regen)))
	}
	t.Logf("GREEN: dual-representation round-trip BYTE-IDENTICAL (%d bytes), both reps stored", len(regen))
}

// TestGapB_ClosureMetadataAndPipeRowSynthesis is the GAP-B polarity test.
//
// RED_MODE=1 (default): reproduce the gap on the PRE-FIX shape — an items table
// WITHOUT the closure_date/round/commit_ref columns cannot store closure
// metadata, so a synthesize-the-pipe-row query has no fields to read (the column
// is absent). Prove the absence is genuine.
//
// RED_MODE=0: the GREEN guard — (a) the parser extracts closure metadata FROM a
// pipe-table row into the DB columns, and (b) renderClosurePipeRow SYNTHESIZES a
// well-formed pipe row from an item carrying ONLY DB fields (no raw body),
// proving db→md can emit a pipe row from stored fields (the conductor's reconcile
// path for the ~74 missing pipe rows).
func TestGapB_ClosureMetadataAndPipeRowSynthesis(t *testing.T) {
	if redMode() {
		dbPath := filepath.Join(t.TempDir(), "old.db")
		raw, err := sql.Open("sqlite3", dbPath)
		if err != nil {
			t.Fatalf("open: %v", err)
		}
		defer raw.Close()
		if _, err := raw.Exec(`CREATE TABLE items (
			atm_id TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL,
			title TEXT NOT NULL, description TEXT NOT NULL,
			current_location TEXT NOT NULL DEFAULT 'Issues', body_md TEXT,
			PRIMARY KEY (atm_id, current_location))`); err != nil {
			t.Fatalf("create old-shape items: %v", err)
		}
		// The closure-metadata columns do not exist on the pre-fix shape, so a
		// query reading them MUST error — the gap that blocked DB-driven pipe-row
		// synthesis.
		_, err = raw.Query(`SELECT closure_date, round, commit_ref FROM items`)
		if err == nil {
			t.Fatalf("RED: expected 'no such column' on the pre-fix shape, but the query SUCCEEDED — GAP B not reproduced")
		}
		if !strings.Contains(err.Error(), "no such column") {
			t.Fatalf("RED: expected a 'no such column' error, got: %v", err)
		}
		t.Logf("RED reproduced: closure-metadata columns absent on pre-fix shape: %v", err)
		return
	}

	// GREEN guard: parse closure metadata out of a pipe row, then prove the
	// renderer can re-emit a pipe row from DB fields alone.
	tmp := t.TempDir()
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("GREEN: md-to-db exited %d", code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// (a) The 'table'-representation row carries the parsed closure metadata.
	var cd, rnd, commit string
	if err := db.QueryRow(`SELECT COALESCE(closure_date,''), COALESCE(round,''), COALESCE(commit_ref,'')
		FROM items WHERE atm_id='HXC-044' AND current_location='Fixed' AND representation='table'`).
		Scan(&cd, &rnd, &commit); err != nil {
		t.Fatalf("GREEN: read closure metadata: %v", err)
	}
	if cd != "2026-06-09" || rnd != "2026-06-09 session" || commit != "f27e986c" {
		t.Fatalf("GREEN: closure metadata mis-parsed: closure_date=%q round=%q commit=%q", cd, rnd, commit)
	}

	// (b) Synthesize a pipe row from DB fields ALONE (no raw body replay) — the
	// db→md emit capability for items that have closure metadata but no pipe row.
	synth := item{
		AtmID: "HXC-077", Type: "Bug", Status: "Fixed (→ Fixed.md)",
		Title:       "synthesized closure row from DB fields only",
		ClosureDate: "2026-06-16", Round: "round-7", CommitRef: "deadbeef",
		ClosureCriteria: "docs/qa/HXC-077/evidence.md",
	}
	row := renderClosurePipeRow(synth)
	wantCells := []string{"2026-06-16", "HXC-077: synthesized closure row from DB fields only",
		"Bug", "Fixed (→ Fixed.md)", "round-7", "deadbeef", "docs/qa/HXC-077/evidence.md"}
	for _, w := range wantCells {
		if !strings.Contains(row, w) {
			t.Fatalf("GREEN: synthesized pipe row missing %q:\n%s", w, row)
		}
	}
	// The synthesized row must have exactly 7 cells (8 pipe delimiters) so it
	// aligns with the 7-column header — a malformed row would break the table.
	if n := strings.Count(strings.TrimRight(row, "\n"), "|"); n != 8 {
		t.Fatalf("GREEN: synthesized pipe row has %d pipes, want 8 (7 columns): %s", n, row)
	}
	t.Logf("GREEN: closure metadata parsed + pipe row synthesized from DB fields: %s", strings.TrimRight(row, "\n"))
}

// TestGapA_RenderRepresentationKeyIsLoadBearing is the §1.1 paired mutation for
// GAP A: it proves renderDocument's (atm_id, representation) body lookup is NOT a
// tautology. We sync the dual-rep fixture, then MUTATE the DB to collapse both
// item segments onto the SAME representation ('section') — the exact mistake the
// pre-fix renderer made when it keyed bodies by atm_id alone. With the mutation
// in place the round-trip MUST break (both segments resolve to the section body,
// dropping the table row). After restoring, the round-trip is byte-identical
// again. A renderer that ignored representation would PASS the mutated case — so
// this test FAILing under the mutation proves the guard is real.
func TestGapA_RenderRepresentationKeyIsLoadBearing(t *testing.T) {
	if redMode() {
		t.Skip("SKIP-OK: GREEN-only §1.1 paired-mutation guard for the representation render key")
	}
	tmp := t.TempDir()
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(fixedPath, []byte(dualRepFixedFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// MUTATION: collapse the 'table' item-segment's representation to 'section'
	// (simulate the pre-fix atm_id-only keying). Now two segments point at the
	// section body → the table row is lost on render.
	if _, err := db.Exec(`UPDATE doc_segments SET representation='section'
		WHERE document='Fixed' AND kind='item' AND atm_id='HXC-044' AND representation='table'`); err != nil {
		t.Fatalf("apply mutation: %v", err)
	}
	mutated, err := renderDocument(db, "Fixed")
	if err != nil {
		t.Fatalf("render (mutated): %v", err)
	}
	if mutated == dualRepFixedFixture {
		t.Fatalf("MUTATION DID NOT BREAK ROUND-TRIP — renderDocument's representation key is a tautology (bluff guard)")
	}
	t.Logf("mutation correctly broke the round-trip (table row lost) — representation render key is load-bearing")

	// RESTORE: put the table segment's representation back; round-trip is whole again.
	if _, err := db.Exec(`UPDATE doc_segments SET representation='table'
		WHERE document='Fixed' AND kind='item' AND atm_id='HXC-044' AND raw IS NULL AND seq=(
			SELECT MIN(seq) FROM doc_segments WHERE document='Fixed' AND kind='item' AND atm_id='HXC-044')`); err != nil {
		t.Fatalf("restore mutation: %v", err)
	}
	restored, err := renderDocument(db, "Fixed")
	db.Close()
	if err != nil {
		t.Fatalf("render (restored): %v", err)
	}
	if restored != dualRepFixedFixture {
		t.Fatalf("restore did not recover byte-identical round-trip:\n%s", firstDiff(dualRepFixedFixture, restored))
	}
}

// TestGapB_PipeRowSynthesisIsParseable closes the loop: a synthesized pipe row,
// placed under the canonical header, is itself recognised by parseFixed as a
// 'table'-representation item with the same closure metadata — proving the
// synthesis is round-trippable (db→md→db) for the reconcile path.
func TestGapB_PipeRowSynthesisIsParseable(t *testing.T) {
	if redMode() {
		t.Skip("SKIP-OK: GREEN-only structural guard for the GAP-B synthesis loop (no pre-fix artifact to reproduce)")
	}
	synth := item{
		AtmID: "HXC-088", Type: "Task", Status: "Completed (→ Fixed.md)",
		Title:       "round-trippable synthesized row",
		ClosureDate: "2026-06-16", Round: "r9", CommitRef: "cafef00d",
		ClosureCriteria: "docs/qa/HXC-088/evidence.md",
	}
	doc := "# Fixed\n\n" + fixedPipeTableHeader + renderClosurePipeRow(synth)
	items, segs := parseFixed(doc)
	var found *item
	for i := range items {
		if items[i].AtmID == "HXC-088" {
			found = &items[i]
		}
	}
	if found == nil {
		t.Fatalf("synthesized row not re-parsed as an item; items=%d segs=%d", len(items), len(segs))
	}
	if found.Representation != "table" {
		t.Fatalf("re-parsed synthesized row representation=%q, want table", found.Representation)
	}
	if found.ClosureDate != "2026-06-16" || found.Round != "r9" || found.CommitRef != "cafef00d" {
		t.Fatalf("re-parsed closure metadata wrong: %q / %q / %q", found.ClosureDate, found.Round, found.CommitRef)
	}
}
