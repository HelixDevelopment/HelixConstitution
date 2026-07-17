// update_body_preservation_test.go — §11.4.93 data-integrity RED/GREEN guard
// for the `update` subcommand's body_md-preservation contract.
//
// Forensic anchor (FACT, reproduced on the live tree): `update --id SPK-481
// --severity Critical` collapsed SPK-481's authored 10 KB body_md to a ~250-byte
// minimal template — updateCmd unconditionally regenerated body_md via
// renderItemBody even when ONLY a structured column (severity) changed. A
// field-only update MUST mutate only the specified column(s) and PRESERVE the
// authored freeform body_md; regenerating from a template is permitted ONLY when
// --description explicitly replaces the freeform content.
//
// §11.4.115 RED-on-broken-artifact polarity: each test asserts the CORRECT
// behaviour, so it FAILS on the pre-fix code (reproducing the truncation) and
// PASSES on the fixed code — the bug-catcher IS the regression-guard. Drives the
// REAL updateCmd against a REAL on-disk SQLite DB (no mock, §11.4.27).
package main

import (
	"strings"
	"testing"
)

// seedRichBody seeds a WIT-001 Issues item via the real add path, then overwrites
// its body_md with a multi-KB authored freeform block — the shape a real md→db
// sync produces (canonical heading + meta block + a large operator-authored
// section). Returns the exact rich body bytes so callers can assert byte-identical
// preservation. add() alone seeds only a minimal template body, which is why the
// rich body is injected directly.
func seedRichBody(t *testing.T, dbPath, status string) string {
	t.Helper()
	seedIssue(t, dbPath, "Bug", "High",
		"Rich-body item for the field-only preservation test",
		"A description long enough to clear the §11.4.91 floor here now")

	freeform := strings.Repeat(
		"- Authored freeform line: multi-KB rich content the operator wrote by "+
			"hand and MUST NOT be destroyed by a field-only update.\n", 100)
	rich := "## WIT-001 — Rich-body item for the field-only preservation test\n\n" +
		"**Status:** " + status + "\n" +
		"**Type:** Bug\n" +
		"**Severity:** High\n\n" +
		"### Forensic anchor — authored freeform section (must survive update)\n\n" +
		freeform + "\n"
	if len(rich) < 2000 {
		t.Fatalf("fixture body too small (%d bytes); need multi-KB to catch truncation", len(rich))
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Keep the status COLUMN consistent with the injected body's **Status:** line
	// (add seeds "Queued"); otherwise the pre-existing statusColumnBodyDesyncs
	// invariant — orthogonal to this test — would be tripped by the fixture.
	if _, err := db.Exec(`UPDATE items SET body_md=?, status=? WHERE atm_id='WIT-001' AND current_location='Issues'`, rich, status); err != nil {
		db.Close()
		t.Fatalf("seed rich body: %v", err)
	}
	db.Close()
	return rich
}

// TestUpdateCmd_PreservesRichBodyOnSeverityOnlyUpdate is the core RED/GREEN guard:
// a --severity-only update MUST leave the authored body_md byte-identical (severity
// is a column-only field; no status change → the §11.4.93 Status-line canonicalise
// is a strict no-op). On the pre-fix code updateCmd regenerated body_md from a
// minimal template → body truncated → this test FAILS (RED).
func TestUpdateCmd_PreservesRichBodyOnSeverityOnlyUpdate(t *testing.T) {
	dbPath := newTestDB(t)
	richBody := seedRichBody(t, dbPath, "Queued")

	if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-001", "--severity", "Critical"}); code != exitOK {
		t.Fatalf("updateCmd exit = %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-001 absent (err=%v)", err)
	}

	// The specified column IS mutated.
	if it.Severity != "Critical" {
		t.Errorf("severity column = %q, want Critical", it.Severity)
	}
	// The authored body_md is PRESERVED byte-for-byte (the data-integrity contract).
	if it.BodyMD != richBody {
		t.Errorf("body_md NOT preserved on --severity-only update: before=%d bytes after=%d bytes "+
			"(update regenerated body_md from a minimal template — the §11.4.93 truncation defect)",
			len(richBody), len(it.BodyMD))
	}
}

// TestUpdateCmd_StatusChangeSyncsStatusLineAndPreservesFreeform proves a --status
// change still works: the `**Status:**` line is canonicalised to the new status
// (the sole guard-enforced column↔body invariant) AND the entire authored freeform
// body is preserved (no truncation). On the pre-fix code the freeform section was
// destroyed by template regeneration → this test FAILS (RED).
func TestUpdateCmd_StatusChangeSyncsStatusLineAndPreservesFreeform(t *testing.T) {
	dbPath := newTestDB(t)
	richBody := seedRichBody(t, dbPath, "Queued")

	if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-001", "--status", "In progress"}); code != exitOK {
		t.Fatalf("updateCmd exit = %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-001 absent (err=%v)", err)
	}

	if it.Status != "In progress" {
		t.Errorf("status column = %q, want In progress", it.Status)
	}
	if !strings.Contains(it.BodyMD, "**Status:** In progress") {
		t.Errorf("body **Status:** line not canonicalised to new status: %q", head(it.BodyMD))
	}
	if strings.Contains(it.BodyMD, "**Status:** Queued") {
		t.Errorf("stale **Status:** Queued line still present after update")
	}
	// The authored freeform section MUST survive a status change (no truncation).
	if !strings.Contains(it.BodyMD, "MUST NOT be destroyed by a field-only update") {
		t.Errorf("authored freeform body destroyed by --status update (truncation): %q", head(it.BodyMD))
	}
	// Only the single Status line changed: the body stays the same order of
	// magnitude (the minimal-template truncation would drop >90%% of the bytes).
	if got, want := len(it.BodyMD), len(richBody); got < want-64 || got > want+64 {
		t.Errorf("body length %d drifted far from preserved %d (expected ~byte-preserving single-line rewrite)", got, want)
	}
}

// head returns a bounded prefix of s for readable test failure messages.
func head(s string) string {
	if len(s) > 300 {
		return s[:300] + "…"
	}
	return s
}
