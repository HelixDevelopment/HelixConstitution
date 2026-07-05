// validate_groups.go — the `validate-groups` subcommand.
//
// Enforces docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §3.1's five group-atomic
// invariants over the live DB, read-only, mirroring sync.go's validateCmd
// pattern (accumulate violation strings, sorted deterministic output, non-zero
// exit on ANY violation — never a bluff PASS on a corrupted assignment state).
//
// Five invariants (§3.1, each check cites the design section verbatim):
//  1. single-valued         — an item can NEVER be in two groups.
//  2. destination-agreement — item.destination MUST equal its group's
//     destination (a group is homogeneous in destination).
//  3. totality (open items) — every item whose status is one of
//     {Queued, In progress, Reopened} MUST have non-null logic_group AND
//     non-null destination.
//  4. referential           — item.logic_group MUST exist in logic_groups.
//  5. urgent-routing         — crash/ANR/high-severity items MUST route to
//     destination=main + logic_group=urgent-main (design §5.1).
//
// §1.1 anti-bluff note: each check below is independently defeatable by a
// single-line mutation (weakening/removing its `violations = append(...)`
// call or its guarding condition) — validate_groups_test.go's paired
// positive/negative fixtures are exactly the harness such a mutation would
// break (the negative fixture would stop failing). A future phase's
// meta_test_false_positive_proof.sh formalises these as gate mutations; this
// phase supplies the invariant + its test-level proof.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

// openItemStatuses is design §3.1's "Totality (open items)" closed set, cited
// VERBATIM from the design doc — NOT the full §11.4.15 open-status
// vocabulary (which also includes Ready for testing / In testing /
// Operator-blocked, deliberately excluded from THIS invariant by §3.1's own
// text: "every item whose `status ∈ {Queued, In progress, Reopened}`").
var openItemStatuses = map[string]bool{
	"Queued":      true,
	"In progress": true,
	"Reopened":    true,
}

// urgentSignalWords is design §5.1's title/forensic_anchor substring set:
// "title/`forensic_anchor` contains `ANR`/`crash`/`tombstone`/`boot-loop`/
// `crash-loop`" (case-insensitive substring match).
var urgentSignalWords = []string{"anr", "crash", "tombstone", "boot-loop", "crash-loop"}

// runValidateGroups mirrors runValidate's os.Exit(...Cmd(args)) wrapper shape.
func runValidateGroups(args []string) {
	os.Exit(validateGroupsCmd(args))
}

// validateGroupsCmd implements `validate-groups --db <p>`.
func validateGroupsCmd(args []string) int {
	fs := flag.NewFlagSet("validate-groups", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "validate-groups: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate-groups: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate-groups: %v\n", err)
		return exitUsage
	}
	groups, err := loadGroups(db, "", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate-groups: %v\n", err)
		return exitUsage
	}
	groupByID := make(map[string]logicGroup, len(groups))
	for _, g := range groups {
		groupByID[g.GroupID] = g
	}

	var violations []string

	// ---- (1) single-valued: "an item can NEVER be in two groups" (§3.1) ----
	// Collected per atm_id across ALL its rows (any current_location /
	// representation — the same atm_id legitimately appears twice per the
	// §11.4.19 tombstone pattern and the GAP-A dual-representation case). The
	// same logical item carrying TWO DIFFERENT non-null logic_group values
	// across its rows IS "being in two groups at once" — exactly what this
	// invariant forbids. §1.1 mutation: deleting this block (or relaxing
	// `len(set) > 1` to always false) makes
	// TestValidateGroups_SingleValued_Negative stop failing.
	byAtmID := map[string]map[string]bool{}
	for _, it := range items {
		lg := strings.TrimSpace(it.LogicGroup)
		if lg == "" {
			continue
		}
		if byAtmID[it.AtmID] == nil {
			byAtmID[it.AtmID] = map[string]bool{}
		}
		byAtmID[it.AtmID][lg] = true
	}
	{
		var atmIDs []string
		for id := range byAtmID {
			atmIDs = append(atmIDs, id)
		}
		sort.Strings(atmIDs) // deterministic iteration (§11.4.50)
		for _, atmID := range atmIDs {
			set := byAtmID[atmID]
			if len(set) > 1 {
				var vals []string
				for v := range set {
					vals = append(vals, v)
				}
				sort.Strings(vals)
				violations = append(violations, fmt.Sprintf(
					"%s: single-valued violation — item classified into %d distinct groups across its rows: %s (design §3.1)",
					atmID, len(vals), strings.Join(vals, ", ")))
			}
		}
	}

	for _, it := range items {
		lg := strings.TrimSpace(it.LogicGroup)
		dest := strings.TrimSpace(it.Destination)
		loc := it.CurrentLocation + "/" + it.repOrDefault()

		// ---- (4) referential: "item.logic_group ∈ logic_groups" (§3.1) ----
		// §1.1 mutation: removing this `if !ok` branch (or the `groupFound`
		// guard below) makes TestValidateGroups_Referential_Negative stop
		// failing.
		var g logicGroup
		groupFound := false
		if lg != "" {
			if gg, ok := groupByID[lg]; ok {
				g = gg
				groupFound = true
			} else {
				violations = append(violations, fmt.Sprintf(
					"%s [%s]: referential-integrity violation — logic_group %q not found in logic_groups (design §3.1)",
					it.AtmID, loc, lg))
			}
		}

		// ---- (2) destination-agreement: "item.destination == its group's
		// destination" (§3.1). Only meaningful once the group actually
		// resolved (4) — an unresolved logic_group would otherwise compare
		// against the zero-value logicGroup{}, producing a misleading
		// secondary message for the SAME root cause referential already
		// reported. §1.1 mutation: comparing dest to any fixed literal
		// (e.g. "main") instead of g.Destination makes
		// TestValidateGroups_DestinationAgreement_Negative stop failing.
		if lg != "" && dest != "" && groupFound {
			if dest != g.Destination {
				violations = append(violations, fmt.Sprintf(
					"%s [%s]: destination-agreement violation — item.destination=%q but group %q has destination=%q (design §3.1)",
					it.AtmID, loc, dest, lg, g.Destination))
			}
		}

		// ---- (3) totality (open items): "every item whose status ∈
		// {Queued, In progress, Reopened} MUST have a non-null logic_group +
		// destination" (§3.1). §1.1 mutation: removing this block (or the
		// openItemStatuses[it.Status] guard) makes
		// TestValidateGroups_Totality_Negative stop failing.
		if openItemStatuses[it.Status] {
			if lg == "" || dest == "" {
				violations = append(violations, fmt.Sprintf(
					"%s [%s]: totality violation — open item (status=%q) missing logic_group=%q / destination=%q (design §3.1)",
					it.AtmID, loc, it.Status, lg, dest))
			}
		}

		// ---- (5) urgent-routing: "crash/ANR/high-sev items ALWAYS →
		// destination=main, highest priority" / "written destination=main,
		// logic_group=urgent-main" (design §1.3 / §5.1). Fires per-field
		// (independently on destination and on logic_group) so a PARTIALLY
		// misclassified urgent item (one field right, one wrong) is still
		// caught; an UNCLASSIFIED urgent item (both fields empty) is caught
		// by totality above instead (if open) — never double-reported here.
		// §1.1 mutation: removing either `if` below makes
		// TestValidateGroups_UrgentRouting_Negative stop failing.
		if isUrgentItem(it) {
			if dest != "" && dest != "main" {
				violations = append(violations, fmt.Sprintf(
					"%s [%s]: urgent-routing violation — urgent item (severity=%q, title=%q) has destination=%q, want main (design §5.1)",
					it.AtmID, loc, it.Severity, it.Title, dest))
			}
			if lg != "" && lg != "urgent-main" {
				violations = append(violations, fmt.Sprintf(
					"%s [%s]: urgent-routing violation — urgent item (severity=%q, title=%q) has logic_group=%q, want urgent-main (design §5.1)",
					it.AtmID, loc, it.Severity, it.Title, lg))
			}
		}
	}

	if len(violations) > 0 {
		sort.Strings(violations)
		fmt.Fprintf(os.Stderr, "validate-groups: %d violation(s):\n", len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		return exitUsage
	}
	fmt.Printf("validate-groups: OK — %d items, %d groups, all design §3.1 invariants satisfied\n", len(items), len(groups))
	return exitOK
}

// isUrgentItem implements design §5.1's urgent-routing predicate: an item is
// urgent iff its severity ranks >=3 on the EXISTING ORCH_CRIT scale (mirrored
// from scripts/multitrack/track_orchestrator.sh:485-490 — crit=4 for
// 'critical'/'c (...'/'c', crit=3 for 'high'/'p1'/'major'; design's "crit≥3 =
// high/critical" is exactly this pair of tiers) OR its title/forensic_anchor
// contains one of the ANR/crash/tombstone/boot-loop/crash-loop signal words
// (case-insensitive substring, §5.1). Ported deliberately from the ALREADY
// EXISTING bash SQL CASE rather than re-derived, so the Go validator and the
// bash orchestrator can never silently disagree on what "urgent" means for
// the SAME severity free-text value (§11.4.6 — no re-guessed mapping).
func isUrgentItem(it item) bool {
	if critRank(it.Severity) >= 3 {
		return true
	}
	if containsAnyUrgentSignal(it.Title) || containsAnyUrgentSignal(it.ForensicAnchor) {
		return true
	}
	return false
}

// critRank mirrors scripts/multitrack/track_orchestrator.sh's ORCH_CRIT SQL
// CASE expression (lines 485-490) verbatim:
//
//	4  lower(severity) LIKE 'critical%' OR 'c (%' OR = 'c'
//	3  lower(severity) LIKE 'high%' OR 'p1%' OR 'major%'
//	2  lower(severity) LIKE 'medium%' OR 'med%' OR 'normal%' OR 'p2%'
//	1  lower(severity) LIKE 'low%' OR 'minor%'
//	0  else (unknown/empty)
func critRank(severity string) int {
	s := strings.ToLower(strings.TrimSpace(severity))
	switch {
	case strings.HasPrefix(s, "critical"), strings.HasPrefix(s, "c ("), s == "c":
		return 4
	case strings.HasPrefix(s, "high"), strings.HasPrefix(s, "p1"), strings.HasPrefix(s, "major"):
		return 3
	case strings.HasPrefix(s, "medium"), strings.HasPrefix(s, "med"), strings.HasPrefix(s, "normal"), strings.HasPrefix(s, "p2"):
		return 2
	case strings.HasPrefix(s, "low"), strings.HasPrefix(s, "minor"):
		return 1
	default:
		return 0
	}
}

// containsAnyUrgentSignal reports whether s (case-insensitive) contains any
// of design §5.1's urgent signal words.
func containsAnyUrgentSignal(s string) bool {
	ls := strings.ToLower(s)
	for _, w := range urgentSignalWords {
		if strings.Contains(ls, w) {
			return true
		}
	}
	return false
}
