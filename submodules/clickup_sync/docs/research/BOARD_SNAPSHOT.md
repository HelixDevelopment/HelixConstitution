# Live Board Snapshot — clickup_sync mirror target

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-06-09T00:00:00Z |
| Captured | 2026-06-09, read-only GET probes (HTTP 200) |
| Target | List `901818394542` ("List") in Folder `901814301358` ("ATMOSphere System"), Space `901811154372` ("ATMOSphere OS"), Team `90182716341` ("FinTech Labs") |

> This is the LIVE state of the ClickUp side we must mirror. It is a **clean slate** — no tasks,
> no custom fields, no tags yet. clickup_sync seeds/maps against this.

## Status set (the board columns)

- List `override_statuses = False` → the List **inherits the Space status set**. Changing statuses = change the Space (or set `override_statuses=true` on the List first). See API_REFERENCE.md §e.
- Identical on List and Space this run:

| orderindex (column L→R) | status name | type | color |
|---|---|---|---|
| 0 | `to do` | open | `#87909e` |
| 1 | `in progress` | custom | `#5f55ee` |
| 2 | `complete` | closed | `#008844` |

- `type` semantics: exactly one `open` (start), zero-or-more `custom` (middle), exactly one `closed`/`done` (terminal). Our SQLite status vocabulary (§11.4.15) MUST map onto these three (or onto an expanded ClickUp set if the operator adds columns). **Mapping is ClickUp-status-name → our-status; ClickUp is the source-of-truth for the SET.**
- There is **no `Deleted` column** — ClickUp deletion = trash (webhook `taskDeleted`), NOT a status. Map our `Deleted`/`Obsolete` to a ClickUp **delete**, not a status (API_REFERENCE.md §k).

## Custom fields

- `GET /api/v2/list/901818394542/field` → **0 fields**. Clean slate.
- The sync-marker field (RISK_ANALYSIS.md §echo-detection) does NOT exist yet → operator seeds it once (UI; no public create endpoint confirmed) OR we use Tags.

## Tags

- `GET /api/v2/space/901811154372/tag` → **0 tags**. Space tags feature `enabled=True`.
- "version tags a task may have several of" → use native Tags (API_REFERENCE.md §g). None exist yet → we create them on first use via `POST /task/{id}/tag/{tag_name}` (which auto-creates the space tag) `UNCONFIRMED:` exact auto-create behavior — verify in Phase 1.

## Custom task types

- Space `features.custom_items.enabled = False` → only the default Task type (`custom_item_id = 0`). Do NOT depend on custom item types (API_REFERENCE.md §f).

## Space features (relevant flags)

- `multiple_assignees = True` — tasks may have several assignees.
- `tags.enabled = True`.
- `custom_items.enabled = False`.

## Tasks

- `task_count = 0` on the folder and the list — **no tasks exist**. First sync is a pure create-from-our-side OR import-from-empty. Because the list is empty, the `date_updated` ms-string format and the per-task `creator`/`assignees` shapes were NOT re-derived live (flagged `UNCONFIRMED:` in API_REFERENCE.md §h, §i — re-derive from the first real task in Phase 1).
