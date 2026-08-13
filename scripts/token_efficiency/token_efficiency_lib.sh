#!/usr/bin/env bash
# ============================================================================
# token_efficiency_lib.sh — §11.4.141 M5+M6: Output reduction + tool-call efficiency
#
# Purpose:    Sourced library providing terse status, batch reads, cached grep.
#
# Usage:      source constitution/scripts/token_efficiency/token_efficiency_lib.sh
#             te_status_line "status message"
#             te_batch_read "file1" "file2" ...
#             te_cached_grep "pattern" "file"
#
# Dependencies: bash, grep
# Cross-references: Constitution §11.4.141 M5+M6.
# Revision:   1
# Last modified: 2026-07-17T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard
[ "${_TE_LIB_LOADED:-0}" = "1" ] && return 0
_TE_LIB_LOADED=1

# Cache directory
_TE_CACHE_DIR="${TMPDIR:-/tmp}/token_efficiency_cache"
mkdir -p "$_TE_CACHE_DIR" 2>/dev/null || true

# --- Public API ---

# te_status_line <message>
# Emit a terse one-line status (no governance restatement, just the delta).
te_status_line() {
    local msg="$1"
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[$ts] $msg"
}

# te_batch_read <file1> [file2] ...
# Read multiple files in one call, returning a structured summary.
# Returns: filename + line count + size for each file.
te_batch_read() {
    local files=("$@")
    local total_lines=0
    local total_bytes=0

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            local lines bytes
            lines=$(wc -l < "$f" 2>/dev/null || echo "0")
            bytes=$(wc -c < "$f" 2>/dev/null || echo "0")
            echo "$f: ${lines}L ${bytes}B"
            total_lines=$((total_lines + lines))
            total_bytes=$((total_bytes + bytes))
        else
            echo "$f: NOT_FOUND"
        fi
    done

    echo "---"
    echo "Total: ${total_lines}L ${total_bytes}B"
}

# te_cached_grep <pattern> <file> [cache_ttl_seconds]
# Grep with result caching. Returns cached result if fresh.
te_cached_grep() {
    local pattern="$1"
    local file="$2"
    local ttl="${3:-300}"
    local cache_key
    cache_key=$(echo "${pattern}_${file}" | md5sum | cut -d' ' -f1)
    local cache_file="$_TE_CACHE_DIR/${cache_key}"

    # Check cache
    if [ -f "$cache_file" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo "0") ))
        if [ "$cache_age" -lt "$ttl" ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Execute and cache
    local result
    result=$(grep "$pattern" "$file" 2>/dev/null || true)
    echo "$result" > "$cache_file"
    echo "$result"
}

# te_clear_cache
# Clear the token efficiency cache.
te_clear_cache() {
    rm -rf "$_TE_CACHE_DIR" 2>/dev/null || true
    mkdir -p "$_TE_CACHE_DIR" 2>/dev/null || true
}
