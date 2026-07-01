#!/usr/bin/env bash
# scripts/release_prefix.sh — resolve the project release/tag prefix (§11.4.151).
#
# Single source of truth for "<PREFIX>-<version>" tag/version naming. EVERY
# release-tag-creating or version-naming script — main repo AND every owned
# submodule (§11.4.28 / §11.4.151) — MUST obtain its prefix from here so the
# SAME prefix spans the whole release and a release is greppable across every
# repo:  git tag -l "$(scripts/release_prefix.sh)-*"
#
# Resolution order (closed-set, deterministic — §11.4.6 no-guessing, §11.4.151):
#   1. HELIX_RELEASE_PREFIX from the environment (authoritative when set).
#   2. HELIX_RELEASE_PREFIX from the git-ignored project-root .env (§11.4.30),
#      PARSED (never sourced) so a hostile .env cannot execute code (§11.4.10).
#   3. Fallback: lowercased snake_case of the project-root directory name
#      (§11.4.29) — always resolvable from the checkout, no operator input.
#
# Usage:
#   prefix="$(bash scripts/release_prefix.sh)"                      # as a command
#   . scripts/release_prefix.sh; prefix="$(helix_release_prefix)"   # sourced
#
# Exit 0 + prints the prefix on stdout (never empty). Non-zero only on a
# genuinely unresolvable root — a directed error, never a guess (§11.4.6).
# Classification: universal (§11.4.17). No hardcoded prefix anywhere.

set -euo pipefail

# Project root: prefer git top-level; else this file's parent's parent
# (scripts/ lives one level under the root).
_hrp_project_root() {
  local root self_dir
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
    printf '%s' "$root"; return 0
  fi
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  (cd "$self_dir/.." && pwd)
}

# Parse HELIX_RELEASE_PREFIX=<value> from a .env WITHOUT sourcing it.
_hrp_from_env_file() {
  local envfile="$1" line val
  [ -f "$envfile" ] || return 0
  line="$(grep -E '^[[:space:]]*HELIX_RELEASE_PREFIX[[:space:]]*=' "$envfile" 2>/dev/null \
          | grep -vE '^[[:space:]]*#' | tail -n1 || true)"
  [ -n "$line" ] || return 0
  val="${line#*=}"
  val="${val#"${val%%[![:space:]]*}"}"   # ltrim
  val="${val%"${val##*[![:space:]]}"}"   # rtrim
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  printf '%s' "$val"
}

# Lowercase snake_case of the project-root dir name (§11.4.29 fallback):
# camelCase/PascalCase -> snake, non-alnum -> _, lowercase, squeeze/trim _.
# e.g. "HelixConstitution" -> "helix_constitution"; "My App" -> "my_app".
_hrp_snake_case() {
  printf '%s' "$1" \
    | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g; s/[^A-Za-z0-9]+/_/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/_+/_/g; s/^_//; s/_$//'
}

helix_release_prefix() {
  local root prefix
  if [ -n "${HELIX_RELEASE_PREFIX:-}" ]; then           # (1) env — authoritative
    printf '%s\n' "$HELIX_RELEASE_PREFIX"; return 0
  fi
  root="$(_hrp_project_root)"
  prefix="$(_hrp_from_env_file "$root/.env")"           # (2) .env (parsed, §11.4.10)
  if [ -n "$prefix" ]; then printf '%s\n' "$prefix"; return 0; fi
  prefix="$(_hrp_snake_case "$(basename "$root")")"     # (3) snake_case fallback
  if [ -z "$prefix" ]; then
    echo "release_prefix: cannot resolve a prefix (no HELIX_RELEASE_PREFIX, no .env value, empty root name)" >&2
    return 1
  fi
  printf '%s\n' "$prefix"
}

# Run directly (not sourced) -> print the resolved prefix.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then helix_release_prefix; fi
