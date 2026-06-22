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

    # Phase 0: explicit override — a consuming project may pin the
    # constitution location via CONSTITUTION_DIR (absolute path).
    if [[ -n "${CONSTITUTION_DIR:-}" && -f "${CONSTITUTION_DIR}/Constitution.md" ]]; then
        echo "${CONSTITUTION_DIR}"
        return 0
    fi

    # Candidate relative locations of the constitution submodule, in
    # priority order. The canonical top-level `constitution/` is kept
    # for backward compatibility; `submodules/constitution/` is the
    # §11.4.28 dependency-layout form (all owned submodules under a
    # root `submodules/` directory, §11.4.29 snake_case).
    local rels=( "constitution" "submodules/constitution" )

    # Phase 1: walk up parents looking for any candidate layout that
    # contains `Constitution.md`.
    while [[ "${cur}" != "/" ]]; do
        local rel
        for rel in "${rels[@]}"; do
            if [[ -f "${cur}/${rel}/Constitution.md" ]]; then
                echo "${cur}/${rel}"
                return 0
            fi
        done
        # Also check if we ARE inside `constitution/` already (e.g. a
        # script inside this submodule), under either layout.
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
            # Check one more time for any candidate layout.
            local toplevel rel
            toplevel="$(git -C "${cur}" rev-parse --show-toplevel 2>/dev/null || true)"
            if [[ -n "${toplevel}" ]]; then
                for rel in "${rels[@]}"; do
                    if [[ -f "${toplevel}/${rel}/Constitution.md" ]]; then
                        echo "${toplevel}/${rel}"
                        return 0
                    fi
                done
            fi
            break
        fi
        local rel
        for rel in "${rels[@]}"; do
            if [[ -f "${super}/${rel}/Constitution.md" ]]; then
                echo "${super}/${rel}"
                return 0
            fi
        done
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
