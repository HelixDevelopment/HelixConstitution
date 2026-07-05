// assign.go — the `assign` subcommand family: next-group | next-item |
// group-complete.
//
// docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §5 (assigner algorithm) + §4
// (group lifecycle / group-complete gate) + §11.4.176/§11.4.119/§11.4.111
// (mechanism authority). Phase P3 of docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md,
// built atop P2's group.go (logicGroup, loadGroup/loadGroups,
// validGroupID/validDestination) and validate_groups.go (openItemStatuses,
// isUrgentItem, critRank) — REUSED verbatim, never re-derived (§11.4.6: the
// Go validator/assigner and the bash orchestrator must never silently
// disagree on what "open" or "urgent" means for the same value).
//
//	assign next-group --track T --destinations D1[,D2,...] --claim-script <path>
//	                   [--ttl SEC] --db <p>
//	assign next-item --track T --group <group_id> [--exclude ID1[,ID2,...]] --db <p>
//	assign group-complete <group_id> --db <p>
//
// §11.4.28 decoupling: this Go package is a UNIVERSAL, project-agnostic
// binary — it MUST NOT hardcode a path to any project's claim-registry
// script (design §8: multitrack_claim.sh is a PROJECT-layer §11.4.176-A
// instantiation living at <project_root>/scripts/multitrack/, NOT part of
// this constitution submodule) nor a project's track<->destination binding
// (design §3.3: PROJECT data, e.g. .ws_state/track_orchestration.tsv). Both
// are therefore REQUIRED explicit inputs (--claim-script, --destinations)
// supplied by the caller (a future project-side orchestrator, design §8 /
// plan P6) — never a baked-in default.
package main

import (
	"bytes"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

// exitNoCandidate signals "nothing actionable right now" — a LEGITIMATE,
// non-error outcome (§11.4.94: a track idles ONLY when no candidate exists;
// this is that observable signal), deliberately DISTINCT from exitOK (a
// candidate WAS claimed/found) and exitUsage (a genuine usage/internal
// error or an outright refusal). Chosen to match multitrack_claim.sh's own
// EBUSY/not-claimed convention (exit 3) for a consistent 3-way signal
// across the pipeline (0 = got one, 1 = broken invocation / refused, 3 =
// nothing right now).
const exitNoCandidate = 3

// runAssign dispatches the `assign` subcommand group (next-group | next-item
// | group-complete), mirroring runGroup's (group.go) dispatcher shape.
func runAssign(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "assign: missing subcommand (next-group | next-item | group-complete)")
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "next-group":
		os.Exit(assignNextGroupCmd(args[1:]))
	case "next-item":
		os.Exit(assignNextItemCmd(args[1:]))
	case "group-complete":
		os.Exit(assignGroupCompleteCmd(args[1:]))
	default:
		fmt.Fprintf(os.Stderr, "assign: unknown subcommand: %s (want next-group | next-item | group-complete)\n", args[0])
		os.Exit(exitUsage)
	}
}

// ---- next-group ----

// groupCandidate is one logic_groups row augmented with a LIVE
// (recomputed-per-call, never persisted) aggregate over its OPEN member
// items: the highest §11.4.111-stable crit rank among them. This is design
// §5's "max_member_severity DESC" ordering key — deliberately NOT stored on
// logic_groups (it changes the instant any member's status/severity
// changes; persisting it would immediately go stale — the same
// resolve-by-stable-identity lesson §11.4.111 teaches about enumeration
// indices applies equally to a derived aggregate).
type groupCandidate struct {
	logicGroup
	maxSeverity int
}

// candidateGroups implements design §5's assign_next_group candidate query,
// DB-side only (no claim-registry interaction — that is assignNextGroupCmd's
// job, so this half is unit-testable without exec'ing any external
// process):
//
//	SELECT group_id FROM logic_groups
//	WHERE destination IN destinations_served_by(track)
//	  AND state IN ('open','in-progress')
//	  AND EXISTS(open member item)
//	ORDER BY priority ASC, max_member_severity DESC, group_id ASC
//
// The design's "group_id NOT IN (claims held by ANOTHER live track)" clause
// is deliberately NOT applied here: design §5's own FOR-loop already
// enforces it by attempting a claim per candidate in priority order and
// falling through on EBUSY (exit 3, assignNextGroupCmd) — a pre-filter here
// would itself need to query the claim registry's live state (another
// exec), duplicating work the try-claim loop already performs atomically
// and authoritatively via the SAME flock critical section that guarantees
// exactly-once (§11.4.176-A).
func candidateGroups(db *sql.DB, destinations []string) ([]groupCandidate, error) {
	groups, err := loadGroups(db, "", "")
	if err != nil {
		return nil, fmt.Errorf("load groups: %w", err)
	}
	items, err := loadItems(db)
	if err != nil {
		return nil, fmt.Errorf("load items: %w", err)
	}

	destSet := make(map[string]bool, len(destinations))
	for _, d := range destinations {
		destSet[d] = true
	}

	// openItemStatuses / critRank are validate_groups.go's design §3.1 /
	// §5.1 closed-set + severity-rank functions, reused verbatim (§11.4.6).
	hasOpen := map[string]bool{}
	maxSev := map[string]int{}
	for _, it := range items {
		lg := strings.TrimSpace(it.LogicGroup)
		if lg == "" || !openItemStatuses[it.Status] {
			continue
		}
		hasOpen[lg] = true
		if r := critRank(it.Severity); r > maxSev[lg] {
			maxSev[lg] = r
		}
	}

	stateEligible := map[string]bool{"open": true, "in-progress": true}

	var out []groupCandidate
	for _, g := range groups {
		if !destSet[g.Destination] {
			continue
		}
		if !stateEligible[g.State] {
			continue
		}
		if !hasOpen[g.GroupID] {
			continue
		}
		out = append(out, groupCandidate{logicGroup: g, maxSeverity: maxSev[g.GroupID]})
	}

	// §11.4.50 deterministic total order: priority ASC, max_member_severity
	// DESC, group_id ASC. group_id alone is already a strict total order
	// (logic_groups.group_id is a PRIMARY KEY), so this comparator produces
	// an identical result across any number of repeated runs on the same
	// data — no coin-flip tie ever reaches the caller.
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Priority != out[j].Priority {
			return out[i].Priority < out[j].Priority
		}
		if out[i].maxSeverity != out[j].maxSeverity {
			return out[i].maxSeverity > out[j].maxSeverity
		}
		return out[i].GroupID < out[j].GroupID
	})
	return out, nil
}

// assignNextGroupCmd implements `assign next-group --track T --destinations
// D1[,D2,...] --claim-script <path> [--ttl SEC] --db <p>` — design §5's
// assign_next_group(track): priority-ordered candidate pick + exactly-once
// claim via the §11.4.176-A registry (multitrack_claim.sh, or any
// project-supplied claim CLI honouring the SAME `claim <id> <owner>`
// exit-code contract: 0 claimed/idempotent-refresh, 3 EBUSY/held-by-another,
// anything else a genuine error).
func assignNextGroupCmd(args []string) int {
	fs := flag.NewFlagSet("assign next-group", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	track := fs.String("track", "", "the track id claiming a group (e.g. track-1)")
	destinations := fs.String("destinations", "", "comma-separated destinations this track serves (design §3.3 track<->group binding — PROJECT-supplied, never hardcoded here)")
	claimScript := fs.String("claim-script", "", "path to the §11.4.176-A exactly-once claim CLI (e.g. scripts/multitrack/multitrack_claim.sh) honouring its claim/exit-code contract")
	ttl := fs.String("ttl", "", "optional claim TTL seconds forwarded to the claim script's --ttl (omitted = claim script's own default)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "assign next-group: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*track) == "" {
		fmt.Fprintln(os.Stderr, "assign next-group: --track is required")
		return exitUsage
	}
	destList := splitCSV(*destinations)
	if len(destList) == 0 {
		fmt.Fprintln(os.Stderr, "assign next-group: --destinations is required (comma-separated, non-empty — design §3.3)")
		return exitUsage
	}
	if strings.TrimSpace(*claimScript) == "" {
		fmt.Fprintln(os.Stderr, "assign next-group: --claim-script is required (§11.4.176-A exactly-once claim CLI path)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign next-group: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	candidates, err := candidateGroups(db, destList)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign next-group: %v\n", err)
		return exitUsage
	}

	for _, c := range candidates {
		code, stderr, runErr := runClaimScript(*claimScript, c.GroupID, *track, *ttl)
		if runErr != nil {
			fmt.Fprintf(os.Stderr, "assign next-group: claim-script invocation failed for %s: %v\n", c.GroupID, runErr)
			return exitUsage
		}
		switch code {
		case 0:
			// Claimed (or idempotent refresh — same track re-claiming its
			// own group). Advance the group's lifecycle state (design §4);
			// harmless/idempotent if it was already in-progress.
			if _, err := db.Exec(`UPDATE logic_groups SET state='in-progress' WHERE group_id=?`, c.GroupID); err != nil {
				fmt.Fprintf(os.Stderr, "assign next-group: claimed %s (track %s) via the exactly-once registry, but failed to record state=in-progress locally: %v — the external claim IS held; reconcile logic_groups.state for %s manually before retrying\n",
					c.GroupID, *track, err, c.GroupID)
				return exitUsage
			}
			fmt.Printf("NEXT-GROUP: %s -> track %s (destination=%s priority=%d)\n", c.GroupID, *track, c.Destination, c.Priority)
			return exitOK
		case 3:
			// EBUSY — another track holds this candidate; try the next
			// priority-ordered candidate (design §5's documented
			// fallthrough — the mutual-exclusion property comes from HERE,
			// not from a pre-filter on the SQL side).
			continue
		default:
			fmt.Fprintf(os.Stderr, "assign next-group: claim-script exited %d for %s (want 0 claimed or 3 EBUSY): %s\n", code, c.GroupID, stderr)
			return exitUsage
		}
	}

	fmt.Printf("NEXT-GROUP: no candidate group available for track %s (destinations=%s) right now\n", *track, strings.Join(destList, ","))
	return exitNoCandidate
}

// runClaimScript execs `<scriptPath> claim <groupID> <track> [--ttl <ttl>]`
// and classifies the outcome. Returns (exitCode, capturedStderr, err) where
// err is non-nil ONLY for a genuine invocation failure (script missing / not
// executable / etc.) — a normal 0 or 3 exit is reported via exitCode with
// err==nil, exactly what assignNextGroupCmd's switch expects.
func runClaimScript(scriptPath, groupID, track, ttl string) (int, string, error) {
	claimArgs := []string{"claim", groupID, track}
	if strings.TrimSpace(ttl) != "" {
		claimArgs = append(claimArgs, "--ttl", ttl)
	}
	cmd := exec.Command(scriptPath, claimArgs...)
	var stderrBuf bytes.Buffer
	cmd.Stderr = &stderrBuf
	runErr := cmd.Run()
	if runErr == nil {
		return 0, stderrBuf.String(), nil
	}
	var exitErr *exec.ExitError
	if errors.As(runErr, &exitErr) {
		return exitErr.ExitCode(), stderrBuf.String(), nil
	}
	return -1, stderrBuf.String(), runErr
}

// splitCSV splits a comma-separated flag value into trimmed, non-empty
// tokens. An empty/whitespace-only input yields a nil slice (callers test
// len()==0 to detect "nothing supplied").
func splitCSV(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	var out []string
	for _, part := range strings.Split(s, ",") {
		p := strings.TrimSpace(part)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// ---- next-item ----

// assignNextItemCmd implements `assign next-item --track T --group
// <group_id> [--exclude ID1[,ID2,...]] --db <p>` — design §5's
// next_item_in_group(track, g): select the next open member item of a
// GIVEN, STORED group by (crit DESC, atm_id ASC). `--group` mirrors design
// §5's own function signature, `next_item_in_group(track, g)`, which takes
// g as an explicit parameter — the caller (a future project-side
// orchestrator, plan P6) already knows which group its track claimed (it
// either called `assign next-group` and got the answer back, or reads its
// own `.ws_state/track_orchestration.tsv`), so re-deriving "track T's
// current group" INSIDE this Go layer (e.g. by shelling out to the claim
// registry's `status`/`owner` verbs and parsing them) would be a needless,
// fragile extra hop for zero added correctness.
//
// §11.4.6 honest gap: design §5's pseudocode ALSO orders by `quick_win ASC`
// and filters `NOT IN (track_done.list)` — NEITHER has a concrete schema
// definition anywhere in this codebase (no `quick_win` column exists on
// `items`; no `track_done` table/mechanism exists anywhere). Inventing
// either would be guessing (§11.4.6). `quick_win` is UNCONFIRMED/omitted
// pending a future concrete definition (e.g. an estimated-effort column not
// yet in schema). `track_done.list`'s INTENT — do not re-offer an item the
// calling track already knows about / has already picked this pass — is
// implemented HONESTLY via the caller-supplied --exclude flag rather than a
// fabricated DB mechanism.
func assignNextItemCmd(args []string) int {
	fs := flag.NewFlagSet("assign next-item", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	track := fs.String("track", "", "the track id this pick is for (audit/logging only — selection is entirely by --group)")
	group := fs.String("group", "", "the STORED logic_group to select the next open member item from (design §5 — never a substring re-derivation)")
	exclude := fs.String("exclude", "", "comma-separated ATM-IDs to skip (caller-tracked already-picked/track_done items — see design §5's track_done.list, honestly implemented as an explicit input)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "assign next-item: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*track) == "" {
		fmt.Fprintln(os.Stderr, "assign next-item: --track is required")
		return exitUsage
	}
	groupID := strings.TrimSpace(*group)
	if groupID == "" {
		fmt.Fprintln(os.Stderr, "assign next-item: --group is required (the track's already-claimed group_id)")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign next-item: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	g, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign next-item: %v\n", err)
		return exitUsage
	}
	if g == nil {
		fmt.Fprintf(os.Stderr, "assign next-item: group %s not found\n", groupID)
		return exitUsage
	}

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign next-item: %v\n", err)
		return exitUsage
	}

	excludeSet := map[string]bool{}
	for _, id := range splitCSV(*exclude) {
		excludeSet[id] = true
	}

	// THE anti-defect fix, verbatim per design §5: selection reads the
	// STORED items.logic_group column ONLY — it never re-derives group
	// membership from title/description substrings, so a branch-name (or
	// any other free-text) mention in an item's description can no longer
	// silently move that item's lane (the ATM-633 class of defect, design
	// §2.2).
	var candidates []item
	for _, it := range items {
		if it.LogicGroup != groupID {
			continue
		}
		if !openItemStatuses[it.Status] {
			continue
		}
		if excludeSet[it.AtmID] {
			continue
		}
		candidates = append(candidates, it)
	}

	// §11.4.50 deterministic total order: crit DESC, atm_id ASC. atm_id
	// alone is already a strict total order across the rows of ONE group in
	// a validate-groups-clean DB (the single-valued invariant means at most
	// one row per atm_id carries this group_id), so this ordering is fully
	// deterministic across any number of repeated calls.
	sort.SliceStable(candidates, func(i, j int) bool {
		ri, rj := critRank(candidates[i].Severity), critRank(candidates[j].Severity)
		if ri != rj {
			return ri > rj
		}
		return candidates[i].AtmID < candidates[j].AtmID
	})

	if len(candidates) == 0 {
		fmt.Printf("NEXT-ITEM: no open item in group %s for track %s right now\n", groupID, *track)
		return exitNoCandidate
	}
	w := candidates[0]
	fmt.Printf("NEXT-ITEM: %s [%s/%s] type=%s status=%s severity=%s title=%s\n",
		w.AtmID, w.CurrentLocation, w.repOrDefault(), w.Type, w.Status, w.Severity, w.Title)
	return exitOK
}

// ---- group-complete ----

// terminalItemStatuses is the §11.4.33 closed-set of terminal closure
// values an item's `status` column carries once "done" — the EXACT four
// literal strings the schema's CHECK constraint (schema_embed.sql:36-41) and
// crud.go's closeStatusMap already use, cited rather than re-derived
// (§11.4.6).
var terminalItemStatuses = map[string]bool{
	"Fixed (→ Fixed.md)":       true,
	"Implemented (→ Fixed.md)": true,
	"Completed (→ Fixed.md)":   true,
	"Obsolete (→ Fixed.md)":    true,
}

// hasClosureEvidence reports whether item_history carries at least one
// closure event (Fixed/Implemented/Completed/Obsolete) for atmID with a
// non-empty evidence_path — the mechanically-checkable proxy for design
// §4's "captured evidence per member (§11.4.5/§11.4.69) in test_diary"
// requirement, using the SAME evidence trail crud.go's `close` subcommand
// ALREADY mandates (`close` refuses without --evidence, crud.go:214-217)
// rather than inventing a new table for this phase.
func hasClosureEvidence(db *sql.DB, atmID string) (bool, error) {
	var n int
	err := db.QueryRow(`SELECT COUNT(1) FROM item_history
		WHERE atm_id=? AND event_type IN ('Fixed','Implemented','Completed','Obsolete')
		  AND evidence_path IS NOT NULL AND TRIM(evidence_path) != ''`, atmID).Scan(&n)
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

// assignGroupCompleteCmd implements `assign group-complete <group_id> --db
// <p>` — design §4's group-atomic completion gate, THE
// "terminal-with-evidence" sub-check: refuses (non-zero) unless EVERY
// member item (every items row whose logic_group == group_id, across every
// current_location/representation) carries a terminal §11.4.33 status AND
// has a captured-evidence closure event recorded in item_history.
//
// §11.4.6 honest boundary: design §4 ALSO requires "the group's destination
// merge is confirmed on the target branch" — this phase does NOT implement
// that half. No concrete, mechanically-checkable git-merge-verification
// procedure is specified anywhere in the design; fabricating one (e.g.
// trusting the free-text `commit_ref` column as proof of a MERGED,
// on-target-branch commit) would be exactly the guess §11.4.6 forbids. This
// gap is tracked, not silently bluffed — design §11 already flags several
// operator-input-needed risks in the same vein; a concrete merge-
// verification mechanism is a later phase's job.
func assignGroupCompleteCmd(args []string) int {
	fs := flag.NewFlagSet("assign group-complete", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "assign group-complete: missing positional <group_id>")
		return exitUsage
	}
	groupID := strings.TrimSpace(pos[0])
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "assign group-complete: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign group-complete: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	g, err := loadGroup(db, groupID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign group-complete: %v\n", err)
		return exitUsage
	}
	if g == nil {
		fmt.Fprintf(os.Stderr, "assign group-complete: group %s not found\n", groupID)
		return exitUsage
	}

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "assign group-complete: %v\n", err)
		return exitUsage
	}

	var members []item
	for _, it := range items {
		if it.LogicGroup == groupID {
			members = append(members, it)
		}
	}
	if len(members) == 0 {
		fmt.Fprintf(os.Stderr, "assign group-complete: group %s has zero classified members — nothing to complete (classify at least one item first)\n", groupID)
		return exitUsage
	}

	var violations []string
	for _, m := range members {
		loc := m.CurrentLocation + "/" + m.repOrDefault()
		if !terminalItemStatuses[m.Status] {
			violations = append(violations, fmt.Sprintf("%s [%s]: not terminal (status=%q)", m.AtmID, loc, m.Status))
			continue
		}
		hasEvidence, err := hasClosureEvidence(db, m.AtmID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "assign group-complete: %v\n", err)
			return exitUsage
		}
		if !hasEvidence {
			violations = append(violations, fmt.Sprintf("%s [%s]: terminal but no captured-evidence closure event in item_history (status=%q)", m.AtmID, loc, m.Status))
		}
	}

	if len(violations) > 0 {
		sort.Strings(violations)
		fmt.Fprintf(os.Stderr, "assign group-complete: %s NOT complete — %d member violation(s):\n", groupID, len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		return exitUsage
	}

	if _, err := db.Exec(`UPDATE logic_groups SET state='group-complete' WHERE group_id=?`, groupID); err != nil {
		fmt.Fprintf(os.Stderr, "assign group-complete: %v\n", err)
		return exitUsage
	}
	walCheckpoint(db)

	fmt.Printf("assign group-complete: %s -> group-complete (%d member(s) all terminal-with-evidence)\n", groupID, len(members))
	return exitOK
}
