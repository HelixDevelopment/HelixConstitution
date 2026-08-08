// atm842_subitem_scope_test.go — ATM-842 RED→GREEN guard (§11.4.115 polarity).
//
// DEFECT (ATM-842): the Status/Type derivation (buildItem), the derivation
// oracle (lastBodyStatus) and the canonicalizer (canonicalizeBodyStatusLine)
// all scanned the WHOLE H2 block with LAST-wins semantics. An item whose block
// contains nested `### ` sub-items therefore took the LAST SUB-ITEM's
// `**Status:**` / `**Type:**` into the item's own columns, and a status change
// REWROTE THE SUB-ITEM's Status line instead of the item's own.
//
// Measured on the live registry (764 items, read-only copy, 2026-08-04):
// 11 items carried a sub-item's Status in their status column and 8 carried a
// sub-item's Type — e.g. ATM-415 (parent `Fixed (→ Fixed.md)`/`Bug`) showed
// `Completed (→ Fixed.md)`/`Task` from its last `### JB.` sub-item, which also
// breaks the §11.4.33 Status↔Type pairing.
//
// FIX: all three scan only the item's OWN metadata region — the block prefix
// BEFORE the first nested `### ` / `#### ` subheading — the exact region the
// pre-existing item-vs-section discriminator statusBeforeSubheading() scans.
//
// SCOPE (proven, not assumed): items carrying SEVERAL `**Status:**` lines in
// their own region with NO intervening subheading (e.g. ATM-392, whose body
// documents the split as "correct, not a contradiction") are a DIFFERENT
// phenomenon and are deliberately left byte-identical by this fix — pinned by
// TestATM842_OwnRegionMultiStatus_UnchangedByFix below.
package main

import (
	"strings"
	"testing"
)

// atm842ParentWithSubItems mirrors the real ATM-415 / ATM-377 / ATM-280 shape:
// an H2 item whose own metadata block is followed by `### ` sub-items that each
// carry their own Status/Type meta lines.
const atm842ParentWithSubItems = `## §X. [ATM-842] Parent item with nested sub-items

**Status:** In progress
**Type:** Bug

Parent prose that belongs to the item itself.

### S1. First sub-item — ` + "`Completed (→ Fixed.md)`" + `

**Status:** Completed (→ Fixed.md)
**Type:** Task

Sub-item prose.

### S2. Second sub-item

**Status:** Queued
**Type:** Feature

Trailing sub-item prose.
`

// TestATM842_DerivationUsesItemOwnRegion: the item's own columns MUST come from
// its own metadata block, never from a nested sub-item.
func TestATM842_DerivationUsesItemOwnRegion(t *testing.T) {
	it := buildItem("ATM-842", "Parent item with nested sub-items", atm842ParentWithSubItems, "Issues")
	if it.Status != "In progress" {
		t.Errorf("Status: got %q, want %q (the item's OWN **Status:** line, not a sub-item's)", it.Status, "In progress")
	}
	if it.Type != "Bug" {
		t.Errorf("Type: got %q, want %q (the item's OWN **Type:** line, not a sub-item's)", it.Type, "Bug")
	}

	got, ok := lastBodyStatus(atm842ParentWithSubItems)
	if !ok {
		t.Fatalf("lastBodyStatus: found=false, want true")
	}
	if got != "In progress" {
		t.Errorf("lastBodyStatus: got %q, want %q", got, "In progress")
	}
}

// TestATM842_CanonicalizePatchesOwnLineNotSubItem: a status change MUST rewrite
// the item's own Status line and leave every sub-item's Status line untouched.
func TestATM842_CanonicalizePatchesOwnLineNotSubItem(t *testing.T) {
	out := canonicalizeBodyStatusLine(atm842ParentWithSubItems, "In testing")

	if !strings.Contains(out, "**Status:** In testing\n**Type:** Bug\n") {
		t.Errorf("own Status line was not rewritten to %q; body:\n%s", "In testing", out)
	}
	// Every sub-item Status line MUST survive byte-identically.
	for _, sub := range []string{
		"**Status:** Completed (→ Fixed.md)\n**Type:** Task\n",
		"**Status:** Queued\n**Type:** Feature\n",
	} {
		if !strings.Contains(out, sub) {
			t.Errorf("sub-item block was CORRUPTED — %q no longer present; body:\n%s", sub, out)
		}
	}
	if strings.Count(out, "**Status:**") != strings.Count(atm842ParentWithSubItems, "**Status:**") {
		t.Errorf("Status-line count changed: got %d, want %d",
			strings.Count(out, "**Status:**"), strings.Count(atm842ParentWithSubItems, "**Status:**"))
	}
	// Round-trip invariant: re-deriving from the canonicalized body yields the
	// value that was written (the generator-symmetry half must still hold).
	if got, ok := lastBodyStatus(out); !ok || got != "In testing" {
		t.Errorf("round-trip: lastBodyStatus(canonicalize(body,%q)) = (%q,%v), want (%q,true)",
			"In testing", got, ok, "In testing")
	}
}

// TestATM842_CanonicalizeNoOpWhenAlreadyConsistent: the documented STRICT
// byte-identical no-op must survive the scope change (a body already carrying
// the column value in its own region is returned unchanged).
func TestATM842_CanonicalizeNoOpWhenAlreadyConsistent(t *testing.T) {
	if got := canonicalizeBodyStatusLine(atm842ParentWithSubItems, "In progress"); got != atm842ParentWithSubItems {
		t.Errorf("canonicalizeBodyStatusLine must be a byte-identical no-op when the item's own\nStatus already equals the column; got a rewrite:\n%s", got)
	}
}

// TestATM842_NoSubHeadingUnchanged is the §11.4.201(1) FALSE-POSITIVE GUARD:
// the overwhelmingly common single-block item (no nested subheading) MUST keep
// behaving exactly as before the fix.
func TestATM842_NoSubHeadingUnchanged(t *testing.T) {
	body := `## §Y. [ATM-843] Plain item, no sub-items

**Status:** Queued
**Type:** Task

Some prose.
`
	it := buildItem("ATM-843", "Plain item, no sub-items", body, "Issues")
	if it.Status != "Queued" || it.Type != "Task" {
		t.Errorf("plain item derivation regressed: got %q/%q, want %q/%q", it.Status, it.Type, "Queued", "Task")
	}
	out := canonicalizeBodyStatusLine(body, "Reopened")
	if !strings.Contains(out, "**Status:** Reopened\n") {
		t.Errorf("plain item canonicalize regressed; body:\n%s", out)
	}
	if got, _ := lastBodyStatus(out); got != "Reopened" {
		t.Errorf("plain item round-trip regressed: got %q", got)
	}
}

// TestATM842_OwnRegionMultiStatus_UnchangedByFix pins the DELIBERATE-SPLIT class
// (real instance: ATM-392, whose body states the two Status lines are "correct,
// not a contradiction"): SEVERAL `**Status:**` lines inside the item's OWN
// region, no intervening subheading. That is a DIFFERENT phenomenon from
// ATM-842 sub-item contamination and MUST stay byte-identical to pre-fix
// behaviour (last-in-own-region wins) — this fix must not silently re-decide it.
func TestATM842_OwnRegionMultiStatus_UnchangedByFix(t *testing.T) {
	body := `## §Z. [ATM-844] Split item carrying two lifecycle states

**Status:** Reopened
**Type:** Bug

Prose for the first sub-state.

**Status:** Queued
**Type:** Bug

Prose for the second sub-state.
`
	it := buildItem("ATM-844", "Split item", body, "Issues")
	if it.Status != "Queued" {
		t.Errorf("own-region multi-status resolution changed: got %q, want %q (last-in-own-region, pre-fix behaviour)", it.Status, "Queued")
	}
	out := canonicalizeBodyStatusLine(body, "In testing")
	if !strings.Contains(out, "**Status:** Reopened\n") {
		t.Errorf("first own-region Status line must stay untouched; body:\n%s", out)
	}
	if !strings.Contains(out, "**Status:** In testing\n") {
		t.Errorf("last own-region Status line must be the patch target; body:\n%s", out)
	}
}
