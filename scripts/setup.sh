#!/usr/bin/env bash
# setup.sh — one-time constitution submodule setup for the consuming project.
#
# Wires the post-update auto-propagation hook so that every `git pull` /
# `git submodule update` of this constitution submodule automatically:
#   1. Registers new/modified skills (§11.4.164)
#   2. Installs new/modified hooks
#   3. Merges MCP configs
#   4. Syntax-validates changed scripts
#   5. Installs git hooks into the consuming project
#
# Idempotent: safe to re-run after every clone or when hooks go stale.
#
# Usage (from the consuming project root):
#   bash constitution/scripts/setup.sh
#   bash constitution/scripts/setup.sh --project-root /path/to/project
#
# Also:
#   bash constitution/scripts/setup.sh --check-only  # verify hooks are wired

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_DIR="${CONST_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$CONST_DIR/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf '%b[const]%b %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%b[const]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
error() { printf '%b[const]%b %s\n' "$RED" "$NC" "$*" >&2; }

CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --project-root) shift; PROJECT_ROOT="$1" ;;
  esac
done

info "Constitution Setup"
info "  Constitution: $CONST_DIR"
info "  Project root: $PROJECT_ROOT"

# ─── 1. Verify identity ──────────────────────────────────────────────

if [ ! -f "$CONST_DIR/Constitution.md" ]; then
  error "Not a constitution submodule: $CONST_DIR"
  exit 1
fi

# ─── 2. Run post-update hook ─────────────────────────────────────────

if [ "$CHECK_ONLY" -eq 1 ]; then
  info "Check-only mode: verifying post_update_hook.sh is present and parseable"
  if [ -x "$SCRIPT_DIR/post_update_hook.sh" ]; then
    bash -n "$SCRIPT_DIR/post_update_hook.sh" 2>&1 && \
      info "  post_update_hook.sh: OK" || \
      error "  post_update_hook.sh: PARSE ERROR"
  else
    error "  post_update_hook.sh: MISSING or not executable"
  fi
  exit 0
fi

info ""
info "Running post-update hook (skill registry + hook wiring) ..."

CONST_DIR="$CONST_DIR" PROJECT_ROOT="$PROJECT_ROOT" \
  bash "$SCRIPT_DIR/post_update_hook.sh"

# ─── 3. Install git hooks (constitution-side) ────────────────────────

info ""
info "Installing constitution git hooks into consuming project"

GIT_HOOKS_SRC="$SCRIPT_DIR/hooks"
GIT_HOOKS_DST="$PROJECT_ROOT/.git/hooks"

if [ -d "$GIT_HOOKS_SRC" ]; then
  mkdir -p "$GIT_HOOKS_DST"
  installed=0
  for hook in "$GIT_HOOKS_SRC"/*; do
    name="$(basename "$hook")"
    cp -f "$hook" "$GIT_HOOKS_DST/$name"
    chmod +x "$GIT_HOOKS_DST/$name"
    info "  $name installed"
    installed=$((installed + 1))
  done
  info "$installed git hooks installed"
else
  warn "No hooks source dir: $GIT_HOOKS_SRC"
fi

# ─── 4. Install project-level git hooks (project-side) ───────────────

PROJECT_HOOKS="$PROJECT_ROOT/scripts/git_hooks"
if [ -d "$PROJECT_HOOKS" ]; then
  info ""
  info "Installing project-level git hooks"
  for hook in "$PROJECT_HOOKS"/*; do
    name="$(basename "$hook")"
    cp -f "$hook" "$GIT_HOOKS_DST/$name"
    chmod +x "$GIT_HOOKS_DST/$name"
    info "  $name installed"
  done
fi

info ""
info "Constitution setup complete."
info "Hooks installed. Re-run after every constitution submodule update."
