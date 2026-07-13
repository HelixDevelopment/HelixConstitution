#!/usr/bin/env bash
# sonarqube_install_check.sh — Helix Universal SonarQube — install verifier.
#
# Purpose      : Prove the SonarScanner CLI is installed and runnable BEFORE any
#                scan is attempted (§11.4.108 install/ARTIFACT layer). Emits the
#                observed scanner version as captured evidence (§11.4.6 — state
#                the fact, never assume). Also reports podman + podman-compose +
#                curl presence and the host vm.max_map_count readiness.
# Usage        : bash sonarqube_install_check.sh
# Inputs       : none (reads PATH + /proc/sys/vm/max_map_count)
# Outputs      : Human-readable report on stdout; exit 0 = scanner runnable.
# Exit codes   : 0 scanner present+runnable · 1 scanner missing/broken ·
#                2 supporting tool (podman/curl) missing
# Side-effects : none (read-only probes)
# Dependencies : bash, sonar-scanner (Factory/software/sonar-scanner/bin), podman
# Cross-ref    : §11.4.69 (evidence) · §11.4.108 (install layer) · §11.4.161
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./sonarqube_lib.sh
. "${SCRIPT_DIR}/sonarqube_lib.sh"

rc=0
echo "=== SonarQube integration — install check ==="

# 1) sonar-scanner CLI (the load-bearing tool) --------------------------------
if sq_have_scanner; then
    ver_line="$(sonar-scanner --version 2>&1 | sed -n 's/.*\(SonarScanner CLI [0-9][0-9.]*\).*/\1/p' | head -1)"
    if [ -n "${ver_line}" ]; then
        echo "PASS  scanner: $(command -v sonar-scanner) — ${ver_line}"
    else
        echo "FAIL  scanner found but --version produced no version banner (broken JRE?)"
        rc=1
    fi
else
    echo "FAIL  sonar-scanner NOT on PATH."
    echo "      Install into ~/Factory/software/sonar-scanner/ (bin on PATH via the"
    echo "      /home/<user>/Factory/software/*/bin glob) — see this dir's README.md."
    rc=1
fi

# 2) rootless podman + compose (§11.4.161) -----------------------------------
if sq_have_podman; then
    echo "PASS  podman: $(podman --version 2>&1)"
    if cc="$(sq_compose_cmd)"; then echo "PASS  compose runtime: ${cc}"; else
        echo "FAIL  no podman-compose / 'podman compose' available"; rc=2; fi
else
    echo "FAIL  podman NOT on PATH (rootless podman is required, §11.4.161)"; rc=2
fi

# 3) curl (sink-side API probes, §11.4.69) -----------------------------------
if command -v curl >/dev/null 2>&1; then echo "PASS  curl: present"; else
    echo "FAIL  curl missing (needed for /api sink-side evidence)"; rc=2; fi

# 4) host ES readiness --------------------------------------------------------
if sq_check_max_map_count >/dev/null 2>&1; then
    echo "PASS  host vm.max_map_count=$(cat /proc/sys/vm/max_map_count) (ES-ready)"
else
    echo "WARN  host vm.max_map_count too low — SonarQube ES will refuse to start"
fi

echo "=== install check exit ${rc} ==="
exit "${rc}"
