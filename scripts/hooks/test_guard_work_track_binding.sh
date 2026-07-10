#!/usr/bin/env bash
# test_guard_work_track_binding.sh — hermetic test suite for the §11.4.191
# work-to-track/branch binding PreToolUse guard (guard-work-track-binding.sh)
# and its shared resolver (multitrack_work_binding.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the guard BLOCKS (exit 2)
# a mis-track COMMIT (a logic-group's file staged on the wrong branch) AND a
# mis-track DISPATCH (an ATM ticket dispatched onto the wrong (track, branch)),
# ALLOWS (exit 0) a correctly-placed commit / dispatch / an unclassified path /
# an unticketed dispatch / a documented `# guardrails:allow` exception / a
# non-Bash-non-Agent tool, and FAIL-CLOSES (exit 2) on an unreadable registry, an
# ambiguous file-scope, and a dynamic `$(…)` pathspec — so the enforcement itself
# provably cannot bluff (both block AND allow AND fail-closed exercised).
#
# The registry SoT is a throwaway sqlite DB built here; the commit-path cases use
# a throwaway git repo with a real initial commit (so `git rev-parse
# --abbrev-ref HEAD` yields a born branch name). No project DB, no project git
# tree, no binary dependency — fully self-contained.
#
# Usage: bash constitution/scripts/hooks/test_guard_work_track_binding.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-work-track-binding.sh"
RES="$HERE/../multitrack/multitrack_work_binding.sh"

PASS=0
FAIL=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 unavailable — the registry-backed cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git unavailable — the commit-path cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Throwaway registry (schema-v4 shape: logic_groups.canonical_track + group_paths).
#   mistiq-vader   -> feature/mistiq-vader / track-2   (the incident group)
#   token-reduction-> main                / track-1
#   roster-2026-07 -> feature/roster-2026-07 / NULL    (branch-enforced-only)
#   grp-a / grp-b  -> same-length globs claiming one 'ambig/' file (ambiguity probe)
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
EMPTYDIR="$(mktemp -d)"
trap 'rm -rf "$TMP" "$EMPTYDIR"' EXIT
DB="$TMP/registry.db"
sqlite3 "$DB" "
CREATE TABLE logic_groups (group_id TEXT PRIMARY KEY, title TEXT, destination TEXT NOT NULL, priority INTEGER NOT NULL, state TEXT, scope_note TEXT, roadmap_ref TEXT, canonical_track TEXT);
INSERT INTO logic_groups (group_id,title,destination,priority,state,canonical_track) VALUES
 ('mistiq-vader','t','feature:mistiq-vader',2,'open','track-2'),
 ('token-reduction','t','main',5,'open','track-1'),
 ('roster-2026-07','t','feature:roster-2026-07',6,'open',NULL),
 ('grp-a','t','feature:grp-a',7,'open','track-1'),
 ('grp-b','t','feature:grp-b',8,'open','track-1');
CREATE TABLE group_paths (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, path_glob TEXT NOT NULL, note TEXT, UNIQUE(group_id,path_glob));
INSERT INTO group_paths (group_id,path_glob) VALUES
 ('mistiq-vader','device/rockchip/atmosphere/remote_host/**'),
 ('mistiq-vader','device/rockchip/rk3588/tests/test_scrcpy_*.sh'),
 ('grp-a','ambig/a*.kt'),
 ('grp-b','ambig/*b.kt');
CREATE TABLE items (atm_id TEXT, type TEXT, status TEXT, title TEXT, description TEXT, logic_group TEXT, current_location TEXT, PRIMARY KEY(atm_id,current_location));
INSERT INTO items (atm_id,type,status,title,description,logic_group,current_location) VALUES
 ('ATM-900','Feature','In progress','t','desc','mistiq-vader','Issues'),
 ('ATM-901','Task','In progress','t','desc','token-reduction','Issues'),
 ('ATM-902','Bug','In progress','t','desc',NULL,'Issues');
"

# ---------------------------------------------------------------------------
# Throwaway git repo: seed commit on main so the branch is BORN, plus a
# feature/mistiq-vader branch. Files are created untracked; each commit case
# resets the index then stages exactly what it needs.
# ---------------------------------------------------------------------------
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name  t
echo seed > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -qm seed
git -C "$REPO" branch feature/mistiq-vader
mkdir -p "$REPO/device/rockchip/atmosphere/remote_host" "$REPO/device/rockchip/rk3588/tests"
echo x > "$REPO/device/rockchip/atmosphere/remote_host/Foo.kt"
echo y > "$REPO/README.md"
echo z > "$REPO/device/rockchip/rk3588/tests/test_scrcpy_box.sh"
echo z > "$REPO/device/rockchip/rk3588/tests/test_other.sh"

assert() { # <name> <want> <got>
  local name="$1" want="$2" got="$3"
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-58s (exit %s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-58s (got %s, want %s)\n' "$name" "$got" "$want"; FAIL=$((FAIL+1))
  fi
}

# run_hook <payload>  — dispatch/non-git path (WI_DB=$DB, cwd irrelevant).
run_hook() { WI_DB="$DB" bash "$HOOK" <<<"$1" >/dev/null 2>&1; echo $?; }

# commit_hook <branch> <payload> [db]  — checkout branch, run guard from $REPO.
commit_hook() {
  local branch="$1" payload="$2" db="${3:-$DB}"
  git -C "$REPO" checkout -q "$branch"
  ( cd "$REPO" && WI_DB="$db" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 ); echo $?
}
stage() { git -C "$REPO" reset -q; git -C "$REPO" add "$@" 2>/dev/null || true; }
unstage_all() { git -C "$REPO" reset -q; }

echo "§11.4.191 guard-work-track-binding.sh hermetic test suite"
echo "hook: $HOOK"
echo "resolver: $RES"
echo "registry: $DB (mistiq-vader=feature/mistiq-vader/track-2)"
echo

# ===========================================================================
# A. DISPATCH path (Agent | Task | TaskCreate) — label + ticket binding.
# ===========================================================================
echo "-- A. dispatch path --"
assert "dispatch mistiq ticket onto (T1/main) BLOCKED"        2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - claude4) ATM-900 scrcpy box"}}')"
assert "dispatch mistiq ticket onto (T2/feature/mistiq-vader)" 0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T2/feature/mistiq-vader - deepseek) ATM-900 scrcpy box"}}')"
assert "dispatch main ticket onto (T1/main) allowed"           0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) ATM-901 token-reduction"}}')"
assert "dispatch unclassified ticket ATM-902 allowed"          0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) ATM-902 misc"}}')"
assert "dispatch mistiq ticket onto (T3/feature/dolby-remap) BLOCKED" 2 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T3/feature/dolby-remap - x) ATM-900 wrong branch"}}')"
assert "dispatch with NO label passes (sibling hook handles)"  0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"unlabeled dispatch ATM-900"}}')"
assert "dispatch labeled with NO ticket allowed"               0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) generic docs task"}}')"
assert "Task tool: mistiq ticket onto (T1/main) BLOCKED"       2 "$(run_hook '{"tool_name":"Task","tool_input":{"description":"(T1/main - x) ATM-900 scrcpy"}}')"
assert "TaskCreate: mistiq ticket onto (T2/feature/mistiq-vader)" 0 "$(run_hook '{"tool_name":"TaskCreate","tool_input":{"description":"(T2/feature/mistiq-vader - kimi) ATM-900 scrcpy"}}')"
assert "dispatch unknown ticket SPK-500 (no item row) allowed" 0 "$(run_hook '{"tool_name":"Agent","tool_input":{"description":"(T1/main - x) SPK-500 unknown"}}')"
assert "non-Bash non-Agent tool (Read) passes through"         0 "$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"x"}}')"

# ===========================================================================
# B. COMMIT path (Bash) — file-scope binding via git plumbing.
# ===========================================================================
echo "-- B. commit path --"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq file staged on main BLOCKED"                    2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq file staged on feature/mistiq-vader allowed"    0 "$(commit_hook feature/mistiq-vader '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage README.md
assert "unclassified README staged on main allowed"            0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/rk3588/tests/test_scrcpy_box.sh
assert "test_scrcpy_*.sh staged on main BLOCKED (glob)"        2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/rk3588/tests/test_other.sh
assert "test_other.sh staged on main allowed (glob precision)" 0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "mistiq on main + # guardrails:allow => WARN allowed"   0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip # guardrails:allow operator-approved reconciliation"}}')"
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "non-commit Bash (git status) allowed"                  0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
# broad-stage (commit_all.sh) sweeps the whole dirty worktree even when nothing
# is staged: the mistiq file dirty+unstaged on main must BLOCK.
unstage_all
assert "commit_all.sh broad stage, mistiq dirty on main BLOCKED" 2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"bash scripts/commit_all.sh -m wip"}}')"
# dynamic $(…) pathspec -> fail-closed (unless escape marker).
unstage_all
assert "dynamic \$(…) pathspec commit BLOCKED (fail-closed)"   2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -- $(ls)"}}')"
assert "dynamic \$(…) pathspec + escape => WARN allowed"       0 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -- $(ls) # guardrails:allow vetted"}}')"
# DB unreadable in the commit path -> fail-closed (WI_DB points nowhere, $REPO
# has no docs/workable_items.db). A mistiq file is staged so FILESET is non-empty.
stage device/rockchip/atmosphere/remote_host/Foo.kt
assert "commit path, registry unreadable => fail-closed BLOCK" 2 "$(commit_hook main '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$TMP/does-not-exist.db")"

# ===========================================================================
# C. RESOLVER-direct — track dimension, glob precision, ambiguity, fail-closed.
# ===========================================================================
echo "-- C. resolver-direct --"
rd() { bash "$RES" "$@" >/dev/null 2>&1; echo $?; }
MF=device/rockchip/atmosphere/remote_host/X.kt
assert "resolver: mistiq file wrong TRACK (branch OK) BLOCKED" 2 "$(rd check --db "$DB" --branch feature/mistiq-vader --track track-9 --file "$MF")"
assert "resolver: mistiq file unknown track '?' allowed"       0 "$(rd check --db "$DB" --branch feature/mistiq-vader --track '?' --file "$MF")"
assert "resolver: ambiguous file scope => fail-closed BLOCK"   2 "$(rd check --db "$DB" --branch main --file ambig/ab.kt)"
assert "resolver: unreadable DB => fail-closed BLOCK"          2 "$(rd check --db "$TMP/nope.db" --branch main --file "$MF")"
# Ticket-path injection guard (RV-A' newline-bypass regression, §11.4.6/§11.4.10):
# single-line AND newline (multi-line) payloads must fail-closed; a valid-format ticket is accepted.
assert "resolver: single-line injection ticket => fail-closed" 2 "$(rd check --db "$DB" --branch main --ticket "ATM-1'; SELECT x")"
assert "resolver: NEWLINE injection ticket => fail-closed"     2 "$(rd check --db "$DB" --branch main --ticket "$(printf 'ATM-1\nINJ')")"
assert "resolver: valid-format ticket accepted (unclassified)" 0 "$(rd check --db "$DB" --branch main --ticket ATM-999999)"
# resolve prints the owning group (stdout content assertion).
RESOLVE_OUT="$(bash "$RES" resolve --db "$DB" --file "$MF" 2>/dev/null)"
if printf '%s' "$RESOLVE_OUT" | grep -q 'mistiq-vader'; then
  printf '  PASS  %-58s\n' "resolve prints owning group 'mistiq-vader'"; PASS=$((PASS+1))
else
  printf '  FAIL  %-58s (got: %s)\n' "resolve prints owning group 'mistiq-vader'" "$RESOLVE_OUT"; FAIL=$((FAIL+1))
fi

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
