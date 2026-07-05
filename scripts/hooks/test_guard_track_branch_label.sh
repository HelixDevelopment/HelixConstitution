#!/usr/bin/env bash
# test_guard_track_branch_label.sh — hermetic test suite for the §11.4.182
# PreToolUse guard hook (guard-track-branch-label.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the hook BLOCKS unlabeled
# agent dispatches (exit 2), ALLOWS labeled ones (exit 0), and NEVER touches
# non-agent tools (exit 0) — so the enforcement itself provably cannot bluff.
#
# Usage: bash constitution/scripts/hooks/test_guard_track_branch_label.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-track-branch-label.sh"

PASS=0
FAIL=0

# run_case <name> <expected-exit> <json-payload>
run_case() {
  local name="$1" want="$2" payload="$3" got
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
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
echo "hook: $HOOK"
echo

# --- ALLOW cases (labeled agent dispatches, exit 0) -----------------------
run_case "labeled Agent (T1/main)"            0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main) ATM-312 investigate","prompt":"x"}}'
run_case "labeled Task (T2/feat/x)"           0 '{"tool_name":"Task","tool_input":{"description":"(T2/feat/x) do work"}}'
run_case "labeled TaskCreate (T3/main)"       0 '{"tool_name":"TaskCreate","tool_input":{"description":"(T3/main) create"}}'
run_case "well-formed (T2/feature/mistiq-vader)" 0 '{"tool_name":"Agent","tool_input":{"description":"(T2/feature/mistiq-vader) SPK-1 work","prompt":"y"}}'
run_case "multi-digit track (T12/main)"       0 '{"tool_name":"Agent","tool_input":{"description":"(T12/main) big track"}}'
run_case "subagent-field fallback label"      0 '{"tool_name":"Agent","tool_input":{"subagent":"(T1/main) via subagent field"}}'

# --- ALLOW cases (non-agent tools always pass, exit 0) --------------------
run_case "non-agent Bash always allowed"      0 '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
run_case "non-agent Read always allowed"      0 '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
run_case "non-agent Edit always allowed"      0 '{"tool_name":"Edit","tool_input":{"file_path":"x","old_string":"a","new_string":"b"}}'
run_case "unknown tool always allowed"        0 '{"tool_name":"SomethingElse","tool_input":{"description":"no label here"}}'

# --- BLOCK cases (unlabeled / malformed agent dispatches, exit 2) ---------
run_case "unlabeled Agent"                    2 '{"tool_name":"Agent","tool_input":{"description":"just do the thing","prompt":"x"}}'
run_case "unlabeled Task"                      2 '{"tool_name":"Task","tool_input":{"description":"do work"}}'
run_case "unlabeled TaskCreate"                2 '{"tool_name":"TaskCreate","tool_input":{"description":"create a task"}}'
run_case "missing description field on Agent" 2 '{"tool_name":"Agent","tool_input":{"prompt":"x"}}'
run_case "malformed: no digit (T/main)"       2 '{"tool_name":"Agent","tool_input":{"description":"(T/main) bad","prompt":"x"}}'
run_case "malformed: non-numeric track (T?/main)" 2 '{"tool_name":"Agent","tool_input":{"description":"(T?/main) bad"}}'
run_case "malformed: no leading paren"        2 '{"tool_name":"Agent","tool_input":{"description":"T1/main) bad"}}'
run_case "malformed: no slash (Tmain)"        2 '{"tool_name":"Agent","tool_input":{"description":"(Tmain) bad"}}'
run_case "malformed: no trailing space"       2 '{"tool_name":"Agent","tool_input":{"description":"(T1/main)nospace"}}'
run_case "malformed: label mid-string"        2 '{"tool_name":"Agent","tool_input":{"description":"prefix (T1/main) not at start"}}'
run_case "empty description"                  2 '{"tool_name":"Agent","tool_input":{"description":""}}'

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
