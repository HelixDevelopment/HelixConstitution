// sync_diff_test.go — §11.4.115 RED-baseline-on-the-broken-artifact +
// polarity-switch coverage for the diffCmd composite-key regression.
//
// Defect (HXC, 2026-06): diffCmd built its DB lookup map keyed by it.AtmID
// ALONE, but the schema PK is the composite (atm_id, current_location,
// representation) and loadItems returns ALL such rows. For any atm_id with 2+
// rows (a Fixed-closure pipe-table row + an H2 section block in the SAME
// tracker — the GAP-A / HXC-044 dual-representation case), the atm_id-keyed map
// kept only the LAST-loaded row, so the OTHER parsed Markdown representation was
// compared against the WRONG DB row → a SPURIOUS "body differs" divergence while
// validate + the md⟷db round-trip gate both PASS. renderDocument already keys
// the same lookup by id + "\x00" + representation (db.go), proving the correct
// pattern; the fix re-keys diffCmd's map by the same composite identity.
//
// Polarity switch per §11.4.115: env RED_MODE (default "1" = reproduce the
// defect on the PRE-FIX collapse-by-atm_id logic; "0" = GREEN regression-guard
// asserting the CURRENT diffCmd reports ZERO divergence on a self-consistent
// dual-representation md⟷db state). One source, two roles — the bug-catcher IS
// the regression-guard. No mocks: real SQLite driver + real parser + real
// syncMDToDB + real diffCmd throughout. redMode() is shared with
// gap_dual_representation_test.go.
package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// captureDiff runs diffCmd(args) capturing its real os.Stdout (diffCmd prints
// divergence lines + the summary to stdout) and returns the exit code + output.
// Unlike captureStdout (version_tags_test.go) it does NOT assert exitOK, because
// the WHOLE POINT is to observe whether diff reports a (spurious) divergence,
// which makes diff return exitUsage.
func captureDiff(t *testing.T, args []string) (int, string) {
	t.Helper()
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w
	rc := diffCmd(args)
	w.Close()
	os.Stdout = orig
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read captured stdout: %v", err)
	}
	return rc, string(out)
}

// TestDiffCmd_CompositeKeyNoSpuriousDivergence is the diffCmd composite-key
// polarity test.
//
// Setup (both modes): write the SAME HXC-044 dual-representation Fixed.md
// (a pipe-table closure row + an H2 section, identical to dualRepFixedFixture in
// gap_dual_representation_test.go), then md→db it. The DB now holds TWO rows for
// (HXC-044, Fixed): representation='table' and representation='section', each
// with its own body. The Markdown and the DB are therefore PERFECTLY in sync —
// a correct diff against that same Fixed.md MUST report ZERO divergence.
//
// RED_MODE=1 (default): reproduce the defect against the PRE-FIX lookup logic.
// We rebuild the atm_id-ONLY map exactly as the buggy diffCmd did
// (dbByID[it.AtmID] = it, last-write-wins), then run the SAME compare loop the
// buggy diffCmd ran. Because both parsed representations of HXC-044 are matched
// against the single surviving (last-loaded) DB row, exactly one of them has a
// body mismatch → a SPURIOUS "body differs" divergence is produced. The test
// asserts that spurious divergence IS present — capturing the defect on the
// broken artifact (§11.4.5 defect-present evidence). If the collapse produced no
// divergence, GAP A is not reproduced and the test FAILs honestly (§11.4.6).
//
// RED_MODE=0: the GREEN guard — run the CURRENT diffCmd against the same
// self-consistent state and assert it returns exitOK with the in-sync summary
// and NO "body differs" / "type" / "status" divergence line for HXC-044.
func TestDiffCmd_CompositeKeyNoSpuriousDivergence(t *testing.T) {
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
		// PRE-FIX artifact: replicate the buggy atm_id-only collapse + the buggy
		// compare loop, in-test, against the real DB + real parser, and prove it
		// manufactures a spurious divergence on a genuinely-in-sync state.
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB: %v", err)
		}
		dbItems, err := loadItems(db)
		db.Close()
		if err != nil {
			t.Fatalf("loadItems: %v", err)
		}

		// Sanity: the DB really does hold two composite-key rows for HXC-044 —
		// otherwise the collapse cannot manufacture the divergence and the RED
		// would be vacuous.
		nHXC044 := 0
		for _, it := range dbItems {
			if it.AtmID == "HXC-044" {
				nHXC044++
			}
		}
		if nHXC044 < 2 {
			t.Fatalf("RED setup invalid: expected >=2 DB rows for HXC-044, got %d "+
				"(loadItems is not returning both representations)", nHXC044)
		}

		// THE BUG, verbatim: key the lookup by atm_id alone (last-write-wins).
		dbByIDBuggy := map[string]item{}
		for _, it := range dbItems {
			dbByIDBuggy[it.AtmID] = it
		}

		content, err := os.ReadFile(fixedPath)
		if err != nil {
			t.Fatal(err)
		}
		parsed, _ := parseFixed(string(content))

		// THE BUG's compare loop: each parsed representation matched against the
		// single surviving atm_id bucket.
		spurious := 0
		for _, p := range parsed {
			d, ok := dbByIDBuggy[p.AtmID]
			if !ok {
				continue
			}
			if p.Type != d.Type || p.Status != d.Status || p.BodyMD != d.BodyMD {
				spurious++
			}
		}
		if spurious == 0 {
			t.Fatalf("RED: expected the atm_id-only collapse to manufacture a spurious " +
				"divergence on the in-sync dual-rep state, but found none — defect not reproduced")
		}
		t.Logf("RED reproduced: atm_id-only collapse manufactures %d spurious divergence(s) "+
			"on a genuinely-in-sync dual-representation md⟷db state (composite-key bug)", spurious)
		return
	}

	// GREEN guard on the FIXED artifact: the real diffCmd, against the same
	// self-consistent dual-rep state, reports ZERO divergence.
	rc, out := captureDiff(t, []string{"--db", dbPath, "--fixed", fixedPath})
	if strings.Contains(out, "body differs") || strings.Contains(out, "HXC-044 type") ||
		strings.Contains(out, "HXC-044 status") {
		t.Fatalf("GREEN: diffCmd reported a SPURIOUS divergence on an in-sync "+
			"dual-representation state (composite-key bug regressed):\n%s", out)
	}
	if rc != exitOK {
		t.Fatalf("GREEN: diffCmd exited %d (want exitOK %d) on an in-sync state:\n%s",
			rc, exitOK, out)
	}
	if !strings.Contains(out, "in sync") {
		t.Fatalf("GREEN: diffCmd did not report in-sync; stdout=%q", out)
	}
	t.Logf("GREEN: diffCmd reports DB and Markdown in sync (zero divergence) for the "+
		"dual-representation HXC-044 state — composite-key lookup correct")
}
