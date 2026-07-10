// atm627_glued_heading_test.go — §11.4.115 RED-polarity regression guard for the
// ATM-627 db-to-md WRITER glued-heading defect.
//
// The corruption class (distinct from the dangling-segment class guarded by
// atm627_roundtrip_test.go): when an item's `body_md` ends WITHOUT a trailing
// newline (the data state the `update` / `repair-bodies` body-mutation path
// leaves — confirmed live on ATM-370/ATM-709/ATM-710, whose bodies end
// `...PROGRESS.md.` / `...NOT device-validated.`), renderDocument (db.go)
// concatenated the NEXT item's body verbatim, gluing its `## <Letter>. [ATM-NNN]`
// heading onto the prior line (e.g. `...PROGRESS.md.## AP. [ATM-381] …`). The
// `^## `-anchored reader (parseIssues) then cannot see that heading at a
// line-start, so the next item is SILENTLY ABSORBED into the previous item's
// body (wrong body/status/type) and reported "present in DB, absent in
// Markdown" by `diff` — the exact stable-20-difference round-trip.
//
// DEFAULT (RED_MODE unset / "0") — the standing GREEN regression-guard —
// reproduces the exact pre-fix data state (an item body with NO trailing
// newline immediately followed by another item's `## ` heading), renders via
// db-to-md, and asserts the next item's heading now appears on its OWN LINE
// (the fix inserted the missing `\n` separator). RED_MODE=1 (opt-in) flips
// polarity to assert the PRE-FIX bluff (the heading was glued mid-line); it
// therefore FAILs on this fixed binary and PASSes only against a pre-fix
// binary — the captured proof the writer fix changed behaviour (§11.4.115).
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// headingOnOwnLine reports whether any LINE of rendered, after its trailing
// "\n" is stripped, begins with "## " AND contains needle. When the heading is
// glued mid-line (`…prev.## §2. [ATM-901] …`) no line starts with "## " and
// contains the needle, so this returns false — the precise pre-fix signature.
func headingOnOwnLine(rendered, needle string) bool {
	for _, ln := range strings.Split(rendered, "\n") {
		t := strings.TrimRight(ln, "\r")
		if strings.HasPrefix(t, "## ") && strings.Contains(t, needle) {
			return true
		}
	}
	return false
}

func TestATM627_WriterEmitsHeadingOnOwnLine(t *testing.T) {
	// Default (unset) = GREEN guard asserting the fix. RED_MODE=1 = assert the
	// pre-fix bluff (expected to FAIL on the fixed binary).
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

	tmp := t.TempDir()
	dbPath := filepath.Join(tmp, "wi.db")

	// Two ADJACENT items (no intervening raw prose): ATM-900 then ATM-901. The
	// source is well-formed so md-to-db imports cleanly; we then reproduce the
	// live defect state by stripping ATM-900's trailing newline directly in the
	// DB (mirroring the update-command data state, per §11.4.115 broken-artifact
	// reproduction).
	issues := "# Issues\n\n" +
		"## §1. [ATM-900] alpha item with enough words to satisfy description length\n\n" +
		"**Type:** Bug\n**Status:** Queued\n\n" +
		"body A ends with a filesystem path docs/research/x/PROGRESS.md.\n" +
		"## §2. [ATM-901] beta item with enough words to satisfy description length\n\n" +
		"**Type:** Feature\n**Status:** In progress\n\n" +
		"body B one two three four five six.\n"
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(issues), 0o644); err != nil {
		t.Fatalf("write issues: %v", err)
	}
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}

	// Reproduce the pre-fix data state: strip ATM-900's trailing newline(s) so
	// its body_md ends on a non-newline byte, exactly like the live ATM-370 /
	// ATM-709 / ATM-710 bodies. rtrim(body_md, char(10)) removes trailing "\n".
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	res, err := db.Exec(`UPDATE items SET body_md = rtrim(body_md, char(10))
		WHERE atm_id='ATM-900' AND current_location='Issues'`)
	if err != nil {
		db.Close()
		t.Fatalf("strip trailing newline: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		db.Close()
		t.Fatalf("strip trailing newline: expected 1 row, got %d", n)
	}
	// Sanity: confirm the reproduced defect state (body ends non-newline).
	var body string
	if err := db.QueryRow(`SELECT body_md FROM items WHERE atm_id='ATM-900' AND current_location='Issues'`).Scan(&body); err != nil {
		db.Close()
		t.Fatalf("read back body: %v", err)
	}
	db.Close()
	if len(body) == 0 || body[len(body)-1] == '\n' {
		t.Fatalf("test setup invalid: ATM-900 body_md must end on a non-newline byte, got tail %q", tail(body))
	}

	outPath := filepath.Join(tmp, "out.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outPath}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	rendered, err := os.ReadFile(outPath)
	if err != nil {
		t.Fatalf("read rendered: %v", err)
	}
	onOwnLine := headingOnOwnLine(string(rendered), "[ATM-901]")

	if assertPreFixBluff {
		// RED_MODE=1: assert the PRE-FIX behaviour — the ATM-901 heading was
		// glued mid-line (NOT on its own line). On the fixed binary this FAILs
		// (the fix put the heading on its own line), and it PASSes only against a
		// pre-fix binary — the §11.4.115 captured proof the fix changed behaviour.
		if onOwnLine {
			t.Fatalf("RED_MODE=1: ATM-901 heading is on its own line — fix is present, pre-fix glue no longer reproducible")
		}
		return
	}

	// DEFAULT GREEN guard: the writer fix means the ATM-901 heading is on its
	// own line even though ATM-900's body_md lacks a trailing newline.
	if !onOwnLine {
		t.Fatalf("ATM-627 writer bluff: ATM-901 heading is GLUED mid-line (not at a line start) in db-to-md output; rendered tail near heading: %q",
			nearNeedle(string(rendered), "[ATM-901]"))
	}
	// The heading being on its own line is precisely what makes it re-parseable:
	// confirm the reader now recovers ATM-901 as a SEPARATE item (not absorbed
	// into ATM-900), closing the "present in DB, absent in Markdown" defect.
	its, _ := parseIssues(string(rendered))
	found := false
	for _, it := range its {
		if it.AtmID == "ATM-901" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("ATM-901 not recovered as a separate item after re-parse of db-to-md output (still absorbed into ATM-900)")
	}
}

// tail returns up to the last 48 bytes of s for diagnostic messages.
func tail(s string) string {
	if len(s) <= 48 {
		return s
	}
	return s[len(s)-48:]
}

// nearNeedle returns a small window of s around the first occurrence of needle,
// for diagnostic messages showing the glue point.
func nearNeedle(s, needle string) string {
	i := strings.Index(s, needle)
	if i < 0 {
		return "(needle not found)"
	}
	start := i - 40
	if start < 0 {
		start = 0
	}
	end := i + len(needle) + 10
	if end > len(s) {
		end = len(s)
	}
	return s[start:end]
}
