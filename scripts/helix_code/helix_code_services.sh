#!/usr/bin/env bash
# ============================================================================
# helix_code_services.sh — install / boot / health wrappers for HelixCode
#
# Purpose:    Phase 1 Task 1.2 of INTEGRATION_PLAN.md. Provides thin wrappers
#             around the HelixCode clone's own installer + compose stack +
#             health probes. SOURCED library — consumers do:
#               source helix_code_home.sh
#               source helix_code_services.sh
#               hc_install && hc_boot_coder && hc_health localhost 18434
#
# Usage:      source constitution/scripts/helix_code/helix_code_services.sh
#             hc_install [--flags]     # delegates to install_helix_path.sh
#             hc_boot_service <name>   # boot a service via compose
#             hc_boot_coder            # boot the HelixLLM coder on :18434
#             hc_stop_service <name>   # stop a service
#             hc_status                # print status of all HelixCode services
#
# Dependencies: helix_code_home.sh (must be sourced first), bash, curl, docker/podman.
# Anti-bluff (§11.4.6): every function checks preconditions from captured state,
#             never assumes "it probably works."
# Cross-references: docs/helix_code/INTEGRATION_PLAN.md §3 Tasks 1.2-1.3,
#             docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md §1-2,
#             Constitution §11.4.6, §11.4.161 (rootless podman).
# Revision:   1
# Last modified: 2026-07-17T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard: do not re-source if already loaded
[ "${_HELIX_CODE_SERVICES_LOADED:-0}" = "1" ] && return 0
_HELIX_CODE_SERVICES_LOADED=1

# Require helix_code_home.sh to be sourced first
if [ "${_HELIX_CODE_HOME_LOADED:-0}" != "1" ]; then
  echo "[helix_code_services] ERROR: source helix_code_home.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

# --- internal helpers --------------------------------------------------------

# Resolve the HelixCode compose file path
hc__compose_file() {
  local home; home="$(hc_home)"
  local f="$home/compose.helixcode-infra.yml"
  if [ ! -f "$f" ]; then
    echo "[helix_code_services] WARN: compose file not found at $f" >&2
    return 1
  fi
  printf '%s' "$f"
}

# Resolve the Containers submodule deploy-stack script
hc__deploy_stack() {
  local home; home="$(hc_home)"
  local ds="$home/submodules/containers/deploy-stack"
  if [ ! -x "$ds" ]; then
    echo "[helix_code_services] WARN: deploy-stack not found at $ds" >&2
    return 1
  fi
  printf '%s' "$ds"
}

# --- public API --------------------------------------------------------------

# Install HelixCode binaries via the clone's own installer.
# Delegates to install_helix_path.sh (HC/install_helix_path.sh:29-30).
# Usage: hc_install [--flags]   (flags passed through to install_helix_path.sh)
hc_install() {
  local home; home="$(hc_home)"
  local installer="$home/install_helix_path.sh"
  if [ ! -f "$installer" ]; then
    echo "[helix_code_services] ERROR: installer not found at $installer" >&2
    return 1
  fi
  echo "[helix_code_services] Installing HelixCode binaries from $home ..." >&2
  HELIX_REPO_ROOT="$home" bash "$installer" "$@"
}

# Boot a HelixCode service via the Containers submodule compose stack.
# Usage: hc_boot_service <service-name>
# §11.4.161: uses rootless podman via the Containers submodule.
hc_boot_service() {
  local svc="${1:?usage: hc_boot_service <service-name>}"
  local home; home="$(hc_home)"
  local compose; compose="$(hc__compose_file)" || return 1
  local deploy; deploy="$(hc__deploy_stack)" || return 1

  echo "[helix_code_services] Booting service '$svc' ..." >&2
  "$deploy" \
    --env "$home/.env" \
    --host-index 1 \
    --compose "$compose" \
    --remote-dir "helix-$svc" \
    2>&1 || {
    echo "[helix_code_services] ERROR: failed to boot $svc" >&2
    return 1
  }
}

# Boot the HelixLLM coder (the multi-track "live sink" on :18434).
# Per §11.4.119 single-owner, ONLY one track owns the GPU coder.
# Usage: hc_boot_coder
hc_boot_coder() {
  echo "[helix_code_services] Booting HelixLLM coder on :18434 ..." >&2
  hc_boot_service "coder" || return 1
  # Wait for health
  local retries=10
  while [ $retries -gt 0 ]; do
    if hc_health localhost 18434 2>/dev/null; then
      echo "[helix_code_services] Coder healthy on :18434" >&2
      return 0
    fi
    retries=$((retries - 1))
    sleep 2
  done
  echo "[helix_code_services] WARN: coder not healthy after 20s" >&2
  return 1
}

# Stop a HelixCode service.
# Usage: hc_stop_service <service-name>
hc_stop_service() {
  local svc="${1:?usage: hc_stop_service <service-name>}"
  local home; home="$(hc_home)"
  echo "[helix_code_services] Stopping service '$svc' ..." >&2
  # Containers submodule teardown
  if command -v podman >/dev/null 2>&1; then
    podman compose -f "$(hc__compose_file)" down "$svc" 2>&1 || true
  elif command -v docker >/dev/null 2>&1; then
    docker compose -f "$(hc__compose_file)" down "$svc" 2>&1 || true
  fi
}

# Print status of all HelixCode services.
# Usage: hc_status
hc_status() {
  local home; home="$(hc_home)"
  echo "=== HelixCode Service Status ==="
  echo "Home: $home"
  echo "Mode: ${HELIX_CODE_MODE:-local}"
  echo ""
  echo "HelixCode server (:8080):  $(hc_health localhost 8080 2>/dev/null || echo 'DOWN')"
  echo "HelixLLM coder (:18434):   $(hc_health localhost 18434 2>/dev/null || echo 'DOWN')"
  echo "HelixLLM gateway (:8443):  $(hc_health localhost 8443 /internal/health 2>/dev/null || echo 'DOWN')"
  echo "HelixAgent (:8100):        $(hc_health localhost 8100 2>/dev/null || echo 'DOWN')"
}

# Verify all installed binaries are on PATH.
# Usage: hc_verify_binaries
hc_verify_binaries() {
  local bins="helixcode helixagent helixllm llm-verifier helixqa helixcli"
  local ok=0 fail=0
  for b in $bins; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "  $b: $(command -v "$b")"
      ok=$((ok + 1))
    else
      echo "  $b: NOT FOUND"
      fail=$((fail + 1))
    fi
  done
  echo "Binaries: $ok found, $fail missing"
  [ $fail -eq 0 ]
}
