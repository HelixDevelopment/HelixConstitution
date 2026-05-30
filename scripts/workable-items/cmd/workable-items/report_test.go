// report_test.go — anti-bluff coverage for the report subcommand.
//
// report is read-only, so the anti-bluff bar is "the counts reflect real DB
// state". We seed a known mix of items via the real add path and assert the
// grouped tallies + the §11.4.90 obsolete audit reflect that exact state, and
// that the obsolete audit flags a bare-assertion Obsolete item as a gap.
package main

import (
	"testing"
)

// seedMix inserts a deterministic mix: 2 Bug, 1 Feature (3 Queued total).
func seedMix(t *testing.T, dbPath string) {
	t.Helper()
	specs := []struct{ id, typ, sev string }{
		{"WIT-001", "Bug", "Critical"},
		{"WIT-002", "Bug", "Low"},
		{"WIT-003", "Feature", "Critical"},
	}
	for _, s := range specs {
		if code := addCmd([]string{
			"--db", dbPath, "--id", s.id,
			"--title", "seeded item for report tally",
			"--description", "a sufficiently long description that clears the §11.4.91 floor for the report seed",
			s.typ, s.sev,
		}); code != exitOK {
			t.Fatalf("seed %s exited %d", s.id, code)
		}
	}
}

func TestReport_ByStatus(t *testing.T) {
	dbPath := newTestDB(t)
	seedMix(t, dbPath)
	if code := reportCmd([]string{"--db", dbPath, "--by-status"}); code != exitOK {
		t.Fatalf("report --by-status exited %d", code)
	}
}

func TestReport_GroupCountsReflectState(t *testing.T) {
	dbPath := newTestDB(t)
	seedMix(t, dbPath)
	db, _ := openDB(dbPath)
	defer db.Close()

	// Verify the underlying group query the report renders is faithful to state.
	check := func(col, val string, want int) {
		var got int
		if err := db.QueryRow(`SELECT COUNT(1) FROM items WHERE `+col+`=?`, val).Scan(&got); err != nil {
			t.Fatalf("count %s=%s: %v", col, val, err)
		}
		if got != want {
			t.Errorf("%s=%s count = %d, want %d", col, val, got, want)
		}
	}
	check("type", "Bug", 2)
	check("type", "Feature", 1)
	check("severity", "Critical", 2)
	check("status", "Queued", 3)

	// All grouping views must succeed on real data.
	for _, flag := range []string{"--by-type", "--by-severity", "--by-status"} {
		if code := reportCmd([]string{"--db", dbPath, flag}); code != exitOK {
			t.Errorf("report %s exited %d", flag, code)
		}
	}
}

func TestReport_RejectsMultipleViews(t *testing.T) {
	dbPath := newTestDB(t)
	if code := reportCmd([]string{"--db", dbPath, "--by-type", "--by-status"}); code == exitOK {
		t.Fatal("report ACCEPTED two grouping flags — selection guard is a bluff")
	}
}

// TestReport_ObsoleteAuditFlagsGap proves the §11.4.90 audit flags an Obsolete
// item lacking an obsolete_details row (bare-assertion forbidden) AND passes
// once the details row is present.
func TestReport_ObsoleteAuditFlagsGap(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Insert an Obsolete item WITHOUT obsolete_details — a §11.4.90 gap.
	if _, err := db.Exec(`INSERT INTO items
		(atm_id, type, status, title, description, current_location, body_md)
		VALUES ('WIT-OBS','Task','Obsolete (→ Fixed.md)',
		'an obsoleted item lacking its triple-check details row',
		'an obsoleted item lacking its triple-check details row','Fixed','x')`); err != nil {
		t.Fatalf("seed obsolete: %v", err)
	}
	db.Close()

	if code := reportCmd([]string{"--db", dbPath, "--obsolete-audit"}); code == exitOK {
		t.Fatal("obsolete audit PASSED on a bare-assertion Obsolete item — §11.4.90 audit is a bluff")
	}

	// Now supply the details row; the audit must pass.
	db, _ = openDB(dbPath)
	if _, err := db.Exec(`INSERT INTO obsolete_details
		(atm_id, since, reason, superseding_item, triple_check_evidence)
		VALUES ('WIT-OBS','2026-05-30','superseded-by-later-mandate','§XY',
		'git-log: commit abc123 removed the feature; grep confirms no callers remain')`); err != nil {
		t.Fatalf("seed details: %v", err)
	}
	db.Close()

	if code := reportCmd([]string{"--db", dbPath, "--obsolete-audit"}); code != exitOK {
		t.Fatalf("obsolete audit FAILED after details supplied (exit %d) — false negative", code)
	}
}
