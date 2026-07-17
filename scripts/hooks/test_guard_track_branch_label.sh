#!/usr/bin/env bash
# test_guard_track_branch_label.sh — hermetic test suite for the §11.4.182
# PreToolUse guard hook (guard-track-branch-label.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the hook
#   - BLOCKS unlabeled / malformed agent dispatches (exit 2),
#   - BLOCKS a format-valid label whose ALIAS disagrees with the LIVE alias
#     (§11.4.182 alias-correctness — the stale-`claude4`-while-live-`claude3`
#     defect this fix closes),
#   - ALLOWS a label whose alias MATCHES the live alias (exit 0),
#   - ALLOWS an honest `?` alias on EITHER side (live unknown OR caller unsure),
#   - NEVER touches non-agent tools (exit 0),
# so the enforcement itself provably cannot bluff.
#
# DETERMINISM (§11.4.50 / §11.4.98): the live alias the hook derives comes from
# CLAUDE_CONFIG_DIR. This suite CONTROLS CLAUDE_CONFIG_DIR PER CASE (never relies
# on the ambient session), so it is fully hermetic + re-runnable regardless of
# which alias is driving the session that runs it. `LIVE` is pinned to a
# synthetic `hooktest` alias for the live-known cases.
#
# Usage: bash constitution/scripts/hooks/test_guard_track_branch_label.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-track-branch-label.sh"

# Synthetic KNOWN live alias for the live-known cases (deterministic, session-
# independent). CLAUDE_CONFIG_DIR basename '.claude-hooktest' -> alias 'hooktest'.
LIVE_CFG="/nonexistent/.claude-hooktest"
LIVE="hooktest"

PASS=0
FAIL=0

# run_case <name> <expected-exit> <json-payload> [<cfg>]
#   cfg absent / ""  -> keep the ambient CLAUDE_CONFIG_DIR
#   cfg "-"          -> RUN WITH CLAUDE_CONFIG_DIR UNSET (live alias '?')
#   cfg <path>       -> RUN WITH CLAUDE_CONFIG_DIR=<path>
run_case() {
  local name="$1" want="$2" payload="$3" cfg="${4:-}" got
  if [ -z "$cfg" ]; then
    printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
  elif [ "$cfg" = "-" ]; then
    printf '%s' "$payload" | env -u CLAUDE_CONFIG_DIR bash "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" >/dev/null 2>&1
  fi
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-58s (exit %s)\n' "$name" "$got"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %-58s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL+1))
  fi
}

echo "§11.4.182 guard-track-branch-label.sh hermetic test suite"
echo "hook:      $HOOK"
echo "live-alias: $LIVE (via CLAUDE_CONFIG_DIR=$LIVE_CFG)"
echo

# --- ALLOW: correct alias (matches live 'hooktest'), format variety, exit 0 ---
run_case "correct alias (T1/main - $LIVE)"          0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE) ATM-312 investigate\",\"prompt\":\"x\"}}"       "$LIVE_CFG"
run_case "correct alias Task (T2/feat/x - $LIVE)"   0 "{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"(T2/feat/x - $LIVE) do work\"}}"                                    "$LIVE_CFG"
run_case "correct alias TaskCreate (T3/main - $LIVE)" 0 "{\"tool_name\":\"TaskCreate\",\"tool_input\":{\"description\":\"(T3/main - $LIVE) create\"}}"                                 "$LIVE_CFG"
run_case "correct alias feature branch (T2/feature/mistiq-vader - $LIVE)" 0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T2/feature/mistiq-vader - $LIVE) SPK-1 work\",\"prompt\":\"y\"}}" "$LIVE_CFG"
run_case "correct alias multi-digit track (T12/main - $LIVE)" 0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T12/main - $LIVE) big track\"}}"                          "$LIVE_CFG"
run_case "correct alias via subagent field"         0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent\":\"(T1/main - $LIVE) via subagent field\"}}"                              "$LIVE_CFG"

# --- ALLOW: honest '?' alias accepted even when live is KNOWN (exit 0) -------
run_case "honest '?' alias while live KNOWN (T1/main - ?)" 0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main - ?) alias unknown"}}'                                        "$LIVE_CFG"

# --- BLOCK: NEW §11.4.182 alias-correctness — concrete WRONG alias, exit 2 ---
# (the exact defect this fix closes: stale/remembered alias e.g. claude4 while
#  the live alias is 'hooktest'.)
run_case "STALE alias claude4 while live=$LIVE BLOCKED"  2 '{"tool_name":"Task","tool_input":{"description":"(T1/main - claude4) ATM-312 some task"}}'                                 "$LIVE_CFG"
run_case "wrong alias deepseek while live=$LIVE BLOCKED" 2 '{"tool_name":"Agent","tool_input":{"description":"(T2/feature/x - deepseek) SPK-9 work","prompt":"x"}}'                    "$LIVE_CFG"
run_case "wrong alias on TaskCreate BLOCKED"            2 '{"tool_name":"TaskCreate","tool_input":{"description":"(T3/main - claude9) create"}}'                                       "$LIVE_CFG"

# --- ALLOW: live alias UNKNOWN (CLAUDE_CONFIG_DIR unset) — cannot verify, so a
#            concrete alias is accepted AND '?' is accepted (exit 0) ----------
run_case "live UNKNOWN accepts concrete alias (T1/main - claude9)" 0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main - claude9) live unknown"}}'                            "-"
run_case "live UNKNOWN accepts '?' (T1/main - ?)"       0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main - ?) both unknown"}}'                                            "-"

# --- ALLOW: non-agent tools always pass untouched (exit 0) -------------------
run_case "non-agent Bash always allowed"      0 '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'                                                                              "$LIVE_CFG"
run_case "non-agent Read always allowed"      0 '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'                                                                        "$LIVE_CFG"
run_case "non-agent Edit always allowed"      0 '{"tool_name":"Edit","tool_input":{"file_path":"x","old_string":"a","new_string":"b"}}'                                               "$LIVE_CFG"
run_case "unknown tool always allowed"        0 '{"tool_name":"SomethingElse","tool_input":{"description":"no label here"}}'                                                           "$LIVE_CFG"

# --- BLOCK: unlabeled / malformed (format fails first, alias-independent) ----
# §11.4.182: the alias component is MANDATORY — an alias-less prefix is BLOCKED.
run_case "alias-less (T1/main) BLOCKED"        2 '{"tool_name":"Agent","tool_input":{"description":"(T1/main) missing alias","prompt":"x"}}'                                           "$LIVE_CFG"
run_case "alias-less (T2/feature/x) BLOCKED"   2 '{"tool_name":"Task","tool_input":{"description":"(T2/feature/x) missing alias"}}'                                                    "$LIVE_CFG"
run_case "empty alias (T1/main - ) BLOCKED"    2 '{"tool_name":"Agent","tool_input":{"description":"(T1/main - ) empty alias"}}'                                                       "$LIVE_CFG"
run_case "unlabeled Agent"                     2 '{"tool_name":"Agent","tool_input":{"description":"just do the thing","prompt":"x"}}'                                                 "$LIVE_CFG"
run_case "unlabeled Task"                       2 '{"tool_name":"Task","tool_input":{"description":"do work"}}'                                                                        "$LIVE_CFG"
run_case "unlabeled TaskCreate"                 2 '{"tool_name":"TaskCreate","tool_input":{"description":"create a task"}}'                                                            "$LIVE_CFG"
run_case "missing description field on Agent"  2 '{"tool_name":"Agent","tool_input":{"prompt":"x"}}'                                                                                  "$LIVE_CFG"
run_case "malformed: no digit (T/main)"        2 '{"tool_name":"Agent","tool_input":{"description":"(T/main - x) bad","prompt":"x"}}'                                                  "$LIVE_CFG"
run_case "malformed: non-numeric track (T?/main)" 2 '{"tool_name":"Agent","tool_input":{"description":"(T?/main - x) bad"}}'                                                          "$LIVE_CFG"
run_case "malformed: no leading paren"         2 '{"tool_name":"Agent","tool_input":{"description":"T1/main - x) bad"}}'                                                               "$LIVE_CFG"
run_case "malformed: no slash (Tmain)"         2 '{"tool_name":"Agent","tool_input":{"description":"(Tmain - x) bad"}}'                                                                "$LIVE_CFG"
run_case "malformed: no trailing space"        2 '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x)nospace"}}'                                                          "$LIVE_CFG"
run_case "malformed: label mid-string"         2 '{"tool_name":"Agent","tool_input":{"description":"prefix (T1/main - x) not at start"}}'                                             "$LIVE_CFG"
run_case "empty description"                   2 '{"tool_name":"Agent","tool_input":{"description":""}}'                                                                              "$LIVE_CFG"

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
