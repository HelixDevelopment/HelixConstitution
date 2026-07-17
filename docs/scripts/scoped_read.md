# scoped_read.sh — Companion Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

§11.4.141 M4 implementation. Prevents full-file loading when a targeted read suffices.

## Functions

| Function | Purpose | Example |
|---|---|---|
| `sr_grep_then_read` | Grep pattern → read matching lines with context | `sr_grep_then_read "func" "main.go" 5` |
| `sr_section_read` | Read section by heading match | `sr_section_read "## Usage" "README.md"` |
| `sr_cached_result` | Cache command results (5min TTL) | `sr_cached_result "key" "command"` |
| `sr_clear_cache` | Clear the cache | `sr_clear_cache` |

## Usage

```sh
source constitution/scripts/token_efficiency/scoped_read.sh

# Read 5 lines of context around "func main" in main.go
sr_grep_then_read "func main" "main.go" 5

# Read the "## Usage" section from README.md
sr_section_read "## Usage" "README.md"

# Cache a command result
sr_cached_result "git_status" "git status --short"
```

## Cross-references

- Constitution §11.4.141 M4
- `token_efficiency_lib.sh` — for status and caching
- `context_compactor.sh` — for context pruning
