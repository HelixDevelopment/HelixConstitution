// sync_diff_names_inputs_test.go — BOB-155 guard: `diff` must never emit a
// success verdict from a comparison that opened no Markdown at all.
//
// Defect (BOB-155, severity High, reproduced 2026-08-21): `diff --db <p>`
// invoked WITHOUT --issues/--fixed printed "diff: DB and Markdown are in sync"
// and exited 0 while having read ZERO Markdown files. The output was
// BYTE-IDENTICAL to a genuinely successful comparison, so a blind instrument
// and a clean tree returned the same reassuring verdict and no reader could
// tell them apart — a §11.4.201(6) FALSE-NULL living inside the project's own
// sync-VERIFICATION tool, which is where that failure mode is least
// survivable. Measured: with a planted `**Status:**` divergence in Issues.md,
// the flagless form said "in sync" (exit 0) while the path-ful form correctly
// reported 2 difference(s) (exit 1).
//
// History (§11.4.120): this false-NULL was itself introduced by the fix for the
// opposite false-POSITIVE — the pre-2026-08-10 code ran the "absent in
// Markdown" loop with an empty parsed set and flagged every DB row. That fix
// added a `haveMarkdown` gate which correctly silenced the noise but then fell
// through to the unconditional success verdict, trading a FAIL-bluff for a
// PASS-bluff. The reconciliation keeps the noise suppressed AND makes the
// vacuous success impossible: refuse, and name the inputs.
//
// No polarity switch (deliberate, §11.4.115(F) + §11.4.248): these are
// unconditional guards asserting the CORRECT contract, so they fail on the
// pre-fix artifact and pass on the fixed one in BOTH RED_MODE settings. The
// §11.4.115 RED observation is recorded as captured evidence in the fix's
// report rather than as a defect-reproducing branch that inverts to a
// permanent failure the moment the fix lands — this package already carries
// standing-red polarity branches of exactly that shape.
//
// No mocks: real SQLite driver, real md→db parser, real diffCmd throughout.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// buildDivergentFixture writes the SPK-481-shaped Issues fixture, syncs it into
// a fresh temp DB (DB and Markdown are now definitionally in sync), then
// rewrites the on-disk Markdown so the item's OWN `**Status:**` line reads
// "Reopened" while the DB column still reads "Operator-blocked". The DB and the
// Markdown are now genuinely divergent. Returns (dbPath, issuesPath).
func buildDivergentFixture(t *testing.T) (string, string) {
	t.Helper()
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("setup: md-to-db exited %d", code)
	}
	// Plant the divergence in the MARKDOWN ONLY, anchored on the unique
	// `**Reopens-count:** 1` line that follows the item's OWN status line (the
	// nested sub-item's line is followed by `**Type:** Bug`), so the item's own
	// status — the one the DB column mirrors — is what diverges.
	const from = "**Status:** Operator-blocked\n**Reopens-count:** 1"
	const to = "**Status:** Reopened\n**Reopens-count:** 1"
	if !strings.Contains(spk481ShapedIssuesFixture, from) {
		t.Fatalf("fixture drifted: anchor %q not found", from)
	}
	diverged := strings.Replace(spk481ShapedIssuesFixture, from, to, 1)
	if err := os.WriteFile(issuesPath, []byte(diverged), 0o644); err != nil {
		t.Fatalf("write diverged issues: %v", err)
	}
	return dbPath, issuesPath
}

// TestDiffCmd_FlaglessNeverReportsVacuousSuccess is the BOB-155 core guard.
//
// It carries its OWN control needle (§11.4.201(7)(b)): before asserting
// anything about the flagless form it proves, through the SAME diffCmd on the
// SAME artifacts, that the planted divergence IS detectable when the Markdown
// is actually supplied. Without that needle a passing assertion could merely
// mean the fixture never diverged.
func TestDiffCmd_FlaglessNeverReportsVacuousSuccess(t *testing.T) {
	dbPath, issuesPath := buildDivergentFixture(t)

	// CONTROL NEEDLE: the divergence is real and this instrument can see it.
	rc, out := captureDiff(t, []string{"--db", dbPath, "--issues", issuesPath})
	if rc == exitOK || !strings.Contains(out, "difference(s)") {
		t.Fatalf("control needle FAILED: path-ful diff did not detect the planted "+
			"divergence (rc=%d) — the fixture is not divergent, so any verdict about "+
			"the flagless form below would be meaningless:\n%s", rc, out)
	}
	t.Logf("control needle OK: path-ful diff sees the planted divergence:\n%s", out)

	// THE DEFECT: same DB, same divergent Markdown on disk, no path flags.
	rc, out = captureDiff(t, []string{"--db", dbPath})

	if rc == exitOK {
		t.Fatalf("BOB-155: flagless `diff --db` returned exitOK (%d) against a DB that "+
			"genuinely diverges from the Markdown on disk — a success verdict from a "+
			"comparison that opened no Markdown at all:\n%s", rc, out)
	}
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("BOB-155: flagless `diff --db` printed the in-sync verdict having read "+
			"no Markdown — indistinguishable from a real successful comparison:\n%s", out)
	}
}

// TestDiffCmd_VerdictNamesItsInputs is the non-negotiable property from the
// BOB-155 acceptance criteria: a reader must always be able to tell a real
// comparison from a vacuous one, which requires the verdict to NAME the files
// it actually read. An unnamed "in sync" is unfalsifiable by inspection.
func TestDiffCmd_VerdictNamesItsInputs(t *testing.T) {
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("setup: md-to-db exited %d", code)
	}

	// In-sync by construction: the DB was just derived from this exact file.
	rc, out := captureDiff(t, []string{"--db", dbPath, "--issues", issuesPath})
	if rc != exitOK {
		t.Fatalf("setup: diff on a freshly-synced pair reported divergence (rc=%d):\n%s", rc, out)
	}
	if !strings.Contains(out, issuesPath) {
		t.Fatalf("BOB-155: the success verdict does not NAME the Markdown file it read "+
			"(want %q in output) — a reader cannot distinguish this from a comparison "+
			"that opened nothing:\n%s", issuesPath, out)
	}
}

// TestDiffCmd_RefusesWhenNoMarkdownSupplied pins the chosen resolution: REFUSE,
// mirroring the sibling subcommands in this same file (`sync md-to-db` and
// `sync db-to-md` both already error out when all of their path flags are
// absent). The refusal must NAME the missing input so it is actionable
// (§11.4.201(5): a guard prints its resolved evidence on every refusal).
func TestDiffCmd_RefusesWhenNoMarkdownSupplied(t *testing.T) {
	tmp := t.TempDir()
	issuesPath := filepath.Join(tmp, "Issues.md")
	if err := os.WriteFile(issuesPath, []byte(spk481ShapedIssuesFixture), 0o644); err != nil {
		t.Fatalf("write issues fixture: %v", err)
	}
	dbPath := filepath.Join(tmp, "wi.db")
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath}); code != exitOK {
		t.Fatalf("setup: md-to-db exited %d", code)
	}

	// Even on a perfectly in-sync pair, the flagless form must refuse rather
	// than answer a question it did not ask.
	rc, out := captureDiff(t, []string{"--db", dbPath})
	if rc == exitOK {
		t.Fatalf("BOB-155: flagless `diff --db` returned exitOK on an in-sync DB instead "+
			"of refusing; a caller cannot tell this from a real comparison:\n%s", out)
	}
	if strings.Contains(out, "in sync") {
		t.Fatalf("BOB-155: flagless `diff --db` still emits an in-sync verdict:\n%s", out)
	}
}

// TestDiffCmd_DBOnlyOptInIsHonestAboutReadingNoMarkdown covers the explicit
// opt-in that preserves the DOCUMENTED DB-internal-integrity invocation shape
// (the statusColumnBodyDesyncs wiring, sync.go) which the blanket refusal would
// otherwise remove. The capability survives — but it must be asked for BY NAME,
// and its verdict must never claim anything about Markdown it never opened.
func TestDiffCmd_DBOnlyOptInIsHonestAboutReadingNoMarkdown(t *testing.T) {
	dbPath, _ := buildDivergentFixture(t)

	rc, out := captureDiff(t, []string{"--db", dbPath, "--db-only"})
	if rc != exitOK {
		t.Fatalf("--db-only on a DB with no INTERNAL desync should pass its own checks "+
			"(rc=%d):\n%s", rc, out)
	}
	if strings.Contains(out, "DB and Markdown are in sync") {
		t.Fatalf("BOB-155: --db-only claimed DB/Markdown sync while reading no Markdown "+
			"— the exact false-null this fix removes:\n%s", out)
	}
	if !strings.Contains(out, "no Markdown") {
		t.Fatalf("BOB-155: the --db-only verdict does not state that it compared no "+
			"Markdown, so it is not self-describing:\n%s", out)
	}
}

// TestDiffCmd_DBOnlyRejectsMarkdownPaths keeps the two modes from being silently
// mixed: --db-only together with a path flag would otherwise read the path or
// ignore it, and either way the verdict would misdescribe what happened.
func TestDiffCmd_DBOnlyRejectsMarkdownPaths(t *testing.T) {
	dbPath, issuesPath := buildDivergentFixture(t)

	rc, out := captureDiff(t, []string{"--db", dbPath, "--db-only", "--issues", issuesPath})
	if rc == exitOK {
		t.Fatalf("--db-only combined with --issues should be refused as ambiguous, got "+
			"exitOK:\n%s", out)
	}
}
