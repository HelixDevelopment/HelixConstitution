#!/usr/bin/env bash
# scripts/hooks/guard-track-branch-label.sh
#
# Claude Code PreToolUse guard hook (mechanical block) enforcing constitution
# §11.4.182 (track+branch work-stream labeling), which composes §11.4.178
# (track-qualified identity). Every agent / subagent / work-stream dispatch MUST
# carry a `(T<N>/<branch> - <alias>)` label prefix on its description so multi-track work
# (/mnt/track1..4) is never ambiguous — and enforcement MUST be independent of
# any agent's recall (§11.4.109-class anti-forgetting hook: a rule the
# orchestrator forgets to paste is not enforcement).
#
# CONTRACT (Claude Code PreToolUse hook):
#   - Receives the tool invocation as JSON on stdin.
#   - Exit 0  -> allow (Claude proceeds).
#   - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal reason.
#   - Any other exit -> non-blocking error (never used).
#
# SCOPE: only the agent-dispatching tools carry a work-stream label:
#   tool_name in { Agent, Task, TaskCreate }.
#   For those, the `description` (or, as a fallback, a `subagent` label) MUST
#   START with `^\(T[0-9]+/[^)]+ - [^)]+\) ` — e.g. `(T1/main - claude1) ATM-312 ...`.
#   Missing / malformed label -> exit 2 with the expected form + how to fix.
#   EVERY OTHER tool passes through untouched (exit 0) — this hook never breaks
#   non-agent tools.
#
# DECOUPLING (§11.4.177): this hook lives in the constitution submodule and is
# inherited BY REFERENCE (never copied). It is project-agnostic: it validates
# the label FORMAT and derives the expected example from the cwd (`/mnt/trackN`)
# + git directly — it does NOT depend on any project-specific helper path.
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

# --------------------------------------------------------------------------
# Extract a JSON string field WITHOUT requiring jq (prefer jq if present).
# Only leaf keys we need: tool_name, description, subagent.
# --------------------------------------------------------------------------
json_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r "$path // empty" 2>/dev/null || true
    return 0
  fi
  local key
  case "$path" in
    .tool_name)               key="tool_name" ;;
    .tool_input.description)  key="description" ;;
    .tool_input.subagent)     key="subagent" ;;
    *)                        key="${path##*.}" ;;
  esac
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""
      i = 1
      n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nx = substr(rest, i+1, 1)
          if (nx == "n") out = out "\n"
          else if (nx == "t") out = out "\t"
          else if (nx == "r") out = out "\r"
          else if (nx == "\"") out = out "\""
          else if (nx == "\\") out = out "\\"
          else if (nx == "/") out = out "/"
          else out = out nx
          i += 2
          continue
        }
        if (c == "\"") break
        out = out c
        i += 1
      }
      printf "%s", out
    }
  '
}

TOOL_NAME="$(json_field .tool_name)"

# Only the agent-dispatching tools carry a work-stream label. Anything else is
# allowed untouched.
case "$TOOL_NAME" in
  Agent|Task|TaskCreate) ;;
  *) exit 0 ;;
esac

# The label lives on `description`; fall back to a `subagent` label if present.
LABEL="$(json_field .tool_input.description)"
if [[ -z "$LABEL" ]]; then
  LABEL="$(json_field .tool_input.subagent)"
fi

# The required prefix: (T<N>/<branch> - <alias>) followed by a single space.
# §11.4.182 mandates the alias component — the claude-toolkit alias in use — so
# parallel-track work (each track driven by a DISTINCT alias) is never ambiguous.
# Track MUST be numeric (an off-track '?' is surfaced by a BLOCK, never mislabeled);
# alias MAY be '?' (honest when CLAUDE_CONFIG_DIR is unset / non-matching).
LABEL_RE='^\(T[0-9]+/[^)]+ - [^)]+\) '

if [[ -n "$LABEL" && "$LABEL" =~ $LABEL_RE ]]; then
  exit 0
fi

# --------------------------------------------------------------------------
# BLOCK: derive the expected example inline (project-agnostic).
#   track  = from cwd /mnt/track<N>/...  (else '?')
#   branch = git rev-parse --abbrev-ref HEAD (else '?')
# --------------------------------------------------------------------------
_dir="$(pwd -P 2>/dev/null || pwd)"
case "$_dir" in
  /mnt/track[0-9]*)
    _n="${_dir#/mnt/track}"; _n="${_n%%/*}"
    case "$_n" in ''|*[!0-9]*) _n='?' ;; esac
    ;;
  *) _n='?' ;;
esac
_br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ -n "$_br" ]] || _br='?'
# alias = CLAUDE_CONFIG_DIR basename '.claude-<alias>' -> '<alias>' (else '?', §11.4.6 honest)
_al='?'
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  _cfgbase="$(basename "$CLAUDE_CONFIG_DIR" 2>/dev/null || true)"
  case "$_cfgbase" in
    .claude-?*) _al="${_cfgbase#.claude-}" ;;
  esac
fi
_expected="(T${_n}/${_br} - ${_al})"

{
  echo "guardrails: BLOCKED — §11.4.182 track+branch work-stream label required"
  echo "Every ${TOOL_NAME} dispatch's description MUST start with a (T<N>/<branch> - <alias>) label."
  if [[ -z "$LABEL" ]]; then
    echo "  Found: <no description/subagent label>"
  else
    echo "  Found: ${LABEL}"
  fi
  echo "  Expected prefix for THIS checkout: '${_expected} '"
  echo "  Form: (T<track-number>/<git-branch> - <alias>) <space> then the task text."
  echo "  Example: '${_expected} ATM-312 MPV drm_prime investigation'"
  echo "  Derive the exact label with: scripts/multitrack/track_branch_label.sh"
} >&2
exit 2
