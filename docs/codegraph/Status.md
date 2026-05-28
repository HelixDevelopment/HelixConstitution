# CodeGraph — Status

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-05-21 |
| Last modified | 2026-05-22 |
| Status | active |
| Status summary | Append-only ledger of every CodeGraph-related event across the constitution submodule's consuming projects: npm updates, sync runs, index regenerations, validate runs, HRDs opened/closed against CodeGraph. Per Universal §11.4.80 + §11.4.65 (multi-format export). Both `scripts/codegraph_update.sh` and `scripts/codegraph_sync.sh` append here automatically. R2 (2026-05-22): replaced project-specific `§107` anchor references with the universal `§11.4` covenant anchor to keep this submodule fully decoupled per §11.4.28. |
| Issues | none |
| Issues summary | — |
| Fixed | (n/a — ledger doc) |
| Continuation | sibling `Status_Summary.md` carries the operator-readable digest per §11.4.53. |

## Table of contents

- [Cadence + automation](#cadence--automation)
- [Event ledger](#event-ledger)

## Cadence + automation

Per §11.4.80, every consuming project MUST run `codegraph_update.sh` at least weekly and `codegraph_sync.sh` after every update + on every meaningful source-change cadence (varies by project). Cadence floor: weekly. Cadence ceiling: per-CI-run.

The scripts append entries below automatically; manual entries are also acceptable when an operator runs the commands directly.

## Event ledger

(events appended below by the automation; newest at the bottom)

## 2026-05-21T05:38:53Z — codegraph update FAILED (§11.4 bluff caught)

- before: `0.6.8`
- target: `0.8.0`
- after:  `unknown` (mismatch — npm exit 0 was bluffing)

## 2026-05-21T05:40:01Z — codegraph rolled back to 0.6.8 (Node-25 incompatibility)

- before: `0.8.0` (installed but non-functional on Node 25.x — engine range  + V8 WASM JIT bug)
- after:  `0.6.8` (last known-working on Node 25.x)
- decision: pin codegraph to 0.6.8 until Node 25 V8 issue is resolved upstream OR operator installs Node 22 LTS alongside
- §11.4 trail: `codegraph_update.sh` correctly caught the failed upgrade via the post-update version check — script working as designed
- follow-up HRD: ENV-CODEGRAPH-NODE25 to track when 0.7+/0.8+ becomes safe again

## 2026-05-21T12:41:31Z — codegraph update FAILED (§11.4 bluff caught)

- before: `0.6.8`
- target: `0.8.0`
- after:  `unknown` (mismatch — npm exit 0 was bluffing)

## 2026-05-21T12:49:03Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T12:51:16Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T14:31:35Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:17:07Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:21:55Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:26:34Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-22T08:44:36Z — codegraph version check

- current: `0.9.2`
- latest:  `0.9.2`
- action:  **no-op** (already at latest)

## 2026-05-28T10:21:08Z — codegraph updated

- before: `0.9.4`
- after:  `0.9.6`
- npm command: `npm install -g @colbymchenry/codegraph@0.9.6`

## 2026-05-28T14:26:35Z — codegraph version check

- current: `0.9.6`
- latest:  `0.9.6`
- action:  **no-op** (already at latest)
