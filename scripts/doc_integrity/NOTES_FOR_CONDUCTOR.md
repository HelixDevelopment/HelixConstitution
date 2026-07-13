# doc-integrity — Notes for the conductor (anchor landing + wiring)

**Revision:** 1
**Last modified:** 2026-07-08T08:30:00Z
**Status:** implementation COMPLETE + self-validated; anchor + seam-wiring are the conductor's remaining steps.
**Authority:** hand-off note for the T1/main conductor per §11.4.26 (constitution update) + the DESIGN.

---

## 1. What is built (FACT)

Project-agnostic Go tool at `constitution/scripts/doc_integrity/` (module
`github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity`, `go 1.21`,
stack: `github.com/xuri/excelize/v2`, `github.com/mattn/go-sqlite3`,
`gopkg.in/yaml.v3` — matches the sibling `workable-items` tool).

- **5 check families** implemented + unit-tested: DEDUP (`DEDUP-01/02`),
  TIMELINE (`TIME-01/01b/02/03/04`), CROSS-DOC (`XDOC-01`), INTEGRITY
  (`INTEG-01/02/03`), STRUCTURAL (`STRUCT-01/02`).
- **4 adapters** (real, tested): `xlsx` (excelize), `markdown-table`,
  `markdown-headings` (Issues/Fixed H2 format), `sqlite` (READ-ONLY,
  `workable_items.db`).
- **`selfcheck`** subcommand + embedded golden fixtures (§11.4.107(10)):
  golden-good PASS, one golden-bad per family FAIL (pinpointed rule), a
  negative-control (distinct same-subject NanoKVM tasks) PASS.
- **Verdict CLI**: `verify` / `report` / `selfcheck` / `version`;
  exit 0 PASS / 1 FAIL / 2 config-error / 3 SKIP (source unavailable —
  honest §11.4.3, never a fake PASS).
- **Wiring hook**: `wire/doc_integrity_gate.sh` (the pre-export/commit seam,
  REFUSES export on FAIL, honest SKIP on tool/source absence).
- **Recommended pre-build gate stub**: `wire/CM-DOC-INTEGRITY-VALIDATION.gate.sh`
  (asserts DESIGN §5.2 invariants (i)–(v); (iii)/(iv)/(v) PENDING until the
  seam + consumer checkset land).

Green evidence: `qa-results/doc_integrity_build_20260708T082430Z.log`
(`gofmt -l` empty, `go vet`, `go build`, `go test -race -count=3` all pass,
selfcheck PASS, load-bearing mutation → selfcheck exit 1, NO_RESIDUE).

## 2. Anchor text (land via §11.4.26 fetch-first)

The finalized **§11.4.186** anchor text is in `DESIGN.md §6` (drafted in house
style, universal per §11.4.17). Only the anchor NUMBER is provisional — confirm
no collision at land time (latest present is §11.4.185 + §12.12, so §11.4.186 is
the open slot). Land into: constitution `Constitution.md` (canonical) + mirrors
`CLAUDE.md` / `AGENTS.md` / `QWEN.md` / `GEMINI.md` + project
`docs/guides/ATMOSPHERE_CONSTITUTION.md` (§11.4.157 lockstep).

## 3. Gate + paired §1.1 mutation spec (DESIGN §5.2 / §6)

- Gate `CM-DOC-INTEGRITY-VALIDATION` — 5 invariants (i)–(v); reference stub at
  `wire/CM-DOC-INTEGRITY-VALIDATION.gate.sh`.
- Gate `CM-COVENANT-114-186-PROPAGATION` — literal `11.4.186` across the
  canonical + consumer fleet.
- Paired mutations (all proven or specified):
  - **m2 (PROVEN this session):** neuter one golden-bad expected-FAIL (or the
    check that catches it) → `selfcheck` exits 1 → `CM-DOC-INTEGRITY-VALIDATION`
    FAILs. Reproduced in an isolated temp copy; NO residue in the real tree.
  - **m1:** strip the `doc_integrity_gate.sh` / `doc-integrity verify`
    invocation from `sync_all_markdown_exports.sh` → gate invariant (iii) FAILs.
  - **m3:** strip the `11.4.186` literal from one consumer file → propagation
    gate FAILs.

## 4. Seam-wiring TODO (conductor — contention paths, so conductor owns them)

Insert `bash constitution/scripts/doc_integrity/wire/doc_integrity_gate.sh
<checkset> <repo_root>` BEFORE the render step in all three seams (export
REFUSED on exit 1):

1. `scripts/testing/sync_all_markdown_exports.sh` — pre-export gate.
2. Docs Chain `verify` — register a `doc_integrity` check node in the
   consumer's `.docs_chain/contexts/*.yaml`.
3. `scripts/commit_all.sh` — refuse the doc-set commit class on FAIL.

## 5. Consumer checkset (data stream owns the values, NOT this tool)

Author `.atmosphere/doc_integrity/checkset.yaml` (consumer-owned, §11.4.28)
registering the ATMOSphere doc-set: `docs/planning/2026.07/V9/Plan_v9.0.xlsx`
(xlsx, sheet "Реалистичный", V9 = authoritative for CROSS-DOC),
`docs/planning/2026.07/V5/MVP.md` + `MVP_Summary.md`, and
`docs/workable_items.db`. Schema + an illustrative example: `DESIGN.md §1.4`.
Do NOT hardcode any of these paths in Go — they are config data.

## 6. §11.4.18 external-doc note

`README.md` (in this module dir) documents the tool + wiring hook usage. If the
project's `CM-SCRIPT-DOCS-SYNC` gate requires a `docs/scripts/<name>.md`
companion for the two `wire/*.sh` scripts, add those pointers when wiring the
seam (out of scope for the tool build; flagged here honestly per §11.4.6).
