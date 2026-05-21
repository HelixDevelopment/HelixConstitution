#!/usr/bin/env bash
# codegraph_update.sh — Helix Universal §11.4.80 CodeGraph regular-update automation.
#
# Checks the locally-installed @colbymchenry/codegraph version against npm's
# latest. If a newer version exists, updates globally (no sudo per §9 / §12).
# Appends the old → new version + timestamp to the constitution submodule's
# docs/codegraph/Status.md audit trail.
#
# Anti-bluff (§107): "update succeeded" PASS observes the NEW version via
# `codegraph --version`, NOT just `npm update`'s exit code. A successful
# npm exit followed by an unchanged version means the update did not take.
#
# Usage:
#   bash <constitution>/scripts/codegraph_update.sh
#
# Exit codes:
#   0 — already at latest OR successfully updated
#   1 — update attempted but new version did not take (bluff caught)
#   2 — environment problem (npm/node missing, network unreachable)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATUS_DOC="${CONST_ROOT}/docs/codegraph/Status.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "${STATUS_DOC}")"

if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm not on PATH. Install Node.js 18+ first." >&2
    exit 2
fi

if ! command -v codegraph >/dev/null 2>&1 \
   && ! command -v npx >/dev/null 2>&1; then
    echo "ERROR: neither codegraph nor npx found. Install Node.js 18+ first." >&2
    exit 2
fi

# Capture current version (resilient to multiple install paths).
current_version=""
if command -v codegraph >/dev/null 2>&1; then
    current_version="$(codegraph --version 2>/dev/null | head -1 || echo 'unknown')"
fi

# Query latest via npm registry.
latest_version="$(npm view @colbymchenry/codegraph version 2>/dev/null || echo '')"
if [ -z "${latest_version}" ]; then
    echo "ERROR: could not query npm registry for @colbymchenry/codegraph latest version." >&2
    exit 2
fi

echo "Current codegraph version: ${current_version:-<not-installed>}"
echo "Latest on npm:             ${latest_version}"

if [ "${current_version}" = "${latest_version}" ]; then
    echo "Already at latest — no update needed."
    {
        echo ""
        echo "## ${TS} — codegraph version check"
        echo ""
        echo "- current: \`${current_version}\`"
        echo "- latest:  \`${latest_version}\`"
        echo "- action:  **no-op** (already at latest)"
    } >> "${STATUS_DOC}"
    exit 0
fi

# Update.
echo "Updating @colbymchenry/codegraph from ${current_version:-<not-installed>} → ${latest_version}..."
if ! npm install -g "@colbymchenry/codegraph@${latest_version}"; then
    echo "ERROR: npm install -g failed. Verify npm prefix is user-writable (no sudo per §9/§12)." >&2
    exit 2
fi

# Verify the new version actually took (§107 anti-bluff).
new_version=""
if command -v codegraph >/dev/null 2>&1; then
    new_version="$(codegraph --version 2>/dev/null | head -1 || echo 'unknown')"
fi

if [ "${new_version}" != "${latest_version}" ]; then
    echo "BLUFF: npm install succeeded but codegraph --version still reports '${new_version}' (expected '${latest_version}')." >&2
    {
        echo ""
        echo "## ${TS} — codegraph update FAILED (§107 bluff caught)"
        echo ""
        echo "- before: \`${current_version}\`"
        echo "- target: \`${latest_version}\`"
        echo "- after:  \`${new_version}\` (mismatch — npm exit 0 was bluffing)"
    } >> "${STATUS_DOC}"
    exit 1
fi

echo "Update successful — codegraph is now ${new_version}."
{
    echo ""
    echo "## ${TS} — codegraph updated"
    echo ""
    echo "- before: \`${current_version:-<not-installed>}\`"
    echo "- after:  \`${new_version}\`"
    echo "- npm command: \`npm install -g @colbymchenry/codegraph@${latest_version}\`"
} >> "${STATUS_DOC}"

exit 0
