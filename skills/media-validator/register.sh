#!/usr/bin/env bash
# ============================================================================
# register.sh — Media Validator skill registration
# ============================================================================
# Purpose:
#   Called by post_update_hook.sh to register the media-validator skill
#   in the consuming project. Creates symlinks, registers in CLAUDE.md
#   if needed, and ensures the skill is discoverable.
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
#   - Symlinks skills/media-validator/ -> constitution/skills/media-validator/
#   - Appends skill reference to .claude/skills.json if it exists
#
# Last verified: 2026-06-21
# ============================================================================

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="media-validator"

echo "[register.sh] Registering skill: ${SKILL_NAME}"

# 1. Ensure skills directory exists
mkdir -p "${PROJECT_ROOT}/skills"

# 2. Create/update symlink
LINK_TARGET="${PROJECT_ROOT}/skills/${SKILL_NAME}"
if [ -L "$LINK_TARGET" ] || [ ! -e "$LINK_TARGET" ]; then
    rm -f "$LINK_TARGET"
    ln -sf "$SCRIPT_DIR" "$LINK_TARGET"
    echo "[register.sh]  -> Linked: ${LINK_TARGET} -> ${SCRIPT_DIR}"
else
    echo "[register.sh]  -> ${LINK_TARGET} already exists and is not a symlink — skipping"
fi

# 3. Register in .claude/skills.json if present
SKILLS_JSON="${PROJECT_ROOT}/.claude/skills.json"
if [ -f "$SKILLS_JSON" ]; then
    # Check if already registered
    if grep -q "\"${SKILL_NAME}\"" "$SKILLS_JSON" 2>/dev/null; then
        echo "[register.sh]  -> Skill '${SKILL_NAME}' already in skills.json"
    else
        echo "[register.sh]  -> Add '${SKILL_NAME}' to ${SKILLS_JSON} manually or via your agent config"
    fi
else
    echo "[register.sh]  -> No .claude/skills.json found — skill registered as filesystem path"
fi

echo "[register.sh] Registration complete: ${SKILL_NAME}"
