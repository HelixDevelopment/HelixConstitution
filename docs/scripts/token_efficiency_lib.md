# token_efficiency_lib.sh — Companion Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

§11.4.141 M5+M6 implementation. Provides terse status, batch reads, and cached grep
for token-efficient operations.

## Functions

| Function | Purpose | Example |
|---|---|---|
| `te_status_line` | Terse one-line status | `te_status_line "Build started"` |
| `te_batch_read` | Read multiple files, return summary | `te_batch_read file1.md file2.md` |
| `te_cached_grep` | Grep with result caching | `te_cached_grep "pattern" "file.sh"` |
| `te_clear_cache` | Clear the cache | `te_clear_cache` |

## Usage

```sh
source constitution/scripts/token_efficiency/token_efficiency_lib.sh

# Terse status
te_status_line "Processing item ATM-751"

# Batch read multiple files
te_batch_read docs/Issues.md docs/Fixed.md

# Cached grep (result cached for 5 minutes)
te_cached_grep "§11.4" CLAUDE.md
```

## Cross-references

- Constitution §11.4.141 M5+M6
- `scoped_read.sh` — for targeted file reads
- `context_compactor.sh` — for context pruning
