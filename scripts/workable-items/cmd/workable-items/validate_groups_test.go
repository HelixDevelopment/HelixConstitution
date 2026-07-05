// validate_groups_test.go — anti-bluff coverage for `validate-groups`, P2 of
// docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md.
//
// Every one of the five design §3.1 invariants gets a PASSING positive
// fixture AND a FAILING negative fixture, run against a t.TempDir() scratch
// DB (never the live docs/workable_items.db, per §11.4.6/§9.2). Negative
// fixtures are built via insertRawItem — direct SQL, bypassing every CLI
// guard — because validate-groups must catch a corrupted/inconsistent state
// REGARDLESS of how it arose (manual edit, a future bug in some OTHER write
// path, a migration artifact), not merely the states its own CLI entry
// points already refuse to create.
//
// §1.1 mutation note (per invariant, mirrored from validate_groups.go's inline
// comments): weakening or deleting the corresponding `violations = append(...)`
// call (or its guarding `if`) in validateGroupsCmd makes that invariant's
// negative test below stop failing — the exact bluff-detection property a
// future meta_test_false_positive_proof.sh mutation pair will encode.
package main

import (
	"database/sql"
	"io"
	"os"
	"strings"
	"testing"
)

// insertRawItem inserts one items row directly via SQL, giving full control
// over status/severity/title/forensic_anchor/destination/logic_group — the
// raw building block negative fixtures need to construct DB states no CLI
// guard would let through, but which validate-groups must still catch.
func insertRawItem(t *testing.T, db *sql.DB, atmID, location, status, severity, title, forensicAnchor, destination, logicGroup string) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO items
		(atm_id, type, status, severity, title, description, forensic_anchor,
		 current_location, body_md, destination, logic_group)
		VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
		atmID, "Bug", status, nullable(severity), title,
		"a sufficiently long description clearing the §11.4.91 floor for this fixture row",
		nullable(forensicAnchor), location, "", nullable(destination), nullable(logicGroup))
	if err != nil {
		t.Fatalf("insertRawItem %s [%s]: %v", atmID, location, err)
	}
}

// captureValidateGroupsStderr runs validateGroupsCmd(args) capturing its real
// os.Stderr (violations are printed there, mirroring sync.go's validateCmd)
// and returns the exit code + captured text, mirroring sync_diff_test.go's
// captureDiff (same os.Pipe technique, swapped to Stderr).
func captureValidateGroupsStderr(t *testing.T, args []string) (int, string) {
	t.Helper()
	orig := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stderr = w
	rc := validateGroupsCmd(args)
	w.Close()
	os.Stderr = orig
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read captured stderr: %v", err)
	}
	return rc, string(out)
}

// ---- (1) single-valued: "an item can NEVER be in two groups" (design §3.1) ----

func TestValidateGroups_SingleValued_Positive(t *testing.T) {
	dbPath := newGroupTestDB(t)
	if code := groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for single-valued positive fixture"}); code != exitOK {
		t.Fatalf("group add exited %d", code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// §11.4.19 tombstone pattern: the SAME atm_id legitimately present in BOTH
	// trackers, carrying the SAME logic_group — must NOT be flagged.
	insertRawItem(t, db, "ATM-SV-POS", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-a")
	insertRawItem(t, db, "ATM-SV-POS", "Fixed", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-a")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on a consistently-classified dual-location item, want %d (false positive on the legitimate §11.4.19 tombstone case)", code, exitOK)
	}
}

func TestValidateGroups_SingleValued_Negative(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for single-valued negative fixture"})
	groupAddCmd([]string{"group-b", "main", "2", "--db", dbPath, "--title", "group b for single-valued negative fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-SV-NEG", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-a")
	insertRawItem(t, db, "ATM-SV-NEG", "Fixed", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-b")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an item classified into two DIFFERENT groups across its rows — single-valued guard is a bluff")
	}
	if !strings.Contains(out, "single-valued violation") {
		t.Errorf("stderr does not mention a single-valued violation:\n%s", out)
	}
}

// ---- (2) destination-agreement: "item.destination == its group's destination" (§3.1) ----

func TestValidateGroups_DestinationAgreement_Positive(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for destination-agreement positive fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-DA-POS", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-a")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on an item whose destination agrees with its group, want %d", code, exitOK)
	}
}

func TestValidateGroups_DestinationAgreement_Negative(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for destination-agreement negative fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// group-a's destination is main; the item disagrees.
	insertRawItem(t, db, "ATM-DA-NEG", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "feature:mismatch", "group-a")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an item whose destination disagrees with its group's destination — destination-agreement guard is a bluff")
	}
	if !strings.Contains(out, "destination-agreement violation") {
		t.Errorf("stderr does not mention a destination-agreement violation:\n%s", out)
	}
}

// ---- (3) totality: every OPEN item MUST carry non-null logic_group + destination (§3.1) ----

func TestValidateGroups_Totality_Positive(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for totality positive fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-TOT-POS", "Issues", "Queued", "Low", "ordinary title", "", "main", "group-a")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on a fully-classified open item, want %d", code, exitOK)
	}
}

func TestValidateGroups_Totality_Negative(t *testing.T) {
	dbPath := newGroupTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Open (status=Queued), unclassified (both destination + logic_group empty).
	insertRawItem(t, db, "ATM-TOT-NEG", "Issues", "Queued", "Low", "ordinary title", "", "", "")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an OPEN item with no logic_group/destination — totality guard is a bluff")
	}
	if !strings.Contains(out, "totality violation") {
		t.Errorf("stderr does not mention a totality violation:\n%s", out)
	}
}

func TestValidateGroups_Totality_NonOpenStatusExemptWhenUnclassified(t *testing.T) {
	// design §3.1 "Nullable for closed": a closed item may carry NULL
	// logic_group/destination (never re-dispatched) — this must NOT be a
	// totality violation. Proves the check is scoped to open statuses only,
	// per §3.1's literal 3-value set, not the full open-status vocabulary.
	dbPath := newGroupTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-TOT-CLOSED", "Fixed", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "", "")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on a CLOSED unclassified item, want %d (totality must not apply to non-open statuses)", code, exitOK)
	}
}

// ---- (4) referential: "item.logic_group must exist in logic_groups" (§3.1) ----

func TestValidateGroups_Referential_Positive(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "group a for referential positive fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-REF-POS", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "group-a")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on an item referencing an EXISTING group, want %d", code, exitOK)
	}
}

func TestValidateGroups_Referential_Negative(t *testing.T) {
	dbPath := newGroupTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// destination is set (so totality never fires here regardless of status);
	// logic_group references a group that was never created.
	insertRawItem(t, db, "ATM-REF-NEG", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "", "main", "ghost-group")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an item whose logic_group does not exist in logic_groups — referential-integrity guard is a bluff")
	}
	if !strings.Contains(out, "referential-integrity violation") {
		t.Errorf("stderr does not mention a referential-integrity violation:\n%s", out)
	}
}

// ---- (5) urgent-routing: crash/ANR/high-sev -> destination=main + logic_group=urgent-main (§5.1) ----

func TestValidateGroups_UrgentRouting_Positive(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"urgent-main", "main", "0", "--db", dbPath, "--title", "urgent-main routing group for positive fixture"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-UR-POS", "Issues", "Queued", "Critical", "ordinary title", "", "main", "urgent-main")
	db.Close()

	if code := validateGroupsCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate-groups exited %d on a Critical item correctly routed to urgent-main/main, want %d", code, exitOK)
	}
}

func TestValidateGroups_UrgentRouting_Negative_WrongGroupBySeverity(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"urgent-main", "main", "0", "--db", dbPath, "--title", "urgent-main routing group for negative fixture"})
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "an ordinary main-destination group"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Critical severity (crit=4 >=3) but classified into the WRONG group;
	// destination itself agrees with group-a (main), so this isolates the
	// urgent-routing check from destination-agreement.
	insertRawItem(t, db, "ATM-UR-NEG", "Issues", "Fixed (→ Fixed.md)", "Critical", "ordinary title", "", "main", "group-a")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED a Critical-severity item NOT routed to urgent-main — urgent-routing guard is a bluff")
	}
	if !strings.Contains(out, "urgent-routing violation") {
		t.Errorf("stderr does not mention an urgent-routing violation:\n%s", out)
	}
}

func TestValidateGroups_UrgentRouting_Negative_TitleSignalWord(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "an ordinary main-destination group"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Low severity (NOT urgent via crit rank) but the title itself signals an
	// ANR — design §5.1's title/forensic_anchor path, independent of severity.
	insertRawItem(t, db, "ATM-UR-NEG-TITLE", "Issues", "Fixed (→ Fixed.md)", "Low", "app hits ANR under load", "", "main", "group-a")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an item whose TITLE signals ANR but is not routed to urgent-main — title-driven urgent-routing guard is a bluff")
	}
	if !strings.Contains(out, "urgent-routing violation") {
		t.Errorf("stderr does not mention an urgent-routing violation:\n%s", out)
	}
}

func TestValidateGroups_UrgentRouting_Negative_ForensicAnchorSignalWord(t *testing.T) {
	dbPath := newGroupTestDB(t)
	groupAddCmd([]string{"group-a", "main", "1", "--db", dbPath, "--title", "an ordinary main-destination group"})
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	insertRawItem(t, db, "ATM-UR-NEG-FA", "Issues", "Fixed (→ Fixed.md)", "Low", "ordinary title", "device observed a boot-loop after flash", "main", "group-a")
	db.Close()

	code, out := captureValidateGroupsStderr(t, []string{"--db", dbPath})
	if code == exitOK {
		t.Fatal("validate-groups PASSED an item whose FORENSIC ANCHOR signals boot-loop but is not routed to urgent-main — guard is a bluff")
	}
	if !strings.Contains(out, "urgent-routing violation") {
		t.Errorf("stderr does not mention an urgent-routing violation:\n%s", out)
	}
}

// ---- isUrgentItem / critRank: pure, DB-free unit coverage ----

func TestCritRank(t *testing.T) {
	cases := []struct {
		sev  string
		want int
	}{
		{"Critical", 4}, {"critical - production down", 4}, {"C (severe)", 4}, {"c", 4},
		{"High", 3}, {"P1", 3}, {"Major", 3},
		{"Medium", 2}, {"Med", 2}, {"Normal", 2}, {"P2", 2},
		{"Low", 1}, {"Minor", 1},
		{"", 0}, {"Unknown", 0}, {"Informational", 0},
	}
	for _, c := range cases {
		if got := critRank(c.sev); got != c.want {
			t.Errorf("critRank(%q) = %d, want %d", c.sev, got, c.want)
		}
	}
}

func TestIsUrgentItem(t *testing.T) {
	if !isUrgentItem(item{Severity: "Critical"}) {
		t.Error("Critical severity should be urgent (crit=4)")
	}
	if !isUrgentItem(item{Severity: "High"}) {
		t.Error("High severity should be urgent (crit=3)")
	}
	if isUrgentItem(item{Severity: "Medium"}) {
		t.Error("Medium severity should NOT be urgent (crit=2)")
	}
	if isUrgentItem(item{Severity: "Low"}) {
		t.Error("Low severity should NOT be urgent (crit=1)")
	}
	if !isUrgentItem(item{Title: "app hits ANR under load", Severity: "Low"}) {
		t.Error("title containing ANR should be urgent regardless of severity")
	}
	if !isUrgentItem(item{ForensicAnchor: "boot-loop observed on D3", Severity: "Low"}) {
		t.Error("forensic_anchor containing boot-loop should be urgent regardless of severity")
	}
	if !isUrgentItem(item{Title: "sudden crash-loop after update", Severity: "Low"}) {
		t.Error("title containing crash-loop should be urgent")
	}
	if isUrgentItem(item{Title: "an ordinary title with no signal words", Severity: "Low"}) {
		t.Error("an ordinary low-severity item should NOT be urgent")
	}
}
