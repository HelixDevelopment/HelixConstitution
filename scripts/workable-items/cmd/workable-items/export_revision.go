// export_revision.go — §11.4.44 monotonic-revision reconciliation for
// `export`.
//
// Forensic anchor (task #68 / BOB-108, filed by the BOB-069 subagent a9876d9b):
// `export` regenerates docs/Issues.md + docs/Fixed.md by replaying the
// §11.4.44 **Revision:**/**Last modified:** header VERBATIM from the
// doc_segments "raw" segment captured at the last `sync md-to-db` import
// (renderDocument, db.go — the byte-identical round-trip path). That segment
// is frozen at whatever the on-disk file's header read at THAT import — it
// does not track a later, legitimate bump the on-disk file received through
// any other path (a manual §11.4.44 bump, docs_chain, or a different sync
// run). Left alone, `export` silently REGRESSES the committed Revision
// counter downward. Reproduced live 2026-08-18 by running the real binary
// against the real repo docs/ tree (immediately reverted via `git checkout`
// after capture): docs/Issues.md Revision 8 -> 6, docs/Fixed.md Revision
// 17 -> 15 — both regressions below the already-committed HEAD value. §11.4.44
// is explicit: "monotonic positive integer, never reset, never skipped" — a
// regression is a violation regardless of source.
//
// reconcileRevisionHeader is the fix: BEFORE writing the regenerated
// document, read the §11.4.44 header ALREADY on disk at targetPath (the
// committed value — the source of truth for "what must never be regressed
// below") and compare it against the header the DB's raw segment carries.
// The final Revision is monotonic-never-reset (never below either side) and
// bumps by exactly 1 ONLY when the regenerated body content genuinely
// differs from what is already committed — a bump is earned by a real
// change, never invented (§11.4.6). When nothing genuinely changed, the
// existing file's Revision AND Last-modified are preserved byte-for-byte
// (no gratuitous re-stamp on a no-op regeneration).
package main

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"time"
)

var (
	revisionLineRe     = regexp.MustCompile(`(?m)^\*\*Revision:\*\*[ \t]*(\d+)[ \t]*$`)
	lastModifiedLineRe = regexp.MustCompile(`(?m)^\*\*Last modified:\*\*.*$`)
)

// reconcileRevisionHeader rewrites the §11.4.44 Revision + Last-modified
// header lines of `rendered` (the just-regenerated document text) so the
// emitted Revision NEVER regresses below whatever is already committed at
// targetPath. When targetPath does not yet exist, there is nothing to
// regress below — rendered is returned unchanged (the DB's own value is
// authoritative for a first-ever write).
func reconcileRevisionHeader(rendered, targetPath string) (string, error) {
	existingBytes, err := os.ReadFile(targetPath)
	if err != nil {
		if os.IsNotExist(err) {
			return rendered, nil
		}
		return "", fmt.Errorf("read existing %s: %w", targetPath, err)
	}
	existing := string(existingBytes)

	renderedRev := extractRevision(rendered)
	existingRev := extractRevision(existing)

	// A bump is earned ONLY by a genuine content change — compare both texts
	// with the two volatile header lines stripped first, so those two
	// always-different lines can never by themselves force a false
	// "content changed" verdict.
	contentChanged := stripRevisionHeader(existing) != stripRevisionHeader(rendered)

	finalRev := existingRev
	if renderedRev > finalRev {
		finalRev = renderedRev
	}

	if !contentChanged {
		// Nothing genuinely changed — restore the ALREADY-COMMITTED header
		// verbatim (never regress, never gratuitously re-stamp).
		out := revisionLineRe.ReplaceAllString(rendered, fmt.Sprintf("**Revision:** %d", finalRev))
		if existingLastMod := lastModifiedLineRe.FindString(existing); existingLastMod != "" {
			out = lastModifiedLineRe.ReplaceAllString(out, existingLastMod)
		}
		return out, nil
	}

	finalRev++
	out := revisionLineRe.ReplaceAllString(rendered, fmt.Sprintf("**Revision:** %d", finalRev))
	out = lastModifiedLineRe.ReplaceAllString(out, fmt.Sprintf("**Last modified:** %s", time.Now().UTC().Format(time.RFC3339)))
	return out, nil
}

// extractRevision reads the §11.4.44 `**Revision:** N` value from doc text,
// or 0 when absent (an unversioned/legacy doc — never treated as "ahead").
func extractRevision(doc string) int {
	m := revisionLineRe.FindStringSubmatch(doc)
	if m == nil {
		return 0
	}
	n, err := strconv.Atoi(m[1])
	if err != nil {
		return 0
	}
	return n
}

// stripRevisionHeader removes the two volatile §11.4.44 header lines
// (Revision + Last modified) so the REST of a document can be compared for
// a genuine content change without those two always-different lines
// forcing a false positive.
func stripRevisionHeader(doc string) string {
	doc = revisionLineRe.ReplaceAllString(doc, "")
	doc = lastModifiedLineRe.ReplaceAllString(doc, "")
	return doc
}
