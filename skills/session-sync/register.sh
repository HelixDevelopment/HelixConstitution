#!/usr/bin/env bash
# ============================================================================
# register.sh — Session Sync skill registration
# ============================================================================
# Purpose:
#   Called by post_update_hook.sh to register the session-sync skill
#   in the consuming project. Creates symlinks and ensures the skill
#   is discoverable by Claude Code and all toolkit aliases.
#
# Usage:
#   bash register.sh <project-root>
#
# Inputs:
#   $1 — consuming project root directory
#
# Outputs:
#   stdout — registration steps
#   Exit 0 — success
#
# Side-effects:
#   - Symlinks skills/session-sync/ -> constitution/skills/session-sync/
#   - Ensures session-sync.sh is executable
#   - Registers in .claude/skills.json if present
#
# Dependencies:
#   bash 4+, ln, chmod
#
# Cross-references:
#   constitution/scripts/post_update_hook.sh — calls this on every pull
#   constitution/Constitution.md §11.4.164 — auto-propagation mandate
#   constitution/Constitution.md §11.4.187 — multi-track orchestration
#
# Last verified: 2026-07-13
# ============================================================================

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="session-sync"

# Relocation-proof symlink creation (§11.4.111): the link target MUST be stored
# RELATIVE to the link, never as this machine's absolute path — an absolute
# target only resolves on the host that ran the install.
. "$(cd "${SCRIPT_DIR}/../.." && pwd)/scripts/portable_symlink_lib.sh"

echo "[register.sh] Registering skill: ${SKILL_NAME}"

# 1. Ensure skills directory exists in the consuming project
mkdir -p "${PROJECT_ROOT}/skills"

# 2. Create/update symlink so the skill is discoverable
LINK_TARGET="${PROJECT_ROOT}/skills/${SKILL_NAME}"
if [ -L "$LINK_TARGET" ] || [ ! -e "$LINK_TARGET" ]; then
    hc_ln_relative "$SCRIPT_DIR" "$LINK_TARGET"
    echo "[register.sh]  -> Linked: ${LINK_TARGET} -> $(readlink "$LINK_TARGET")"
else
    echo "[register.sh]  -> ${LINK_TARGET} already exists and is not a symlink — skipping"
fi

# 3. Ensure session-sync.sh is executable
chmod +x "${SCRIPT_DIR}/session-sync.sh" 2>/dev/null || true

# 4. Also create convenience symlink in project scripts/ if scripts/ exists
if [ -d "${PROJECT_ROOT}/scripts" ]; then
    CONVENIENCE_LINK="${PROJECT_ROOT}/scripts/sync_remote_session.sh"
    if [ -L "$CONVENIENCE_LINK" ] || [ ! -e "$CONVENIENCE_LINK" ]; then
        hc_ln_relative "${SCRIPT_DIR}/session-sync.sh" "$CONVENIENCE_LINK"
        echo "[register.sh]  -> Convenience link: ${CONVENIENCE_LINK} -> $(readlink "$CONVENIENCE_LINK")"
    fi
fi

# 5. Register in .claude/skills.json if present
SKILLS_JSON="${PROJECT_ROOT}/.claude/skills.json"
if [ -f "$SKILLS_JSON" ]; then
    if grep -q "\"${SKILL_NAME}\"" "$SKILLS_JSON" 2>/dev/null; then
        echo "[register.sh]  -> Skill '${SKILL_NAME}' already in skills.json"
    else
        echo "[register.sh]  -> NOTE: Add '${SKILL_NAME}' to ${SKILLS_JSON} manually or via agent config"
    fi
fi

# 6. Register with multi-track ruler if present
RULER_CONFIG="${PROJECT_ROOT}/config/multitrack"
if [ -d "$RULER_CONFIG" ]; then
    echo "[register.sh]  -> Multi-track config detected — session-sync is track-aware"
fi

echo "[register.sh] Registration complete: ${SKILL_NAME}"
