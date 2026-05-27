# workable-items — §11.4.93 SQLite-SSoT Go binary

**Revision:** 1
**Last modified:** 2026-05-27T06:30:00Z
**Description:** Authoritative source-of-truth registry for every workable item in every consuming project. Bidirectional regen between SQLite DB and Markdown trackers per Constitution §11.4.93.

## Overview

Per Constitution §11.4.93, every consuming project's workable-items
inventory (Issues.md / Fixed.md / Issues_Summary.md / Fixed_Summary.md /
Status.md fleet / CONTINUATION.md §3) is reconstructible from this
DB-backed registry. The DB is the **authoritative** source; all
Markdown / HTML / PDF surfaces are generator output.

Sync drift is mechanically impossible because every regeneration
starts from the DB.

## Layout

| Path | Purpose |
|---|---|
| `schema.sql` | DDL — 6 tables: items + item_history + obsolete_details + operator_block_details + firebase_metadata + meta |
| `cmd/workable-items/main.go` | Go binary entrypoint (Phase 2 scaffold) |
| `pkg/itemsdb/` | SQLite access layer (Phase 2 scaffold) |
| `pkg/mdparser/` | Markdown→DB parser (Phase 3 scaffold) |
| `pkg/mdrender/` | DB→Markdown renderer (Phase 4 scaffold) |
| `tests/` | Unit + integration + stress + chaos tests per §11.4.85 |

## Subcommands (Phase 2 spec)

```
workable-items sync md-to-db        # parse Issues.md+Fixed.md → upsert DB
workable-items sync db-to-md        # regen MD docs from DB
workable-items diff                 # show DB vs MD divergence (CI gate)
workable-items validate             # invariant + schema sanity (pre-build gate)
workable-items add <type> <severity> --title <T> --description <D>
workable-items close <atm-id> --status <fixed|implemented|completed|obsolete> --evidence <path>
workable-items report --by-type|--by-status|--by-severity|--obsolete-audit
```

## Anti-bluff coverage (mandatory per §11.4.93 + §11.4.85)

| Layer | Test |
|---|---|
| Unit | every CRUD operation + every schema invariant + closed-set validators |
| Integration | full MD→DB→MD round-trip byte-identical (modulo whitespace tolerance) |
| Stress per §11.4.85 | 1000-row insert; 10 concurrent writers; sustained read throughput |
| Chaos per §11.4.85 | mid-write SIGKILL; corrupt-DB recovery; disk-full; FD exhaustion |
| Paired §1.1 mutation | strip CRUD function → unit test FAILs |
| HelixQA Challenge | `CME-WORKABLE-ITEMS-001` exercises end-to-end DB→MD→DB→MD |

## 6-phase migration per §11.4.93 (consuming-project work)

1. **Phase 1** — Issues entry `§LA` filed, scope-locked.
2. **Phase 2** — Go binary scaffold + DDL committed (this PWU).
3. **Phase 3** — `sync md-to-db` lands + captures initial migration.
4. **Phase 4** — `sync db-to-md` lands + byte-identical round-trip CI gate.
5. **Phase 5** — Existing bash generators (`generate_issues_summary.sh` etc.)
   become Go-binary shims.
6. **Phase 6** — Legacy text-direct edits prohibited (pre-commit hook).

## Composes with constitution anchors

§11.4 / §11.4.12 / §11.4.15 / §11.4.16 / §11.4.17 / §11.4.19 /
§11.4.21 / §11.4.27 / §11.4.30 / §11.4.33 / §11.4.34 / §11.4.42 /
§11.4.43 / §11.4.44 / §11.4.45 / §11.4.50 / §11.4.52 / §11.4.53 /
§11.4.54 / §11.4.55 / §11.4.56 / §11.4.57 / §11.4.58 / §11.4.60 /
§11.4.65 / §11.4.74 / §11.4.77 / §11.4.83 / §11.4.85 / §11.4.86 /
§11.4.87 / §11.4.89 / §11.4.90 / §11.4.91 / §11.4.92.

## Canonical authority

[`../../Constitution.md`](../../Constitution.md) §11.4.93.
