// classify.go — the `classify --propose` subcommand.
//
// docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §9 (classification approach for
// all 415 items) + §11.4.6 (no-guessing — explicit-membership-first, NEVER
// substring-against-free-text). Phase P3 of
// docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md.
//
//	classify --propose --db <p> --out <path-prefix>
//
// Writes <prefix>.md + <prefix>.tsv — a REVIEW file only; classify NEVER
// writes the DB. Design §9 step 1: "reads, per item, only structured
// signals ... and (as a WEAK hint only, field-scoped to `title`, never
// `description`) topic keywords". THIS IS THE ANTI-DEFECT REQUIREMENT: the
// historical bug (ATM-633, design §2.2) happened because the OLD
// substring-matching selector scanned `description` too — a branch-name
// mention in its description alone dragged an infra ticket into the wrong
// lane. classify NEVER reads `description` for keyword matching; only
// `title` (mirrored by isUrgentItem's existing title+forensic_anchor+
// severity scoping in validate_groups.go, reused verbatim here).
//
// Design §9 step 3 (`workable-items group set --from <reviewed.tsv>` —
// APPLYING a reviewed proposal to the DB) is explicitly OUT of this phase's
// scope: docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md's P3 subcommand list is
// `assign {next-group,next-item,group-complete}` + `classify --propose`
// only — no "apply" verb.
package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// classificationProposal is one proposed row of the design §9 review file.
type classificationProposal struct {
	AtmID       string
	Location    string
	Repr        string
	Title       string
	LogicGroup  string
	Destination string
	Confidence  string // closed-set: high | medium | low | none
	Signal      string // the structured signal (or its absence) that drove the proposal — audit trail
}

// classificationConfidence is the closed-set of confidence labels classify
// may emit (§11.4.6 — a fixed, auditable vocabulary, never a free-text
// score). Asserted against by classify_test.go's
// TestClassify_EveryProposalHasClosedSetConfidence so the set can never
// silently drift from what proposeFor actually emits.
var classificationConfidence = map[string]bool{"high": true, "medium": true, "low": true, "none": true}

// runClassify implements `classify --propose --db <p> --out <path-prefix>`.
func runClassify(args []string) {
	os.Exit(classifyCmd(args))
}

func classifyCmd(args []string) int {
	fs := flag.NewFlagSet("classify", flag.ContinueOnError)
	propose := fs.Bool("propose", false, "propose logic_group/destination classifications for every currently-unclassified item (design §9); writes a review file, NEVER the DB")
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	out := fs.String("out", "group_classification_proposal", "output path PREFIX — writes <prefix>.md + <prefix>.tsv (design §9; project callers pass e.g. docs/tracks/group_classification_proposal)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if !*propose {
		fmt.Fprintln(os.Stderr, "classify: --propose is required (the only supported mode this phase implements — design §9 step 1)")
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "classify: --db is required")
		return exitUsage
	}
	if strings.TrimSpace(*out) == "" {
		fmt.Fprintln(os.Stderr, "classify: --out must be non-empty")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "classify: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	groups, err := loadGroups(db, "", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "classify: %v\n", err)
		return exitUsage
	}
	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "classify: %v\n", err)
		return exitUsage
	}
	parentOf, err := parentAtmIDs(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "classify: %v\n", err)
		return exitUsage
	}

	groupByID := make(map[string]logicGroup, len(groups))
	for _, g := range groups {
		groupByID[g.GroupID] = g
	}
	// classifiedByID: any ALREADY-classified atm_id -> its logic_group,
	// scanned across every row/location/representation. A
	// validate-groups-clean DB guarantees single-valued consistency here;
	// classify itself does not re-validate that invariant — validate-groups
	// (P2) already owns it.
	classifiedByID := map[string]string{}
	for _, it := range items {
		if lg := strings.TrimSpace(it.LogicGroup); lg != "" {
			if _, ok := classifiedByID[it.AtmID]; !ok {
				classifiedByID[it.AtmID] = lg
			}
		}
	}

	var proposals []classificationProposal
	for _, it := range items {
		if strings.TrimSpace(it.LogicGroup) != "" {
			continue // already classified — one-time seeding targets unclassified items only
		}
		proposals = append(proposals, proposeFor(it, groups, groupByID, classifiedByID, parentOf))
	}

	// §11.4.50 deterministic output order: atm_id ASC, then location, then
	// representation — the full 3-tuple mirrors the items PRIMARY KEY, a
	// strict total order (atm_id alone is not globally unique across
	// locations/representations).
	sort.SliceStable(proposals, func(i, j int) bool {
		if proposals[i].AtmID != proposals[j].AtmID {
			return proposals[i].AtmID < proposals[j].AtmID
		}
		if proposals[i].Location != proposals[j].Location {
			return proposals[i].Location < proposals[j].Location
		}
		return proposals[i].Repr < proposals[j].Repr
	})

	if err := writeProposalTSV(*out+".tsv", proposals); err != nil {
		fmt.Fprintf(os.Stderr, "classify: write tsv: %v\n", err)
		return exitUsage
	}
	if err := writeProposalMD(*out+".md", proposals); err != nil {
		fmt.Fprintf(os.Stderr, "classify: write md: %v\n", err)
		return exitUsage
	}

	fmt.Printf("classify: proposed %d unclassified item(s) -> %s.md / %s.tsv (review before a future `group set --from`)\n",
		len(proposals), *out, *out)
	return exitOK
}

// parentAtmIDs returns atm_id -> parent_atm_id for every row that HAS a
// non-empty parent_atm_id (§11.4.148/§11.4.149 sub-task hierarchy). A
// minimal, classify.go-local query rather than widening the shared `item`
// struct/loadItems (db.go) for the benefit of ONE classify signal — none of
// the existing shared loaders currently surface parent_atm_id, and doing so
// would widen the blast radius (§11.4.92 Pass 2) of this phase onto every
// OTHER caller of loadItems/loadItem well beyond what classify itself needs.
func parentAtmIDs(db *sql.DB) (map[string]string, error) {
	rows, err := db.Query(`SELECT atm_id, COALESCE(parent_atm_id,'') FROM items
		WHERE parent_atm_id IS NOT NULL AND TRIM(parent_atm_id) != ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var id, parent string
		if err := rows.Scan(&id, &parent); err != nil {
			return nil, err
		}
		out[id] = parent
	}
	return out, rows.Err()
}

// proposeFor derives ONE proposal for it, in design §9's signal-precedence
// order:
//
//  1. urgent-routing (design §5.1) — reuses isUrgentItem/critRank VERBATIM
//     from validate_groups.go (never re-derived, §11.4.6); already scoped to
//     title + forensic_anchor + severity, never description.
//  2. parent_atm_id inheritance — a sub-task naturally belongs to its
//     already-classified parent's group (§11.4.148/§11.4.149 hierarchy).
//  3. composes_with inheritance — the first composes_with reference that
//     resolves to an ALREADY-classified item.
//  4. title-keyword weak hint — field-scoped to `title` ONLY (see
//     matchGroupsByTitleKeyword), NEVER `description`. THE exact field
//     scoping the ATM-633 defect requires: its description mentions a
//     branch name, its title does not, so it must NOT match here.
//  5. fallback to `unassigned-triage`.
func proposeFor(it item, groups []logicGroup, groupByID map[string]logicGroup, classifiedByID map[string]string, parentOf map[string]string) classificationProposal {
	base := classificationProposal{
		AtmID: it.AtmID, Location: it.CurrentLocation, Repr: it.repOrDefault(), Title: it.Title,
	}

	if isUrgentItem(it) {
		if g, ok := groupByID["urgent-main"]; ok {
			base.LogicGroup, base.Destination, base.Confidence = g.GroupID, g.Destination, "high"
			base.Signal = "urgent-routing:severity-or-title-or-forensic-anchor-signal"
			return base
		}
		base.LogicGroup, base.Destination, base.Confidence = "unassigned-triage", "main", "low"
		base.Signal = "urgent-signal-but-no-urgent-main-group-registered-yet"
		return base
	}

	if parentID, ok := parentOf[it.AtmID]; ok && parentID != "" {
		if pg, ok := classifiedByID[parentID]; ok && pg != "" {
			dest := ""
			if g, ok := groupByID[pg]; ok {
				dest = g.Destination
			}
			base.LogicGroup, base.Destination, base.Confidence = pg, dest, "high"
			base.Signal = "parent_atm_id:" + parentID
			return base
		}
	}

	if refs := parseComposesWithRefs(it.ComposesWith); len(refs) > 0 {
		for _, ref := range refs {
			if cg, ok := classifiedByID[ref]; ok && cg != "" {
				dest := ""
				if g, ok := groupByID[cg]; ok {
					dest = g.Destination
				}
				base.LogicGroup, base.Destination, base.Confidence = cg, dest, "medium"
				base.Signal = "composes_with:" + ref
				return base
			}
		}
	}

	matched := matchGroupsByTitleKeyword(it.Title, groups)
	if len(matched) == 1 {
		g := matched[0].group
		base.LogicGroup, base.Destination, base.Confidence = g.GroupID, g.Destination, "low"
		base.Signal = "title-keyword:" + matched[0].token
		return base
	}
	if len(matched) > 1 {
		base.LogicGroup, base.Destination, base.Confidence = "unassigned-triage", "main", "low"
		base.Signal = "ambiguous-title-keyword-matched-multiple-groups"
		return base
	}

	base.LogicGroup, base.Destination, base.Confidence = "unassigned-triage", "main", "none"
	base.Signal = "no-structured-signal-matched"
	return base
}

// parseComposesWithRefs parses the composes_with JSON-encoded-array column
// (schema_embed.sql:59) into a plain string slice. A malformed/empty value
// degrades HONESTLY to "no refs" (nil) rather than erroring the whole
// classify run — composes_with is a best-effort signal, not a hard
// dependency, and a parse failure here must never abort seeding for every
// OTHER item.
func parseComposesWithRefs(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var refs []string
	if err := json.Unmarshal([]byte(raw), &refs); err != nil {
		return nil
	}
	return refs
}

// titleKeywordMatch is one (group, matched-token) pairing found by
// matchGroupsByTitleKeyword.
type titleKeywordMatch struct {
	group logicGroup
	token string
}

// nonWordRE splits free text into candidate tokens on any run of
// non-alphanumeric-non-dot characters. Dots are preserved so a compound
// token like "5.1" survives as ONE token (e.g. the `audio-5.1-multichannel`
// group_id) — splitting on '.' too would shatter it into "5"/"1" and create
// noisy false-positive matches against any title containing a bare digit.
var nonWordRE = regexp.MustCompile(`[^a-z0-9.]+`)

// stopwordsForKeywords is a small, STANDARD, project-agnostic set of common
// short English function words filtered out of a group's derived keyword
// surface. Discovered as a genuine gap by this phase's own RED-first
// test-writing (§11.4.102/§11.4.115): the length>=3 floor ALONE let "for"
// through, producing a false-positive collision between two otherwise
// UNRELATED titles that each merely happened to contain the word "for" —
// exactly the noisy-weak-hint failure mode design §9 warns "topic
// keywords" must stay clear of. This is a universally-recognised
// text-processing stopword list (an ENGINEERING CHOICE about a matching
// ALGORITHM's noise floor, not a factual claim §11.4.6 governs) — it
// contains no ATMOSphere-specific or otherwise project-specific terms.
var stopwordsForKeywords = map[string]bool{
	"the": true, "and": true, "for": true, "are": true, "was": true, "not": true,
	"but": true, "all": true, "any": true, "can": true, "had": true, "has": true,
	"her": true, "him": true, "his": true, "how": true, "its": true, "let": true,
	"may": true, "new": true, "now": true, "old": true, "one": true, "our": true,
	"out": true, "per": true, "see": true, "she": true, "too": true, "two": true,
	"use": true, "via": true, "who": true, "why": true, "yet": true, "you": true,
	"your": true, "with": true, "from": true, "this": true, "that": true,
	"have": true, "been": true, "were": true, "will": true, "when": true,
	"what": true, "them": true, "then": true, "than": true, "into": true,
	"only": true, "also": true, "over": true, "such": true, "some": true,
	"more": true, "most": true, "each": true, "both": true, "very": true,
	"just": true, "about": true, "after": true, "again": true, "being": true,
	"under": true, "while": true, "where": true, "which": true, "there": true,
	"these": true, "those": true, "would": true, "could": true, "should": true,
}

// tokenizeForKeywords lowercases s and splits it into tokens (see
// nonWordRE), keeping only tokens of length >= 3 that are NOT a common
// stopword — a minimal, project-agnostic noise filter (length floor +
// stopword list; NO project-specific keyword list).
func tokenizeForKeywords(s string) []string {
	lower := strings.ToLower(s)
	raw := nonWordRE.Split(lower, -1)
	var out []string
	for _, t := range raw {
		if len(t) >= 3 && !stopwordsForKeywords[t] {
			out = append(out, t)
		}
	}
	return out
}

// matchGroupsByTitleKeyword implements design §9 step 1's "(as a WEAK hint
// only, field-scoped to `title`, never `description`) topic keywords": for
// every candidate group (excluding the two routing/fallback sentinels
// `urgent-main` and `unassigned-triage`, which are never topic-matched),
// derive its keyword surface from ITS OWN group_id (split on '-', dots
// preserved) plus its OWN title words — PROJECT-SUPPLIED data (design
// §3.2's `logic_groups.yaml`), never a keyword list hardcoded into this
// universal binary. A token counts as a match only as a case-insensitive
// WHOLE-WORD hit inside the item's TITLE (word-boundary regex; description
// is never consulted), never a bare substring, avoiding spurious
// partial-word hits. Returns the DISTINCT set of matching groups
// (deduplicated — a group matching on multiple tokens counts once), in
// deterministic group_id order, each paired with the FIRST token that
// matched it (for the proposal's audit-trail Signal field).
func matchGroupsByTitleKeyword(title string, groups []logicGroup) []titleKeywordMatch {
	var out []titleKeywordMatch
	for _, g := range groups {
		if g.GroupID == "urgent-main" || g.GroupID == "unassigned-triage" {
			continue
		}
		tokens := append(tokenizeForKeywords(g.GroupID), tokenizeForKeywords(g.Title)...)
		seen := map[string]bool{}
		matchedToken := ""
		for _, tok := range tokens {
			if seen[tok] {
				continue
			}
			seen[tok] = true
			re, err := regexp.Compile(`(?i)\b` + regexp.QuoteMeta(tok) + `\b`)
			if err != nil {
				continue
			}
			if re.MatchString(title) {
				matchedToken = tok
				break
			}
		}
		if matchedToken != "" {
			out = append(out, titleKeywordMatch{group: g, token: matchedToken})
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].group.GroupID < out[j].group.GroupID })
	return out
}

// writeProposalTSV / writeProposalMD render the design §9 review file in
// both machine-readable (TSV) and human-readable (Markdown table) form.

func writeProposalTSV(path string, proposals []classificationProposal) error {
	if err := ensureParentDir(path); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("atm_id\tcurrent_location\trepresentation\ttitle\tproposed_logic_group\tproposed_destination\tconfidence\tsignal\n")
	for _, p := range proposals {
		fmt.Fprintf(&b, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			p.AtmID, p.Location, p.Repr, tsvEscape(p.Title), p.LogicGroup, p.Destination, p.Confidence, tsvEscape(p.Signal))
	}
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

func writeProposalMD(path string, proposals []classificationProposal) error {
	if err := ensureParentDir(path); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# Group Classification Proposal\n\n")
	b.WriteString("Design: docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §9. Review file ONLY — ")
	b.WriteString("classify never writes the DB; apply a reviewed proposal via a future `group set --from`.\n\n")
	b.WriteString("| ATM ID | Location | Title | Proposed Group | Proposed Destination | Confidence | Signal |\n")
	b.WriteString("|---|---|---|---|---|---|---|\n")
	for _, p := range proposals {
		fmt.Fprintf(&b, "| %s | %s/%s | %s | %s | %s | %s | %s |\n",
			p.AtmID, p.Location, p.Repr, mdEscape(p.Title), p.LogicGroup, p.Destination, p.Confidence, mdEscape(p.Signal))
	}
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// ensureParentDir creates path's parent directory tree if absent — mirrors
// openDB's (db.go) same MkdirAll precedent, so `--out` may point at a
// not-yet-existing subdirectory (e.g. a fresh project's docs/tracks/) without
// the caller having to pre-create it.
func ensureParentDir(path string) error {
	dir := filepath.Dir(path)
	if dir == "" || dir == "." {
		return nil
	}
	return os.MkdirAll(dir, 0o755)
}

func tsvEscape(s string) string {
	s = strings.ReplaceAll(s, "\t", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	return s
}

func mdEscape(s string) string {
	s = strings.ReplaceAll(s, "|", "\\|")
	s = strings.ReplaceAll(s, "\n", " ")
	return s
}
