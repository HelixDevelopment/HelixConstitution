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

# run_case_effort <name> <expected-exit> <json-payload> <cfg> <effort-setting>
#   Hermetic control of the EFFORT signal too (the existing run_case only
#   controls CLAUDE_CONFIG_DIR, and the ambient session may carry a real
#   CLAUDE_EFFORT value -- these cases must not depend on that).
#   effort-setting "" (empty)  -> UNSET all 4 candidate effort vars (no signal)
#   effort-setting <value>     -> set CLAUDE_EFFORT=<value>, unset the other 3
run_case_effort() {
  local name="$1" want="$2" payload="$3" cfg="$4" effort="$5" got
  if [ -z "$effort" ]; then
    printf '%s' "$payload" | env -u CLAUDE_CONFIG_DIR -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT -u AGENT_EFFORT -u CMA_EFFORT \
      CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$payload" | env -u CLAUDE_CONFIG_DIR -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT -u AGENT_EFFORT -u CMA_EFFORT \
      CLAUDE_CONFIG_DIR="$cfg" CLAUDE_EFFORT="$effort" bash "$HOOK" >/dev/null 2>&1
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

echo
echo "§11.4.182/§11.4.201 EFFORT-BLUFF-CHECK extension (5-field <effort> field honesty)"
echo

# --- golden-GOOD: 5-field label with a REAL effort value, live signal present
#     and resolvable (regardless of exact-value match -- the guard only polices
#     a DISHONEST '?', never enforces the caller picked the identical tier) --
run_case_effort "5-field real effort ('high') + live signal present -> ALLOW" \
  0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - opus - high) ATM-1 work\",\"prompt\":\"x\"}}" \
  "$LIVE_CFG" "high"
run_case_effort "5-field real effort ('low', mismatched vs live 'high') -> ALLOW" \
  0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - sonnet - low) ATM-2 work\"}}" \
  "$LIVE_CFG" "high"

# --- golden-BAD (the exact bug this fix closes): 5-field label claims '?'
#     effort while a REAL effort signal is present + resolvable -> BLOCKED ---
run_case_effort "5-field '?' effort while live signal='high' BLOCKED" \
  2 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - sonnet - ?) ATM-3 dishonest\",\"prompt\":\"x\"}}" \
  "$LIVE_CFG" "high"
run_case_effort "5-field '?' effort while live signal='xhigh' BLOCKED (Task)" \
  2 "{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"(T2/feat/x - $LIVE - opus - ?) ATM-4 dishonest\"}}" \
  "$LIVE_CFG" "xhigh"

# --- NEGATIVE CONTROL (§11.4.201(1) false-positive guard): '?' effort is
#     HONEST + MUST NOT be blocked when NO effort signal is present at all --
run_case_effort "5-field '?' effort + NO live signal -> ALLOW (honest)" \
  0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - opus - ?) ATM-5 honest unknown\",\"prompt\":\"x\"}}" \
  "$LIVE_CFG" ""
# NEGATIVE CONTROL variant: an out-of-ladder env value resolves to a live '?'
# too (the labeler's own closed-ladder validation) -- still must NOT block.
run_case_effort "5-field '?' effort + out-of-ladder env value -> ALLOW" \
  0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - opus - ?) ATM-6 out-of-ladder\"}}" \
  "$LIVE_CFG" "banana"

# --- ALLOW: legacy 3-field / 4-field forms (no effort field AT ALL) are NEVER
#     flagged, regardless of whether a live effort signal is present --------
run_case_effort "3-field legacy (no effort field) + live signal present -> ALLOW" \
  0 "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"(T1/main - $LIVE) ATM-7 legacy 3-field\",\"prompt\":\"x\"}}" \
  "$LIVE_CFG" "high"
run_case_effort "4-field legacy (model, no effort field) + live signal present -> ALLOW" \
  0 "{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"(T1/main - $LIVE - opus) ATM-8 legacy 4-field\"}}" \
  "$LIVE_CFG" "high"

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
