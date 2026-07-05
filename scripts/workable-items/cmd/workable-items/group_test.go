// group_test.go — anti-bluff coverage for the `group` subcommand family
// (add | list | set | state), P2 of docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md.
//
// Every test exercises the REAL SQLite driver against a t.TempDir() scratch
// DB (never the live docs/workable_items.db, per §11.4.6/§9.2) via the exact
// same *Cmd entry points main.go dispatches to — no mocks, no shortcuts.
package main

import (
	"path/filepath"
	"testing"
)

// newGroupTestDB is newTestDB (crud_test.go) reused verbatim for group.go's
// tests — same §11.4.151 HELIX_RELEASE_PREFIX pin, same t.TempDir() scratch
// path, never the tracked docs/workable_items.db.
func newGroupTestDB(t *testing.T) string {
	t.Helper()
	t.Setenv("HELIX_RELEASE_PREFIX", "wit")
	return filepath.Join(t.TempDir(), "workable_items.db")
}

// ---- add ----

func TestGroupAdd_InsertsQueryableRow(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"grp-a", "main", "3", "--db", dbPath,
		"--title", "test group alpha for CRUD coverage",
		"--scope-note", "a plain-language membership note, never a matcher",
		"--roadmap-ref", "ROADMAP.md#test",
	})
	if code != exitOK {
		t.Fatalf("group add exited %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	g, err := loadGroup(db, "grp-a")
	if err != nil {
		t.Fatalf("loadGroup: %v", err)
	}
	if g == nil {
		t.Fatal("group add did not persist grp-a (row absent) — add is a bluff")
	}
	if g.Destination != "main" {
		t.Errorf("destination = %q, want main", g.Destination)
	}
	if g.Priority != 3 {
		t.Errorf("priority = %d, want 3", g.Priority)
	}
	if g.State != "open" {
		t.Errorf("state = %q, want open (default)", g.State)
	}
	if g.ScopeNote == "" {
		t.Error("scope_note not persisted")
	}
	if g.RoadmapRef == "" {
		t.Error("roadmap_ref not persisted")
	}
}

func TestGroupAdd_AcceptsFeatureDestination(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"grp-feature", "feature:mistiq-vader", "7", "--db", dbPath,
		"--title", "a feature-destination group for CRUD coverage",
	})
	if code != exitOK {
		t.Fatalf("group add exited %d, want %d", code, exitOK)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	g, err := loadGroup(db, "grp-feature")
	if err != nil || g == nil {
		t.Fatalf("loadGroup: %v (group nil=%v)", err, g == nil)
	}
	if g.Destination != "feature:mistiq-vader" {
		t.Errorf("destination = %q, want feature:mistiq-vader", g.Destination)
	}
}

func TestGroupAdd_RejectsInvalidGroupID(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"Grp_With_Bad_Chars", "main", "1", "--db", dbPath, "--title", "bad id group for negative coverage",
	})
	if code == exitOK {
		t.Fatal("group add ACCEPTED an uppercase/underscore group_id — §11.4.29 guard is a bluff")
	}
}

func TestGroupAdd_RejectsInvalidDestination(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"grp-bad-dest", "not-a-valid-destination", "1", "--db", dbPath, "--title", "bad destination group for negative coverage",
	})
	if code == exitOK {
		t.Fatal("group add ACCEPTED an out-of-domain destination — design §3.1 guard is a bluff")
	}
}

func TestGroupAdd_RejectsInvalidPriority(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"grp-bad-priority", "main", "not-an-int", "--db", dbPath, "--title", "bad priority group for negative coverage",
	})
	if code == exitOK {
		t.Fatal("group add ACCEPTED a non-integer priority — guard is a bluff")
	}
}

func TestGroupAdd_RejectsInvalidState(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupAddCmd([]string{
		"grp-bad-state", "main", "1", "--db", dbPath, "--title", "bad state group for negative coverage",
		"--state", "bogus-state",
	})
	if code == exitOK {
		t.Fatal("group add ACCEPTED a non-closed-set state — §4 lifecycle guard is a bluff")
	}
}

func TestGroupAdd_RejectsDuplicateGroupID(t *testing.T) {
	dbPath := newGroupTestDB(t)
	base := []string{"grp-dup", "main", "1", "--db", dbPath, "--title", "duplicate group id for negative coverage"}
	if code := groupAddCmd(base); code != exitOK {
		t.Fatalf("first add exited %d, want %d", code, exitOK)
	}
	if code := groupAddCmd(base); code == exitOK {
		t.Fatal("group add ACCEPTED a duplicate group_id — uniqueness guard is a bluff")
	}
}

// ---- list ----

func TestGroupList_OrdersByPriorityThenGroupID(t *testing.T) {
	dbPath := newGroupTestDB(t)
	// Deliberately added OUT of priority order to prove ORDER BY, not
	// insertion order, governs the output.
	for _, row := range [][3]string{
		{"video-bugs", "main", "2"},
		{"urgent-main", "main", "0"},
		{"zzz-same-priority", "main", "2"},
		{"mistiq-vader-rebrand", "feature:mistiq-vader", "7"},
	} {
		if code := groupAddCmd([]string{row[0], row[1], row[2], "--db", dbPath, "--title", "priority ordering fixture group " + row[0]}); code != exitOK {
			t.Fatalf("add %s exited %d", row[0], code)
		}
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	groups, err := loadGroups(db, "", "")
	if err != nil {
		t.Fatalf("loadGroups: %v", err)
	}
	want := []string{"urgent-main", "video-bugs", "zzz-same-priority", "mistiq-vader-rebrand"}
	if len(groups) != len(want) {
		t.Fatalf("loadGroups returned %d rows, want %d", len(groups), len(want))
	}
	for i, g := range groups {
		if g.GroupID != want[i] {
			t.Errorf("position %d: group_id = %q, want %q (priority ASC, group_id ASC tie-break — §11.4.50 determinism)", i, g.GroupID, want[i])
		}
	}

	if code := groupListCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("groupListCmd exited %d, want %d", code, exitOK)
	}
}

func TestGroupList_FiltersByDestinationAndState(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"a-main", "main", "1", "--db", dbPath, "--title", "main destination filter fixture"})
	groupAddCmd([]string{"b-feature", "feature:x", "2", "--db", dbPath, "--title", "feature destination filter fixture"})

	db, _ := openDB(dbPath)
	defer db.Close()

	onlyMain, err := loadGroups(db, "main", "")
	if err != nil {
		t.Fatalf("loadGroups(main): %v", err)
	}
	if len(onlyMain) != 1 || onlyMain[0].GroupID != "a-main" {
		t.Errorf("destination=main filter returned %+v, want exactly [a-main]", onlyMain)
	}

	onlyOpen, err := loadGroups(db, "", "open")
	if err != nil {
		t.Fatalf("loadGroups(state=open): %v", err)
	}
	if len(onlyOpen) != 2 {
		t.Errorf("state=open filter returned %d rows, want 2 (both default to open)", len(onlyOpen))
	}
}

func TestGroupList_EmptyDBIsExitOK(t *testing.T) {
	dbPath := newGroupTestDB(t)
	// openDB alone (no group added) must still succeed with an empty list —
	// list is read-only and must not require pre-existing data to run clean.
	if code := groupListCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("group list on empty registry exited %d, want %d", code, exitOK)
	}
}

// ---- set (Mode A: group field edit) ----

func TestGroupSet_ModeA_UpdatesFields(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-edit", "main", "5", "--db", dbPath, "--title", "original title before edit"})

	code := groupSetCmd([]string{
		"grp-edit", "--db", dbPath,
		"--title", "updated title after edit",
		"--destination", "feature:new-dest",
		"--priority", "9",
		"--scope-note", "updated scope note",
	})
	if code != exitOK {
		t.Fatalf("group set (Mode A) exited %d, want %d", code, exitOK)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	g, err := loadGroup(db, "grp-edit")
	if err != nil || g == nil {
		t.Fatalf("loadGroup after set: err=%v nil=%v", err, g == nil)
	}
	if g.Title != "updated title after edit" {
		t.Errorf("title = %q, want updated", g.Title)
	}
	if g.Destination != "feature:new-dest" {
		t.Errorf("destination = %q, want feature:new-dest", g.Destination)
	}
	if g.Priority != 9 {
		t.Errorf("priority = %d, want 9", g.Priority)
	}
	if g.ScopeNote != "updated scope note" {
		t.Errorf("scope_note = %q, want updated scope note", g.ScopeNote)
	}
}

func TestGroupSet_ModeA_RejectsUnknownGroup(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupSetCmd([]string{"nonexistent-group", "--db", dbPath, "--title", "irrelevant"})
	if code == exitOK {
		t.Fatal("group set (Mode A) ACCEPTED an edit against a nonexistent group_id — existence guard is a bluff")
	}
}

func TestGroupSet_ModeA_RequiresAtLeastOneMutableField(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-noop", "main", "1", "--db", dbPath, "--title", "a group with nothing to change"})
	code := groupSetCmd([]string{"grp-noop", "--db", dbPath})
	if code == exitOK {
		t.Fatal("group set (Mode A) ACCEPTED a call with zero mutable-field flags — guard is a bluff")
	}
}

func TestGroupSet_ModeA_RejectsInvalidDestinationOnEdit(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-bad-edit-dest", "main", "1", "--db", dbPath, "--title", "group for invalid-destination edit test"})
	code := groupSetCmd([]string{"grp-bad-edit-dest", "--db", dbPath, "--destination", "not-valid"})
	if code == exitOK {
		t.Fatal("group set (Mode A) ACCEPTED an out-of-domain --destination — guard is a bluff")
	}
}

// ---- set (Mode B: item classification) ----

// TestGroupSet_ModeB_ClassifiesItem_InheritsGroupDestination is the decisive
// anti-bluff proof for design §3.1's destination-agreement invariant: after
// classification the ITEM's destination column equals the GROUP's
// destination — not independently supplied, INHERITED by the write path
// itself, so the two values structurally cannot disagree.
func TestGroupSet_ModeB_ClassifiesItem_InheritsGroupDestination(t *testing.T) {
	dbPath := newGroupTestDB(t)
	if code := groupAddCmd([]string{
		"mistiq-vader-rebrand", "feature:mistiq-vader", "7", "--db", dbPath,
		"--title", "mistiq vader rebrand group for classification test",
	}); code != exitOK {
		t.Fatalf("group add exited %d", code)
	}
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-500",
		"--title", "an item to classify into the rebrand group",
		"--description", "a sufficiently long description clearing the §11.4.91 floor for this fixture",
		"Task", "Medium",
	}); code != exitOK {
		t.Fatalf("add item exited %d", code)
	}

	code := groupSetCmd([]string{"--db", dbPath, "--item", "WIT-500", "--group", "mistiq-vader-rebrand"})
	if code != exitOK {
		t.Fatalf("group set (Mode B) exited %d, want %d", code, exitOK)
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	it, err := loadItem(db, "WIT-500", "Issues")
	if err != nil || it == nil {
		t.Fatalf("loadItem after classify: err=%v nil=%v", err, it == nil)
	}
	if it.LogicGroup != "mistiq-vader-rebrand" {
		t.Errorf("item logic_group = %q, want mistiq-vader-rebrand", it.LogicGroup)
	}
	if it.Destination != "feature:mistiq-vader" {
		t.Errorf("item destination = %q, want feature:mistiq-vader (INHERITED from group, not independently set) — destination-agreement (design §3.1) is broken", it.Destination)
	}

	// The classified item must now pass validate-groups' destination-agreement
	// + referential + totality checks (status=Queued from addCmd, now classified).
	if vc := validateGroupsCmd([]string{"--db", dbPath}); vc != exitOK {
		t.Errorf("validate-groups after a correct Mode B classification exited %d, want %d (classification should satisfy every §3.1 invariant it touches)", vc, exitOK)
	}
}

func TestGroupSet_ModeB_RejectsUnknownGroup(t *testing.T) {
	dbPath := newGroupTestDB(t)
	addCmd([]string{
		"--db", dbPath, "--id", "WIT-501",
		"--title", "an item for the unknown-group negative test",
		"--description", "a sufficiently long description clearing the §11.4.91 floor for this fixture",
		"Bug", "Low",
	})
	code := groupSetCmd([]string{"--db", dbPath, "--item", "WIT-501", "--group", "nonexistent-group"})
	if code == exitOK {
		t.Fatal("group set (Mode B) ACCEPTED classification into a nonexistent group — referential guard is a bluff")
	}

	db, _ := openDB(dbPath)
	defer db.Close()
	it, _ := loadItem(db, "WIT-501", "Issues")
	if it != nil && it.LogicGroup != "" {
		t.Errorf("item logic_group = %q after a REJECTED classification, want unchanged empty", it.LogicGroup)
	}
}

func TestGroupSet_ModeB_RejectsUnknownItem(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-for-unknown-item", "main", "1", "--db", dbPath, "--title", "group for the unknown-item negative test"})
	code := groupSetCmd([]string{"--db", dbPath, "--item", "WIT-999", "--group", "grp-for-unknown-item"})
	if code == exitOK {
		t.Fatal("group set (Mode B) ACCEPTED classification of a nonexistent item id — existence guard is a bluff")
	}
}

func TestGroupSet_ModeB_RejectsPositionalWithItemFlag(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-conflict", "main", "1", "--db", dbPath, "--title", "group for the mixed-mode negative test"})
	// Mixing a Mode-A positional with the Mode-B --item flag is a usage error,
	// not a silently-resolved ambiguity.
	code := groupSetCmd([]string{"grp-conflict", "--db", dbPath, "--item", "WIT-1", "--group", "grp-conflict"})
	if code == exitOK {
		t.Fatal("group set ACCEPTED a positional <group_id> mixed with --item — mode-conflict guard is a bluff")
	}
}

// ---- state ----

func TestGroupState_TransitionsValid(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-lifecycle", "main", "1", "--db", dbPath, "--title", "a group exercising the full lifecycle"})

	if code := groupStateCmd([]string{"grp-lifecycle", "in-progress", "--db", dbPath}); code != exitOK {
		t.Fatalf("group state -> in-progress exited %d, want %d", code, exitOK)
	}
	db, _ := openDB(dbPath)
	g, _ := loadGroup(db, "grp-lifecycle")
	db.Close()
	if g == nil || g.State != "in-progress" {
		t.Fatalf("state after transition = %+v, want in-progress", g)
	}

	if code := groupStateCmd([]string{"grp-lifecycle", "group-complete", "--db", dbPath}); code != exitOK {
		t.Fatalf("group state -> group-complete exited %d, want %d", code, exitOK)
	}
	db, _ = openDB(dbPath)
	g, _ = loadGroup(db, "grp-lifecycle")
	db.Close()
	if g == nil || g.State != "group-complete" {
		t.Fatalf("state after 2nd transition = %+v, want group-complete", g)
	}
}

func TestGroupState_RejectsInvalidState(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"grp-bad-transition", "main", "1", "--db", dbPath, "--title", "group for the invalid-state negative test"})
	code := groupStateCmd([]string{"grp-bad-transition", "closed-forever", "--db", dbPath})
	if code == exitOK {
		t.Fatal("group state ACCEPTED a non-closed-set state value — §4 lifecycle guard is a bluff")
	}
}

func TestGroupState_RejectsUnknownGroup(t *testing.T) {
	dbPath := newGroupTestDB(t)
	code := groupStateCmd([]string{"no-such-group", "in-progress", "--db", dbPath})
	if code == exitOK {
		t.Fatal("group state ACCEPTED a transition against a nonexistent group_id — existence guard is a bluff")
	}
}

// ---- validGroupID / validDestination (pure, DB-free unit coverage) ----

func TestValidGroupID(t *testing.T) {
	valid := []string{"urgent-main", "mistiq-vader-rebrand", "audio-5.1-multichannel", "a", "video-bugs"}
	for _, s := range valid {
		if !validGroupID(s) {
			t.Errorf("validGroupID(%q) = false, want true", s)
		}
	}
	invalid := []string{"", "Urgent-Main", "has_underscore", "has space", "HAS-CAPS", "trailing/slash"}
	for _, s := range invalid {
		if validGroupID(s) {
			t.Errorf("validGroupID(%q) = true, want false", s)
		}
	}
}

func TestValidDestination(t *testing.T) {
	if !validDestination("main") {
		t.Error(`validDestination("main") = false, want true`)
	}
	if !validDestination("feature:mistiq-vader") {
		t.Error(`validDestination("feature:mistiq-vader") = false, want true`)
	}
	for _, bad := range []string{"", "Main", "feature:", "feature:Has_Bad_Chars", "branch:main", "master"} {
		if validDestination(bad) {
			t.Errorf("validDestination(%q) = true, want false", bad)
		}
	}
}
