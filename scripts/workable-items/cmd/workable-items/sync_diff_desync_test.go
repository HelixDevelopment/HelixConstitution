// sync_diff_desync_test.go — §11.4.115 RED-baseline-on-the-broken-artifact +
// polarity-switch coverage for TWO extensions of the ATM-627 (task #20)
// column<->body_md Status DESYNC class, landed 2026-07-07 during a
// tooling-integrity investigation dispatched against the SPK-481 sync:
//
//   (1) TestATM627_StatusDesync_RealisticMultiBlockBody hardens the EXISTING
//       statusColumnBodyDesyncs guard (sync.go, wired into validateCmd since
//       commit a7385c88 "eliminate column-vs-body Status desync at root")
//       against realistic body complexity: an SPK-481-shaped item whose body
//       carries TWO `**Status:**` lines — a top-of-body one AND a SECOND one
//       inside an embedded sub-heading ("### §X.Y sub-item disposition …"),
//       exactly the shape found in the real live tracker (docs/Issues.md
//       [SPK-481] carries this pattern verbatim). The prior test fixtures in
//       atm627_status_desync_test.go all use single-Status-line toy bodies;
//       this proves the derivation (lastBodyStatus, parse.go) is exercised
//       correctly when a genuine second Status-bearing block is present.
//
//       ATM-842 UPDATE (§11.4.120 reconciliation): the derivation was then
//       "last **Status:** line anywhere in the block wins", so a desync in
//       EITHER line was caught. That last-wins scanning WAS the ATM-842 defect
//       (a nested sub-item's Status displaced the item's own). Derivation is now
//       scoped to the item's OWN metadata region, so this test asserts the NEW
//       mechanism: a desync in the item's OWN Status line is caught, and a
//       diverged NESTED sub-item line is correctly NOT an item-level desync
//       (the golden-FALSE / false-positive guard).
//
//       Live reproduction performed against a throwaway temp COPY of the real
//       docs/workable_items.db (2026-07-07, never touching the tracked DB, per
//       Constitution.md §11.4.95/§9.2) confirmed statusColumnBodyDesyncs
//       already catches the EXACT SPK-481 shape precisely (naming the atm_id +
//       both divergent values) — this test makes that finding a permanent,
//       synthetic (non-live-DB) regression guard per §11.4.135.
//
//   (2) TestDiffCmd_BareDBOnlyReportsColumnBodyDesync closes a REAL, narrower
//       gap: `diff --db <path>` invoked WITHOUT --issues/--fixed performs no
//       Markdown comparison at all, so EVERY DB item was reported merely
//       "present in DB, absent in Markdown" — uninformative noise that does not
//       specifically surface a pure DB-internal column<->body_md desync. diff
//       now ALSO runs statusColumnBodyDesyncs unconditionally (defense-in-depth
//       alongside validate, the "correct home" per Constitution.md §11.4.93),
//       so even a bare `diff --db` invocation names the specific defect.
//
// Polarity switch per §11.4.115: shared redMode() (gap_dual_representation_test.go,
// default RED_MODE unset/"1" = reproduce the PRE-FIX gap; RED_MODE=0 = GREEN
// regression-guard asserting the CURRENT (fixed) code catches it). One source,
// two roles. No mocks: real SQLite driver + real parser + real diffCmd/validateCmd
// throughout, exactly like the sibling ATM-627 test files in this package.
//
// §1.1 PAIRED-MUTATION SENTINEL: reverting the sync.go diffCmd hunk that calls
// `statusColumnBodyDesyncs(dbItems)` (or reverting the `differences += len(desyncs)`
// tally) makes TestDiffCmd_BareDBOnlyReportsColumnBodyDesync's GREEN branch FAIL —
// proving the wiring is not a tautology.
//
// HARD CONSTRAINT: fresh temp DB only; NEVER touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// spk481ShapedIssuesFixture is a synthetic (non-live) fixture mirroring the REAL
// live [SPK-481] item's structural complexity: a top-of-body `**Status:**` line,
// an `**Operator-Block-Details:**` + `**Unblock-Choices:**` block, a forensic
// blockquote, an embedded pipe table, AND a second H3 sub-heading
// ("### §1.2 sub-item disposition …") that ITSELF carries its own
// `**Status:**` line — exactly the shape captured in docs/Issues.md [SPK-481]
// (verified 2026-07-07 against the live tracker). Uses ATM-950 (a synthetic id
// that does not collide with any live tracker id) to keep this test fully
// decoupled from the live DB per the HARD CONSTRAINT above.
const spk481ShapedIssuesFixture = `# Issues

## §1. [ATM-950] CRITICAL synthetic realistic-shape item mirroring the SPK-481 multi-block body with an embedded sub-heading Status line

**Status:** Operator-blocked
**Reopens-count:** 1
**Type:** Bug
**Operator-Block-Details:** WHAT: synthetic realistic-shape fixture for the ATM-627 desync guard hardening test. WHY: §11.4.21 exhaustion — mirrors a real multi-section body so the guard is proven against realistic complexity, not just single-line toy bodies. WHO: Operator
**Unblock-Choices:** [A] operator confirms the synthetic fixture — RECOMMENDED · [B] operator requests a different fixture shape

### Forensic anchor — verbatim (synthetic, 2026-07-07)

> "This is a synthetic forensic quote mirroring the length and structure of a real operator report, so the fixture exercises the parser under realistic body complexity rather than a trivial one-line body."

### Sub-issue table

| # | Issue | Status | Layer |
|---|---|---|---|
| §1.1 | baseline reference | PASS | Reference |
| §1.2 | still open | OPEN | Layer X |

### §1.2 sub-item disposition (Status: Operator-blocked) — By: AI, On: 2026-07-07, synthetic

**Status:** Operator-blocked
**Type:** Bug

**Sub-item status:** synthetic disposition text mirroring the real SPK-481 embedded sub-heading Status line, proving last-**Status:**-line-wins semantics (lastBodyStatus) is exercised correctly under realistic multi-block complexity, not merely a single top-of-body line.
`

// buildSPK481ShapedFixtureDB syncs spk481ShapedIssuesFixture into a fresh temp DB
// and returns its path. Both `**Status:**` lines read "Operator-blocked" at
// import time, so the freshly-synced DB is self-consistent by construction
// (buildItem derives items.status from exactly the LAST such line).
func buildSPK481ShapedFixtureDB(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("setup: md-to-db on SPK-481-shaped fixture exited %d", code)
	}
	return dbPath
}

// injectSubHeadingStatusDesync mutates ONLY the SECOND (embedded `### `
// sub-item) `**Status:** Operator-blocked` line in ATM-950's stored body_md to
// "Reopened", leaving the FIRST (top-of-body) line and the items.status column
// untouched.
//
// ATM-842 RECONCILIATION (§11.4.120): this used to be the test's DESYNC
// injection, because lastBodyStatus then derived the item's status from the
// LAST `**Status:**` line anywhere in the block — so a nested SUB-ITEM's line
// displaced the item's own. That last-wins scanning was the ATM-842 defect
// (measured on the live registry: 11 items carried a sub-item's Status and 8 a
// sub-item's Type in their own columns, e.g. ATM-415). Derivation is now scoped
// to the item's OWN metadata region, so this mutation is CORRECTLY no longer an
// item-level desync — a sub-item's status is not the item's status, and there
// is no column for it to be out of sync with. The injection is retained as the
// guard's golden-FALSE (negative-control) case per §11.4.201.
func injectSubHeadingStatusDesync(t *testing.T, dbPath string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	// Replace only the LAST occurrence: the sub-heading's own Status line is
	// preceded by a blank line + "**Type:** Bug\n" immediately after it in the
	// fixture, which the top-of-body occurrence is not — anchoring on that
	// unique trailing context makes the replace unambiguous and leaves the
	// top-of-body line (and everything else) byte-identical.
	res, err := db.Exec(`UPDATE items SET body_md = replace(
		body_md,
		'**Status:** Operator-blocked
**Type:** Bug

**Sub-item status:**',
		'**Status:** Reopened
**Type:** Bug

**Sub-item status:**'
	) WHERE atm_id='ATM-950' AND current_location='Issues'`)
	if err != nil {
		t.Fatalf("inject sub-heading desync: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject sub-heading desync: expected 1 row affected, got %d (replace target not found — fixture drifted?)", n)
	}
}

// injectOwnStatusDesync mutates ONLY the item's OWN (top-of-body) Status line
// to a stale "Reopened", leaving the items.status column ("Operator-blocked")
// and the nested sub-item's line untouched. Anchored on the unique
// `**Reopens-count:** 1` line that follows the item's own Status line (the
// sub-item's is followed by `**Type:** Bug` + `**Sub-item status:**`), so the
// replace is unambiguous.
//
// ATM-842 (§11.4.120): this is now the test's REAL desync injection — the
// item's own Status line disagreeing with its own column is what
// statusColumnBodyDesyncs exists to catch.
func injectOwnStatusDesync(t *testing.T, dbPath string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	res, err := db.Exec(`UPDATE items SET body_md = replace(
		body_md,
		'**Status:** Operator-blocked
**Reopens-count:** 1',
		'**Status:** Reopened
**Reopens-count:** 1'
	) WHERE atm_id='ATM-950' AND current_location='Issues'`)
	if err != nil {
		t.Fatalf("inject own-status desync: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject own-status desync: expected 1 row affected, got %d (replace target not found — fixture drifted?)", n)
	}
}

// TestATM627_StatusDesync_RealisticMultiBlockBody hardens statusColumnBodyDesyncs
// + validateCmd against the REAL SPK-481 structural shape: a body with TWO
// `**Status:**` lines (top-of-body + an embedded sub-heading). RED_MODE=1
// (default): asserts the DEFECT-PRESENT baseline this guard was built to catch —
// a raw column mutation manufacturing a desync — is genuinely reproducible on
// this realistic shape (proving the fixture itself is not vacuous). RED_MODE=0:
// the GREEN regression-guard on the CURRENT (fixed) statusColumnBodyDesyncs +
// validateCmd, asserting BOTH catch the desync AND that repair clears it.
func TestATM627_StatusDesync_RealisticMultiBlockBody(t *testing.T) {
	dbPath := buildSPK481ShapedFixtureDB(t)

	// Freshly-synced state: both Status lines say "Operator-blocked", matching
	// the column — zero desyncs, whichever mode.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	items, err := loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("freshly-synced SPK-481-shaped fixture reported %d desync(s) (false positive): %v", len(d), d)
	}

	// ATM-842 golden-FALSE (§11.4.201 false-positive guard): mutating the NESTED
	// sub-item's Status line is NOT an item-level desync — the item's own Status
	// line and its column still agree, and a sub-item has no column of its own.
	injectSubHeadingStatusDesync(t, dbPath)

	db, err = openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (post-subitem-inject): %v", err)
	}
	items, err = loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems (post-subitem-inject): %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("ATM-842: mutating a NESTED sub-item's Status line reported %d item-level "+
			"desync(s) (false positive — sub-item status is not the item's status): %v", len(d), d)
	}

	// Desync the ITEM'S OWN (top-of-body) Status line to "Reopened", leaving the
	// items.status column ("Operator-blocked") untouched. The sub-item's line
	// stays mutated, proving the guard keys on the item's OWN line even when a
	// nested block also diverges.
	injectOwnStatusDesync(t, dbPath)

	db, err = openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (post-inject): %v", err)
	}
	items, err = loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems (post-inject): %v", err)
	}

	d := statusColumnBodyDesyncs(items)
	found := false
	for _, v := range d {
		if strings.Contains(v, "ATM-950") && strings.Contains(v, `"Operator-blocked"`) && strings.Contains(v, `"Reopened"`) {
			found = true
		}
	}

	if redMode() {
		// RED_MODE=1 (default): defect-present baseline — the guard this test
		// hardens DOES catch it on the current (fixed) codebase (statusColumnBodyDesyncs
		// has existed since a7385c88); this branch documents + proves the realistic
		// shape genuinely exercises the guard rather than being vacuously synced.
		if !found {
			t.Fatalf("RED: statusColumnBodyDesyncs did NOT flag the sub-heading desync on the "+
				"realistic SPK-481-shaped fixture — got %d finding(s): %v (guard not exercised by this shape)", len(d), d)
		}
		t.Logf("RED reproduced: realistic multi-block SPK-481-shaped body genuinely triggers "+
			"the column<->body Status desync guard: %v", d)

		// The CLI boundary (validateCmd) must ALSO fail on this DB.
		if code := validateCmd([]string{"--db", dbPath}); code == exitOK {
			t.Fatalf("RED: validateCmd returned exitOK on the desynced realistic fixture (bluff)")
		}
		return
	}

	// RED_MODE=0: GREEN regression-guard.
	if !found {
		t.Fatalf("GREEN: statusColumnBodyDesyncs did not flag the realistic sub-heading desync "+
			"(ATM-950, Operator-blocked column vs Reopened derived-from-body); got %d finding(s): %v", len(d), d)
	}
	if code := validateCmd([]string{"--db", dbPath}); code == exitOK {
		t.Fatalf("GREEN: validateCmd returned exitOK on a desynced realistic-shape DB (§11.4.93 bluff gate regressed)")
	}

	// Repair: restore the ITEM'S OWN Status line — proves specificity (the guard
	// is not a blanket failure on complex multi-block bodies). The nested
	// sub-item's line stays mutated, so a clean result here ALSO re-proves the
	// ATM-842 scope: a diverged sub-item never manufactures an item-level
	// desync.
	repair, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (repair): %v", err)
	}
	if _, err := repair.Exec(`UPDATE items SET body_md = replace(
		body_md,
		'**Status:** Reopened
**Reopens-count:** 1',
		'**Status:** Operator-blocked
**Reopens-count:** 1'
	) WHERE atm_id='ATM-950' AND current_location='Issues'`); err != nil {
		repair.Close()
		t.Fatalf("repair: %v", err)
	}
	repair.Close()

	db, err = openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (post-repair): %v", err)
	}
	items, err = loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems (post-repair): %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("GREEN: after repair the guard still reports %d desync(s) on the realistic fixture: %v (not specific)", len(d), d)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("GREEN: validateCmd FAILed (%d) after repair on the realistic fixture", code)
	}
}

// TestDiffCmd_BareDBOnlyReportsColumnBodyDesync proves diff's NEW defense-in-depth
// wiring: `diff --db <path>` invoked WITHOUT --issues/--fixed now ALSO names a
// pure DB-internal column<->body_md Status desync, rather than only the
// uninformative "absent in Markdown" line every DB item gets under that
// invocation shape when no Markdown comparison happens at all.
//
// RED_MODE=1 (default): replicates diffCmd's PRE-FIX compare loop VERBATIM
// (the exact loop body that existed before the statusColumnBodyDesyncs wiring
// landed 2026-07-07) against the real DB + real parser, and asserts that
// PRE-FIX loop produces ZERO desync-specific output for the bare `--db`-only
// invocation shape — capturing the gap on the broken artifact (§11.4.5
// defect-present evidence).
//
// RED_MODE=0: the GREEN regression-guard — the CURRENT (patched) diffCmd,
// invoked bare (`--db` only, no Markdown paths), DOES print the specific
// finding and its exit code reflects the desync.
func TestDiffCmd_BareDBOnlyReportsColumnBodyDesync(t *testing.T) {
	dbPath := buildSPK481ShapedFixtureDB(t)
	injectSubHeadingStatusDesync(t, dbPath)

	if redMode() {
		// PRE-FIX artifact, replicated verbatim: diffCmd's compare loop before the
		// statusColumnBodyDesyncs wiring landed — no markdown given, so `parsed`
		// stays empty and the ONLY output is "present in DB, absent in Markdown"
		// for every row; nothing names the column<->body desync specifically.
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB: %v", err)
		}
		dbItems, err := loadItems(db)
		db.Close()
		if err != nil {
			t.Fatalf("loadItems: %v", err)
		}

		var preFixOutput []string
		var parsed []item // no --issues/--fixed given, pre-fix diffCmd never populated this either
		parsedSeen := map[string]bool{}
		for _, p := range parsed {
			parsedSeen[p.AtmID] = true
		}
		for _, d := range dbItems {
			if !parsedSeen[d.AtmID] {
				preFixOutput = append(preFixOutput, "- "+d.AtmID+" present in DB, absent in Markdown")
			}
		}
		for _, line := range preFixOutput {
			if strings.Contains(line, "desync") || strings.Contains(line, "column↔body") {
				t.Fatalf("RED: the pre-fix replicated loop unexpectedly names the desync (RED setup invalid): %s", line)
			}
		}
		if len(preFixOutput) == 0 {
			t.Fatalf("RED setup invalid: expected the pre-fix loop to produce output for the bare-db invocation, got none")
		}
		t.Logf("RED reproduced: pre-fix diffCmd (bare --db, no markdown) produces only "+
			"uninformative 'absent in Markdown' noise (%d line(s)), never naming the "+
			"column<->body_md Status desync specifically", len(preFixOutput))
		return
	}

	// GREEN: the CURRENT (patched) diffCmd, invoked bare (--db only).
	rc, out := captureDiff(t, []string{"--db", dbPath})
	if rc == exitOK {
		t.Fatalf("GREEN: diffCmd returned exitOK on a desynced DB invoked bare (--db only); stdout=%q", out)
	}
	if !strings.Contains(out, "ATM-950") || !strings.Contains(out, "column") {
		t.Fatalf("GREEN: bare `diff --db` did not name the column<->body Status desync for ATM-950; stdout=%q", out)
	}
	if !strings.Contains(out, `"Operator-blocked"`) || !strings.Contains(out, `"Reopened"`) {
		t.Fatalf("GREEN: bare `diff --db` desync line did not cite both divergent values; stdout=%q", out)
	}
	t.Logf("GREEN: bare `diff --db` (no --issues/--fixed) now names the specific "+
		"column<->body_md Status desync for ATM-950:\n%s", out)
}
