#!/usr/bin/env bash
# ============================================================================
# scoped_read.sh — §11.4.141 M4: Retrieval-first over full-file loading
#
# Purpose:    Sourced library that prevents full-file loading when a targeted
#             read suffices. Grep for patterns, read only matching lines.
#
# Usage:      source constitution/scripts/token_efficiency/scoped_read.sh
#             sr_grep_then_read "pattern" "file" [context_lines]
#             sr_section_read "heading" "file"
#             sr_cached_result "key" "command"
#
# Dependencies: bash, grep, awk
# Cross-references: Constitution §11.4.141 M4, §11.4.78, §11.4.79.
# Revision:   1
# Last modified: 2026-07-17T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard: do not re-source if already loaded
[ "${_SCOPED_READ_LOADED:-0}" = "1" ] && return 0
_SCOPED_READ_LOADED=1

# Cache directory for results
_SR_CACHE_DIR="${TMPDIR:-/tmp}/scoped_read_cache"
mkdir -p "$_SR_CACHE_DIR" 2>/dev/null || true

# --- Public API ---

# sr_grep_then_read <pattern> <file> [context_lines]
# Grep for pattern, extract line numbers, read only those lines with context.
# Returns: matching lines with N lines of context (default 3).
sr_grep_then_read() {
    local pattern="$1"
    local file="$2"
    local context="${3:-3}"

    if [ ! -f "$file" ]; then
        echo "[scoped_read] File not found: $file" >&2
        return 1
    fi

    # Find matching lines
    local matches
    matches=$(grep -n "$pattern" "$file" 2>/dev/null | cut -d: -f1)

    if [ -z "$matches" ]; then
        return 0
    fi

    # Read context around each match
    local line_num
    for line_num in $matches; do
        local start=$((line_num - context))
        [ "$start" -lt 1 ] && start=1
        local end=$((line_num + context))
        sed -n "${start},${end}p" "$file"
        echo "---"
    done
}

# sr_section_read <heading> <file>
# Read a specific section by heading match. Returns content from heading to next heading.
sr_section_read() {
    local heading="$1"
    local file="$2"

    if [ ! -f "$file" ]; then
        echo "[scoped_read] File not found: $file" >&2
        return 1
    fi

    # Find heading line number
    local heading_line
    heading_line=$(grep -n "$heading" "$file" 2>/dev/null | head -1 | cut -d: -f1)

    if [ -z "$heading_line" ]; then
        return 0
    fi

    # Find next heading (same or higher level)
    local next_heading
    next_heading=$(awk -v start="$heading_line" 'NR > start && /^#{1,6} / { print NR; exit }' "$file")

    if [ -z "$next_heading" ]; then
        # Section goes to end of file
        tail -n +"$heading_line" "$file"
    else
        # Section from heading to next heading
        sed -n "${heading_line},$((next_heading - 1))p" "$file"
    fi
}

# sr_cached_result <key> <command>
# Cache a command result to avoid re-execution within a session.
# Returns cached result if available, otherwise executes and caches.
sr_cached_result() {
    local key="$1"
    local cmd="$2"
    local cache_file="$_SR_CACHE_DIR/${key}"

    # Check cache (valid for 5 minutes)
    if [ -f "$cache_file" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo "0") ))
        if [ "$cache_age" -lt 300 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Execute and cache
    local result
    result=$(eval "$cmd" 2>/dev/null)
    echo "$result" > "$cache_file"
    echo "$result"
}

# sr_clear_cache
# Clear the scoped read cache.
sr_clear_cache() {
    rm -rf "$_SR_CACHE_DIR" 2>/dev/null || true
    mkdir -p "$_SR_CACHE_DIR" 2>/dev/null || true
}
