# helix_code_services.md — Services Guide

**Revision:** 1
**Last modified:** 2026-07-17T00:00:00Z

## Overview

HelixCode service management wrappers: install, boot, stop, health-check, and status
for the HelixCode / HelixLLM / HelixAgent service fleet.

## Prerequisites

- `helix_code_home.sh` sourced first (provides `hc_home()`)
- bash ≥ 4.0
- Docker or Podman (for compose-based services)
- Network access to `github.com:HelixDevelopment/HelixCode.git`

## Quick Start

```sh
source constitution/scripts/helix_code/helix_code_home.sh
source constitution/scripts/helix_code/helix_code_services.sh

# Install binaries
hc_install

# Boot the coder (multi-track live sink)
hc_boot_coder

# Check status
hc_status

# Verify all binaries on PATH
hc_verify_binaries
```

## Functions

| Function | Purpose |
|---|---|
| `hc_install [--flags]` | Install HelixCode binaries via `install_helix_path.sh` |
| `hc_boot_service <name>` | Boot a service via the Containers submodule compose |
| `hc_boot_coder` | Boot the HelixLLM coder on `:18434` (with health wait) |
| `hc_stop_service <name>` | Stop a service |
| `hc_status` | Print health status of all 4 HelixCode services |
| `hc_verify_binaries` | Verify all 6 binaries are on PATH |
| `hc_health [host] [port] [path]` | Health check (from `helix_code_home.sh`) |

## Service Ports

| Service | Port | Health Endpoint |
|---|---|---|
| HelixCode server | `:8080` | `/health` |
| HelixLLM coder | `:18434` | `/health` |
| HelixLLM gateway | `:8443` | `/internal/health` |
| HelixAgent | `:8100` | `/health` |

## Safety

- §11.4.161: uses rootless podman via the Containers submodule
- §11.4.119: single-owner GPU — only one track boots the coder
- §12.6: 60% memory ceiling applies to service boot

## Cross-references

- `docs/helix_code/INTEGRATION_PLAN.md` §3 Tasks 1.2-4
- `docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md` §1
- `docs/helix_code/RISK_ANALYSIS.md` — port collisions, GPU contention
