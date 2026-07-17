# helix_code_home.sh — Companion Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

Sourced library that resolves `HELIX_CODE_HOME` (the HelixCode meta-repo location) using
the 3-case contract defined in `docs/helix_code/INTEGRATION_PLAN.md §2.1`.

## Prerequisites

- bash ≥ 4.0
- git
- Network access to `github.com:HelixDevelopment/HelixCode.git` (for case-b auto-clone)

## Usage

```sh
# Source the library
source constitution/scripts/helix_code/helix_code_home.sh

# Resolve the HelixCode home (clones if needed)
home="$(hc_home)"
echo "HelixCode at: $home"

# Check remote base URL (empty if mode=local)
base="$(hc_remote_base)"

# Health check a service
hc_health localhost 8080 /health
```

## Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `HELIX_CODE_HOME` | `~/.bashrc` or project `.env` | Override meta-repo path |
| `HELIX_CODE_MODE` | `~/.bashrc` or project `.env` | `local` (default) or `remote` |
| `HELIX_CODE_REMOTE_BASE_URL` | `~/api_keys.sh` or project `.env` | Remote deployment base URL |
| `HELIX_PROJECT_ROOT` | (rarely set) | Override project root detection |

## Resolution Order

1. `$HELIX_CODE_HOME` env var
2. `HELIX_CODE_HOME` in project `.env`
3. Default: `<project-root>/submodules/helix_code`

## Edge Cases

- **Path set but empty:** triggers full recursive clone (case b)
- **Path set, no `.git`:** triggers full recursive clone (case b)
- **Path unset:** defaults to submodule path, clones if absent (case c)
- **Path present + valid:** ensures submodules are initialized (case a)

## Related Scripts

- `constitution/scripts/multitrack/multitrack_config.sh` — similar resolver pattern
- `constitution/scripts/subagent_tier.sh` — env-else-submodule-default idiom
- `constitution/scripts/release_prefix.sh` — 3-tier env→.env→default pattern

## Cross-references

- `docs/helix_code/INTEGRATION_PLAN.md` §2 — env-var contract
- `docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md` §2 — mini-POC
- `docs/helix_code/CONSTITUTION_DESIGN.md` §3 — constitution mechanism
- Constitution §11.4.6 (no-guessing), §11.4.18 (script docs), §11.4.28 (decoupling)
