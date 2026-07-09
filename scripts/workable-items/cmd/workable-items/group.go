// group.go — the `group` subcommand family: add | list | set | state.
//
// docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §3.2 (logic_groups registry) +
// §6 (Go subcommands `group {add,list,set,state}` are UNIVERSAL,
// constitution/scripts/workable-items/cmd/) + §11.4.176/§11.4.119/§11.4.111
// (mechanism authority). This is Phase P2 of
// docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md: CRUD over the logic_groups table
// PLUS the item-classification write-path (items.logic_group /
// items.destination) — the group-atomic track-assignment mechanism's
// authoritative data-entry point. Schema (logic_groups table +
// items.destination/logic_group columns) already exists from P1 (ATM-659,
// constitution commit e0d4ae5) — this phase does NOT touch schema/migration.
//
//	group add <group_id> <destination> <priority> --title <T>
//	          [--state open|in-progress|group-complete]
//	          [--scope-note <T>] [--roadmap-ref <T>] --db <p>
//	group list [--destination <D>] [--state <S>] --db <p>
//	group set <group_id> [--title T] [--destination D] [--priority N]
//	          [--scope-note T] [--roadmap-ref T] --db <p>
//	group set --item <ATM-ID> --group <group_id> [--location Issues|Fixed] --db <p>
//	group state <group_id> <open|in-progress|group-complete> --db <p>
//
// `group set --item` (Mode B) INHERITS the target group's destination onto
// the item in the SAME write, so the §3.1 destination-agreement invariant is
// satisfied STRUCTURALLY for every classification this command performs —
// there is no code path through which a classified item's destination can
// disagree with its own group's destination.
//
// `group state` is an UNCONDITIONAL (unguarded) lifecycle-state setter — raw
// CRUD over logic_groups.state only. The GATED group-complete transition
// (refusing unless every member item is terminal-with-evidence, design §4) is
// a LATER phase's job (`assign group-complete`, P3); P2 supplies only the bare
// setter that phase will build the gate on top of.
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// groupStates is the design §4 group lifecycle state-machine closed set.
var groupStates = map[string]bool{
	"open":           true,
	"in-progress":    true,
	"group-complete": true,
}

func groupStateList() string { return "open | in-progress | group-complete" }

// logicGroup is the in-memory representation of one logic_groups row
// (schema.sql / schema_embed.sql §3.2, landed by P1).
type logicGroup struct {
	GroupID     string
	Title       string
	Destination string
	Priority    int
	State       string
	ScopeNote   string
	RoadmapRef  string
}

// runGroup dispatches the `group` subcommand group
// (add | branch | list | set | state).
func runGroup(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "group: missing subcommand (add | branch | list | set | state)")
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "add":
		os.Exit(groupAddCmd(args[1:]))
	case "branch":
		os.Exit(groupBranchCmd(args[1:]))
	case "list":
		os.Exit(groupListCmd(args[1:]))
	case "set":
		os.Exit(groupSetCmd(args[1:]))
	case "state":
		os.Exit(groupStateCmd(args[1:]))
	default:
		fmt.Fprintf(os.Stderr, "group: unknown subcommand: %s (want add | branch | list | set | state)\n", args[0])
		os.Exit(exitUsage)
	}
}

// ---- branch (§11.4.181 registry-driven feature-branch mint) ----

// groupBranchCmd implements `group branch <group_id> --db <p> [--repo <dir>]
// [--print-only]`.
//
// This is the ONLY sanctioned feature-branch create path (§11.4.181): it
// RESOLVES the canonical branch name `feature/<slug>` from the group's
// registered `logic_groups.destination` (`feature:<slug>`) and creates it — the
// name is a LOOKED-UP FACT, never re-invented (§11.4.6 / §11.4.181(2)). The
// §11.4.109-class PreToolUse guard hook `guard-branch-consistency.sh` blocks any
// ad-hoc `git checkout -b feature/*` whose name is not a registered destination,
// so a divergent branch cannot be created at all — this helper is how the
// CORRECT branch is created.
//
// Refusals (exit exitUsage — never a wrong/ambiguous create, §11.4.6):
//   - group_id not registered in logic_groups   (cannot mint for an unknown group)
//   - group's destination is not 'feature:<slug>' (a 'main' group lands on the
//     main branch; there is no feature branch to mint)
//
// Idempotent success (exit exitOK): a group has EXACTLY ONE canonical branch
// (deterministic from its destination), so if `feature/<slug>` already exists it
// IS this group's branch — never a "different" one; we `git checkout` (switch)
// to it instead of failing `git checkout -b`.
func groupBranchCmd(args []string) int {
	fs := flag.NewFlagSet("group branch", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	repo := fs.String("repo", ".", "git repository directory to create the branch in")
	printOnly := fs.Bool("print-only", false, "resolve + print the canonical branch name; do NOT touch git")
	pos, flagArgs := partitionArgs(args, map[string]bool{"print-only": true})
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "group branch: missing positional <group_id>")
		return exitUsage
	}
	groupID := strings.TrimSpace(pos[0])
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "group branch: --db is required")
		return exitUsage
	}
	if groupID == "" {
		fmt.Fprintln(os.Stderr, "group branch: <group_id> must be non-empty")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group branch: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	g, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group branch: %v\n", err)
		return exitUsage
	}
	if g == nil {
		fmt.Fprintf(os.Stderr, "group branch: group %s is not registered in logic_groups — cannot mint a branch for an unknown group (§11.4.181: the canonical name is a looked-up fact, never invented)\n", groupID)
		return exitUsage
	}
	if !strings.HasPrefix(g.Destination, "feature:") {
		fmt.Fprintf(os.Stderr, "group branch: group %s has destination %q — only 'feature:<slug>' groups get a feature branch (a 'main' group lands on the main branch; there is no feature branch to mint)\n", groupID, g.Destination)
		return exitUsage
	}
	// Canonical branch name = the registry's destination, mapped
	// feature:<slug> -> feature/<slug> (the §11.4.181 D naming scheme).
	canonical := "feature/" + strings.TrimPrefix(g.Destination, "feature:")

	if *printOnly {
		fmt.Println(canonical)
		return exitOK
	}

	exists := gitBranchExists(*repo, canonical)
	var cmd *exec.Cmd
	if exists {
		cmd = exec.Command("git", "-C", *repo, "checkout", canonical)
	} else {
		cmd = exec.Command("git", "-C", *repo, "checkout", "-b", canonical)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintf(os.Stderr, "group branch: git checkout failed: %v\n%s", err, string(out))
		return exitUsage
	}
	if exists {
		fmt.Printf("group branch: %s -> %s (already existed; checked out)\n", groupID, canonical)
	} else {
		fmt.Printf("group branch: %s -> %s (created + checked out)\n", groupID, canonical)
	}
	return exitOK
}

// gitBranchExists reports whether refs/heads/<branch> exists in the repo at dir.
func gitBranchExists(dir, branch string) bool {
	cmd := exec.Command("git", "-C", dir, "rev-parse", "--verify", "--quiet", "refs/heads/"+branch)
	return cmd.Run() == nil
}

// ---- add ----

// groupAddCmd implements `group add <group_id> <destination> <priority>
// --title <T> [--state s] [--scope-note T] [--roadmap-ref T] --db <p>`.
func groupAddCmd(args []string) int {
	fs := flag.NewFlagSet("group add", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	title := fs.String("title", "", "group title (>=6 words / §11.4.91 clarity floor)")
	state := fs.String("state", "open", "initial lifecycle state: "+groupStateList())
	scopeNote := fs.String("scope-note", "", "plain-language membership definition (audit only, never a matcher — design §3.2)")
	roadmapRef := fs.String("roadmap-ref", "", "pointer to the ROADMAP/priority-doc line that set this priority")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 3 {
		fmt.Fprintln(os.Stderr, "group add: missing positional <group_id> <destination> <priority>")
		return exitUsage
	}
	groupID := strings.TrimSpace(pos[0])
	destination := strings.TrimSpace(pos[1])
	priorityStr := strings.TrimSpace(pos[2])

	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "group add: --db is required")
		return exitUsage
	}
	if groupID == "" {
		fmt.Fprintln(os.Stderr, "group add: <group_id> must be non-empty")
		return exitUsage
	}
	if !validGroupID(groupID) {
		fmt.Fprintf(os.Stderr, "group add: <group_id> %q must be lowercase snake/kebab (§11.4.29): letters a-z, digits, hyphens only\n", groupID)
		return exitUsage
	}
	if !validDestination(destination) {
		fmt.Fprintf(os.Stderr, "group add: <destination> %q must be 'main' or 'feature:<slug>' (design §3.1)\n", destination)
		return exitUsage
	}
	priority, err := strconv.Atoi(priorityStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group add: <priority> %q must be an integer\n", priorityStr)
		return exitUsage
	}
	if strings.TrimSpace(*title) == "" {
		fmt.Fprintln(os.Stderr, "group add: --title is required")
		return exitUsage
	}
	st := strings.TrimSpace(*state)
	if !groupStates[st] {
		fmt.Fprintf(os.Stderr, "group add: --state must be one of: %s\n", groupStateList())
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group add: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	exists, err := groupExists(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group add: %v\n", err)
		return exitUsage
	}
	if exists {
		fmt.Fprintf(os.Stderr, "group add: group %s already exists\n", groupID)
		return exitUsage
	}

	if _, err := db.Exec(`INSERT INTO logic_groups
		(group_id, title, destination, priority, state, scope_note, roadmap_ref)
		VALUES (?,?,?,?,?,?,?)`,
		groupID, *title, destination, priority, st, nullable(*scopeNote), nullable(*roadmapRef)); err != nil {
		fmt.Fprintf(os.Stderr, "group add: insert: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("group add: created %s (destination=%s priority=%d state=%s)\n", groupID, destination, priority, st)
	return exitOK
}

// ---- list ----

// groupListCmd implements `group list [--destination D] [--state S] --db <p>`.
// Read-only; prints every logic_groups row ordered by priority ASC then
// group_id ASC (§11.4.50 deterministic total order — the same order a later
// phase's assigner will consume, design §5).
func groupListCmd(args []string) int {
	fs := flag.NewFlagSet("group list", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	destFilter := fs.String("destination", "", "filter by destination (optional)")
	stateFilter := fs.String("state", "", "filter by state (optional)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "group list: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group list: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	groups, err := loadGroups(db, strings.TrimSpace(*destFilter), strings.TrimSpace(*stateFilter))
	if err != nil {
		fmt.Fprintf(os.Stderr, "group list: %v\n", err)
		return exitUsage
	}
	if len(groups) == 0 {
		fmt.Println("group list: no groups match")
		return exitOK
	}
	for _, g := range groups {
		fmt.Printf("%-28s  dest=%-20s  priority=%-4d  state=%-14s  %s\n",
			g.GroupID, g.Destination, g.Priority, g.State, g.Title)
	}
	return exitOK
}

// ---- set ----

// groupSetCmd implements the two-mode `group set`:
//
//	Mode A (edit a group's own fields):
//	  group set <group_id> [--title T] [--destination D] [--priority N]
//	            [--scope-note T] [--roadmap-ref T] --db <p>
//
//	Mode B (classify one item into a group — the items.logic_group /
//	items.destination write path the design requires):
//	  group set --item <ATM-ID> --group <group_id>
//	            [--location Issues|Fixed] --db <p>
//
// Mode is selected by the presence of --item (checked via fs.Visit, so it is
// unambiguous regardless of flag order).
func groupSetCmd(args []string) int {
	fs := flag.NewFlagSet("group set", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	title := fs.String("title", "", "new title")
	destination := fs.String("destination", "", "new destination: main | feature:<slug>")
	priority := fs.String("priority", "", "new priority (integer)")
	scopeNote := fs.String("scope-note", "", "new scope note")
	roadmapRef := fs.String("roadmap-ref", "", "new roadmap ref")
	item := fs.String("item", "", "Mode B: ATM-ID to classify into --group")
	groupFlag := fs.String("group", "", "Mode B: target group_id for --item")
	location := fs.String("location", "Issues", "Mode B: which tracker --item lives in: Issues | Fixed")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "group set: --db is required")
		return exitUsage
	}

	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { set[f.Name] = true })

	if set["item"] {
		if len(pos) > 0 {
			fmt.Fprintln(os.Stderr, "group set: --item (Mode B: item classification) does not take a positional <group_id> — use --group instead")
			return exitUsage
		}
		return groupSetItemMode(*dbPath, strings.TrimSpace(*item), strings.TrimSpace(*groupFlag), strings.TrimSpace(*location))
	}

	// ---- Mode A: group field edit ----
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "group set: missing positional <group_id> (or use --item for item-classification mode)")
		return exitUsage
	}
	groupID := strings.TrimSpace(pos[0])
	if !set["title"] && !set["destination"] && !set["priority"] && !set["scope-note"] && !set["roadmap-ref"] {
		fmt.Fprintln(os.Stderr, "group set: at least one mutable field flag is required (--title/--destination/--priority/--scope-note/--roadmap-ref)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	cur, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "group set: group %s not found\n", groupID)
		return exitUsage
	}

	if set["title"] {
		if strings.TrimSpace(*title) == "" {
			fmt.Fprintln(os.Stderr, "group set: --title cannot be empty")
			return exitUsage
		}
		cur.Title = *title
	}
	if set["destination"] {
		d := strings.TrimSpace(*destination)
		if !validDestination(d) {
			fmt.Fprintf(os.Stderr, "group set: --destination %q must be 'main' or 'feature:<slug>'\n", d)
			return exitUsage
		}
		cur.Destination = d
	}
	if set["priority"] {
		p, err := strconv.Atoi(strings.TrimSpace(*priority))
		if err != nil {
			fmt.Fprintf(os.Stderr, "group set: --priority %q must be an integer\n", *priority)
			return exitUsage
		}
		cur.Priority = p
	}
	if set["scope-note"] {
		cur.ScopeNote = *scopeNote
	}
	if set["roadmap-ref"] {
		cur.RoadmapRef = *roadmapRef
	}

	if _, err := db.Exec(`UPDATE logic_groups SET
		title=?, destination=?, priority=?, scope_note=?, roadmap_ref=?
		WHERE group_id=?`,
		cur.Title, cur.Destination, cur.Priority, nullable(cur.ScopeNote), nullable(cur.RoadmapRef), groupID); err != nil {
		fmt.Fprintf(os.Stderr, "group set: update: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("group set: %s updated (destination=%s priority=%d)\n", groupID, cur.Destination, cur.Priority)
	return exitOK
}

// groupSetItemMode implements Mode B: classify ONE item into a group,
// INHERITING the group's destination onto the item so design §3.1's
// destination-agreement invariant is satisfied STRUCTURALLY by every
// classification this command performs (there is no way to reach a
// disagreeing state through this path — the value is copied from the SAME
// row read inside the SAME call, never independently supplied).
func groupSetItemMode(dbPath, atmID, groupID, location string) int {
	if atmID == "" {
		fmt.Fprintln(os.Stderr, "group set: --item requires a non-empty ATM-ID")
		return exitUsage
	}
	if groupID == "" {
		fmt.Fprintln(os.Stderr, "group set: --item requires --group <group_id>")
		return exitUsage
	}
	loc := location
	if loc != "Issues" && loc != "Fixed" {
		fmt.Fprintln(os.Stderr, "group set: --location must be Issues or Fixed")
		return exitUsage
	}

	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	g, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: %v\n", err)
		return exitUsage
	}
	if g == nil {
		fmt.Fprintf(os.Stderr, "group set: group %s not found (referential integrity — classify into an existing group only)\n", groupID)
		return exitUsage
	}

	it, err := loadItem(db, atmID, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: %v\n", err)
		return exitUsage
	}
	if it == nil {
		fmt.Fprintf(os.Stderr, "group set: item %s not found in %s\n", atmID, loc)
		return exitUsage
	}

	res, err := db.Exec(`UPDATE items SET logic_group=?, destination=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=?`, groupID, g.Destination, atmID, loc)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group set: classify: %v\n", err)
		return exitUsage
	}
	if n, _ := res.RowsAffected(); n < 1 {
		fmt.Fprintf(os.Stderr, "group set: classify affected 0 rows for %s [%s]\n", atmID, loc)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("group set: classified %s -> group=%s destination=%s\n", atmID, groupID, g.Destination)
	return exitOK
}

// ---- state ----

// groupStateCmd implements `group state <group_id> <new_state> --db <p>`.
func groupStateCmd(args []string) int {
	fs := flag.NewFlagSet("group state", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 2 {
		fmt.Fprintln(os.Stderr, "group state: missing positional <group_id> <new_state>")
		return exitUsage
	}
	groupID := strings.TrimSpace(pos[0])
	newState := strings.TrimSpace(pos[1])
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "group state: --db is required")
		return exitUsage
	}
	if !groupStates[newState] {
		fmt.Fprintf(os.Stderr, "group state: <new_state> must be one of: %s\n", groupStateList())
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group state: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	g, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "group state: %v\n", err)
		return exitUsage
	}
	if g == nil {
		fmt.Fprintf(os.Stderr, "group state: group %s not found\n", groupID)
		return exitUsage
	}

	if _, err := db.Exec(`UPDATE logic_groups SET state=? WHERE group_id=?`, newState, groupID); err != nil {
		fmt.Fprintf(os.Stderr, "group state: update: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("group state: %s %s -> %s\n", groupID, g.State, newState)
	return exitOK
}

// ---- shared persistence + validation helpers ----

func groupExists(db *sql.DB, groupID string) (bool, error) {
	var n int
	err := db.QueryRow(`SELECT COUNT(1) FROM logic_groups WHERE group_id=?`, groupID).Scan(&n)
	return n > 0, err
}

// loadGroups returns logic_groups rows, optionally filtered by destination
// and/or state (empty string = no filter), ordered priority ASC then
// group_id ASC (§11.4.50 determinism).
func loadGroups(db *sql.DB, destFilter, stateFilter string) ([]logicGroup, error) {
	q := `SELECT group_id, title, destination, priority, state,
		COALESCE(scope_note,''), COALESCE(roadmap_ref,'')
		FROM logic_groups WHERE 1=1`
	var qargs []any
	if destFilter != "" {
		q += ` AND destination = ?`
		qargs = append(qargs, destFilter)
	}
	if stateFilter != "" {
		q += ` AND state = ?`
		qargs = append(qargs, stateFilter)
	}
	q += ` ORDER BY priority ASC, group_id ASC`
	rows, err := db.Query(q, qargs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []logicGroup
	for rows.Next() {
		var g logicGroup
		if err := rows.Scan(&g.GroupID, &g.Title, &g.Destination, &g.Priority, &g.State, &g.ScopeNote, &g.RoadmapRef); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// loadGroup returns the single logic_groups row for groupID, or nil if absent.
func loadGroup(db *sql.DB, groupID string) (*logicGroup, error) {
	var g logicGroup
	err := db.QueryRow(`SELECT group_id, title, destination, priority, state,
		COALESCE(scope_note,''), COALESCE(roadmap_ref,'')
		FROM logic_groups WHERE group_id=?`, groupID).
		Scan(&g.GroupID, &g.Title, &g.Destination, &g.Priority, &g.State, &g.ScopeNote, &g.RoadmapRef)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &g, nil
}

// validGroupID enforces §11.4.29 lowercase snake/kebab for group_id: lowercase
// ASCII letters, digits, and hyphens only (matches design §3.2's examples:
// 'mistiq-vader-rebrand', 'audio-5.1-multichannel' — NOTE: '.' is therefore
// intentionally also accepted so 'audio-5.1-multichannel' itself validates).
func validGroupID(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.' {
			continue
		}
		return false
	}
	return true
}

// validDestination enforces design §3.1's destination domain: 'main' or
// 'feature:<slug>' where slug is itself lowercase snake/kebab per §11.4.29.
func validDestination(s string) bool {
	if s == "main" {
		return true
	}
	if strings.HasPrefix(s, "feature:") {
		return validGroupID(strings.TrimPrefix(s, "feature:"))
	}
	return false
}
