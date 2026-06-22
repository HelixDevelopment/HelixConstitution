// diary_cmd.go — §11.4.149 per-workable-item testing-diary CLI subcommand group.
//
// This file closes the §11.4.149 tooling gap: the test_diary / test_diary_summary
// tables (schema_embed.sql) and the storage/render helpers (diary.go) existed,
// but NO `workable-items` subcommand populated or read them — a per-item testing
// diary entry could only be recorded via raw SQL (forbidden; the Go binary is the
// sanctioned tooling per §11.4.93 / §11.4.149(e)). The `diary` subcommand group
// makes the diary reachable through the sanctioned binary:
//
//	diary add --id <atm> --db <p> --tested-by <W> --result <R> [--detail T]
//	          [--observations T] [--evidence path] [--feature-class c]
//	          [--action-taken T] [--status-from s] [--status-to s] [--date-time ISO]
//	diary list --id <atm> --db <p>
//	diary summary --db <p> [--id <atm>]
//
// §11.4.149 PASS-requires-evidence is enforced at THREE layers here: (1) the CLI
// guard rejects a PASS with an empty --evidence; (2) this command ALSO requires
// the evidence path to EXIST on disk (a PASS citing a non-existent artefact is a
// PASS-bluff — the evidence does not actually exist); (3) the schema CHECK in
// test_diary independently rejects a PASS row with an empty evidence_path. The
// observations prose is authored by whoever ran the test — ZERO LLM in the data
// path (§11.4.149(e)); the tooling only stores / renders / validates.
//
// Deterministic: date_time is caller-provided (--date-time, ISO-8601) or defaults
// to the current UTC instant, matching the established diary.go idiom.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"time"
)

// runDiary dispatches the `diary` subcommand group (add | list | summary). It is
// the sanctioned entry point for §11.4.149 per-item testing-diary records.
func runDiary(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "diary: missing subcommand (add | list | summary)")
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "add":
		os.Exit(diaryGroupAddCmd(args[1:]))
	case "list":
		os.Exit(diaryGroupListCmd(args[1:]))
	case "summary":
		os.Exit(diaryGroupSummaryCmd(args[1:]))
	default:
		fmt.Fprintf(os.Stderr, "diary: unknown subcommand: %s (want add | list | summary)\n", args[0])
		os.Exit(exitUsage)
	}
}

// diaryGroupAddCmd implements `diary add`: insert one test_diary row for an item
// (or ATM-NNN-SSS sub-task). Validates the §11.4.149 closed sets, requires the
// target id to exist, and ENFORCES the §11.4.149 anti-bluff invariant — a PASS
// run REQUIRES a non-empty --evidence path that EXISTS on disk.
func diaryGroupAddCmd(args []string) int {
	fs := flag.NewFlagSet("diary add", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "item OR ATM-NNN-SSS sub-task id the run targets")
	testedBy := fs.String("tested-by", "", "User | Operator | AI-agent | HelixQA")
	result := fs.String("result", "", "PASS | FAIL | SKIP")
	detail := fs.String("detail", "", "short verdict detail (SKIP should carry its reason here)")
	observations := fs.String("observations", "", "in-depth observations (markdown)")
	evidence := fs.String("evidence", "", "§11.4.69 captured-evidence path (REQUIRED for PASS; must exist)")
	featureClass := fs.String("feature-class", "", "§11.4.69 sink-side feature class")
	actionTaken := fs.String("action-taken", "", "action taken (status change or not, + why)")
	statusFrom := fs.String("status-from", "", "status before this run (when it changed)")
	statusTo := fs.String("status-to", "", "status after this run (when it changed)")
	dateTime := fs.String("date-time", "", "ISO-8601 UTC run time (default: now)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	atm := strings.TrimSpace(*id)
	if atm == "" {
		fmt.Fprintln(os.Stderr, "diary add: --id is required")
		return exitUsage
	}
	if strings.TrimSpace(*dbPath) == "" {
		fmt.Fprintln(os.Stderr, "diary add: --db is required")
		return exitUsage
	}
	tb := strings.TrimSpace(*testedBy)
	if !diaryTestedBy[tb] {
		fmt.Fprintln(os.Stderr, "diary add: --tested-by must be one of: User | Operator | AI-agent | HelixQA")
		return exitUsage
	}
	res := strings.ToUpper(strings.TrimSpace(*result))
	if !diaryResults[res] {
		fmt.Fprintln(os.Stderr, "diary add: --result must be one of: PASS | FAIL | SKIP")
		return exitUsage
	}

	ev := strings.TrimSpace(*evidence)
	// §11.4.149 anti-bluff: a PASS without captured evidence is a PASS-bluff. This
	// command goes one step beyond the diary.go non-empty guard — the cited
	// evidence path MUST actually exist on disk (a PASS pointing at a
	// non-existent artefact has no captured evidence).
	if res == "PASS" {
		if ev == "" {
			fmt.Fprintln(os.Stderr, "diary add: a PASS run REQUIRES --evidence (§11.4.149 — a PASS without captured evidence is a bluff)")
			return exitUsage
		}
		info, err := os.Stat(ev)
		if err != nil || info.IsDir() {
			fmt.Fprintf(os.Stderr, "diary add: PASS --evidence %q does not exist as a file on disk (§11.4.149 — evidence must be real captured proof)\n", ev)
			return exitUsage
		}
	}

	obs := strings.TrimSpace(*observations)
	if obs == "" {
		fmt.Fprintln(os.Stderr, "diary add: --observations are required")
		return exitUsage
	}

	dt := strings.TrimSpace(*dateTime)
	if dt == "" {
		dt = time.Now().UTC().Format(time.RFC3339)
	}
	act := strings.TrimSpace(*actionTaken)
	if act == "" {
		act = "status unchanged"
	}
	statusChanged := 0
	if strings.TrimSpace(*statusFrom) != "" || strings.TrimSpace(*statusTo) != "" {
		statusChanged = 1
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary add: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// §11.4.6 soft-FK: the diary target id MUST exist as an item / sub-task.
	exists, err := itemExistsAnyLocation(db, atm)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary add: %v\n", err)
		return exitUsage
	}
	if !exists {
		fmt.Fprintf(os.Stderr, "diary add: target %s not found in items (a diary entry needs an existing item / sub-task)\n", atm)
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary add: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	var entryID int64
	row := tx.QueryRow(`INSERT INTO test_diary
		(atm_id, date_time, tested_by, result, result_detail, observations,
		 action_taken, status_changed, status_from, status_to, evidence_path, feature_class)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?) RETURNING entry_id`,
		atm, dt, tb, res, nullable(*detail), obs,
		act, statusChanged, nullable(*statusFrom), nullable(*statusTo),
		nullable(ev), nullable(*featureClass))
	if err := row.Scan(&entryID); err != nil {
		fmt.Fprintf(os.Stderr, "diary add: insert diary row: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "diary add: commit: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("diary add: recorded entry_id=%d on %s (%s, tested_by=%s)\n", entryID, atm, res, tb)
	return exitOK
}

// diaryGroupListCmd implements `diary list --id <atm>`: print every diary row for
// the item in chronological order (oldest first). Read-only.
func diaryGroupListCmd(args []string) int {
	fs := flag.NewFlagSet("diary list", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "item OR ATM-NNN-SSS sub-task id to list")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	atm := strings.TrimSpace(*id)
	if atm == "" {
		fmt.Fprintln(os.Stderr, "diary list: --id is required")
		return exitUsage
	}
	if strings.TrimSpace(*dbPath) == "" {
		fmt.Fprintln(os.Stderr, "diary list: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary list: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	rows, err := loadDiary(db, atm) // newest-first
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary list: %v\n", err)
		return exitUsage
	}
	if len(rows) == 0 {
		fmt.Printf("diary list: no diary entries for %s\n", atm)
		return exitOK
	}

	fmt.Printf("Testing diary for %s (%d entr%s, oldest first):\n", atm, len(rows), plural(len(rows), "y", "ies"))
	// loadDiary returns newest-first; print chronological (oldest first).
	for i := len(rows) - 1; i >= 0; i-- {
		r := rows[i]
		fmt.Printf("  [%d] %s  %-9s  %s\n", r.EntryID, r.DateTime, r.TestedBy, r.Result)
		if r.ResultDetail != "" {
			fmt.Printf("       detail:        %s\n", r.ResultDetail)
		}
		fmt.Printf("       observations:  %s\n", oneLine(r.Observations))
		fmt.Printf("       action:        %s\n", r.ActionTaken)
		if r.StatusFrom != "" || r.StatusTo != "" {
			fmt.Printf("       status:        %s -> %s\n", defaultStr(r.StatusFrom, "?"), defaultStr(r.StatusTo, "?"))
		}
		if r.FeatureClass != "" {
			fmt.Printf("       feature-class: %s\n", r.FeatureClass)
		}
		if r.EvidencePath != "" {
			fmt.Printf("       evidence:      %s\n", r.EvidencePath)
		}
	}
	return exitOK
}

// diaryGroupSummaryCmd implements `diary summary [--id <atm>]`: print the
// test_diary_summary rollup (total / pass / fail / skip + last verdict + last
// run) for one item or for every item with diary rows. Read-only.
func diaryGroupSummaryCmd(args []string) int {
	fs := flag.NewFlagSet("diary summary", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	id := fs.String("id", "", "single item id (default: all items with diary rows)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if strings.TrimSpace(*dbPath) == "" {
		fmt.Fprintln(os.Stderr, "diary summary: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary summary: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	ids, err := summaryTargets(db, strings.TrimSpace(*id), strings.TrimSpace(*id) == "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "diary summary: %v\n", err)
		return exitUsage
	}
	if len(ids) == 0 {
		fmt.Println("diary summary: no diary entries recorded")
		return exitOK
	}

	fmt.Println("Testing-diary summary (total/pass/fail/skip, last verdict, last run):")
	for _, atm := range ids {
		s, err := loadSummary(db, atm)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diary summary: %s: %v\n", atm, err)
			return exitUsage
		}
		fmt.Printf("  %-16s  total=%d P=%d F=%d S=%d  last=%s @ %s\n",
			atm, s.TotalRuns, s.PassRuns, s.FailRuns, s.SkipRuns,
			defaultStr(s.LastResult, "none"), defaultStr(s.LastRun, "—"))
	}
	return exitOK
}

// ---- tiny local helpers ----

// oneLine collapses a multi-line observations field to a single trimmed line for
// the list view (the full prose lives in the DB + the Diary.md export).
func oneLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return strings.TrimSpace(s[:i]) + " …"
	}
	return s
}

// plural returns sing when n == 1, else plur.
func plural(n int, sing, plur string) string {
	if n == 1 {
		return sing
	}
	return plur
}
