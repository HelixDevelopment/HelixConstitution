# gate_helix_code_home_resolves.sh — Gate Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

Pre-build gate `CM-HELIX-CODE-HOME-RESOLVES` — verifies the HelixCode home resolver
exists, is parse-clean, and its companion doc is present. Phase 1 Task 1.1 gate for
the HelixCode integration (INTEGRATION_PLAN.md §3).

## Invariants

| # | Name | Check |
|---|---|---|
| S1 | script-exists | `helix_code_home.sh` exists AND is executable |
| S2 | script-parseable | `bash -n` exits 0 |
| S3 | companion-doc | `helix_code_home.md` exists AND is non-empty |

GREEN = 111, any 0 = FAIL.

## Usage

```bash
# Run the gate
bash constitution/scripts/helix_code/gate_helix_code_home_resolves.sh

# Self-test (verifies golden-good/golden-bad fixtures)
bash constitution/scripts/helix_code/gate_helix_code_home_resolves.sh --selftest
```

## Paired §1.1 Mutation

The metatest strips the case-(b) auto-clone from `helix_code_home.sh` → the gate's
functional invariant breaks → gate FAILs. Proves the gate is load-bearing, not a bluff.

## Cross-references

- `docs/helix_code/INTEGRATION_PLAN.md` §3 Task 1.1
- `constitution/scripts/helix_code/helix_code_home.sh` — the resolver
- `constitution/docs/scripts/helix_code_home.md` — the resolver companion doc
- Constitution §11.4.6 (no-guessing), §11.4.18 (script docs)
