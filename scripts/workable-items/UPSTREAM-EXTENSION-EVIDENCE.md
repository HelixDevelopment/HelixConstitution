# workable-items UPSTREAM EXTENSION — §11.4.74 LVA-3 OWED-subcommands + export pipeline

**Revision:** 1
**Last modified:** 2026-05-31T00:00:00Z

Adds the `update` / `reopen` / `block` subcommands + the `export` documentation
pipeline that Lava's LVA-3 §11.4.74 migration found OWED. Project-agnostic per
CONST-051 (no Lava-specific context; generic reusable subcommands only).

## Files changed (inside the constitution submodule)

| File | Change |
|---|---|
| `scripts/workable-items/cmd/workable-items/mutate.go` | NEW — `update` / `reopen` / `block` subcommands + helpers. |
| `scripts/workable-items/cmd/workable-items/export.go` | NEW — `export` subcommand + summary generators + pandoc-gated HTML/PDF/DOCX. |
| `scripts/workable-items/cmd/workable-items/mutate_test.go` | NEW — 8 table-driven tests for update/reopen/block. |
| `scripts/workable-items/cmd/workable-items/export_test.go` | NEW — 1 test (multi-assert) for export docs+summaries+honest no-fake siblings. |
| `scripts/workable-items/cmd/workable-items/main.go` | dispatch + usage extended for `update`/`reopen`/`block`/`export`. |
| `scripts/workable-items/README.md` | Revision 3 — documents the four new subcommands. |

## New subcommand contracts

- `update --id <ID> --db <p> [--title|--severity|--description|--type|--status|--created-by|--assigned-to ...] [--location Issues|Fixed]`
  — mutates ONLY the explicitly-set fields (`flag.Visit`-driven), regenerates
  `body_md`, appends an `item_history` `Updated` row (§11.4.34). Rejects unknown
  IDs, missing field flags, and a §11.4.91-too-short `--description`.
- `reopen --id <ID> --db <p> --why <closed-vocab> --who <AI|User> --when <ISO> --incident <path>`
  — sets `status=Reopened`, embeds `**Reopened-Details:**` in `body_md`, records
  the four §11.4.34 facts in `item_history`. Rejects any missing fact, a
  non-vocabulary `--why`, and a non-`AI|User` `--who`.
- `block --id <ID> --db <p> --details <text> [--why <text>] [--unblock <text>] [--who <text>]`
  — sets `status=Operator-blocked`, embeds `**Operator-Block-Details:**`, writes
  an `operator_block_details` row (§11.4.21). Rejects empty `--details`.
- `export --db <p> [--out-dir <d>] [--no-formats] [--out-issues|--out-fixed <p>]`
  — regenerates Issues.md + Fixed.md (byte-identical round-trip) + Issues_Summary.md
  (§11.4.12 open-only Type×Status tally + per-item rows) + Fixed_Summary.md
  (§11.4.53 closed-only) + §11.4.65 HTML/PDF/DOCX siblings via pandoc.
  pandoc/weasyprint steps are `exec.LookPath`-gated — when absent the `.md` is
  still emitted and an HONEST message is printed; NO fake sibling is fabricated
  (§6.J / §11.4.6).

## pandoc / weasyprint availability in THIS environment

`pandoc` and `weasyprint` are BOTH PRESENT on this host:

```
go         -> /opt/homebrew/bin/go (go1.26.2 darwin/arm64)
pandoc     -> /opt/homebrew/bin/pandoc
weasyprint -> /opt/homebrew/bin/weasyprint
```

Therefore the full HTML/PDF/DOCX generation path WAS exercised end-to-end here.
The end-to-end smoke (below) shows all 4 .md docs each produced .html + .docx +
.pdf siblings (16 files total). The `export_test.go` automated test exercises the
`--no-formats` path AND asserts the honest no-fake-sibling behaviour.

## go build (verbatim)

```
$ CGO_ENABLED=1 GOMAXPROCS=2 go build ./...
B_OK   (exit 0)
```

## go vet (verbatim)

```
$ CGO_ENABLED=1 GOMAXPROCS=2 go vet ./...
V_OK   (exit 0)
```

## go test (verbatim) — full suite, 35 tests, all PASS (26 pre-existing + 9 new)

```
$ CGO_ENABLED=1 GOMAXPROCS=2 go test -count=1 ./...
ok  	github.com/HelixDevelopment/HelixConstitution/scripts/workable-items/cmd/workable-items	0.704s
```

New tests (verbatim `-v`, all PASS):

```
--- PASS: TestUpdateCmd_MutatesFieldsAndRecordsHistory (0.01s)
--- PASS: TestUpdateCmd_RejectsShortDescription (0.01s)
--- PASS: TestUpdateCmd_RejectsUnknownID (0.01s)
--- PASS: TestUpdateCmd_RequiresAField (0.01s)
--- PASS: TestReopenCmd_SetsReopenedWithFullAttribution (0.01s)
--- PASS: TestReopenCmd_RejectsPartialAttribution (0.01s)
--- PASS: TestBlockCmd_SetsOperatorBlockedWithDetails (0.01s)
--- PASS: TestBlockCmd_RejectsEmptyDetails (0.01s)
--- PASS: TestExportCmd_EmitsDocsAndSummaries (0.01s)
PASS
ok  	github.com/HelixDevelopment/HelixConstitution/scripts/workable-items/cmd/workable-items	0.215s
```

## --help (verbatim)

```
workable-items — §11.4.93 SQLite-SSoT for workable items

Usage:
  workable-items <subcommand> [args...]

Subcommands:
  sync md-to-db --db <p> [--issues <p>] [--fixed <p>]   Parse trackers, upsert DB.
  sync db-to-md --db <p> [--out-issues <p>] [--out-fixed <p>]  Regenerate trackers from DB.
  diff --db <p> [--issues <p>] [--fixed <p>]            Show DB vs Markdown divergence.
  validate --db <p>                                     Closed-set + §11.4.91 invariants.
  add <type> <severity> --db <p> --title <T> --description <D> [--id <id>] [--prefix <P>] [--created-by <h>] [--assigned-to <h>]
                                                        Create a new Queued item in Issues.
  update --id <ID> --db <p> [--title|--severity|--description|--type|--status|--created-by|--assigned-to ...] [--location Issues|Fixed]
                                                        Mutate fields on an existing item (§11.4.34 audit).
  reopen --id <ID> --db <p> --why <reason> --who <AI|User> --when <ISO> --incident <p> [--location Issues|Fixed]
                                                        Set Status=Reopened with §11.4.34 source attribution.
  block --id <ID> --db <p> --details <T> [--why <T>] [--unblock <T>] [--who <T>] [--location Issues|Fixed]
                                                        Set Status=Operator-blocked with §11.4.21 details.
  close <atm-id> --db <p> --status <fixed|implemented|completed|obsolete> --evidence <p>
                                                        Atomic Issues→Fixed closure (§11.4.19).
  report --db <p> [--by-type|--by-status|--by-severity|--by-assigned|--by-creator|--obsolete-audit]
                                                        Read-only grouped tally / §11.4.90 audit.
  export --db <p> [--out-dir <d>] [--issues <p>] [--fixed <p>] [--out-issues <p>] [--out-fixed <p>]
                                                        Regenerate Issues.md + Fixed.md + Summary docs + HTML/PDF/DOCX (§11.4.12/§11.4.53).

Canonical authority: Constitution.md §11.4.93.
```

## End-to-end smoke (real binary, all four new subcommands + export with pandoc PRESENT)

```
$ workable-items add Bug Critical --db wi.db --title "..." --description "..."
add: created WIT-001 (Bug, status=Queued) in Issues
$ workable-items update --id WIT-001 --db wi.db --status "In progress"
update: WIT-001 updated in Issues (status=In progress, type=Bug)
$ workable-items reopen --id WIT-001 --db wi.db --why test-failed --who AI --when 2026-05-31 --incident qa/x.log
reopen: WIT-001 reopened in Issues (By:AI On:2026-05-31 Reason:test-failed Evidence:qa/x.log)
$ workable-items block --id WIT-001 --db wi.db --details "Needs operator host"
block: WIT-001 set Operator-blocked in Issues (WHAT:Needs operator host)
$ workable-items export --db wi.db --out-dir ./out
export: wrote out/Issues.md
export: wrote out/Fixed.md
export: wrote out/Issues_Summary.md
export: wrote out/Fixed_Summary.md
export: wrote out/Issues.html
export: wrote out/Issues.docx
export: wrote out/Issues.pdf
export: wrote out/Fixed.html
export: wrote out/Fixed.docx
export: wrote out/Fixed.pdf
export: wrote out/Issues_Summary.html
export: wrote out/Issues_Summary.docx
export: wrote out/Issues_Summary.pdf
export: wrote out/Fixed_Summary.html
export: wrote out/Fixed_Summary.docx
export: wrote out/Fixed_Summary.pdf
```

Generated `Issues_Summary.md` content (proves the open-only Type×Status tally +
per-item row reflect the block):

```
# Issues_Summary

Open workable items (current_location = Issues), regenerated from the SQLite single-source-of-truth (§11.4.12).

## Counts by Type × Status

| Type | Status | Count |
|---|---|---|
| Bug | Operator-blocked | 1 |
| **TOTAL** | | **1** |

## Items

| ATM ID | Type | Status | Severity | Description |
|---|---|---|---|---|
| WIT-001 | Bug | Operator-blocked | High | A smoke test bug with enough words to clear the floor here |
```

`report --by-status` after the block (read-only cross-confirmation):

```
Workable items by Status:
  Operator-blocked  1
  ---------------------
  TOTAL             1
```

## Falsifiability rehearsals (§1.1 / §11.4.43) — each MUTATED → FAIL → reverted → PASS

Each rehearsal: applied the mutation, ran the targeted test (exit 1 = FAIL =
caught), reverted from a clean backup, re-ran (exit 0 = PASS).

### Rehearsal 1 — `update` history append

- **Mutation:** removed the `recordHistory(tx, *id, "Updated", ...)` call in `updateCmd`.
- **Test:** `TestUpdateCmd_MutatesFieldsAndRecordsHistory`
- **Observed FAIL (exit 1):**
  ```
  --- FAIL: TestUpdateCmd_MutatesFieldsAndRecordsHistory (0.01s)
      mutate_test.go:80: Updated history rows = 0, want 1
  FAIL
  ```
- **Reverted:** yes (restored from backup; re-run exit 0).

### Rehearsal 2 — `reopen` §11.4.34 attribution guard

- **Mutation:** removed the `--why` required + closed-vocab guards in `reopenCmd`.
- **Test:** `TestReopenCmd_RejectsPartialAttribution`
- **Observed FAIL (exit 1):** the test reported `reopenCmd succeeded; want failure (§11.4.34)`
  for the "missing why" + "bad why vocab" cases (assertion at `mutate_test.go:188`).
- **Reverted:** yes (restored from backup; re-run exit 0).

### Rehearsal 3 — `block` §11.4.21 empty-details guard

- **Mutation:** removed the empty-`--details` guard in `blockCmd`.
- **Test:** `TestBlockCmd_RejectsEmptyDetails`
- **Observed FAIL (exit 1):** `blockCmd with blank --details succeeded; want failure (§11.4.21)`
  (assertion at `mutate_test.go:256`).
- **Reverted:** yes (restored from backup; re-run exit 0).

### Rehearsal 4 — `export` Issues_Summary open-only filter

- **Mutation:** `renderIssuesSummary` made to include ALL items (closed leak).
- **Test:** `TestExportCmd_EmitsDocsAndSummaries`
- **Observed FAIL (exit 1):** `Issues_Summary leaked closed item WIT-003`
  (assertion at `export_test.go:89`).
- **Reverted:** yes (restored from backup; full suite re-run exit 0,
  `ok ... 0.704s`).

## §11.4.84 working-tree quiescence

Post-rehearsal `grep -rl "MUTATED" cmd/` returns **0** files; `diff` confirms
`mutate.go` + `export.go` are byte-identical to the verified-good backups — no
mutation residue remains in the source tree.

## Bluff-Audit stamp (ready to paste into the CONST-049 commit)

```
Bluff-Audit: mutate_test.go (TestUpdateCmd_MutatesFieldsAndRecordsHistory, TestReopenCmd_RejectsPartialAttribution, TestBlockCmd_RejectsEmptyDetails) + export_test.go (TestExportCmd_EmitsDocsAndSummaries)
  Mutation 1: removed update's recordHistory("Updated") append
  Observed-Failure 1: mutate_test.go:80: Updated history rows = 0, want 1
  Mutation 2: removed reopen's --why required + closed-vocab guards
  Observed-Failure 2: mutate_test.go:188: reopenCmd succeeded; want failure (§11.4.34)
  Mutation 3: removed block's empty --details guard
  Observed-Failure 3: mutate_test.go:256: blockCmd with blank --details succeeded; want failure (§11.4.21)
  Mutation 4: made renderIssuesSummary include closed items (open-only filter dropped)
  Observed-Failure 4: export_test.go:89: Issues_Summary leaked closed item WIT-003
  Reverted: yes
```

## MAIN-AGENT ACTION REQUIRED

This is a **constitution-submodule** change. The subagent did NOT commit or push
anything. The MAIN AGENT MUST perform the **CONST-049 7-step pipeline** for the
constitution submodule: fetch-first → careful conflict resolution → commit (with
the Bluff-Audit stamp above) → push to ALL FOUR constitution upstreams (GitHub +
GitLab + GitFlic + GitVerse per the submodule's own `install_upstreams.sh`) →
then bump the parent `submodules/constitution` pin in the parent repo.
