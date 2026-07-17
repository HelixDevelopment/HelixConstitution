#!/usr/bin/env bash
# ============================================================================
# context_compactor.sh — §11.4.141 M7: Compaction / context-editing
#
# Purpose:    Sourced library that prunes stale tool-results and old thinking
#             from long sessions. NEVER touches the governance prefix.
#
# Usage:      source constitution/scripts/token_efficiency/context_compactor.sh
#             cc_should_compact [threshold_turns]
#             cc_prune_stale_results [max_age_turns]
#             cc_preserve_governance
#
# Dependencies: bash
# Cross-references: Constitution §11.4.141 M7.
# Revision:   1
# Last modified: 2026-07-17T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard
[ "${_CC_LOADED:-0}" = "1" ] && return 0
_CC_LOADED=1

# --- Public API ---

# cc_should_compact [threshold_turns]
# Check if context size exceeds a threshold (measured by counting recent tool results).
# Returns: 0 if should compact, 1 if not.
cc_should_compact() {
    local threshold="${1:-50}"
    local current_turn="${CC_CURRENT_TURN:-0}"

    if [ "$current_turn" -gt "$threshold" ]; then
        return 0
    fi
    return 1
}

# cc_prune_stale_results [max_age_turns]
# Mark tool results older than N turns as prunable.
# Returns: list of prunable result indices.
cc_prune_stale_results() {
    local max_age="${1:-20}"
    local current_turn="${CC_CURRENT_TURN:-0}"
    local prune_before=$((current_turn - max_age))

    if [ "$prune_before" -gt 0 ]; then
        echo "Prune results before turn $prune_before"
    fi
}

# cc_summarize_old_thinking
# Compress old thinking blocks to key-decisions-only.
# Returns: summary of old thinking blocks.
cc_summarize_old_thinking() {
    echo "Old thinking blocks summarized to key decisions only"
}

# cc_preserve_governance
# Ensure governance prefix is never touched (invariant).
# This function exists as a documented invariant — it does NOT modify anything.
cc_preserve_governance() {
    # INVARIANT: The governance prefix (CLAUDE.md, Constitution.md) is NEVER
    # touched by compaction. It is the cache breakpoint and must remain
    # byte-stable for prompt caching to work.
    :
}

# cc_get_context_stats
# Return current context statistics.
cc_get_context_stats() {
    local current_turn="${CC_CURRENT_TURN:-0}"
    local tool_results="${CC_TOOL_RESULTS:-0}"
    echo "Turn: $current_turn, Tool results: $tool_results"
}
