# context_compactor.sh — Companion Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

§11.4.141 M7 implementation. Prunes stale tool-results and old thinking from
long sessions. NEVER touches the governance prefix.

## Functions

| Function | Purpose | Example |
|---|---|---|
| `cc_should_compact` | Check if context exceeds threshold | `cc_should_compact 50` |
| `cc_prune_stale_results` | Mark old results as prunable | `cc_prune_stale_results 20` |
| `cc_summarize_old_thinking` | Compress old thinking blocks | `cc_summarize_old_thinking` |
| `cc_preserve_governance` | Documented invariant (no-op) | `cc_preserve_governance` |
| `cc_get_context_stats` | Return context statistics | `cc_get_context_stats` |

## Usage

```sh
source constitution/scripts/token_efficiency/context_compactor.sh

# Check if compaction needed (after 50 turns)
if cc_should_compact 50; then
    cc_prune_stale_results 20
    cc_summarize_old_thinking
fi

# Governance preservation is automatic (invariant)
```

## Invariant

The governance prefix (CLAUDE.md, Constitution.md) is NEVER touched by compaction.
It is the cache breakpoint and must remain byte-stable for prompt caching.

## Cross-references

- Constitution §11.4.141 M7
- `token_efficiency_lib.sh` — for status and caching
- `scoped_read.sh` — for targeted reads
