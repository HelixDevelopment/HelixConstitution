#!/usr/bin/env bash
# scripts/multitrack/track_branch_label.sh
#
# Purpose : Emit the §11.4.182 track+branch+alias work-stream identity label
#           `(T<N>/<branch> - <alias>)` for the CURRENT checkout, deterministically
#           derived (never guessed, §11.4.6). This is the reference labeler the
#           §11.4.182 guard hook (guard-track-branch-label.sh) points operators at,
#           and the canonical source for the prefix every agent/subagent dispatch
#           + operator-facing work-stream reference MUST start with.
# Usage   : bash constitution/scripts/multitrack/track_branch_label.sh
#           (run from within the checkout whose label you want)
# Inputs  : cwd (for /mnt/track<N> track detection), git HEAD (branch),
#           CLAUDE_CONFIG_DIR env (alias).
# Outputs : one line on stdout: `(T<N>/<branch> - <alias>)` + trailing newline.
# Side-effects: none (read-only; §11.4.128-safe).
# Deps    : bash, git (optional — falls back to '?' branch if absent).
# Cross-refs: §11.4.182 (label mandate), §11.4.178 (track-qualified identity),
#           §11.4.187 (multitrack engine), guard-track-branch-label.sh.
# Decoupling (§11.4.177): project-agnostic — derives everything from the
#           invocation context, carries NO project literal.
# Classification: universal.
#
# Derivation (all deterministic; honest '?' fallbacks are never a guess §11.4.6):
#   <N>     : from cwd '/mnt/track<N>/...'  else '?'
#   <branch>: git rev-parse --abbrev-ref HEAD  else '?'
#   <alias> : CLAUDE_CONFIG_DIR basename '.claude-<alias>' -> '<alias>'  else '?'

set -uo pipefail

# --- track number from the checkout path -----------------------------------
_dir="$(pwd -P 2>/dev/null || pwd)"
case "$_dir" in
  /mnt/track[0-9]*)
    _n="${_dir#/mnt/track}"; _n="${_n%%/*}"
    case "$_n" in ''|*[!0-9]*) _n='?' ;; esac
    ;;
  *) _n='?' ;;
esac

# --- branch from git --------------------------------------------------------
_br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ -n "$_br" ]] || _br='?'

# --- alias from CLAUDE_CONFIG_DIR basename '.claude-<alias>' -----------------
_al='?'
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  _cfgbase="$(basename "$CLAUDE_CONFIG_DIR" 2>/dev/null || true)"
  case "$_cfgbase" in
    .claude-?*) _al="${_cfgbase#.claude-}" ;;
  esac
fi

printf '(T%s/%s - %s)\n' "$_n" "$_br" "$_al"
