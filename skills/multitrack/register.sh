#!/usr/bin/env bash
# ============================================================================
# register.sh — Multitrack engine auto-install seam (§11.4.164; RB-08).
# ============================================================================
# Purpose:
#   Called by post_update_hook.sh's `skills/*/register.sh` bucket
#   (install_skills(): `register="${src}/register.sh"; [ -f "$register" ] &&
#   bash "$register" "$PROJECT_ROOT"`) whenever `constitution/skills/
#   multitrack/**` changes in a `git submodule update --remote constitution`
#   pull. Its ENTIRE body is a single delegated `exec` into the generic
#   bootstrap so a constitution pull auto-wires the multi-track system
#   out-of-the-box (DESIGN §2.2 — this is the "belt" of the belt-and-
#   suspenders pair; the "suspenders" is the consuming project's own
#   scripts/setup.sh calling multitrack_bootstrap.sh once at first clone,
#   §11.4.36).
#
# Usage:   bash register.sh <project-root>
# Inputs:  $1 — consuming project root (post_update_hook.sh always passes
#          its own $PROJECT_ROOT here; defaults to $PWD if invoked
#          standalone).
# Outputs: multitrack_bootstrap.sh's own stdout/stderr + its exit code,
#          relayed VERBATIM via `exec` (no wrapper logic of any kind —
#          post_update_hook.sh's install_skills() already treats a
#          non-zero register.sh exit as a non-fatal WARN + continues, so a
#          genuinely-missing per-host config here does not abort the pull;
#          see multitrack_bootstrap.sh's exit-code table).
# Side-effects: NONE of its own — 100% delegated to multitrack_bootstrap.sh
#          (this file contains no wiring logic; it is the auto-install
#          TRIGGER only, per §11.4.28 decoupling — the engine lives ONLY in
#          scripts/multitrack/).
# Cross-references:
#   constitution/scripts/multitrack/multitrack_bootstrap.sh (the body)
#   constitution/scripts/post_update_hook.sh (the invoking seam, §11.4.164
#     STEP 2 install_skills())
#   docs/research/universal_auto_multitrack_20260704/DESIGN.md §2.2
#   docs/superpowers/plans/ruler_bridge_plan.md RB-08
#   constitution/scripts/multitrack/test_multitrack_bootstrap.sh (RED/GREEN)
# Last verified: 2026-07-09
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"

exec bash "$SCRIPT_DIR/../../scripts/multitrack/multitrack_bootstrap.sh" "${1:-$(pwd)}"
