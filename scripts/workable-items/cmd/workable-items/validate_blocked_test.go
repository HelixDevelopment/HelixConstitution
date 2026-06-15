// validate_blocked_test.go — anti-bluff coverage for the §11.4.21 / §11.4.148 D3
// BLOCKED-unblock-choices validator + the `Blocked`/`BLOCKED` status alias.
//
// Every test drives the REAL SQLite driver + real block subcommand + real
// validateCmd (no mocks). The decisive anti-bluff assertions:
//  (1) an Operator-blocked item WITHOUT enumerated unblock CHOICES makes
//      validate FAIL (non-zero exit) — proving the gate is not a no-op;
//  (2) the SAME item WITH enumerated `[A]/[B]` choices makes validate PASS —
//      proving the gate accepts a well-formed unblock field;
//  (3) an Operator-blocked item with NO operator_block_details row FAILs;
//  (4) the `Blocked` / `BLOCKED` raw status normalises to `Operator-blocked`
//      (the documented §11.4.148 D3 alias, not a silent fork);
//  (5) the choice-marker helper recognises `[A]`, bullets, and rejects prose.
package main

import (
	"testing"
)

// addBlockable inserts a fresh Issues item ready to be blocked.
func addBlockable(t *testing.T, dbPath, id string) {
	t.Helper()
	code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "blockable item " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Task", "Medium",
	})
	if code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}
}

// TestValidate_BlockedWithoutEnumeratedChoices_Fails is the RED assertion: a
// blocked item whose unblock_condition is bare prose (no [A]/[B]/bullet) makes
// validate FAIL. Without this gate the validator would PASS and the operator
// would have no enumerated way to clear the block (§11.4.148 D3 PASS-bluff).
func TestValidate_BlockedWithoutEnumeratedChoices_Fails(t *testing.T) {
	dbPath := newTestDB(t)
	addBlockable(t, dbPath, "WIT-401")
	code := blockCmd([]string{
		"--db", dbPath, "--id", "WIT-401",
		"--details", "operator must reconfigure the host ADB daemon limits",
		"--why", "daemon reconfig needs host root; not self-resolvable",
		// prose-only unblock condition — NO enumerated choices
		"--unblock", "operator raises the host ADB daemon file-descriptor limit",
		"--who", "Operator",
	})
	if code != exitOK {
		t.Fatalf("block exited %d, want %d", code, exitOK)
	}
	if got := validateCmd([]string{"--db", dbPath}); got == exitOK {
		t.Fatal("validate PASSed on a blocked item with no enumerated unblock CHOICES — §11.4.148 D3 gate is a bluff")
	}
}

// TestValidate_BlockedWithEnumeratedChoices_Passes is the GREEN assertion: the
// same item, re-blocked with `[A]/[B]/[C]` enumerated choices, makes validate
// PASS. The gate and the RED test together form the §1.1 pair.
func TestValidate_BlockedWithEnumeratedChoices_Passes(t *testing.T) {
	dbPath := newTestDB(t)
	addBlockable(t, dbPath, "WIT-402")
	code := blockCmd([]string{
		"--db", dbPath, "--id", "WIT-402",
		"--details", "operator decides the host ADB daemon mitigation",
		"--why", "daemon reconfig needs host root; not self-resolvable",
		"--unblock", "[A] operator raises host LimitNOFILE for adb-server.service · " +
			"[B] operator caps parallel device count to 2 (no daemon change) · " +
			"[C] operator approves running the stress test against a remote ADB host",
		"--who", "Operator",
	})
	if code != exitOK {
		t.Fatalf("block exited %d, want %d", code, exitOK)
	}
	if got := validateCmd([]string{"--db", dbPath}); got != exitOK {
		t.Fatalf("validate exited %d on a blocked item WITH enumerated unblock CHOICES (expected OK)", got)
	}
}

// TestValidate_BlockedWithoutDetailsRow_Fails proves an Operator-blocked item
// with NO operator_block_details row at all is caught.
func TestValidate_BlockedWithoutDetailsRow_Fails(t *testing.T) {
	dbPath := newTestDB(t)
	addBlockable(t, dbPath, "WIT-403")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	// Flip the status to Operator-blocked directly WITHOUT inserting an OBD row.
	if _, err := db.Exec(`UPDATE items SET status='Operator-blocked' WHERE atm_id=?`, "WIT-403"); err != nil {
		t.Fatalf("update status: %v", err)
	}
	db.Close()
	if got := validateCmd([]string{"--db", dbPath}); got == exitOK {
		t.Fatal("validate PASSed on an Operator-blocked item with no operator_block_details row — gate is a bluff")
	}
}

// TestNormalizeStatus_BlockedAlias proves `Blocked` / `BLOCKED` / `blocked`
// normalise to the canonical `Operator-blocked` value (§11.4.148 D3 documented
// alias — not a new closed-set value, not a silent fork per §11.4.6).
func TestNormalizeStatus_BlockedAlias(t *testing.T) {
	for _, raw := range []string{"Blocked", "BLOCKED", "blocked", "  Blocked  "} {
		if got := normalizeStatus(raw); got != "Operator-blocked" {
			t.Errorf("normalizeStatus(%q) = %q, want Operator-blocked", raw, got)
		}
	}
	// Sanity: the canonical value and the Operator- prefix still map correctly.
	if got := normalizeStatus("Operator-blocked"); got != "Operator-blocked" {
		t.Errorf("normalizeStatus(Operator-blocked) = %q", got)
	}
}

// TestHasEnumeratedUnblockChoices is the pure-function table: choice markers
// recognised, prose / empty rejected.
func TestHasEnumeratedUnblockChoices(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"[A] do X · [B] do Y", true},
		{"[1] approve · [2] decline", true},
		{"- operator does X\n- operator does Y", true},
		{"* approve removal\n* keep it", true},
		{"operator raises the host ADB daemon limit", false},
		{"", false},
		{"   \n  ", false},
		{"a single prose sentence with no marker at all here", false},
	}
	for _, c := range cases {
		if got := hasEnumeratedUnblockChoices(c.in); got != c.want {
			t.Errorf("hasEnumeratedUnblockChoices(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}
