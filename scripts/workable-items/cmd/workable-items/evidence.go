// evidence.go — HXC-224: the RECORD-TIME half of the closure-evidence
// invariant.
//
// # THE DEFECT THIS CLOSES
//
// A closure's `item_history.evidence_path` is the pointer to the captured proof
// that IS the closure's warrant (§11.4.5 / §11.4.69 / §11.4.123 / §11.4.226).
// HXC-217 landed the DETECTIVE half — unresolvableClosureEvidence (sync.go)
// flags a closed item whose evidence path does not resolve, at `validate` time.
// The PREVENTIVE half was never implemented: the subcommands that RECORD an
// evidence path accepted any non-empty string, so a closure citing a path that
// had never existed landed in the single source of truth and was only flagged
// on a subsequent sweep, if one ran. Reproduced on the pre-fix source against a
// copy of the live records (2026-08-08):
//
//	close … --evidence /tmp/DEFINITELY_NOT_A_REAL_PATH/x.log  →  exit 0, mutation landed
//
// A closure recorded with a fabricated evidence path is a §11.4 PASS-bluff
// written directly into the tracker: it reads as evidence-backed everywhere
// downstream while the proof it cites cannot be produced on demand.
//
// # THE GUARD, AND WHY IT REFUSES EXACTLY WHAT IT REFUSES
//
// checkEvidencePath is deliberately calibrated against the LIVE evidence corpus
// rather than an assumed shape (§11.4.6 — measured, not guessed). Of the 77
// distinct evidence paths recorded in the live tree at the time of writing:
// 54 are non-empty files, 22 are DIRECTORIES (the `docs/qa/<run-id>/` shape
// §11.4.83 mandates), 1 does not resolve (the single real HXC-217 finding).
// Refusing directories — the obvious naive rule — would therefore have been a
// mass §11.4.201(1) FALSE-POSITIVE refusal against 22 legitimate closures: a
// FAIL-bluff exactly as damaging as the PASS-bluff being fixed.
//
// Accepted: a non-empty regular file, or a non-empty directory (symlinks are
// followed, matching the validator).
// Refused: a path that does not resolve; a resolvable path that is EMPTY (a
// 0-byte file or an empty directory carries no captured proof — §11.4.69's
// `ab_pass_with_evidence` verifies exists AND non-empty); anything that is
// neither a regular file nor a directory.
//
// The empty-artefact rule makes this guard deliberately STRICTER than the
// HXC-217 validator, which only stats. Stricter at record time is safe — it can
// never accept something the detective gate would later reject. The reverse
// asymmetry would be the bug, and is what the process-cwd note below prevents.
//
// # PATH ANCHORING (the subtle part)
//
// Resolution goes through resolveInvocationRelative — the SAME anchoring the
// HXC-217 validator uses (the HXC-201 $PWD mechanism). This is load-bearing in
// both directions:
//
//   - Without it, a legitimate repo-relative `docs/qa/<run-id>/…` path would be
//     resolved against THIS PROCESS's cwd, which `go run -C` relocates into the
//     tool's own source tree — refusing essentially every real evidence path.
//     Measured precedent: a validator run from the tool's own source directory
//     reported 124 spurious violations; the same run with $PWD at the repo root
//     reported 1 real one.
//   - Using the SAME function as the validator (rather than a more lenient
//     "resolves either way" rule) keeps the preventive and detective halves in
//     agreement. A path that resolves only against the process cwd is refused
//     here precisely because `validate` would flag it later; accepting it would
//     merely defer the refusal to a harder-to-diagnose moment.
//
// Every refusal prints the raw value AND the resolved path, so a false refusal
// is diagnosable in one read (§11.4.201(5) — a refusal reports its resolved
// evidence).
//
// # SCOPE
//
// Wired into the subcommands that record a CLOSURE-class evidence path: close,
// obsolete-details, subtask-status (→ Completed) and move. `reopen --incident`
// also writes item_history.evidence_path but is deliberately NOT wired: a
// Reopened event is by construction not a closure, and the HXC-217 validator
// explicitly exempts open items. Enforcing at record time what the detective
// gate declines to enforce would create a new policy — and a new false-refusal
// class — rather than close the HXC-224 gap.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return nil` removes the guard; close_evidence_recordtime_test.go then FAILs
// on every refusal case — proving the guard is not a tautology.
package main

import (
	"fmt"
	"os"
	"strings"
)

// checkEvidencePath reports whether `evidence` names captured proof that can be
// produced on demand at the recorded path.
//
// An empty (or whitespace-only) value returns nil: whether --evidence is
// REQUIRED is each caller's decision (close and obsolete-details require it,
// move does not), and each caller already reports its own missing-flag error.
// Silently making the flag mandatory here would change unrelated commands'
// contracts.
func checkEvidencePath(evidence string) error {
	raw := strings.TrimSpace(evidence)
	if raw == "" {
		return nil
	}

	resolved := resolveInvocationRelative(raw)
	info, statErr := os.Stat(resolved)
	if statErr != nil {
		// Two observed sub-classes, named separately because their remediations
		// differ: capture an artefact vs. locate one. Classification happens
		// only AFTER resolution failed, so a legitimate path containing a space
		// is never mis-refused as narrative.
		kind := "well-formed path, but nothing exists there"
		if strings.ContainsAny(raw, " \t\r\n") {
			kind = "narrative or multi-value text in a single-path field"
		}
		return fmt.Errorf(
			"evidence %q does not resolve (%s; resolved to %q) — a closure's captured proof must be producible on demand (§11.4.5/§11.4.69/§11.4.123/§11.4.226). Capture the artefact first, then record the closure",
			firstLine(raw), kind, resolved)
	}

	switch {
	case info.IsDir():
		entries, err := os.ReadDir(resolved)
		if err != nil {
			return fmt.Errorf(
				"evidence %q resolves to a directory that cannot be read (resolved to %q): %v",
				firstLine(raw), resolved, err)
		}
		if len(entries) == 0 {
			return fmt.Errorf(
				"evidence %q resolves to an EMPTY directory (resolved to %q) — an evidence directory with no artefacts in it carries no captured proof (§11.4.69 evidence must exist AND be non-empty)",
				firstLine(raw), resolved)
		}
	case info.Mode().IsRegular():
		if info.Size() == 0 {
			return fmt.Errorf(
				"evidence %q resolves to an EMPTY file (0 bytes; resolved to %q) — a capture that produced nothing is not captured proof (§11.4.69 evidence must exist AND be non-empty)",
				firstLine(raw), resolved)
		}
	default:
		return fmt.Errorf(
			"evidence %q resolves to neither a regular file nor a directory (mode %s; resolved to %q) — captured proof must be a readable artefact",
			firstLine(raw), info.Mode(), resolved)
	}

	return nil
}

// requireEvidencePath applies checkEvidencePath and reports the refusal on
// stderr prefixed with the subcommand name, returning false when the caller
// must abort with exitUsage. Keeping the report here means every wired
// subcommand refuses with the identical, actionable message.
func requireEvidencePath(cmd, evidence string) bool {
	if err := checkEvidencePath(evidence); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", cmd, err)
		return false
	}
	return true
}
