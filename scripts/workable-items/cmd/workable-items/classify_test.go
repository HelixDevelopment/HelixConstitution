// classify_test.go — anti-bluff coverage for `classify --propose`, P3 of
// docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md.
//
// The decisive test in this file is
// TestClassifyPropose_ATM633GoldenBad_DescriptionMentionMustNotClassify:
// the canonical golden-bad fixture (design §2.2) — an item whose
// DESCRIPTION mentions a branch name ("mistiq-vader") but whose TITLE does
// not — MUST NOT be proposed into the mistiq-vader-rebrand group. This is
// the field-scoping anti-defect the whole ASSIGNMENT_MECHANISM exists to
// fix (§11.4.107(10) self-validated golden-good/golden-bad analyzer
// discipline).
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// insertRawItemWithDescription is insertRawItem (validate_groups_test.go)
// widened with an explicit description parameter — needed here because the
// ATM-633 golden-bad fixture's WHOLE POINT is a description that differs
// from its title, and insertRawItem hardcodes a fixed description string.
func insertRawItemWithDescription(t *testing.T, db *sql.DB, atmID, location, status, severity, title, description, forensicAnchor, destination, logicGroup string) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO items
		(atm_id, type, status, severity, title, description, forensic_anchor,
		 current_location, body_md, destination, logic_group)
		VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
		atmID, "Feature", status, nullable(severity), title, description,
		nullable(forensicAnchor), location, "", nullable(destination), nullable(logicGroup))
	if err != nil {
		t.Fatalf("insertRawItemWithDescription %s [%s]: %v", atmID, location, err)
	}
}

// parseProposalTSV reads a classify-produced .tsv file into atm_id -> the
// tab-separated field slice AFTER atm_id (location, representation, title,
// proposed_logic_group, proposed_destination, confidence, signal), skipping
// the header row.
func parseProposalTSV(t *testing.T, path string) map[string][]string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read proposal tsv %s: %v", path, err)
	}
	lines := strings.Split(strings.TrimRight(string(raw), "\n"), "\n")
	out := map[string][]string{}
	for i, line := range lines {
		if i == 0 || strings.TrimSpace(line) == "" {
			continue // header
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 1 {
			continue
		}
		out[fields[0]] = fields[1:]
	}
	return out
}

// ================================================================
// tokenizeForKeywords / matchGroupsByTitleKeyword (pure unit coverage)
// ================================================================

func TestTokenizeForKeywords(t *testing.T) {
	got := tokenizeForKeywords("audio-5.1-multichannel")
	want := []string{"audio", "5.1", "multichannel"}
	if len(got) != len(want) {
		t.Fatalf("tokenizeForKeywords = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("token[%d] = %q, want %q", i, got[i], want[i])
		}
	}
	// Short tokens (<3 chars) are dropped as noise.
	if got := tokenizeForKeywords("a-ab-abc"); len(got) != 1 || got[0] != "abc" {
		t.Errorf("tokenizeForKeywords(a-ab-abc) = %v, want [abc] (sub-3-char tokens filtered)", got)
	}
}

func TestMatchGroupsByTitleKeyword_SingleMatch(t *testing.T) {
	groups := []logicGroup{
		{GroupID: "mistiq-vader-rebrand", Title: "Mistiq Vader rebrand workstream", Destination: "feature:mistiq-vader"},
	}
	matched := matchGroupsByTitleKeyword("Prepare mistiq rebrand asset pipeline", groups)
	if len(matched) != 1 || matched[0].group.GroupID != "mistiq-vader-rebrand" {
		t.Fatalf("matchGroupsByTitleKeyword = %+v, want exactly [mistiq-vader-rebrand]", matched)
	}
}

func TestMatchGroupsByTitleKeyword_NoMatchOnDescriptionOnlyWord(t *testing.T) {
	// The word "vader" appears NOWHERE in this title (only description would
	// carry it, in a real fixture) — matchGroupsByTitleKeyword is only ever
	// called with a TITLE argument by proposeFor, so this proves the
	// function itself has no way to see description content at all.
	groups := []logicGroup{
		{GroupID: "mistiq-vader-rebrand", Title: "Mistiq Vader rebrand workstream", Destination: "feature:mistiq-vader"},
	}
	matched := matchGroupsByTitleKeyword("Multi-track dev: encrypted-btrfs per-track SSDs for parallel work", groups)
	if len(matched) != 0 {
		t.Fatalf("matchGroupsByTitleKeyword matched %+v against a title with no mistiq/vader/rebrand token — false positive", matched)
	}
}

func TestMatchGroupsByTitleKeyword_AmbiguousMultipleGroups(t *testing.T) {
	groups := []logicGroup{
		{GroupID: "video-bugs", Title: "Video playback bugs", Destination: "main"},
		{GroupID: "video-audio-sync", Title: "Video audio sync issues", Destination: "main"},
	}
	matched := matchGroupsByTitleKeyword("investigate video regression on secondary display", groups)
	if len(matched) != 2 {
		t.Fatalf("matchGroupsByTitleKeyword = %+v, want BOTH video-* groups to match (ambiguous case)", matched)
	}
}

func TestMatchGroupsByTitleKeyword_ExcludesRoutingSentinels(t *testing.T) {
	groups := []logicGroup{
		{GroupID: "urgent-main", Title: "Urgent main routing", Destination: "main"},
		{GroupID: "unassigned-triage", Title: "Unassigned triage bucket", Destination: "main"},
	}
	// "urgent" and "triage" both appear in the title, but these two
	// group_ids are sentinels — never topic-matched.
	matched := matchGroupsByTitleKeyword("an urgent triage needed here", groups)
	if len(matched) != 0 {
		t.Fatalf("matchGroupsByTitleKeyword matched sentinel group(s) %+v — urgent-main/unassigned-triage must never be topic-matched", matched)
	}
}

func TestMatchGroupsByTitleKeyword_WordBoundaryNotSubstring(t *testing.T) {
	groups := []logicGroup{
		{GroupID: "ai-tools", Title: "AI tooling improvements", Destination: "main"},
	}
	// "ai" as a bare substring appears inside "again" and "main" — the
	// word-boundary regex must NOT fire on those.
	matched := matchGroupsByTitleKeyword("fix this again in the main pipeline", groups)
	if len(matched) != 0 {
		t.Fatalf("matchGroupsByTitleKeyword matched %+v via a bare substring hit inside another word — word-boundary guard is a bluff", matched)
	}
}

// ================================================================
// parseComposesWithRefs
// ================================================================

func TestParseComposesWithRefs(t *testing.T) {
	if got := parseComposesWithRefs(`["ATM-1","ATM-2"]`); len(got) != 2 || got[0] != "ATM-1" || got[1] != "ATM-2" {
		t.Errorf("parseComposesWithRefs valid JSON = %v, want [ATM-1 ATM-2]", got)
	}
	if got := parseComposesWithRefs(""); got != nil {
		t.Errorf("parseComposesWithRefs(\"\") = %v, want nil", got)
	}
	if got := parseComposesWithRefs("not-json-at-all"); got != nil {
		t.Errorf("parseComposesWithRefs(malformed) = %v, want nil (degrade honestly, never crash the run)", got)
	}
}

// ================================================================
// proposeFor (pure, per-signal unit coverage)
// ================================================================

func TestProposeFor_UrgentRoutesToUrgentMain(t *testing.T) {
	groups := []logicGroup{{GroupID: "urgent-main", Destination: "main", Priority: 0}}
	groupByID := map[string]logicGroup{"urgent-main": groups[0]}
	p := proposeFor(item{AtmID: "A1", Severity: "Critical", Title: "ordinary title"}, groups, groupByID, map[string]string{}, map[string]string{})
	if p.LogicGroup != "urgent-main" || p.Destination != "main" || p.Confidence != "high" {
		t.Errorf("proposeFor(urgent) = %+v, want logic_group=urgent-main destination=main confidence=high", p)
	}
}

func TestProposeFor_UrgentButNoUrgentMainGroupRegistered(t *testing.T) {
	p := proposeFor(item{AtmID: "A2", Severity: "Critical", Title: "ordinary title"}, nil, map[string]logicGroup{}, map[string]string{}, map[string]string{})
	if p.LogicGroup != "unassigned-triage" || p.Confidence != "low" {
		t.Errorf("proposeFor(urgent, no urgent-main registered) = %+v, want unassigned-triage/low", p)
	}
	if !strings.Contains(p.Signal, "urgent-signal-but-no-urgent-main-group-registered") {
		t.Errorf("signal = %q, want it to record the gap honestly", p.Signal)
	}
}

func TestProposeFor_ParentInheritance(t *testing.T) {
	groups := []logicGroup{{GroupID: "grp-parent", Destination: "feature:x"}}
	groupByID := map[string]logicGroup{"grp-parent": groups[0]}
	classifiedByID := map[string]string{"ATM-PARENT": "grp-parent"}
	parentOf := map[string]string{"ATM-CHILD": "ATM-PARENT"}
	p := proposeFor(item{AtmID: "ATM-CHILD", Severity: "Low", Title: "a sub-task of the parent"}, groups, groupByID, classifiedByID, parentOf)
	if p.LogicGroup != "grp-parent" || p.Destination != "feature:x" || p.Confidence != "high" {
		t.Errorf("proposeFor(parent inheritance) = %+v, want grp-parent/feature:x/high", p)
	}
}

func TestProposeFor_ComposesWithInheritance(t *testing.T) {
	groups := []logicGroup{{GroupID: "grp-y", Destination: "main"}}
	groupByID := map[string]logicGroup{"grp-y": groups[0]}
	classifiedByID := map[string]string{"ATM-Y": "grp-y"}
	p := proposeFor(item{AtmID: "ATM-X", Severity: "Low", Title: "ordinary title", ComposesWith: `["ATM-Y"]`}, groups, groupByID, classifiedByID, map[string]string{})
	if p.LogicGroup != "grp-y" || p.Confidence != "medium" {
		t.Errorf("proposeFor(composes_with inheritance) = %+v, want grp-y/medium", p)
	}
}

func TestProposeFor_TitleKeywordWeakHint(t *testing.T) {
	groups := []logicGroup{{GroupID: "mistiq-vader-rebrand", Title: "Mistiq Vader rebrand", Destination: "feature:mistiq-vader"}}
	groupByID := map[string]logicGroup{"mistiq-vader-rebrand": groups[0]}
	p := proposeFor(item{AtmID: "ATM-T", Severity: "Low", Title: "prepare mistiq asset pipeline"}, groups, groupByID, map[string]string{}, map[string]string{})
	if p.LogicGroup != "mistiq-vader-rebrand" || p.Confidence != "low" {
		t.Errorf("proposeFor(title keyword) = %+v, want mistiq-vader-rebrand/low", p)
	}
}

func TestProposeFor_NoSignalFallsBackToTriage(t *testing.T) {
	groups := []logicGroup{{GroupID: "mistiq-vader-rebrand", Title: "Mistiq Vader rebrand", Destination: "feature:mistiq-vader"}}
	groupByID := map[string]logicGroup{"mistiq-vader-rebrand": groups[0]}
	p := proposeFor(item{AtmID: "ATM-N", Severity: "Low", Title: "totally unrelated title text"}, groups, groupByID, map[string]string{}, map[string]string{})
	if p.LogicGroup != "unassigned-triage" || p.Confidence != "none" {
		t.Errorf("proposeFor(no signal) = %+v, want unassigned-triage/none", p)
	}
}

func TestProposeFor_EveryBranchEmitsClosedSetConfidence(t *testing.T) {
	groups := []logicGroup{
		{GroupID: "urgent-main", Destination: "main"},
		{GroupID: "grp-parent", Destination: "main"},
		{GroupID: "grp-y", Destination: "main"},
		{GroupID: "mistiq-vader-rebrand", Title: "Mistiq Vader rebrand", Destination: "feature:mistiq-vader"},
	}
	groupByID := map[string]logicGroup{}
	for _, g := range groups {
		groupByID[g.GroupID] = g
	}
	classifiedByID := map[string]string{"ATM-PARENT": "grp-parent", "ATM-Y": "grp-y"}
	parentOf := map[string]string{"ATM-CHILD": "ATM-PARENT"}
	fixtures := []item{
		{AtmID: "F1", Severity: "Critical", Title: "x"},
		{AtmID: "ATM-CHILD", Severity: "Low", Title: "x"},
		{AtmID: "F3", Severity: "Low", Title: "x", ComposesWith: `["ATM-Y"]`},
		{AtmID: "F4", Severity: "Low", Title: "prepare mistiq pipeline"},
		{AtmID: "F5", Severity: "Low", Title: "nothing matches here"},
	}
	for _, it := range fixtures {
		p := proposeFor(it, groups, groupByID, classifiedByID, parentOf)
		if !classificationConfidence[p.Confidence] {
			t.Errorf("proposeFor(%s) emitted confidence %q, not in the closed set %v", it.AtmID, p.Confidence, classificationConfidence)
		}
	}
}

// ================================================================
// classifyCmd — end-to-end (DB -> review file)
// ================================================================

// TestClassifyPropose_ATM633GoldenBad_DescriptionMentionMustNotClassify is
// the canonical golden-bad / golden-good pair (§11.4.107(10)) for this
// phase's entire reason for existing: a description-only branch-name
// mention must NOT drag an item into that group; a title mention SHOULD.
func TestClassifyPropose_ATM633GoldenBad_DescriptionMentionMustNotClassify(t *testing.T) {
	dbPath := newGroupTestDB(t)
	if code := groupAddCmd([]string{
		"mistiq-vader-rebrand", "feature:mistiq-vader", "7", "--db", dbPath,
		"--title", "Mistiq Vader rebrand workstream for the speaker product",
	}); code != exitOK {
		t.Fatalf("group add exited %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// GOLDEN-BAD: the ATM-633 pattern (design §2.2) — an infra ticket whose
	// TITLE never mentions mistiq/vader, but whose DESCRIPTION references
	// the feature/mistiq-vader branch name. Medium severity (NOT urgent), no
	// parent, no composes_with — the ONLY signal a defective substring
	// matcher could have used is the description mention.
	insertRawItemWithDescription(t, db, "ATM-633-BAD", "Issues", "Queued", "Medium",
		"Multi-track dev: encrypted-btrfs per-track SSDs for parallel work",
		"Infra work to set up per-track SSDs; testing uses the feature/mistiq-vader branch name as one of several example branches, but this ticket is NOT about that rebrand.",
		"", "", "")
	// GOLDEN-GOOD: a genuinely mistiq-related item whose TITLE itself
	// carries the signal.
	insertRawItemWithDescription(t, db, "ATM-633-GOOD", "Issues", "Queued", "Medium",
		"Prepare mistiq rebrand asset pipeline",
		"Ordinary description, unrelated to the title-keyword signal being tested.",
		"", "", "")
	// Already-classified control: must be SKIPPED entirely by classify
	// (one-time seeding targets unclassified items only).
	insertRawItemWithDescription(t, db, "ATM-633-ALREADY", "Issues", "Queued", "Medium",
		"an already-classified control item", "irrelevant", "", "main", "mistiq-vader-rebrand")
	db.Close()

	outPrefix := filepath.Join(t.TempDir(), "proposal")
	code := classifyCmd([]string{"--propose", "--db", dbPath, "--out", outPrefix})
	if code != exitOK {
		t.Fatalf("classify --propose exited %d, want %d", code, exitOK)
	}

	rows := parseProposalTSV(t, outPrefix+".tsv")

	bad, ok := rows["ATM-633-BAD"]
	if !ok {
		t.Fatalf("ATM-633-BAD missing from the proposal output entirely:\n%v", rows)
	}
	// fields: [location, representation, title, proposed_logic_group, proposed_destination, confidence, signal]
	if bad[3] == "mistiq-vader-rebrand" {
		t.Fatalf("classify --propose classified ATM-633-BAD (branch name ONLY in description) INTO mistiq-vader-rebrand — the exact field-scoping defect this mechanism exists to fix. Row: %v", bad)
	}
	if bad[3] != "unassigned-triage" {
		t.Errorf("ATM-633-BAD proposed_logic_group = %q, want unassigned-triage (no title/structured signal should have matched)", bad[3])
	}

	good, ok := rows["ATM-633-GOOD"]
	if !ok {
		t.Fatalf("ATM-633-GOOD missing from the proposal output entirely:\n%v", rows)
	}
	if good[3] != "mistiq-vader-rebrand" {
		t.Errorf("ATM-633-GOOD (title itself says 'mistiq') proposed_logic_group = %q, want mistiq-vader-rebrand", good[3])
	}

	if _, ok := rows["ATM-633-ALREADY"]; ok {
		t.Errorf("classify --propose RE-PROPOSED an already-classified item — one-time-seeding scope is broken: %v", rows["ATM-633-ALREADY"])
	}

	// The .md sibling must exist too and must not itself claim the bad
	// mapping either (defence against a divergent md/tsv writer).
	mdRaw, err := os.ReadFile(outPrefix + ".md")
	if err != nil {
		t.Fatalf("read proposal md: %v", err)
	}
	md := string(mdRaw)
	if !strings.Contains(md, "ATM-633-BAD") || !strings.Contains(md, "ATM-633-GOOD") {
		t.Errorf("proposal.md missing expected rows:\n%s", md)
	}
}

func TestClassifyCmd_RequiresProposeFlag(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := classifyCmd([]string{"--db", dbPath, "--out", filepath.Join(t.TempDir(), "p")})
	if code == exitOK {
		t.Fatal("classify ACCEPTED a call with no --propose flag — this phase supports ONLY --propose, guard is a bluff")
	}
}

func TestClassifyCmd_RequiresDB(t *testing.T) {
	code := classifyCmd([]string{"--propose", "--out", filepath.Join(t.TempDir(), "p")})
	if code == exitOK {
		t.Fatal("classify ACCEPTED a call with no --db — guard is a bluff")
	}
}

func TestClassifyCmd_WritesUnderRequestedOutPrefix(t *testing.T) {
	dbPath := newGroupTestDB(t)
	db, _ := openDB(dbPath)
	insertRawItemWithDescription(t, db, "ATM-OUT-1", "Issues", "Queued", "Low", "an item to propose", "description text", "", "", "")
	db.Close()

	outPrefix := filepath.Join(t.TempDir(), "sub", "dir", "myproposal")
	if code := classifyCmd([]string{"--propose", "--db", dbPath, "--out", outPrefix}); code != exitOK {
		t.Fatalf("classify --propose exited %d, want %d", code, exitOK)
	}
	if _, err := os.Stat(outPrefix + ".tsv"); err != nil {
		t.Errorf("expected %s.tsv to exist: %v", outPrefix, err)
	}
	if _, err := os.Stat(outPrefix + ".md"); err != nil {
		t.Errorf("expected %s.md to exist: %v", outPrefix, err)
	}
}
