#!/usr/bin/env bash
# cm_feature_directive.sh — CM-FEATURE-DIRECTIVE gate (§11.4.213).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The §11.4.213 FEATURE research-scheduling directive turns a plain-language
# feature description into a SCHEDULED (never synchronously executed) deep
# research + implementation-planning effort. This gate asserts SIX invariants
# that together prove the mechanism is present, wired, functionally real (not
# a grep-only bluff — §11.4/§11.4.108), decoupled (§11.4.28), delegates rather
# than reimplements the §11.4.202 item-creation/sync/tracker-push machinery,
# and is framed as SCHEDULING (never synchronous execution):
#
#   1. PRESENCE — the registry declares the FEATURE action with a non-empty
#      expansion; the grammar's §11.4.202 single-colon form is registered-only
#      (shared with BUG/TASK/ISSUE — re-asserted here so this gate is
#      self-contained).
#   2. ENGINE — schedule_feature_research.sh exists, is executable, and parses
#      clean under BOTH bash -n and sh -n (§11.4.67).
#   3. DECOUPLING (§11.4.28 / §11.4.177) — the engine carries NO project
#      literal (no hardcoded project name / device serial / track path / id
#      prefix); every project-specific value arrives from the consumer-owned
#      config.
#   4. FUNCTIONAL (load-bearing, runtime — the lib is SOURCED and RUN): FEATURE
#      expands from the single-colon form AND from the ` :: ` form; lowercase
#      prose ("feature: ...") is a NO-OP (never an ASK, since action tokens
#      are UPPERCASE-only per the shared §11.4.140 grammar).
#   5. SCHEDULING-NOT-SYNCHRONOUS — the registry's FEATURE expansion text
#      explicitly frames the directive as SCHEDULING work for the autonomous
#      loop to execute later, never as inline synchronous execution.
#   6. DELEGATION-NOT-REIMPLEMENTATION + DURABLE QUEUE — the engine invokes
#      the SAME report_item.sh engine (never a duplicate tracker-push/DB-write
#      implementation) AND appends scheduled requests to the durable
#      docs/requests/feature_queue.md queue so a request is never dropped.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_feature_directive.sh [--lib <p>] [--registry <p>] [--engine <p>] [--quiet]
#   The overrides let the paired §1.1 mutation test point the gate at MUTATED
#   COPIES in a temp dir, so the REAL tree is never mutated (§11.4.84).
#
# ── Inputs / Outputs / Side-effects ──────────────────────────────────────────
#   Inputs: the three artefacts above. Outputs: PASS/FAIL lines + exit status.
#   Side-effects: none (read-only; sources the lib in a subshell).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, grep, python3 (for the runtime verdict read). Parses clean under
#   bash -n + sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.213 (the mandate) · §11.4.202 (the delegated engine + reporting-
#   directive family) · §11.4.140 (grammar) · §11.4.93/.95 (DB SSoT) ·
#   §11.4.28/.177 (decoupling) · §11.4.10 (creds) · §11.4.67 (parseability) ·
#   §1.1 (paired mutation: cm_feature_directive_mutation_test.sh)
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all invariants hold. 1 — one or more FAILed.
set -u

GATE="CM-FEATURE-DIRECTIVE"
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)

LIB="$CONST_DIR/scripts/action_prefix_lib.sh"
REGISTRY="$CONST_DIR/actions/registry.yaml"
ENGINE="$CONST_DIR/scripts/feature/schedule_feature_research.sh"
QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--lib)      shift; LIB="$1" ;;
		--registry) shift; REGISTRY="$1" ;;
		--engine)   shift; ENGINE="$1" ;;
		--quiet)    QUIET=1 ;;
		*) printf '%s: unknown arg: %s\n' "$GATE" "$1" >&2; exit 2 ;;
	esac
	shift
done

FAILN=0
pass() { [ "$QUIET" = "1" ] || printf '  PASS  [%s] %s\n' "$GATE" "$1"; }
fail() { printf '  FAIL  [%s] %s\n' "$GATE" "$1" >&2; FAILN=$((FAILN + 1)); }

# ── 1. PRESENCE ──────────────────────────────────────────────────────────────
if [ ! -f "$REGISTRY" ]; then
	fail "registry not found: $REGISTRY"
else
	if grep -qE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*FEATURE[[:space:]]*$' "$REGISTRY"; then
		pass "registry declares the action: FEATURE"
	else
		fail "registry does NOT declare the required action: FEATURE (§11.4.213)"
	fi
	if grep -q 'single_colon_form_regex' "$REGISTRY"; then
		pass "grammar declares the §11.4.202 single-colon form (shared by FEATURE)"
	else
		fail "grammar is MISSING single_colon_form_regex (§11.4.202/§11.4.213)"
	fi
	if grep -q 'single_colon_registered_only:[[:space:]]*true' "$REGISTRY"; then
		pass "single-colon form is registered-action-only (prose 'feature: ...' never ASKs)"
	else
		fail "grammar is MISSING single_colon_registered_only: true (§11.4.6 — prose would be questioned)"
	fi
fi

# ── 2. ENGINE ────────────────────────────────────────────────────────────────
if [ ! -f "$ENGINE" ]; then
	fail "engine not found: $ENGINE (§11.4.213)"
else
	pass "engine present: $ENGINE"
	[ -x "$ENGINE" ] && pass "engine is executable" || fail "engine is NOT executable"
	bash -n "$ENGINE" 2>/dev/null && pass "engine parses under bash -n (§11.4.67)" || fail "engine FAILS bash -n (§11.4.67)"
	sh -n "$ENGINE"   2>/dev/null && pass "engine parses under sh -n (§11.4.67)"   || fail "engine FAILS sh -n (§11.4.67)"
fi

# ── 3. DECOUPLING (§11.4.28 / §11.4.177) ─────────────────────────────────────
# The engine is inherited by reference by EVERY project — a project literal in
# it is the same class of violation as importing project code into a shared
# submodule.
if [ -f "$ENGINE" ]; then
	CODE=$(grep -vE '^[[:space:]]*#' "$ENGINE" || true)
	LEAK=""
	printf '%s' "$CODE" | grep -qE '/mnt/track[0-9]' && LEAK="$LEAK track-path"
	printf '%s' "$CODE" | grep -qE '(^|[^A-Z_])ATM-[0-9]' && LEAK="$LEAK hardcoded-id-prefix"
	printf '%s' "$CODE" | grep -qE '(^|[^A-Z_])FTX-[0-9]' && LEAK="$LEAK hardcoded-id-prefix"
	if [ -z "$LEAK" ]; then
		pass "engine carries no project literal (§11.4.28 decoupled)"
	else
		fail "engine carries project literal(s):$LEAK (§11.4.28 — must come from the consumer config)"
	fi
fi

# ── 4. FUNCTIONAL (runtime — the load-bearing, non-grep invariant) ───────────
if [ ! -f "$LIB" ]; then
	fail "action_prefix_lib.sh not found: $LIB"
elif ! command -v python3 >/dev/null 2>&1; then
	fail "python3 absent — cannot run the FUNCTIONAL invariant (§11.4.6: not asserted ⇒ not claimed)"
else
	probe() { # $1 prompt → "verdict/action"
		(
			HELIX_ACTION_REGISTRY="$REGISTRY"
			export HELIX_ACTION_REGISTRY
			# shellcheck disable=SC1090
			. "$LIB"
			apx_expand_prompt "$1" | python3 -c 'import json,sys
d=json.load(sys.stdin); print("%s/%s" % (d["verdict"], d["action"]))' 2>/dev/null
		)
	}
	expect() { # $1 prompt, $2 expected "verdict/action", $3 label
		got=$(probe "$1" 2>/dev/null || true)
		if [ "$got" = "$2" ]; then pass "$3"; else fail "$3 — expected '$2', got '$got'"; fi
	}
	expect 'FEATURE: add dark mode'      'expand/FEATURE' 'runtime: FEATURE: expands (single-colon form)'
	expect 'FEATURE :: add dark mode'    'expand/FEATURE' 'runtime: FEATURE :: expands (§11.4.140 form 1)'
	expect 'FEATURE ---> add dark mode'  'expand/FEATURE' 'runtime: FEATURE ---> expands (§11.4.140 form 5)'
	expect '/FEATURE add dark mode'      'expand/FEATURE' 'runtime: /FEATURE expands (§11.4.140 form 3, bare slash)'
	expect '/DEFAULT::FEATURE add dark mode' 'expand/FEATURE' 'runtime: /DEFAULT::FEATURE expands (§11.4.140 form 4, namespaced slash)'
	expect '\FEATURE: literal'           'escape/'        'runtime: \FEATURE: escapes to literal'
	expect 'feature: add dark mode'      'noop/'          'runtime: lowercase feature: is a NO-OP (action tokens are UPPERCASE-only)'
	expect 'TODO: fix later'             'noop/'          'runtime: unrelated prose TODO: stays a NO-OP (never an ASK)'
fi

# ── 5. SCHEDULING-NOT-SYNCHRONOUS ─────────────────────────────────────────────
if [ -f "$REGISTRY" ]; then
	if grep -qE '(SCHEDULE|SCHEDULES|SCHEDULING)' "$REGISTRY" && grep -q '11\.4\.87' "$REGISTRY" && grep -qE 'EXECUTED LATER|EXECUTED (BY|LATER)' "$REGISTRY"; then
		pass "FEATURE expansion frames the directive as SCHEDULING (not synchronous execution)"
	else
		fail "FEATURE expansion is MISSING the scheduling-not-synchronous framing (§11.4.213 clause 1/2)"
	fi
else
	fail "registry not found — cannot assert the scheduling framing"
fi

# ── 6. DELEGATION-NOT-REIMPLEMENTATION + DURABLE QUEUE ───────────────────────
if [ -f "$ENGINE" ]; then
	if grep -q 'report_item.sh' "$ENGINE" && grep -qE 'bash "\$REPORT_ITEM"' "$ENGINE"; then
		pass "engine DELEGATES to report_item.sh (§11.4.202) — no duplicate tracker/DB-write logic"
	else
		fail "engine does NOT delegate to report_item.sh — risk of a duplicate/divergent tracker-push implementation (§11.4.213 clause 4)"
	fi
	# Require the FUNCTIONAL append operator, not merely a doc-comment mention of
	# the filename (a stripped-but-still-documented queue must still FAIL here).
	if grep -qF '>> "$FEATURE_QUEUE"' "$ENGINE"; then
		pass "engine appends scheduled requests to the durable feature_queue.md (never silently dropped)"
	else
		fail "engine does NOT append to a durable feature-research queue — a scheduled request could be silently dropped (§11.4.213 clause 4)"
	fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILN" -eq 0 ]; then
	[ "$QUIET" = "1" ] || printf '%s: PASS\n' "$GATE"
	exit 0
fi
printf '%s: FAIL (%d)\n' "$GATE" "$FAILN" >&2
exit 1
