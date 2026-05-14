#!/usr/bin/env bash
# find_constitution.sh — Locate the Helix Constitution submodule from
# arbitrary nested depth.
#
# Sourced or executed from any submodule of any project that includes
# the constitution submodule. Walks up parent directories until it
# finds `constitution/Constitution.md`, or follows
# `git rev-parse --show-superproject-working-tree` recursively to find
# the top-level project.
#
# Usage (executed):
#   bash <path-to-this>/find_constitution.sh
#   → prints the absolute path to the constitution submodule root
#
# Usage (sourced):
#   . "$(<path>/find_constitution.sh)"   # NOT recommended — use the
#                                          'CONSTITUTION_DIR=$(...)' form
#   CONSTITUTION_DIR="$(bash <path>/find_constitution.sh)"
#
# Exit codes:
#   0 — constitution submodule located, path printed to stdout
#   1 — constitution submodule not found anywhere

set -euo pipefail

find_constitution_root() {
    local start_dir="${1:-$PWD}"
    local cur="${start_dir}"

    # Phase 1: walk up parents looking for a sibling `constitution/`
    # directory that contains `Constitution.md`.
    while [[ "${cur}" != "/" ]]; do
        if [[ -f "${cur}/constitution/Constitution.md" ]]; then
            echo "${cur}/constitution"
            return 0
        fi
        # Also check if we ARE inside `constitution/` already (e.g. a
        # script inside this submodule).
        if [[ "$(basename "${cur}")" == "constitution" && \
              -f "${cur}/Constitution.md" ]]; then
            echo "${cur}"
            return 0
        fi
        cur="$(dirname "${cur}")"
    done

    # Phase 2: follow git superproject pointer if we are inside a
    # submodule. Repeat until at top-level.
    cur="${start_dir}"
    while true; do
        local super
        super="$(git -C "${cur}" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
        if [[ -z "${super}" ]]; then
            # No more parents — we are at the top-level project.
            # Check one more time for a sibling `constitution/`.
            local toplevel
            toplevel="$(git -C "${cur}" rev-parse --show-toplevel 2>/dev/null || true)"
            if [[ -n "${toplevel}" && -f "${toplevel}/constitution/Constitution.md" ]]; then
                echo "${toplevel}/constitution"
                return 0
            fi
            break
        fi
        if [[ -f "${super}/constitution/Constitution.md" ]]; then
            echo "${super}/constitution"
            return 0
        fi
        cur="${super}"
    done

    return 1
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    # Executed (not sourced)
    if find_constitution_root "${PWD}"; then
        exit 0
    else
        echo "ERROR: constitution submodule not found above ${PWD}" >&2
        exit 1
    fi
fi
