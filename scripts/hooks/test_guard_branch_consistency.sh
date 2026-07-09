#!/usr/bin/env bash
# test_guard_branch_consistency.sh — hermetic test suite for the §11.4.181
# create-time PreToolUse guard hook (guard-branch-consistency.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the hook BLOCKS a manual
# feature-branch create with an UNREGISTERED name (exit 2), ALLOWS a REGISTERED
# name / the mint helper / a documented exception / a delete / a non-feature
# branch / non-git / non-Bash (exit 0), and FAILS-CLOSED (exit 2) when the
# registry cannot be read — so the enforcement itself provably cannot bluff.
#
# The registry SoT is a throwaway sqlite DB built here (only the logic_groups
# table the hook SELECTs), pointed at via $WI_DB — no project DB, no binary
# dependency; fully self-contained.
#
# Usage: bash constitution/scripts/hooks/test_guard_branch_consistency.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-branch-consistency.sh"

PASS=0
FAIL=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 unavailable — the registry-backed cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi

# --- throwaway registry: only 'feature:mistiq-vader' is registered -----------
TMPDIR_T="$(mktemp -d)"
EMPTYDIR="$(mktemp -d)"   # outside any git tree -> fail-closed probe
trap 'rm -rf "$TMPDIR_T" "$EMPTYDIR"' EXIT
TESTDB="$TMPDIR_T/registry.db"
sqlite3 "$TESTDB" "CREATE TABLE logic_groups (group_id TEXT PRIMARY KEY, title TEXT, destination TEXT NOT NULL, priority INTEGER NOT NULL, state TEXT, scope_note TEXT, roadmap_ref TEXT); INSERT INTO logic_groups (group_id,title,destination,priority,state) VALUES ('mistiq-vader','t','feature:mistiq-vader',10,'open'), ('urgent-main','t','main',0,'open');"

# run_case <name> <expected-exit> <json-payload> [mode]
#   mode default  -> registry mode: WI_DB=$TESTDB (verifiable)
#   mode failclosed -> run from a non-git tmp dir with WI_DB unset (unverifiable)
run_case() {
  local name="$1" want="$2" payload="$3" mode="${4:-registry}" got
  if [ "$mode" = "failclosed" ]; then
    got=$(cd "$EMPTYDIR" && env -u WI_DB bash "$HOOK" <<<"$payload" >/dev/null 2>&1; echo $?)
  else
    got=$(WI_DB="$TESTDB" bash "$HOOK" <<<"$payload" >/dev/null 2>&1; echo $?)
  fi
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-56s (exit %s)\n' "$name" "$got"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %-56s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL+1))
  fi
}

echo "§11.4.181 guard-branch-consistency.sh hermetic test suite"
echo "hook: $HOOK"
echo "registry: $TESTDB (registered: feature/mistiq-vader)"
echo

# --- ALLOW cases (exit 0) --------------------------------------------------
run_case "non-Bash tool (Agent) passes through"        0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main) x"}}'
run_case "non-git Bash (ls) passes through"            0 '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
run_case "git status (not a branch create)"            0 '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
run_case "git checkout existing (no -b)"               0 '{"tool_name":"Bash","tool_input":{"command":"git checkout main"}}'
run_case "checkout -b REGISTERED name"                 0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/mistiq-vader"}}'
run_case "switch -c REGISTERED name"                   0 '{"tool_name":"Bash","tool_input":{"command":"git switch -c feature/mistiq-vader"}}'
run_case "git branch REGISTERED name"                  0 '{"tool_name":"Bash","tool_input":{"command":"git branch feature/mistiq-vader"}}'
run_case "sanctioned mint-helper invocation"           0 '{"tool_name":"Bash","tool_input":{"command":"bin/workable-items group branch mistiq-vader --db docs/workable_items.db"}}'
run_case "documented-exception escape marker"          0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/adhoc # guardrails:allow operator-approved reconciliation"}}'
run_case "branch DELETE (-d) not a create"             0 '{"tool_name":"Bash","tool_input":{"command":"git branch -d feature/old-divergent"}}'
run_case "branch DELETE (-D) not a create"             0 '{"tool_name":"Bash","tool_input":{"command":"git branch -D feature/gone"}}'
run_case "non-feature branch create untouched"         0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b hotfix/urgent"}}'

# --- BLOCK cases (exit 2) --------------------------------------------------
run_case "checkout -b UNREGISTERED name blocked"       2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/unregistered-name"}}'
run_case "checkout -B UNREGISTERED name blocked"       2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -B feature/force-divergent"}}'
run_case "switch -c UNREGISTERED name blocked"         2 '{"tool_name":"Bash","tool_input":{"command":"git switch -c feature/another-divergent"}}'
run_case "git branch UNREGISTERED name blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git branch feature/typo-vadder"}}'
run_case "git branch -f UNREGISTERED blocked"          2 '{"tool_name":"Bash","tool_input":{"command":"git branch -f feature/forced-divergent"}}'
run_case "quoted UNREGISTERED name blocked"            2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b '"'"'feature/quoted-divergent'"'"'"}}'
run_case "fail-closed: registry unreadable blocks"     2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/whatever"}}' failclosed

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
