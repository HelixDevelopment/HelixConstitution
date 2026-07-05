#!/usr/bin/env bash
# scripts/hooks/action_prefix_expand.sh
#
# Claude Code UserPromptSubmit hook — LAYER 2 of the universal "ACTION_NAME ::"
# prompt-prefix system (§11.4.140). The §11.4.109 anti-forgetting pattern applied
# to prompt prefixes: the expansion holds even if the model's recall lapses,
# because this hook rewrites/augments the prompt deterministically BEFORE the
# model sees it.
#
# ── CONTRACT (Claude Code UserPromptSubmit hook) ─────────────────────────────
#   Verified against https://code.claude.com/docs/en/hooks (2026-06-09):
#   - Receives the event JSON on stdin; the user's prompt lives at .prompt.
#   - Exit 0 with a JSON body
#       {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",
#                              "additionalContext":"<text>"}}
#     ADDS <text> to the conversation context (additive, discreet) — Claude then
#     obeys the injected expansion. Plain stdout would also be added as context
#     but more visibly; we use the JSON form for control.
#   - Exit 0 with EMPTY stdout → no-op (prompt passes through unchanged).
#   - Exit 2 → would BLOCK the prompt; we NEVER use that (a prefix system must
#     never reject a user's prompt).
#
# ── Behaviour ────────────────────────────────────────────────────────────────
#   - match (registered action)  → inject additionalContext = the expansion +
#                                   rules + the residual task framing; exit 0.
#   - no-match / escape           → empty stdout; exit 0 (pass-through).
#   - unknown grammar-shaped token→ inject a clarify note (§11.4.66/§11.4.105):
#                                   "this looks like an action prefix but is not
#                                   registered; ask which was meant; do not
#                                   invent an expansion (§11.4.6)". exit 0.
#   - any internal error          → FAIL-OPEN to pass-through (empty stdout,
#                                   exit 0) + a one-line stderr note. The hook
#                                   never crashes a prompt.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   stdin  : UserPromptSubmit event JSON
#   $HELIX_ACTION_REGISTRY (optional) : registry path override (§11.4.28)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   stdout : the hookSpecificOutput JSON (match/ask) OR empty (no-op).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None beyond reading the registry. Read-only.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/action_prefix_lib.sh (the pure expander). jq preferred, awk fallback.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (mandate), §11.4.109 (anti-forgetting), §11.4.6 (no-guessing),
#   §11.4.66/§11.4.105 (clarify), §11.4.67 (sh -n + bash -n clean),
#   §11.4.80 (inherited by reference — NEVER copied into the consuming project).
#
# Classification: universal (§11.4.17)

set -euo pipefail

# Fail-open wrapper: any unexpected error inside the hook degrades to a clean
# pass-through (empty stdout, exit 0) so a malformed payload never blocks a user.
apx_hook_main() {
  local hook_dir lib
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
  lib="$hook_dir/../action_prefix_lib.sh"
  if [ ! -f "$lib" ]; then
    echo "action_prefix_expand: library not found: $lib" >&2
    return 0   # fail-open
  fi
  # shellcheck source=/dev/null
  . "$lib"

  local payload prompt
  payload="$(cat || true)"
  [ -n "$payload" ] || return 0   # nothing to do

  prompt="$(apx_hook_json_field "$payload" prompt)"
  [ -n "$prompt" ] || return 0    # empty prompt → no-op

  local result verdict expansion residual action closest
  result="$(apx_expand_prompt "$prompt")" || return 0
  verdict="$(apx__json_get "$result" verdict)"

  case "$verdict" in
    expand)
      action="$(apx__json_get "$result" action)"
      expansion="$(apx__json_get "$result" expansion)"
      residual="$(apx__json_get "$result" residual)"
      local namespace form ctx
      namespace="$(apx__json_get "$result" namespace)"
      form="$(apx__json_get "$result" form)"
      ctx="[Action-Prefix System §11.4.140] The user's prompt began with the registered action prefix for '${action}' (namespace '${namespace}', grammar form '${form}' — one of the five equivalent forms ACTION ::, PREFIX::ACTION ::, /ACTION, /PREFIX::ACTION, ACTION ---> ). Apply this action's registered expansion and execute the remainder under it. Expansion: ${expansion} Task (remainder of the prompt): ${residual}"
      apx_hook_emit_context "$ctx"
      return 0
      ;;
    ask)
      action="$(apx__json_get "$result" action)"
      closest="$(apx__json_get "$result" closest)"
      local note
      note="[Action-Prefix System §11.4.140] The prompt's first line matches the action-prefix grammar (one of the five forms ACTION ::, PREFIX::ACTION ::, /ACTION, /PREFIX::ACTION, ACTION ---> ) with action token '${action}', but '${action}' is NOT a registered action in actions/registry.yaml. Per §11.4.66/§11.4.105: do NOT silently expand or drop it and do NOT invent an expansion (§11.4.6). Ask the user which registered action was meant"
      if [ -n "$closest" ]; then
        note="$note (closest registered action: '${closest}')"
      fi
      note="$note, or treat the line as a literal prompt if it is not an action."
      apx_hook_emit_context "$note"
      return 0
      ;;
    *)
      # noop / escape → pass-through (empty stdout).
      return 0
      ;;
  esac
}

# Extract a top-level JSON string field WITHOUT requiring jq (mirrors the
# guard-forbidden-commands.sh extractor so the hook ports cleanly).
apx_hook_json_field() {
  local payload="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null || true
    return 0
  fi
  printf '%s' "$payload" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""; i = 1; n = length(rest)
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
          i += 2; continue
        }
        if (c == "\"") break
        out = out c; i += 1
      }
      printf "%s", out
    }
  '
}

# Emit the UserPromptSubmit additionalContext JSON for $1.
apx_hook_emit_context() {
  local ctx="$1"
  local esc
  esc="$(printf '%s' "$ctx" | apx__json_escape)"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$esc"
}

apx_hook_main
exit 0
