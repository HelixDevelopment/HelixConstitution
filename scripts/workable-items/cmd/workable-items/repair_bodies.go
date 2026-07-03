// repair_bodies.go — the `repair-bodies` subcommand (ATM-627 / task #20).
//
// §11.4.93 / §11.4.95: items.status is the authoritative single source of truth;
// body_md is a derived surface that `sync db-to-md` (renderDocument) replays into
// the trackers. Two classes of body_md drift accumulate when a direct
// `UPDATE items SET status=…` bypasses renderItemBody:
//
//   - STALE-LINE (38 items on the live tree): a NON-empty section body whose LAST
//     `**Status:**` line disagrees with the column. renderDocument's
//     canonicalizeBodyStatusLine already emits the column-consistent line on the
//     fly, but the STORED body_md stays stale, so `validate`'s column↔body guard
//     (statusColumnBodyDesyncs) keeps flagging it. repair-bodies persists the
//     canonicalized line INTO storage — a surgical single-line rewrite that
//     preserves every other line (prose + `**Reopened-Details:**` /
//     `**Operator-Block-Details:**` blocks) verbatim.
//
//   - EMPTY-BODY (72 items on the live tree; 26 non-Queued desyncs + 46 Queued
//     that are not desyncs but still vanish from a db→md regen): a section item
//     whose body_md is empty/NULL. canonicalizeBodyStatusLine is a no-op on it
//     (no line to rewrite), so repair-bodies POPULATES it via renderItemBody —
//     the SAME renderer the `add` path uses — emitting the `**Status:**` /
//     `**Type:**` / `**Severity:**` / `**Created-By:**` / `**Assigned-To:**`
//     block + the description from the authoritative columns.
//
// After repair-bodies, `validate` reports 0 column↔body desyncs. The operation is
// IDEMPOTENT: a second run classifies every item as noop (a populated body already
// derives its column; a rewritten line already equals its column) and issues NO
// UPDATE — the DB is byte-identical.
//
// HARD CONSTRAINT (§11.4.95 / §9.2): the conductor runs this against the live
// docs/workable_items.db inside the §9.2-backed sync pipeline
// (scripts/testing/workable_items_sync_all.sh). This binary only ever writes the
// --db it is given; the test-suite drives it exclusively against /tmp copies.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// repairAction classifies what repair-bodies will do to one item's body_md.
type repairAction string

const (
	repairNoop     repairAction = "noop"
	repairRewrite  repairAction = "rewrite"
	repairPopulate repairAction = "populate"
)

// classifyRepair decides the repair action + the new body_md for one item. It is
// the generator-symmetric mirror of the column↔body invariant enforced by
// statusColumnBodyDesyncs (sync.go) + renderDocument's canonicalizeBodyStatusLine
// (db.go / parse.go) — repair-bodies persists into storage exactly what those two
// derive on the fly, so a repaired DB round-trips byte-identically.
//
//   - A NON-'section' representation ('table' pipe-table row) is ALWAYS noop: its
//     Status lives in the pipe cell, NOT a `**Status:**` line, and its verbatim
//     row must be preserved (populating it would destroy the pipe row). No 'table'
//     rows exist on the live tree today (all 415 items are 'section'), but the
//     guard keeps repair-bodies correct if one is ever added — it mirrors
//     statusColumnBodyDesyncs's own `repOrDefault() != "section"` skip.
//   - An EMPTY/whitespace-only section body is POPULATED via renderItemBody from
//     the authoritative columns (the SPK/ATM empty-body class).
//   - A NON-empty section body has its LAST `**Status:**` line canonicalized to
//     the column via canonicalizeBodyStatusLine — a STRICT byte-identical no-op
//     when already synced (or when the body carries no `**Status:**` line at all),
//     a surgical single-line rewrite when stale.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return repairNoop, it.BodyMD` disables the repair; TestRepairBodies_
// ClearsDesyncs_RedPolarity + …_Idempotent then FAIL (post-repair validate still
// reports desyncs) — proving the repair is not a tautology.
func classifyRepair(it item) (repairAction, string) {
	if it.repOrDefault() != "section" {
		return repairNoop, it.BodyMD
	}
	if strings.TrimSpace(it.BodyMD) == "" {
		body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity,
			it.Description, it.Status, it.CreatedBy, it.AssignedTo)
		return repairPopulate, body
	}
	newBody := canonicalizeBodyStatusLine(it.BodyMD, it.Status)
	if newBody == it.BodyMD {
		return repairNoop, it.BodyMD
	}
	return repairRewrite, newBody
}

func runRepairBodies(args []string) {
	os.Exit(repairBodiesCmd(args))
}

// repairBodiesCmd implements `repair-bodies [--dry-run] [--db PATH]`.
func repairBodiesCmd(args []string) int {
	fs := flag.NewFlagSet("repair-bodies", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	dryRun := fs.Bool("dry-run", false, "print per-item summary + totals, write nothing")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "repair-bodies: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: %v\n", err)
		return exitUsage
	}

	type plan struct {
		it      item
		action  repairAction
		newBody string
	}
	var toApply []plan
	var nRewrite, nPopulate, nNoop int
	for _, it := range items {
		action, newBody := classifyRepair(it)
		switch action {
		case repairRewrite:
			nRewrite++
		case repairPopulate:
			nPopulate++
		default:
			nNoop++
			continue
		}
		toApply = append(toApply, plan{it: it, action: action, newBody: newBody})
		if *dryRun {
			detail := fmt.Sprintf("empty body -> render **Status:** %s", it.Status)
			if action == repairRewrite {
				old, _ := lastBodyStatus(it.BodyMD)
				detail = fmt.Sprintf("stale **Status:** %q -> column %q", old, it.Status)
			}
			fmt.Printf("  %s [%s/%s]: %s (%s)\n",
				it.AtmID, it.CurrentLocation, it.repOrDefault(), action, detail)
		}
	}

	if *dryRun {
		fmt.Printf("repair-bodies (dry-run): scanned %d items — %d rewrite, %d populate, %d noop (nothing written)\n",
			len(items), nRewrite, nPopulate, nNoop)
		return exitOK
	}

	if len(toApply) == 0 {
		fmt.Printf("repair-bodies: scanned %d items — already canonical (0 rewrite, 0 populate); no changes\n", len(items))
		return exitOK
	}

	// Single transaction (WAL journal per schema_embed.sql): every body_md write
	// commits atomically or not at all.
	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`UPDATE items SET body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: prepare: %v\n", err)
		return exitUsage
	}
	defer stmt.Close()

	for _, p := range toApply {
		res, err := stmt.Exec(p.newBody, p.it.AtmID, p.it.CurrentLocation, p.it.repOrDefault())
		if err != nil {
			fmt.Fprintf(os.Stderr, "repair-bodies: update %s: %v\n", p.it.AtmID, err)
			return exitUsage
		}
		if n, _ := res.RowsAffected(); n != 1 {
			fmt.Fprintf(os.Stderr, "repair-bodies: update %s [%s/%s] affected %d rows (expected 1)\n",
				p.it.AtmID, p.it.CurrentLocation, p.it.repOrDefault(), n)
			return exitUsage
		}
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("repair-bodies: scanned %d items — applied %d change(s): %d rewrite, %d populate, %d noop\n",
		len(items), len(toApply), nRewrite, nPopulate, nNoop)
	return exitOK
}
