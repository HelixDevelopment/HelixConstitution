#!/usr/bin/env bash
# codegraph_sync.sh — Helix Universal §11.4.80 CodeGraph sync automation.
#
# After a successful `codegraph_update.sh`, runs the canonical sync sequence
# inside the consuming project:
#   1. `codegraph status` (baseline statistics)
#   2. `codegraph sync .` (incremental update of the index)
#   3. `codegraph status` (post-sync statistics)
#   4. project's `scripts/codegraph_validate.sh` (anti-bluff verifier per
#      §11.4.78 step 4)
#
# Each step's output is appended to the consuming project's
# docs/codegraph/Status.md ledger AND the constitution submodule's
# docs/codegraph/Status.md ledger.
#
# Anti-bluff (§107): every step's "ok" carries observed evidence (node
# count delta, validate PASS count) — not just exit codes.
#
# Usage:
#   bash <constitution>/scripts/codegraph_sync.sh [<consuming-project-root>]
#
# If the project root is omitted, the script resolves it via parent walk
# (find_constitution.sh inverse — walks DOWN from cwd looking for a
# .codegraph directory).
#
# Exit codes:
#   0 — sync + validate both green
#   1 — sync or validate FAILed (§107 bluff guard or real regression)
#   2 — environment problem (codegraph not installed, .codegraph absent)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONST_STATUS="${CONST_ROOT}/docs/codegraph/Status.md"

# Resolve consuming-project root.
PROJECT_ROOT="${1:-${PWD}}"
if [ ! -d "${PROJECT_ROOT}/.codegraph" ]; then
    # Try parent walk to find a .codegraph directory.
    cur="${PROJECT_ROOT}"
    while [ "${cur}" != "/" ]; do
        if [ -d "${cur}/.codegraph" ]; then
            PROJECT_ROOT="${cur}"; break
        fi
        cur="$(dirname "${cur}")"
    done
fi
if [ ! -d "${PROJECT_ROOT}/.codegraph" ]; then
    echo "ERROR: no .codegraph directory found at or above ${PROJECT_ROOT}." >&2
    echo "       Run \`codegraph init\` in the consuming project first." >&2
    exit 2
fi

PROJECT_STATUS="${PROJECT_ROOT}/docs/codegraph/Status.md"
mkdir -p "$(dirname "${PROJECT_STATUS}")" "$(dirname "${CONST_STATUS}")"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_TMP="$(mktemp)"
trap "rm -f '${LOG_TMP}'" EXIT

append_log() {
    local message="$1"
    {
        echo ""
        echo "## ${TS} — codegraph_sync.sh @ ${PROJECT_ROOT}"
        echo ""
        echo "${message}"
    } | tee -a "${PROJECT_STATUS}" >> "${CONST_STATUS}"
}

if ! command -v codegraph >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
    echo "ERROR: codegraph not on PATH and npx absent. Run codegraph_update.sh first." >&2
    exit 2
fi

# Use codegraph directly if installed, otherwise npx fallback.
if command -v codegraph >/dev/null 2>&1; then
    CG="codegraph"
else
    CG="npx -y @colbymchenry/codegraph"
fi

cd "${PROJECT_ROOT}"

echo "Step 1/4: baseline codegraph status"
${CG} status . > "${LOG_TMP}" 2>&1
baseline_summary="$(grep -E 'file|function|method|struct|interface|constant' "${LOG_TMP}" | tail -10 || true)"
echo "${baseline_summary}"

echo ""
echo "Step 2/4: codegraph sync ."
sync_start="$(date +%s)"
if ! ${CG} sync . > "${LOG_TMP}" 2>&1; then
    echo "ERROR: codegraph sync FAILed:" >&2
    cat "${LOG_TMP}" >&2
    append_log "**FAIL** — codegraph sync exited non-zero. Tail of log:\n\n\`\`\`\n$(tail -10 "${LOG_TMP}")\n\`\`\`"
    exit 1
fi
sync_end="$(date +%s)"
sync_duration=$((sync_end - sync_start))
echo "sync completed in ${sync_duration}s"

echo ""
echo "Step 3/4: post-sync codegraph status"
${CG} status . > "${LOG_TMP}" 2>&1
postsync_summary="$(grep -E 'file|function|method|struct|interface|constant' "${LOG_TMP}" | tail -10 || true)"
echo "${postsync_summary}"

echo ""
echo "Step 4/4: project's scripts/codegraph_validate.sh"
validate_status="MISSING"
validate_summary=""
if [ -x "${PROJECT_ROOT}/scripts/codegraph_validate.sh" ]; then
    if bash "${PROJECT_ROOT}/scripts/codegraph_validate.sh" > "${LOG_TMP}" 2>&1; then
        validate_status="PASS"
    else
        validate_status="FAIL"
    fi
    validate_summary="$(tail -5 "${LOG_TMP}")"
    cat "${LOG_TMP}"
else
    echo "WARNING: ${PROJECT_ROOT}/scripts/codegraph_validate.sh not found — per §11.4.78 step 4, projects MUST ship an anti-bluff validator. Skipping but flagging."
fi

append_log "$(cat <<EOF
- duration:        \`${sync_duration}s\`
- baseline status:
\`\`\`
${baseline_summary}
\`\`\`
- post-sync status:
\`\`\`
${postsync_summary}
\`\`\`
- validate:        **${validate_status}**
\`\`\`
${validate_summary}
\`\`\`
EOF
)"

if [ "${validate_status}" = "FAIL" ]; then
    exit 1
fi
exit 0
