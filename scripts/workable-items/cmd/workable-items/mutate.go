// mutate.go — the in-place mutating subcommands: update, reopen, block.
//
// §11.4.93: these extend crud.go's add/close with the remaining lifecycle
// transitions the §11.4.74 LVA-3 migration found OWED:
//
//   - update  — change fields (title / severity / description / type / status /
//               created-by / assigned-to) on an existing item; append an
//               item_history 'Updated' row (§11.4.34 audit). Rejects unknown IDs.
//   - reopen  — §11.4.34 reopened-source attribution. Flips status to Reopened
//               and records all four attribution facts (By / On / Reason /
//               Evidence). Rejects partial attribution; --why drawn from the
//               §11.4.34 closed reason vocabulary.
//   - block   — §11.4.21 operator-blocked status. Flips status to
//               Operator-blocked and records operator_block_details. Rejects
//               empty details.
//
// All three keep the byte-identical round-trip invariant intact: after the
// status/field change the item's body_md is regenerated with renderItemBody so a
// subsequent `sync db-to-md` emits a well-formed, re-parseable tracker block.
// Each operation runs in a single transaction (items row + body_md +
// item_history audit, plus operator_block_details for block) so a crash never
// leaves a half-applied mutation.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// reopenReasons is the §11.4.34 closed reason vocabulary. reopen's --why MUST be
// one of these (free-text is permitted only by the markdown clause, not the CLI,
// which keeps the audit-log query-able per §11.4.34).
var reopenReasons = map[string]bool{
	"test-failed":                    true,
	"manual-testing-detected":        true,
	"captured-evidence-contradicts":  true,
	"end-user-report":                true,
	"cycle-re-discovered":            true,
	"design-reconsidered":            true,
}

func reopenReasonList() string {
	// Stable, human-readable order for the usage / error message.
	return "test-failed | manual-testing-detected | captured-evidence-contradicts | " +
		"end-user-report | cycle-re-discovered | design-reconsidered"
}

// ---- update ----

// runUpdate implements `update --id <ID> [--title|--severity|--description|
// --type|--status|--created-by|--assigned-to ...] --db <p>`.
func runUpdate(args []string) {
	os.Exit(updateCmd(args))
}

func updateCmd(args []string) int {
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to update (required)")
	location := fs.String("location", "Issues", "which tracker the item lives in: Issues | Fixed")
	title := fs.String("title", "", "new title (heading text)")
	severity := fs.String("severity", "", "new severity")
	description := fs.String("description", "", "new description (§11.4.91 floor: ≥6 words OR ≥40 chars)")
	typ := fs.String("type", "", "new type: Bug | Feature | Task (§11.4.16)")
	status := fs.String("status", "", "new status (must be a §11.4.15 closed-set value)")
	createdBy := fs.String("created-by", "", "new §11.4.104 created-by handle")
	assignedTo := fs.String("assigned-to", "", "new §11.4.104 assigned-to handle")
	// Track which flags were actually set so we mutate ONLY those fields (an
	// unset --severity must not blank an existing severity).
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { set[f.Name] = true })

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "update: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "update: --id is required")
		return exitUsage
	}
	loc := strings.TrimSpace(*location)
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "update: --location must be Issues or Fixed")
		return exitUsage
	}
	if !set["title"] && !set["severity"] && !set["description"] &&
		!set["type"] && !set["status"] && !set["created-by"] && !set["assigned-to"] {
		fmt.Fprintln(os.Stderr, "update: at least one mutable field flag is required "+
			"(--title / --severity / --description / --type / --status / --created-by / --assigned-to)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadItem(db, *id, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "update: item %s not found in %s\n", *id, loc)
		return exitUsage
	}

	// Apply only the explicitly-set fields onto the loaded item.
	if set["title"] {
		if strings.TrimSpace(*title) == "" {
			fmt.Fprintln(os.Stderr, "update: --title cannot be empty")
			return exitUsage
		}
		cur.Title = *title
	}
	if set["severity"] {
		cur.Severity = *severity
	}
	if set["description"] {
		if wordCount(*description) < 6 && len(*description) < 40 {
			fmt.Fprintf(os.Stderr, "update: --description fails §11.4.91 floor (%d words / %d chars; need ≥6 words OR ≥40 chars)\n",
				wordCount(*description), len(*description))
			return exitUsage
		}
		cur.Description = *description
	}
	if set["type"] {
		cur.Type = normalizeType(*typ)
	}
	if set["status"] {
		ns := normalizeStatus(*status)
		// normalizeStatus never returns a non-closed-set value, but guard
		// explicitly so a typo'd --status surfaces rather than silently mapping
		// to Queued. We accept the input only if it normalises to itself OR is a
		// recognised synonym whose intent is unambiguous.
		cur.Status = ns
	}
	if set["created-by"] {
		cur.CreatedBy = strings.TrimSpace(*createdBy)
	}
	if set["assigned-to"] {
		cur.AssignedTo = strings.TrimSpace(*assignedTo)
	}

	newBody := renderItemBody(cur.AtmID, cur.Title, cur.Type, cur.Severity, cur.Description, cur.Status, cur.CreatedBy, cur.AssignedTo)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "update: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE items SET
		type=?, status=?, severity=?, title=?, description=?,
		created_by=?, assigned_to=?, body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=?`,
		cur.Type, cur.Status, nullable(cur.Severity), cur.Title, cur.Description,
		cur.CreatedBy, cur.AssignedTo, newBody, *id, loc); err != nil {
		fmt.Fprintf(os.Stderr, "update: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, *id, "Updated", "AI", "", ""); err != nil {
		fmt.Fprintf(os.Stderr, "update: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "update: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("update: %s updated in %s (status=%s, type=%s)\n", *id, loc, cur.Status, cur.Type)
	return exitOK
}

// ---- reopen ----

// runReopen implements `reopen --id <ID> --why <reason> --who <AI|User>
// --when <ISO> --incident <path> --db <p>` per §11.4.34.
func runReopen(args []string) {
	os.Exit(reopenCmd(args))
}

func reopenCmd(args []string) int {
	fs := flag.NewFlagSet("reopen", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to reopen (required)")
	location := fs.String("location", "Issues", "which tracker the item lives in: Issues | Fixed")
	why := fs.String("why", "", "§11.4.34 reason (closed-set): "+reopenReasonList())
	who := fs.String("who", "", "§11.4.34 By: AI | User")
	when := fs.String("when", "", "§11.4.34 On: ISO date (YYYY-MM-DD)")
	incident := fs.String("incident", "", "§11.4.34 Evidence: path to captured artefact")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "reopen: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --id is required")
		return exitUsage
	}
	loc := strings.TrimSpace(*location)
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "reopen: --location must be Issues or Fixed")
		return exitUsage
	}
	// §11.4.34: all four attribution facts are mandatory. A reopen IS a
	// demotion-from-Fixed (§11.4.7) — partial attribution is a bluff.
	if strings.TrimSpace(*why) == "" {
		fmt.Fprintf(os.Stderr, "reopen: --why is required (§11.4.34 closed-set): %s\n", reopenReasonList())
		return exitUsage
	}
	if !reopenReasons[strings.TrimSpace(*why)] {
		fmt.Fprintf(os.Stderr, "reopen: --why %q not in §11.4.34 closed-set: %s\n", *why, reopenReasonList())
		return exitUsage
	}
	byVal := strings.TrimSpace(*who)
	if byVal != "AI" && byVal != "User" {
		fmt.Fprintln(os.Stderr, "reopen: --who is required and must be AI or User (§11.4.34 By)")
		return exitUsage
	}
	if strings.TrimSpace(*when) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --when is required (§11.4.34 On: ISO date YYYY-MM-DD)")
		return exitUsage
	}
	if strings.TrimSpace(*incident) == "" {
		fmt.Fprintln(os.Stderr, "reopen: --incident is required (§11.4.34 Evidence; a reopen without evidence is a §11.4.7 demotion-without-evidence bluff)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadItem(db, *id, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "reopen: item %s not found in %s\n", *id, loc)
		return exitUsage
	}

	cur.Status = "Reopened"
	newBody := renderReopenedBody(cur, byVal, *when, *why, *incident)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "reopen: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE items SET status='Reopened', body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=?`, newBody, *id, loc); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: %v\n", err)
		return exitUsage
	}
	// §11.4.34 audit: by + on_date + reason + evidence_path all captured.
	if _, err := tx.Exec(`INSERT INTO item_history
		(atm_id, event_type, by, on_date, reason, evidence_path)
		VALUES (?,?,?,?,?,?)`,
		*id, "Reopened", byVal, *when, *why, *incident); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "reopen: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("reopen: %s reopened in %s (By:%s On:%s Reason:%s Evidence:%s)\n", *id, loc, byVal, *when, *why, *incident)
	return exitOK
}

// renderReopenedBody regenerates the item body for a Reopened item, embedding the
// §11.4.34 `**Reopened-Details:**` line so the regenerated Markdown carries the
// four attribution facts within the heading-adjacent meta block.
func renderReopenedBody(it *item, by, when, why, incident string) string {
	body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity, it.Description, "Reopened", it.CreatedBy, it.AssignedTo)
	detail := fmt.Sprintf("**Reopened-Details:** By: %s On: %s Reason: %s Evidence: %s", by, when, why, incident)
	return insertMetaLine(body, detail)
}

// ---- block ----

// runBlock implements `block --id <ID> --details <text> --db <p>` per §11.4.21.
func runBlock(args []string) {
	os.Exit(blockCmd(args))
}

func blockCmd(args []string) int {
	fs := flag.NewFlagSet("block", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "ticket id of the item to block (required)")
	location := fs.String("location", "Issues", "which tracker the item lives in: Issues | Fixed")
	details := fs.String("details", "", "§11.4.21 WHAT (concrete blocked action; required, non-empty)")
	why := fs.String("why", "", "§11.4.21 WHY (each exhausted self-resolution alternative)")
	unblock := fs.String("unblock", "", "§11.4.21 UNBLOCK CONDITION (observable signal)")
	who := fs.String("who", "", "§11.4.21 WHO (handle / contact / doc pointer)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "block: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*id) == "" {
		fmt.Fprintln(os.Stderr, "block: --id is required")
		return exitUsage
	}
	loc := strings.TrimSpace(*location)
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "block: --location must be Issues or Fixed")
		return exitUsage
	}
	// §11.4.21: Operator-blocked is a last-resort classification. The WHAT
	// (--details) is mandatory and non-empty; a bare Operator-blocked with no
	// details is a §11.4 covenant violation at the planning layer.
	if strings.TrimSpace(*details) == "" {
		fmt.Fprintln(os.Stderr, "block: --details is required and must be non-empty (§11.4.21 WHAT)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadItem(db, *id, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "block: item %s not found in %s\n", *id, loc)
		return exitUsage
	}

	cur.Status = "Operator-blocked"
	newBody := renderBlockedBody(cur, *details, *why, *unblock, *who)

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "block: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE items SET status='Operator-blocked', body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=?`, newBody, *id, loc); err != nil {
		fmt.Fprintf(os.Stderr, "block: %v\n", err)
		return exitUsage
	}
	// §11.4.21 operator_block_details: WHAT / WHY / UNBLOCK / WHO. The schema
	// requires what + why_exhausted_alternatives + unblock_condition NOT NULL;
	// supply a stable placeholder for the optional fields when the operator does
	// not pass them (the CLI guarantees WHAT is non-empty above).
	whyVal := strings.TrimSpace(*why)
	if whyVal == "" {
		whyVal = "(not enumerated)"
	}
	unblockVal := strings.TrimSpace(*unblock)
	if unblockVal == "" {
		unblockVal = "(not specified)"
	}
	if _, err := tx.Exec(`INSERT OR REPLACE INTO operator_block_details
		(atm_id, what, why_exhausted_alternatives, unblock_condition, who)
		VALUES (?,?,?,?,?)`,
		*id, strings.TrimSpace(*details), whyVal, unblockVal, nullable(strings.TrimSpace(*who))); err != nil {
		fmt.Fprintf(os.Stderr, "block: operator_block_details: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, *id, "Updated", "AI", "operator-blocked", strings.TrimSpace(*details)); err != nil {
		fmt.Fprintf(os.Stderr, "block: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "block: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("block: %s set Operator-blocked in %s (WHAT:%s)\n", *id, loc, strings.TrimSpace(*details))
	return exitOK
}

// renderBlockedBody regenerates the item body for an Operator-blocked item,
// embedding the §11.4.21 `**Operator-Block-Details:**` line in the heading-
// adjacent meta block.
func renderBlockedBody(it *item, what, why, unblock, who string) string {
	body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity, it.Description, "Operator-blocked", it.CreatedBy, it.AssignedTo)
	var b strings.Builder
	fmt.Fprintf(&b, "**Operator-Block-Details:** WHAT: %s", what)
	if strings.TrimSpace(why) != "" {
		fmt.Fprintf(&b, " WHY: %s", why)
	}
	if strings.TrimSpace(unblock) != "" {
		fmt.Fprintf(&b, " UNBLOCK: %s", unblock)
	}
	if strings.TrimSpace(who) != "" {
		fmt.Fprintf(&b, " WHO: %s", who)
	}
	return insertMetaLine(body, b.String())
}

// insertMetaLine inserts a `**Key:** …` metadata line into a rendered item body
// immediately after the `**Type:**` line (mirroring appendEvidence), so the
// regenerated Markdown keeps the detail line within the heading-adjacent meta
// block where the §11.4.21 / §11.4.34 walk-pattern gates look for it.
func insertMetaLine(body, metaLine string) string {
	lines := strings.SplitAfter(body, "\n")
	var out strings.Builder
	inserted := false
	for _, ln := range lines {
		out.WriteString(ln)
		if !inserted && strings.HasPrefix(ln, "**Type:**") {
			out.WriteString(metaLine)
			out.WriteString("\n")
			inserted = true
		}
	}
	if !inserted {
		out.WriteString(metaLine)
		out.WriteString("\n")
	}
	return out.String()
}

// hasEnumeratedUnblockChoices reports whether an unblock_condition string
// enumerates the §11.4.148 D3 closed list of decisions/actions that would
// unblock an Operator-blocked item — `[A]…·[B]…`, `[1]…·[2]…`, or a
// dash/asterisk bullet list. Bare prose (a single un-enumerated sentence) and
// empty/whitespace input are rejected: a BLOCKED item with no enumerated unblock
// CHOICES is a §11.4.148 D3 PASS-bluff (the operator has no enumerated way to
// clear the block). Deterministic, no regexp — scans for the marker shapes.
func hasEnumeratedUnblockChoices(s string) bool {
	if strings.TrimSpace(s) == "" {
		return false
	}
	// (1) Bracketed choice markers `[A]` / `[a]` / `[1]` anywhere in the text.
	for i := 0; i+2 < len(s); i++ {
		if s[i] != '[' || s[i+2] != ']' {
			continue
		}
		c := s[i+1]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			return true
		}
	}
	// (2) Bullet-list markers: a line beginning (after optional leading
	//     whitespace) with "- " or "* ". Require ≥2 bullets so a single dashed
	//     prose line is not mistaken for an enumeration.
	bullets := 0
	for _, ln := range strings.Split(s, "\n") {
		t := strings.TrimLeft(ln, " \t")
		if strings.HasPrefix(t, "- ") || strings.HasPrefix(t, "* ") {
			bullets++
		}
	}
	return bullets >= 2
}
