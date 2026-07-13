// sync.go — the functional subcommands: md-to-db, db-to-md, validate, diff.
//
// §11.4.93 bidirectional sync between the Markdown trackers and the SQLite
// single-source-of-truth, plus closed-set validation (§11.4.15/16/91).
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

// syncMDToDB parses Issues.md + Fixed.md and upserts the DB.
func syncMDToDB(args []string) int {
	fs := flag.NewFlagSet("sync md-to-db", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync md-to-db: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	total := 0
	if *issuesPath != "" {
		content, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read issues: %v\n", err)
			return exitUsage
		}
		items, segs := parseIssues(string(content))
		if err := replaceDocument(db, "Issues", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist issues: %v\n", err)
			return exitUsage
		}
		fmt.Printf("Issues.md: %d items, %d segments\n", len(items), len(segs))
		total += len(items)
	}
	if *fixedPath != "" {
		content, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read fixed: %v\n", err)
			return exitUsage
		}
		items, segs := parseFixed(string(content))
		if err := replaceDocument(db, "Fixed", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("Fixed.md: %d items, %d segments\n", len(items), len(segs))
		total += len(items)
	}
	if *issuesPath == "" && *fixedPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: at least one of --issues / --fixed is required")
		return exitUsage
	}
	fmt.Printf("synced %d total items into %s\n", total, *dbPath)
	return exitOK
}

// syncDBToMD regenerates Issues.md + Fixed.md from the DB segments.
func syncDBToMD(args []string) int {
	fs := flag.NewFlagSet("sync db-to-md", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	outIssues := fs.String("out-issues", "", "output path for regenerated Issues.md")
	outFixed := fs.String("out-fixed", "", "output path for regenerated Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync db-to-md: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	if *outIssues != "" {
		text, err := renderDocument(db, "Issues")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render issues: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outIssues, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write issues: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outIssues, len(text))
	}
	if *outFixed != "" {
		text, err := renderDocument(db, "Fixed")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render fixed: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outFixed, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outFixed, len(text))
	}
	if *outIssues == "" && *outFixed == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: at least one of --out-issues / --out-fixed is required")
		return exitUsage
	}
	return exitOK
}

// validateCmd asserts the §11.4 closed-set + clarity invariants over the DB.
func validateCmd(args []string) int {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "validate: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}

	statusSet := map[string]bool{}
	for _, s := range closedStatuses {
		statusSet[s] = true
	}
	typeSet := map[string]bool{"Bug": true, "Feature": true, "Task": true}

	var violations []string
	seen := map[string]bool{}
	for _, it := range items {
		// §11.4.54 — duplicate (atm_id, location, representation). The composite
		// PRIMARY KEY makes this impossible at the storage layer (the same id MAY
		// appear once per tracker, AND once per representation within a tracker —
		// a pipe-table 'table' row + an H2 'section' block, GAP A / HXC-044), but
		// we assert it explicitly for clarity. The key MUST include representation
		// so the legitimate dual-representation case is not a false duplicate.
		key := it.AtmID + "\x00" + it.CurrentLocation + "\x00" + it.repOrDefault()
		if seen[key] {
			violations = append(violations, fmt.Sprintf("duplicate atm_id in %s [%s]: %s",
				it.CurrentLocation, it.repOrDefault(), it.AtmID))
		}
		seen[key] = true

		// §11.4.15/21/90 — status closed-set.
		if !statusSet[it.Status] {
			violations = append(violations, fmt.Sprintf("%s: status %q not in closed-set", it.AtmID, it.Status))
		}
		// §11.4.16 — type closed-set.
		if !typeSet[it.Type] {
			violations = append(violations, fmt.Sprintf("%s: type %q not in {Bug,Feature,Task}", it.AtmID, it.Type))
		}
		// §11.4.91 — description ≥6 words OR ≥40 chars.
		if wordCount(it.Description) < 6 && len(it.Description) < 40 {
			violations = append(violations, fmt.Sprintf("%s: description too short (%d words / %d chars): %q",
				it.AtmID, wordCount(it.Description), len(it.Description), it.Description))
		}
		// §11.4.148 D3 — every Operator-blocked item MUST carry an
		// operator_block_details row whose unblock_condition enumerates the
		// closed list of decisions/actions that would unblock it ([A]…·[B]…).
		// A missing details row OR a bare-prose unblock condition (no enumerated
		// CHOICES) is a §11.4.148 D3 PASS-bluff.
		if it.Status == "Operator-blocked" {
			var unblock sql.NullString
			err := db.QueryRow(`SELECT unblock_condition FROM operator_block_details WHERE atm_id=?`,
				it.AtmID).Scan(&unblock)
			switch {
			case err == sql.ErrNoRows:
				violations = append(violations, fmt.Sprintf(
					"%s: Operator-blocked with no operator_block_details row (§11.4.148 D3)", it.AtmID))
			case err != nil:
				violations = append(violations, fmt.Sprintf(
					"%s: operator_block_details query: %v", it.AtmID, err))
			case !hasEnumeratedUnblockChoices(unblock.String):
				violations = append(violations, fmt.Sprintf(
					"%s: Operator-blocked unblock_condition has no enumerated unblock CHOICES (§11.4.148 D3): %q",
					it.AtmID, unblock.String))
			}
		}
	}

	// §11.4.93 renderability + §11.4.111 current_location closed-set (ATM-627).
	// The DB is the single source of truth (§11.4.95); a DB that `db-to-md`
	// cannot render is NOT a faithful source — regen is silently blocked. The
	// prior validate checked status/type/description only and returned exit 0
	// on such a DB (a §11.4.6/§11.4.93 bluff gate: green while regen impossible).
	// These two checks fail-closed on exactly that corruption class.

	// (a) current_location closed-set {Issues, Fixed}. A stray value such as the
	// half-migration artifact "Fixed.md" orphans the item: renderDocument scopes
	// its body lookup to current_location=document, so a "Fixed.md" item is
	// invisible to BOTH the Issues and the Fixed render (§11.4.19 atomic-migration
	// invariant broken).
	for _, it := range items {
		switch it.CurrentLocation {
		case "Issues", "Fixed":
			// ok
		default:
			violations = append(violations, fmt.Sprintf(
				"%s: current_location %q not in closed-set {Issues,Fixed} (§11.4.93/§11.4.111) [%s]",
				it.AtmID, it.CurrentLocation, it.repOrDefault()))
		}
	}

	// (b) renderability guard: every doc_segment item-reference MUST resolve to
	// an item at (current_location=document, representation). renderDocument
	// returns a hard error on the first dangling segment; surfacing it here as a
	// validation violation turns the silent regen-blocker into a caught, actionable
	// failure (§11.4.120 — the gate asserts the real "DB is renderable" invariant).
	for _, document := range []string{"Issues", "Fixed"} {
		if _, err := renderDocument(db, document); err != nil {
			violations = append(violations, fmt.Sprintf(
				"%s: DB not renderable by db-to-md (§11.4.93): %v", document, err))
		}
	}

	// (c) §11.4.135 DIRECT dangling-doc_segment integrity guard (ATM-627 defect
	// class). renderDocument (b) catches this INDIRECTLY — it aborts on the FIRST
	// unresolvable segment per document. danglingItemSegments asserts the same
	// invariant DIRECTLY via an explicit segment↔item join, so EVERY offending
	// segment is enumerated (not just the first-in-seq per document) and the
	// finding is a self-documenting integrity violation rather than a "not
	// renderable" side-effect. Composes with (b); does not replace it.
	if dangling, derr := danglingItemSegments(db); derr != nil {
		violations = append(violations, fmt.Sprintf("dangling-segment integrity query: %v", derr))
	} else {
		violations = append(violations, dangling...)
	}

	// (d) §11.4.93 / ATM-627 — REVERSE dangling-segment guard: item exists with NO
	// doc_segments row for its (atm_id, current_location, representation). (c) above
	// catches segment->no-item; renderDocument silently DROPS this class instead of
	// erroring (it only iterates existing doc_segments rows, so an item lacking one
	// is invisible to db-to-md with NO error surfaced) — the exact "db-to-md drops
	// segmentless items" defect ATM-627 reports. Without this guard, validate
	// reported OK on a DB that would silently regenerate Issues.md/Fixed.md missing
	// every segmentless item (a §11.4.6/§11.4.93 bluff gate).
	if missing, merr := itemsMissingSegments(db); merr != nil {
		violations = append(violations, fmt.Sprintf("missing-segment integrity query: %v", merr))
	} else {
		violations = append(violations, missing...)
	}

	// (e) §11.4.93 / ATM-627 (task #20) — column↔body Status desync guard. items.status
	// is authoritative (§11.4.95); when a direct `UPDATE items SET status=…` bypasses
	// renderItemBody it advances the column while body_md's `**Status:**` line stays
	// stale → `sync db-to-md` (renderDocument) would emit the stale line, misreporting
	// the item to every reader. The prior validate checked the status CLOSED-SET only,
	// never column↔body agreement, so a desynced item passed exit 0 (a §11.4.6/§11.4.93
	// bluff gate). This guard fails-closed on exactly that class; the generator-symmetry
	// half (canonicalizeBodyStatusLine, wired into renderDocument, parse.go) prevents
	// recurrence by emitting the Status line from the column. Composes with (b)/(c) —
	// orthogonal invariants (those: segment↔item location; this: column↔body Status).
	violations = append(violations, statusColumnBodyDesyncs(items)...)

	// (f) §11.4.15 / §11.4.148 / ATM-627 INTEG-03 — location↔status invariant. A
	// Fixed-location item MUST carry a terminal closed-set status (a `… (→ Fixed.md)`
	// value); a NON-terminal status at Fixed (e.g. Reopened) is the exact INTEG-03
	// desync — the pre-fix `reopen` flipped status→Reopened WITHOUT migrating
	// current_location Fixed→Issues, stranding a non-terminal item in the CLOSED
	// archive. The prior validate never asserted location↔status, so such an item
	// passed exit 0 while every tracker reader saw a non-terminal item in Fixed (a
	// §11.4.6/§11.4.15 bluff gate). This guard fails-closed on exactly that class;
	// composes with (e) — orthogonal invariants (that: column↔body Status agreement;
	// this: current_location↔status closed-set agreement).
	violations = append(violations, fixedLocationNonTerminalStatus(items)...)

	if len(violations) > 0 {
		sort.Strings(violations)
		fmt.Fprintf(os.Stderr, "validate: %d violation(s):\n", len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		return exitUsage
	}
	fmt.Printf("validate: OK — %d items, all invariants satisfied\n", len(items))
	return exitOK
}

// danglingItemSegments returns, for the ATM-627 dangling-doc_segment defect
// CLASS, a human-readable description of every doc_segments row with kind='item'
// whose (atm_id, document, representation) has NO matching item at
// (atm_id, current_location=document, representation) — i.e. the invariant
// "item.current_location must equal the document of every doc_segment that
// belongs to that item" is violated.
//
// This is the DIRECT, first-class integrity assertion of the §11.4.135 guard,
// decoupled from renderDocument's control-flow side-effect. It is read-only, so
// it can never break an existing valid DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return nil, nil` removes the guard; atm627_integrity_guard_test.go then FAILs
// — proving the guard is not a tautology.
func danglingItemSegments(db *sql.DB) ([]string, error) {
	// A kind='item' segment is DANGLING when the LEFT JOIN to items on
	// (atm_id, current_location=document, representation) finds no partner. The
	// representation defaults to 'section' on both sides (COALESCE) to mirror
	// renderDocument's body-lookup key exactly.
	rows, err := db.Query(`
		SELECT s.document, s.seq, s.atm_id, COALESCE(s.representation,'section')
		FROM doc_segments s
		LEFT JOIN items i
		  ON i.atm_id = s.atm_id
		 AND i.current_location = s.document
		 AND COALESCE(i.representation,'section') = COALESCE(s.representation,'section')
		WHERE s.kind = 'item'
		  AND s.atm_id IS NOT NULL
		  AND i.atm_id IS NULL
		ORDER BY s.document, s.seq`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var document, atmID, rep string
		var seq int
		if err := rows.Scan(&document, &seq, &atmID, &rep); err != nil {
			return nil, err
		}
		out = append(out, fmt.Sprintf(
			"dangling item-segment (document=%s, seq=%d, atm_id=%s, rep=%s): no item at current_location=%s (§11.4.135/ATM-627)",
			document, seq, atmID, rep, document))
	}
	return out, rows.Err()
}

// terminalStatuses is the closed set of Fixed-location statuses, derived from
// closeStatusMap's terminal .status values so it can NEVER drift from the closer
// (add a new close status keyword → this set gains it automatically). These are the
// only statuses a current_location='Fixed' item may carry.
func terminalStatuses() map[string]bool {
	out := make(map[string]bool, len(closeStatusMap))
	for _, m := range closeStatusMap {
		out[m.status] = true
	}
	return out
}

// fixedLocationNonTerminalStatus returns, for the ATM-627 INTEG-03 location↔status
// defect CLASS, a description of every item at current_location='Fixed' whose status
// is NOT a terminal closed-set value (a `… (→ Fixed.md)` value). A non-terminal status
// in the Fixed archive means the item is not actually closed — it belongs in Issues.
// This is the detective gate for the reopen-does-not-relocate defect: after the fix a
// reopened item migrates to Issues, so a correctly-reopened DB has ZERO findings here.
// Read-only, so it can never break an already-consistent DB.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil`
// removes the guard; TestValidate_CatchesReopenedInFixed (RED polarity per §11.4.115)
// then FAILs — proving the guard is not a tautology.
func fixedLocationNonTerminalStatus(items []item) []string {
	terminal := terminalStatuses()
	var out []string
	for _, it := range items {
		if it.CurrentLocation != "Fixed" {
			continue
		}
		if !terminal[strings.TrimSpace(it.Status)] {
			out = append(out, fmt.Sprintf(
				"%s: Fixed-location item has NON-terminal status %q — a Fixed-location item must carry a terminal `… (→ Fixed.md)` status; a non-terminal item belongs in Issues (§11.4.15/ATM-627 INTEG-03) [%s]",
				it.AtmID, it.Status, it.repOrDefault()))
		}
	}
	return out
}

// itemsMissingSegments is the REVERSE of danglingItemSegments: it returns, for
// EVERY item at (atm_id, current_location, representation) that has NO matching
// doc_segments row (kind='item', document=current_location, atm_id, representation),
// a human-readable description of the gap. This is the direct-integrity assertion of
// the ATM-627 "db-to-md drops N segmentless items" defect class: renderDocument
// (validateCmd check (b)) walks doc_segments in seq order and only ever emits items
// THAT HAVE a segment row — an item with none is simply never visited, so
// renderDocument returns NO error and a naive `db-to-md` regen SILENTLY OMITS the
// item from the regenerated Markdown. Before this guard, `validate` reported "OK"
// on a DB in exactly that state (112 items on the live tree, captured 2026-07-05) —
// a §11.4.6/§11.4.93 bluff gate: green while regen is lossy.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil, nil`
// removes the guard; TestATM627_SegmentBackfill_ValidateCatchesMissingSegments (RED
// polarity per §11.4.115) then FAILs — proving the guard is not a tautology.
func itemsMissingSegments(db *sql.DB) ([]string, error) {
	rows, err := db.Query(`
		SELECT i.atm_id, i.current_location, COALESCE(i.representation,'section')
		FROM items i
		LEFT JOIN doc_segments s
		  ON s.atm_id = i.atm_id
		 AND s.document = i.current_location
		 AND COALESCE(s.representation,'section') = COALESCE(i.representation,'section')
		 AND s.kind = 'item'
		WHERE s.id IS NULL
		ORDER BY i.current_location, i.atm_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []string
	for rows.Next() {
		var atmID, document, rep string
		if err := rows.Scan(&atmID, &document, &rep); err != nil {
			return nil, err
		}
		out = append(out, fmt.Sprintf(
			"missing item-segment (atm_id=%s, rep=%s): item at current_location=%s has NO doc_segments row — db-to-md would silently drop it (§11.4.93/ATM-627)",
			atmID, rep, document))
	}
	return out, rows.Err()
}

// statusColumnBodyDesyncs returns a human-readable description of every item whose
// authoritative items.status column DISAGREES with the Status the md→db parser would
// derive from its body_md (lastBodyStatus). This is the ATM-627 (task #20) DURABLE
// guard for the column↔body Status desync CLASS: a direct `UPDATE items SET status=…`
// that bypasses renderItemBody advances the column while body_md's `**Status:**` line
// stays stale → `sync db-to-md` would emit the stale line, misreporting the item's
// state to every tracker reader. The prior validate checked the status CLOSED-SET only,
// never column↔body agreement, so a desynced item passed exit 0 (a §11.4.6/§11.4.93
// bluff gate: green while db-to-md emits a wrong Status).
//
// Read-only — it can never break a valid DB. Items whose body carries NO `**Status:**`
// line are SKIPPED (nothing to compare); only a PRESENT-but-disagreeing line is a
// violation. Generator-symmetric (§11.4.93): the oracle IS the parser's own column
// derivation (lastBodyStatus → normalizeStatus, last-Status-line-wins), so a body whose
// Status line carries trailing prose / a `**Priority:**` tail / multiple `**Status:**`
// tokens normalises to the column it was first derived from and is NOT a false positive.
// Composes with the R3 dangling-segment guard (danglingItemSegments) — orthogonal
// invariants (that: segment↔item location; this: column↔body Status).
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with `return nil`
// removes the guard; atm627_status_desync_test.go then FAILs — proving the guard is
// NOT a tautology.
func statusColumnBodyDesyncs(items []item) []string {
	var out []string
	for _, it := range items {
		// The `**Status:**`-line invariant governs H2 'section' bodies. A 'table'
		// representation carries its Status in the pipe cell (emitLegacyTable /
		// export.go pipe-row synthesizer), NOT a `**Status:**` line, so it is out of
		// scope for THIS guard (skipping it avoids a false positive against a valid
		// pipe row that legitimately has no `**Status:**` line).
		if it.repOrDefault() != "section" {
			continue
		}
		// deriveStatusFromBody: mirror buildItem's FULL column derivation for a section
		// body — the normalised last `**Status:**` line, OR buildItem's struct-default
		// "Queued" when the section body carries NO `**Status:**` line at all (an empty
		// / status-less body: md→db would set the column to "Queued", so a column that
		// is NOT "Queued" is NOT recoverable from body_md — the SPK-512/519/609
		// empty-body class). This is the exact generator-symmetric oracle.
		want, hasLine := lastBodyStatus(it.BodyMD)
		if !hasLine {
			want = "Queued"
		}
		if want == it.Status {
			continue
		}
		detail := fmt.Sprintf("body_md **Status:** line derives %q", want)
		if !hasLine {
			detail = "body_md has NO **Status:** line (md→db would derive \"Queued\")"
		}
		out = append(out, fmt.Sprintf(
			"%s [%s/%s]: items.status=%q but %s (§11.4.93/ATM-627 column↔body desync)",
			it.AtmID, it.CurrentLocation, it.repOrDefault(), it.Status, detail))
	}
	return out
}

// diffCmd reports items whose parsed-from-Markdown state differs from the DB.
func diffCmd(args []string) int {
	fs := flag.NewFlagSet("diff", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "diff: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	dbItems, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}

	// §11.4.93/ATM-627 defense-in-depth: diff ALSO surfaces the column<->body_md
	// Status DESYNC class (items.status disagreeing with the last **Status:**
	// line in body_md) independently of the Markdown-vs-DB comparison below.
	// validateCmd (the "correct home" per Constitution.md §11.4.93, since it is
	// the DB-internal-integrity gate) already asserts this via
	// statusColumnBodyDesyncs; wiring the SAME check into diff closes a real gap
	// in diff's OWN invocation surface: `diff --db <path>` with NEITHER
	// --issues NOR --fixed given performs no Markdown comparison at all (every
	// DB item is trivially reported "absent in Markdown" — uninformative noise
	// for this purpose), so a pure DB-internal desync was invisible to that
	// invocation shape. Reproduced + fixed 2026-07-07 (workable-items §11.4.93
	// tooling-integrity gate); see sync_diff_desync_test.go for the RED/GREEN
	// polarity proof.
	desyncs := statusColumnBodyDesyncs(dbItems)
	for _, d := range desyncs {
		fmt.Printf("! %s\n", d)
	}

	// Key by the COMPOSITE identity (atm_id, current_location, representation) —
	// the schema PRIMARY KEY — NOT by atm_id alone. loadItems returns one row per
	// composite key (an atm_id MAY appear once per tracker AND once per
	// representation within a tracker — a pipe-table 'table' row + an H2 'section'
	// block, GAP A / HXC-044), and renderDocument (db.go) already keys its body
	// lookup by id + "\x00" + representation for exactly this reason. Collapsing
	// to atm_id alone here kept only the LAST-loaded row, so the OTHER parsed
	// representation was compared against the wrong DB row → a spurious "body
	// differs" / "type differs" false-positive while validate + the round-trip
	// gate both PASS.
	itemKey := func(it item) string {
		return it.AtmID + "\x00" + it.CurrentLocation + "\x00" + it.repOrDefault()
	}
	dbByID := map[string]item{}
	for _, it := range dbItems {
		dbByID[itemKey(it)] = it
	}

	var parsed []item
	if *issuesPath != "" {
		c, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read issues: %v\n", err)
			return exitUsage
		}
		its, _ := parseIssues(string(c))
		parsed = append(parsed, its...)
	}
	if *fixedPath != "" {
		c, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read fixed: %v\n", err)
			return exitUsage
		}
		its, _ := parseFixed(string(c))
		parsed = append(parsed, its...)
	}

	differences := 0
	parsedSeen := map[string]bool{}
	for _, p := range parsed {
		parsedSeen[itemKey(p)] = true
		d, ok := dbByID[itemKey(p)]
		if !ok {
			fmt.Printf("+ %s present in Markdown, absent in DB\n", p.AtmID)
			differences++
			continue
		}
		if p.Status != d.Status {
			fmt.Printf("~ %s status: md=%q db=%q\n", p.AtmID, p.Status, d.Status)
			differences++
		}
		if p.Type != d.Type {
			fmt.Printf("~ %s type: md=%q db=%q\n", p.AtmID, p.Type, d.Type)
			differences++
		}
		if p.BodyMD != d.BodyMD {
			fmt.Printf("~ %s body differs (md=%d bytes db=%d bytes)\n", p.AtmID, len(p.BodyMD), len(d.BodyMD))
			differences++
		}
	}
	for _, d := range dbItems {
		if !parsedSeen[itemKey(d)] {
			fmt.Printf("- %s present in DB, absent in Markdown\n", d.AtmID)
			differences++
		}
	}

	differences += len(desyncs)

	if differences == 0 {
		fmt.Println("diff: DB and Markdown are in sync")
		return exitOK
	}
	fmt.Printf("diff: %d difference(s)\n", differences)
	return exitUsage
}
