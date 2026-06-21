# Semgrep — Status

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-06-21 |
| Last modified | 2026-06-21T00:00:00Z |
| Status | active |
| Status summary | Append-only ledger of semgrep integration events across consuming projects: installs, builds, validation runs. Per Universal §11.4.80 (sibling pattern) + §11.4.65 (multi-format export). Both `scripts/semgrep/semgrep_setup.sh` and `scripts/semgrep/semgrep_validate.sh` append here automatically. |
| Issues | none |
| Issues summary | — |
| Fixed | (n/a — ledger doc) |
| Continuation | sibling `Status_Summary.md` carries the operator-readable digest per §11.4.53. |

## Table of contents

- [Cadence + automation](#cadence--automation)
- [Event ledger](#event-ledger)

## Cadence + automation

Every consuming project MUST run `semgrep_setup.sh` once per checkout (or after every constitution pull) to ensure semgrep is installed. `semgrep_validate.sh` runs as part of the pre-build gate suite (per §11.4.110) and optionally as a cron/weekly check per §11.4.45 cadence.

The scripts append entries below automatically; manual entries are also acceptable when an operator runs the commands directly.

## Event ledger

(events appended below by the automation; newest at the bottom)

## 2026-06-21T20:27:28Z — validate check PASSED

- evidence: /run/media/milosvasic/DATA4TB/Projects/Android_15/constitution/docs/.semgrep/scan_2026-06-21T20:27:28Z.json\n- exit code: 0

## 2026-06-21T20:27:28Z — registry check PASSED

- evidence: /run/media/milosvasic/DATA4TB/Projects/Android_15/constitution/docs/.semgrep/registry_2026-06-21T20:27:28Z.txt

## 2026-06-21T20:34:13Z — validate check PASSED

- evidence: /run/media/milosvasic/DATA4TB/Projects/Android_15/constitution/docs/.semgrep/scan_2026-06-21T20:34:13Z.json\n- exit code: 0

## 2026-06-21T20:34:13Z — registry check PASSED

- evidence: /run/media/milosvasic/DATA4TB/Projects/Android_15/constitution/docs/.semgrep/registry_2026-06-21T20:34:13Z.txt
