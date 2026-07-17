#!/usr/bin/env bash
# cm_cli_agent_plugins_wired_mutation_test.sh — paired §1.1 mutation test for the
# CM-CLI-AGENT-PLUGINS-WIRED gate (§11.4.140 / §11.4.164).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A gate that cannot FAIL is a bluff gate (§11.4 / §1.1). This test PROVES the
# gate catches every regression class it claims to catch, by mutating a COPY of
# the constitution tree and asserting the gate FAILs on the mutated copy — and
# that it PASSes on the pristine copy (the golden-good control, so a
# fail-on-everything gate cannot pass this test either).
#
#   GOLDEN-GOOD  pristine copy                                   → gate MUST PASS
#   M1           delete one action's <name>.md command file      → gate MUST FAIL (inv. 3)
#   M2           strip the CONFLICT note from bug.md             → gate MUST FAIL (inv. 5)
#   M3           remove the install_cli_agent_plugins.sh call
#                from post_update_hook.sh                        → gate MUST FAIL (inv. 9)
#   M4           blank a SKILL.md `description:`                 → gate MUST FAIL (inv. 6)
#
# Each mutation additionally asserts the gate names the RIGHT invariant — a gate
# that FAILs for an unrelated reason would be a false-positive pass of this test.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash scripts/gates/cm_cli_agent_plugins_wired_mutation_test.sh [--quiet]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   The constitution tree this script lives in (read-only) + the gate script.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per mutation + a verdict. Exit 0 — the gate is proven
#   non-bluff. Exit 1 — a mutation did NOT make the gate fail (the gate itself is
#   defective) or the golden-good control did not pass.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE on the repo. Every mutation is applied inside a `mktemp -d` sandbox that
#   the EXIT trap removes (§11.4.14 / §11.4.84 — the REAL tree is never mutated,
#   so no mutation residue can ever be staged).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, cp, sed, mktemp, grep. Parses clean under bash -n and sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation) · §11.4.140 · §11.4.164 · §11.4.84 (quiescence —
#   sandbox-only mutation) · gate: cm_cli_agent_plugins_wired.sh
#
# Classification: universal (§11.4.17)
# Last verified: 2026-07-15
set -u

NAME="CM-CLI-AGENT-PLUGINS-WIRED mutation"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../.." >/dev/null 2>&1 && pwd)
GATE="$SELF_DIR/cm_cli_agent_plugins_wired.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { say "  PASS  [$NAME] $*"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

[ -x "$GATE" ] || { printf 'FATAL: gate not executable: %s\n' "$GATE" >&2; exit 2; }

TMP=$(mktemp -d) || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

PRISTINE="$TMP/pristine"
WORK="$TMP/work"

# ── build the pristine sandbox copy (only what the gate reads) ───────────────
mkdir -p "$PRISTINE/scripts"
cp -a "$ROOT/.claude-plugin" "$PRISTINE/.claude-plugin"
cp -a "$ROOT/plugins"        "$PRISTINE/plugins"
cp -a "$ROOT/actions"        "$PRISTINE/actions"
cp -a "$ROOT/skills"         "$PRISTINE/skills"
for s in action_prefix_lib.sh generate_agent_prefix_commands.sh \
         install_cli_agent_plugins.sh post_update_hook.sh; do
	cp -a "$ROOT/scripts/$s" "$PRISTINE/scripts/$s"
done

reset_work() { rm -rf "$WORK"; cp -a "$PRISTINE" "$WORK"; }

# run_gate <label> — prints combined output, returns the gate's exit code
run_gate() { bash "$GATE" --root "$WORK" 2>&1; }

# expect_fail <label> <invariant-substring>
expect_fail() {
	label="$1"; want="$2"
	out=$(run_gate); rc=$?
	if [ "$rc" -eq 0 ]; then
		bad "$label: the gate PASSED on the mutated tree — THE GATE IS A BLUFF GATE for this regression class"
		return 1
	fi
	if printf '%s\n' "$out" | grep -q "FAIL.*$want"; then
		ok "$label: gate FAILed as required (cited invariant: $want)"
	else
		bad "$label: gate failed (rc=$rc) but did NOT cite invariant '$want' — it may be failing for the WRONG reason"
		printf '%s\n' "$out" | sed 's/^/        | /' >&2
		return 1
	fi
	return 0
}

say "== $NAME (sandbox: $TMP) =="

# ── GOLDEN-GOOD control — the pristine copy MUST pass ────────────────────────
reset_work
if out=$(run_gate); then
	ok "GOLDEN-GOOD: pristine copy PASSes the gate (the gate is not fail-on-everything)"
else
	bad "GOLDEN-GOOD: pristine copy did NOT pass the gate — the gate is broken or over-strict"
	printf '%s\n' "$out" | sed 's/^/        | /' >&2
fi

# ── M1 — delete one action's <name>.md command file (invariant 3) ────────────
reset_work
rm -f "$WORK/plugins/helix/commands/task.md"
expect_fail "M1 (deleted commands/task.md)" "3/commands" || true

# ── M2 — strip the CONFLICT note from bug.md (invariant 5) ───────────────────
reset_work
sed -i '/CONFLICT (registry/,/silently shadows a host command\. -->/d' "$WORK/plugins/helix/commands/bug.md"
if grep -q 'CONFLICT (registry' "$WORK/plugins/helix/commands/bug.md"; then
	bad "M2: the mutation did not actually strip the CONFLICT note — mutation is a no-op, test invalid"
else
	expect_fail "M2 (CONFLICT note stripped from bug.md)" "5/conflict" || true
fi

# ── M3 — remove the installer call from post_update_hook.sh (invariant 9) ────
reset_work
sed -i 's/install_cli_agent_plugins\.sh/noop_not_the_installer.sh/g' "$WORK/scripts/post_update_hook.sh"
if grep -q 'install_cli_agent_plugins\.sh' "$WORK/scripts/post_update_hook.sh"; then
	bad "M3: the mutation did not actually remove the installer reference — mutation is a no-op, test invalid"
else
	expect_fail "M3 (installer call removed from post_update_hook.sh)" "9/autoload" || true
fi

# ── M4 — blank a SKILL.md description (invariant 6) ──────────────────────────
reset_work
sed -i 's/^description: .*/description: ""/' "$WORK/skills/action-prefix-system/SKILL.md"
if grep -q '^description: ""' "$WORK/skills/action-prefix-system/SKILL.md"; then
	expect_fail "M4 (blanked SKILL.md description)" "6/skills" || true
else
	bad "M4: the mutation did not blank the description — mutation is a no-op, test invalid"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $NAME: PASS — gate proven non-bluff (1 golden-good + 4 mutations) =="
	exit 0
fi
printf '== %s: FAIL (%s problem(s)) — the GATE itself is defective, fix the gate ==\n' "$NAME" "$FAILS" >&2
exit 1
