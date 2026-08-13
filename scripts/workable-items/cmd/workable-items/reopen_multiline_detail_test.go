// reopen_multiline_detail_test.go — §11.4.115 RED-polarity regression guard for the
// F1 attribution-hygiene defect in upsertMetaLine (mutate.go).
//
// FORENSIC ANCHOR (FACT, measured 2026-07-20 on a read-only copy of the live DB):
// three real Fixed items — ATM-393, ATM-398, ATM-448 — carry their prior §11.4.34
// attribution as a MULTI-LINE bulleted block:
//
//	**Reopened-Details:**
//	- **By:** AI
//	- **On:** 2026-05-17
//	- **Reason:** …
//	- **Evidence:** …
//
// The `- **By:/On:/Reason:/Evidence:**` bullets do NOT start with the
// `**Reopened-Details:**` header key, so the pre-fix upsertMetaLine replaced ONLY
// the header line and left the four bullets ORPHANED — a contradictory DUAL
// attribution (the new inline `By: … On: 2026-07-…` above the stale
// `- **By:** AI - **On:** 2026-05-17` bullets). That is exactly the §11.4.6
// ambiguity the upsertMetaLine doc-comment CLAIMS to prevent. Not data-loss (the
// opposite of the bug the engine fixes) — the harm is attribution-hygiene on
// re-reopen. §11.4.194 gap: the fix assumed a prior detail is a single line (the
// shape the NEW code emits); these three live items violate that assumption.
//
// §11.4.115 polarity: each assertion states the CORRECT post-fix behaviour, so it
// FAILS on the pre-fix code (the orphaned PRIOR-* bullets survive) and PASSES on the
// fixed code (a single canonical inline attribution survives). The bug-catcher IS the
// regression-guard. Drives the REAL reopenCmd against a REAL on-disk SQLite DB
// (no mock, §11.4.27).
//
// §1.1 PAIRED MUTATION (documented): revert upsertMetaLine's contiguous-bullet-run
// consumption (mutate.go) → TestReopenCmd_MultilinePriorDetail_CollapsesToOne FAILs
// (PRIOR-* bullets orphaned); restore → GREEN. Proves the fix + guard are not
// tautologies.
//
// §11.4.201(7)(a) carrier-vs-thing NEGATIVE CONTROL: an unrelated `- **By:** …`
// bullet placed ELSEWHERE in the authored body (not the contiguous run immediately
// after the header) MUST survive — the fix consumes only the attribution run
// immediately following the header, never a body-content bullet that merely looks
// like one. This is the false-positive guard (§11.4.107(10)).
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches docs/workable_items.db.
package main

import (
	"strings"
	"testing"
)

// distinctive markers so "old attribution gone" vs "carrier survives" are unambiguous.
const (
	priorBy       = "PRIOR-AI-ATTRIBUTION"
	priorOn       = "2026-05-17-PRIOR"
	priorReason   = "PRIOR-REASON-captured-evidence-contradicts"
	priorEvidence = "docs/evidence/WIT-PRIOR.md"
	carrierMarker = "UNRELATED-CARRIER-BULLET-MUST-SURVIVE"
	authoredMark  = "authored forensic line that exists in NO column and MUST survive"
)

// seedFixedItemWithMultilineReopen seeds a Fixed item via the REAL add + close paths,
// then injects a body carrying a real ATM-393/398/448-shape MULTI-LINE
// `**Reopened-Details:**` bulleted block (a prior reopen's attribution) plus an
// authored section that itself contains a carrier `- **By:**` bullet elsewhere.
func seedFixedItemWithMultilineReopen(t *testing.T, dbPath, id string) {
	t.Helper()
	seedFixedItem(t, dbPath, id)

	var b strings.Builder
	b.WriteString("## P. [" + id + "] a closed item that will be reopened later\n\n")
	b.WriteString("**Status:** Fixed (→ Fixed.md)\n")
	b.WriteString("**Type:** Bug\n")
	// The prior MULTI-LINE §11.4.34 attribution block (the ATM-393 shape). Header
	// directly followed by four contiguous attribution bullets (no blank line),
	// exactly as the live items carry it.
	b.WriteString("**Reopened-Details:**\n")
	b.WriteString("- **By:** " + priorBy + "\n")
	b.WriteString("- **On:** " + priorOn + "\n")
	b.WriteString("- **Reason:** " + priorReason + " (a prior multi-line reason authored on ONE physical line that exists in NO column)\n")
	b.WriteString("- **Evidence:** " + priorEvidence + " — the prior multi-line attribution a real md→db sync produced.\n")
	b.WriteString("\n### Authored freeform section (must survive reopen)\n\n")
	// A carrier bullet ELSEWHERE — not the contiguous run after the header — that must
	// survive (§11.4.201(7)(a)). Separated from the attribution block by a blank line
	// + a heading + a blank line, so it is never part of the consumed run.
	b.WriteString("- **By:** " + carrierMarker + "\n\n")
	for i := 0; i < 40; i++ {
		b.WriteString("* **Authored:** " + authoredMark + " — gate invariants, paired mutations, cross-references.\n")
	}
	b.WriteString("\n")
	rich := b.String()

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(`UPDATE items SET body_md=? WHERE atm_id=? AND current_location='Fixed'`, rich, id); err != nil {
		t.Fatalf("seed multi-line reopen body: %v", err)
	}
}

// reopenAndLoad runs the real reopenCmd with full §11.4.34 attribution and returns the
// resulting Issues-side body.
func reopenAndLoad(t *testing.T, dbPath, id, who, when, why, incident string) string {
	t.Helper()
	if code := reopenCmd([]string{"--db", dbPath, "--id", id,
		"--why", why, "--who", who, "--when", when, "--incident", incident}); code != exitOK {
		t.Fatalf("reopenCmd(%s): exit %d", id, code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, id, "Issues")
	if err != nil || it == nil {
		t.Fatalf("loadItem(%s, Issues) after reopen: %v", id, err)
	}
	return it.BodyMD
}

// TestReopenCmd_MultilinePriorDetail_CollapsesToOne is the KEYSTONE guard: reopening
// an item whose prior attribution is a MULTI-LINE bulleted block MUST leave a SINGLE
// canonical inline attribution — the stale attribution bullets MUST be gone, and no
// contradictory dual attribution may remain.
func TestReopenCmd_MultilinePriorDetail_CollapsesToOne(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItemWithMultilineReopen(t, dbPath, "WIT-410")
	got := reopenAndLoad(t, dbPath, "WIT-410", "AI", "2026-07-20",
		"captured-evidence-contradicts", "docs/evidence/WIT-410.md")

	// (1) exactly ONE **Reopened-Details:** header/line remains.
	if n := strings.Count(got, "**Reopened-Details:**"); n != 1 {
		t.Fatalf("**Reopened-Details:** appears %d times, want exactly 1 (single canonical attribution)", n)
	}

	// (2) the NEW canonical inline attribution is present.
	const wantDetail = "**Reopened-Details:** By: AI On: 2026-07-20 Reason: captured-evidence-contradicts Evidence: docs/evidence/WIT-410.md"
	if !strings.Contains(got, wantDetail) {
		t.Fatalf("new canonical inline attribution absent; want %q\n--- got ---\n%s", wantDetail, got)
	}

	// (3) the stale MULTI-LINE attribution bullets are GONE — this is the F1 defect.
	// On the pre-fix code all four survive as orphaned dual attribution.
	for _, stale := range []string{priorBy, priorOn, priorReason, priorEvidence} {
		if strings.Contains(got, stale) {
			t.Errorf("orphaned prior attribution bullet survived reopen (F1 dual-attribution defect): %q still present\n--- got ---\n%s", stale, got)
		}
	}

	// (4) NEGATIVE CONTROL (§11.4.201(7)(a)): a carrier `- **By:**` bullet ELSEWHERE
	// in the authored body MUST survive — the fix must not over-consume.
	if !strings.Contains(got, carrierMarker) {
		t.Errorf("carrier bullet elsewhere in the body was wrongly consumed (over-consumption): %q missing\n--- got ---\n%s", carrierMarker, got)
	}

	// (5) authored freeform content survives byte-for-byte (no truncation).
	if c := strings.Count(got, authoredMark); c != 40 {
		t.Errorf("authored freeform lines survived = %d, want 40 (no truncation)", c)
	}

	// (6) status line canonicalized; no stale terminal status.
	if !strings.Contains(got, "**Status:** Reopened") {
		t.Error("body **Status:** line not canonicalized to Reopened")
	}
	if strings.Contains(got, "**Status:** Fixed (→ Fixed.md)") {
		t.Error("stale terminal **Status:** line survived the reopen (column↔body desync)")
	}
}

// TestReopenCmd_MultilinePriorDetail_HistoryKeepsBoth proves the append-only audit
// trail still records the reopen event even though the body keeps only one inline
// attribution — history is where reopen history belongs, not the heading-adjacent body.
func TestReopenCmd_MultilinePriorDetail_HistoryKeepsBoth(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItemWithMultilineReopen(t, dbPath, "WIT-411")
	_ = reopenAndLoad(t, dbPath, "WIT-411", "User", "2026-07-21",
		"manual-testing-detected", "docs/evidence/WIT-411.md")

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if n := historyCount(t, db, "WIT-411", "Reopened"); n != 1 {
		t.Errorf("item_history Reopened rows = %d, want 1 (this reopen recorded)", n)
	}
}
