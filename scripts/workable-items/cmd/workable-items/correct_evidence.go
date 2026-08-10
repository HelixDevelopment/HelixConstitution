// correct_evidence.go — the `correct-history-evidence` subcommand.
//
// # WHY THIS EXISTS
//
// §11.4.226 evidence-class-at-closure requires every closure's
// item_history.evidence_path to be a RESOLVABLE artefact path — never a
// narrative sentence, never a "was tested manually" free-text field. The
// HXC-217 validator (unresolvableClosureEvidence, sync.go) catches the
// divergence; the HXC-224 record-time guard (evidence.go) prevents a NEW
// closure from citing an unresolvable path.
//
// Historical rows written BEFORE HXC-224 landed can still carry the defect
// shape. Two real examples on the boba live DB (2026-08-10):
//
//   - BOB-009 history id=3 (Completed 2026-06-09) evidence_path =
//     "boba-ctl is now default for start/stop; --no-boba-ctl falls back to
//     raw compose" — narrative, no file
//   - BOB-010 history id=4 (Completed 2026-06-09) evidence_path =
//     "SQLite DB integrated with pre-build gate; 20 items tracked;
//     docs_chain validation wired" — narrative, no file
//
// The shipped artefacts backing both closures DO exist
// (scripts/boba-ctl.sh, scripts/docs_chain.sh, both landed by commit
// 0558399). Every other mutating subcommand refuses to touch item_history
// (per the append-only §11.4.34 audit contract), and raw SQL is forbidden by
// the §11.4.93 tool-only-mutation discipline. So the ONLY compliant way to
// swap the narrative for the real path is a dedicated correction subcommand
// that: (a) validates the new path through the SAME checkEvidencePath used
// by close, so it can never re-introduce the defect it exists to repair;
// (b) refuses on a non-terminal item (§11.4.226 scope) and on an
// out-of-scope history row (only closure events); (c) writes an audit row
// so the correction is queryable, never a silent overwrite.
//
// # NON-GOALS
//
// This subcommand is NOT a general history editor. It does not touch
// event_type, by, on_date, or reason on the historical row — those are the
// invariants §11.4.34 relies on. It only rewrites the evidence_path slot of
// one closure history row, and only when the new value passes the same guard
// a fresh closure would.
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"strings"
)

// closureEvents is the set of item_history.event_type values recognised as
// closure events per §11.4.33's Type-aware closure vocabulary. `Obsolete` is
// included because obsolete_details closures also record evidence_path via
// recordHistory (obsolete.go).
var closureEvents = map[string]bool{
	"Fixed":       true,
	"Implemented": true,
	"Completed":   true,
	"Obsolete":    true,
}

// runCorrectHistoryEvidence is the main.go dispatch stub.
func runCorrectHistoryEvidence(args []string) {
	os.Exit(correctHistoryEvidenceCmd(args))
}

// correctHistoryEvidenceCmd implements
// `correct-history-evidence --db <p> --atm-id <ID> --history-id <N>
//                           --evidence-path <path> [--reason <text>]`.
func correctHistoryEvidenceCmd(args []string) int {
	fs := flag.NewFlagSet("correct-history-evidence", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB (required)")
	atmID := fs.String("atm-id", "", "ticket id whose history row is being corrected (required)")
	historyID := fs.Int64("history-id", 0, "id of the item_history row (required; >0)")
	evidencePath := fs.String("evidence-path", "", "new evidence_path — must resolve to a real, non-empty file/dir (required)")
	reason := fs.String("reason", "", "why the original was wrong — recorded verbatim in the audit row")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "correct-history-evidence: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*atmID) == "" {
		fmt.Fprintln(os.Stderr, "correct-history-evidence: --atm-id is required")
		return exitUsage
	}
	if *historyID <= 0 {
		fmt.Fprintln(os.Stderr, "correct-history-evidence: --history-id is required and must be > 0")
		return exitUsage
	}
	if strings.TrimSpace(*evidencePath) == "" {
		fmt.Fprintln(os.Stderr, "correct-history-evidence: --evidence-path is required")
		return exitUsage
	}
	// Validate the NEW path with the SAME guard close/obsolete-details use.
	// This is load-bearing: without it the tool could swap one unresolvable
	// value for another and the very defect it exists to fix would recur.
	if !requireEvidencePath("correct-history-evidence", *evidencePath) {
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// §11.4.226 scope guard: correction applies to CLOSED items. The item
	// may live at Issues (defense in depth against a Reopened cycle that
	// relocated a still-Fixed row — should not happen but do not silently
	// admit it) or Fixed. loadItem checks one location at a time, so probe
	// both.
	cur, err := loadItem(db, *atmID, "Fixed")
	if err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		cur, err = loadItem(db, *atmID, "Issues")
		if err != nil {
			fmt.Fprintf(os.Stderr, "correct-history-evidence: %v\n", err)
			return exitUsage
		}
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: item %s not found in Issues or Fixed\n", *atmID)
		return exitUsage
	}
	terminal := terminalStatuses()
	if !terminal[strings.TrimSpace(cur.Status)] {
		fmt.Fprintf(os.Stderr,
			"correct-history-evidence: refusing — item %s carries NON-terminal status %q (§11.4.226 evidence-class-at-closure scopes this correction to CLOSED items; a non-closed item's audit trail is out of scope)\n",
			*atmID, cur.Status)
		return exitUsage
	}

	// Look up the target history row: enforce (id, atm_id) match so a mis-typed
	// --history-id cannot silently rewrite a row belonging to another item.
	var evt, oldEv string
	row := db.QueryRow(
		`SELECT event_type, COALESCE(evidence_path,'') FROM item_history WHERE id=? AND atm_id=?`,
		*historyID, *atmID,
	)
	if err := row.Scan(&evt, &oldEv); err != nil {
		if err == sql.ErrNoRows {
			fmt.Fprintf(os.Stderr,
				"correct-history-evidence: no item_history row id=%d for %s\n",
				*historyID, *atmID)
			return exitUsage
		}
		fmt.Fprintf(os.Stderr, "correct-history-evidence: query history row: %v\n", err)
		return exitUsage
	}
	if !closureEvents[evt] {
		fmt.Fprintf(os.Stderr,
			"correct-history-evidence: refusing — history row id=%d has event_type %q (§11.4.226 scopes correction to closure events: Fixed|Implemented|Completed|Obsolete; a %s row's evidence is not this tool's concern)\n",
			*historyID, evt, evt)
		return exitUsage
	}

	// Compose the audit-row reason. `Updated` is the only closed-set event_type
	// available (the schema CHECK forbids inventing `EvidenceCorrected`), so the
	// distinguishing information rides in `reason` where a query can find it:
	// the marker "evidence-corrected", the corrected row's id + event, a short
	// snippet of the OLD value (so a query can grep it), and the operator's
	// --reason text.
	oldSnippet := firstLine(oldEv)
	if len(oldSnippet) > 80 {
		oldSnippet = oldSnippet[:80] + "…"
	}
	auditReason := fmt.Sprintf(
		"evidence-corrected history_id=%d event=%s old=%q",
		*historyID, evt, oldSnippet,
	)
	if r := strings.TrimSpace(*reason); r != "" {
		auditReason += " reason=" + r
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`UPDATE item_history SET evidence_path=? WHERE id=? AND atm_id=?`,
		*evidencePath, *historyID, *atmID,
	); err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: update history row: %v\n", err)
		return exitUsage
	}
	// Append the audit row. `Updated` + `AI` + on_date=today (recordHistory's
	// default), reason=auditReason, evidence_path=the corrected value — every
	// slot a query on "did this correction happen" needs.
	if err := recordHistory(tx, *atmID, "Updated", "AI", auditReason, strings.TrimSpace(*evidencePath)); err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: audit history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "correct-history-evidence: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("correct-history-evidence: %s history id=%d (%s) evidence_path set to %s (audit row appended)\n",
		*atmID, *historyID, evt, *evidencePath)
	return exitOK
}
