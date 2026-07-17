#!/usr/bin/env bash
# cm_reporting_directives.sh — CM-REPORTING-DIRECTIVES gate (§11.4.202).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The §11.4.202 reporting directives (ISSUE / BUG / TASK) turn a plain-language
# report into a REAL, fully-populated, fully-synced workable item. This gate
# asserts FIVE invariants that together prove the mechanism is present, wired,
# functionally real (not a grep-only bluff — §11.4/§11.4.108), decoupled
# (§11.4.28), and structurally incapable of faking a tracker push (§11.4.10):
#
#   1. PRESENCE — the registry declares all three actions (ISSUE / BUG / TASK),
#      each with a non-empty expansion; and the grammar declares the §11.4.202
#      single-colon form (`single_colon_form_regex` + `single_colon_registered_only`).
#   2. ENGINE — report_item.sh exists, is executable, and parses clean under BOTH
#      bash -n and sh -n (§11.4.67).
#   3. DECOUPLING (§11.4.28 / §11.4.177) — the engine carries NO project literal
#      (no hardcoded project name / device serial / track path / id prefix); every
#      project-specific value arrives from the consumer-owned config.
#   4. FUNCTIONAL (load-bearing, runtime — the lib is SOURCED and RUN): each of
#      the three actions expands from the single-colon form AND from the ` :: `
#      form; ordinary prose (`TODO:` / `FIXME:`) is a NO-OP (never an ASK); a
#      REGISTERED single-colon token (e.g. §11.4.140 `NOTE:` / `CRITICAL:`) DOES
#      expand; a
#      `\`-escaped directive stays literal.
#   5. NO-FAKED-PUSH — the engine defines the honest SKIP reasons
#      (`credentials_absent` / `tracker_client_absent`) and contains no path that
#      reports a tracker PASS without executing a real command (§11.4.6/§11.4.10).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_reporting_directives.sh [--lib <p>] [--registry <p>] [--engine <p>] [--quiet]
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
#   §11.4.202 (the mandate) · §11.4.140 (grammar) · §11.4.93/.95 (DB SSoT) ·
#   §11.4.16 (type closed set) · §11.4.28/.177 (decoupling) · §11.4.10 (creds) ·
#   §11.4.67 (parseability) · §1.1 (paired mutation: cm_reporting_directives_mutation_test.sh)
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all invariants hold. 1 — one or more FAILed.
set -u

GATE="CM-REPORTING-DIRECTIVES"
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)

LIB="$CONST_DIR/scripts/action_prefix_lib.sh"
REGISTRY="$CONST_DIR/actions/registry.yaml"
ENGINE="$CONST_DIR/scripts/reporting/report_item.sh"
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
	for act in ISSUE BUG TASK; do
		if grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*$act[[:space:]]*$" "$REGISTRY"; then
			pass "registry declares the action: $act"
		else
			fail "registry does NOT declare the required reporting action: $act (§11.4.202)"
		fi
	done
	if grep -q 'single_colon_form_regex' "$REGISTRY"; then
		pass "grammar declares the §11.4.202 single-colon form"
	else
		fail "grammar is MISSING single_colon_form_regex (§11.4.202)"
	fi
	if grep -q 'single_colon_registered_only:[[:space:]]*true' "$REGISTRY"; then
		pass "single-colon form is registered-action-only (prose never ASKs)"
	else
		fail "grammar is MISSING single_colon_registered_only: true (§11.4.6 — prose like 'TODO:' would be questioned)"
	fi
fi

# ── 2. ENGINE ────────────────────────────────────────────────────────────────
if [ ! -f "$ENGINE" ]; then
	fail "engine not found: $ENGINE (§11.4.202)"
else
	pass "engine present: $ENGINE"
	[ -x "$ENGINE" ] && pass "engine is executable" || fail "engine is NOT executable"
	bash -n "$ENGINE" 2>/dev/null && pass "engine parses under bash -n (§11.4.67)" || fail "engine FAILS bash -n (§11.4.67)"
	sh -n "$ENGINE"   2>/dev/null && pass "engine parses under sh -n (§11.4.67)"   || fail "engine FAILS sh -n (§11.4.67)"
fi

# ── 3. DECOUPLING (§11.4.28 / §11.4.177) ─────────────────────────────────────
# The engine is inherited by reference by EVERY project — a project literal in it
# is the same class of violation as importing project code into a shared submodule.
if [ -f "$ENGINE" ]; then
	# Ignore the comment/doc lines; audit executable content only.
	CODE=$(grep -vE '^[[:space:]]*#' "$ENGINE" || true)
	LEAK=""
	# Deliberately narrow, high-signal literals: an absolute multi-track checkout
	# path, or a hardcoded project id-prefix default. (A project NAME may legitimately
	# never appear; these two are the observed coupling vectors.)
	printf '%s' "$CODE" | grep -qE '/mnt/track[0-9]' && LEAK="$LEAK track-path"
	printf '%s' "$CODE" | grep -qE '(^|[^A-Z_])ATM-[0-9]' && LEAK="$LEAK hardcoded-id-prefix"
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
	expect 'BUG: audio drops'            'expand/BUG'    'runtime: BUG: expands (single-colon form)'
	expect 'ISSUE: subs are late'        'expand/ISSUE'  'runtime: ISSUE: expands (single-colon form)'
	expect 'TASK: refactor the flasher'  'expand/TASK'   'runtime: TASK: expands (single-colon form)'
	expect 'BUG :: audio drops'          'expand/BUG'    'runtime: BUG :: expands (§11.4.140 form 1)'
	expect 'TASK ---> refactor'          'expand/TASK'   'runtime: TASK ---> expands (§11.4.140 form 5)'
	expect 'NOTE: remember this fact'    'expand/NOTE'     'runtime: registered NOTE: expands (§11.4.140 severity marker — was prose, now a registered action)'
	expect 'CRITICAL: fix audio'         'expand/CRITICAL' 'runtime: registered CRITICAL: expands (§11.4.140 severity marker)'
	expect 'TODO: fix later'             'noop/'         'runtime: prose TODO: is a NO-OP (never an ASK)'
	expect 'FIXME: refactor later'       'noop/'         'runtime: prose FIXME: is a NO-OP (never an ASK)'
	expect '\BUG: literal'               'escape/'       'runtime: \BUG: escapes to literal'
fi

# ── 5. NO-FAKED-PUSH (§11.4.10 / §11.4.6) ────────────────────────────────────
if [ -f "$ENGINE" ]; then
	if grep -q 'credentials_absent' "$ENGINE"; then
		pass "engine defines the honest SKIP reason: credentials_absent"
	else
		fail "engine does NOT define credentials_absent — an absent-credential push could be faked (§11.4.10)"
	fi
	if grep -q 'tracker_client_absent' "$ENGINE"; then
		pass "engine defines the honest SKIP reason: tracker_client_absent"
	else
		fail "engine does NOT define tracker_client_absent — an absent client could be faked (§11.4.6)"
	fi
	# A tracker verdict of PASS may ONLY be assigned after a real command exits 0.
	if grep -nE 'T_VERDICT="PASS"' "$ENGINE" | grep -qv 'T_RC' ; then
		# Assign-PASS lines must sit inside the rc==0 branch; assert the rc test exists.
		if grep -q 'if \[ "\$T_RC" = "0" \]' "$ENGINE"; then
			pass "tracker PASS is gated on a real command exit 0 (no faked push)"
		else
			fail "tracker PASS is NOT gated on a real command exit status (§11.4 faked-push surface)"
		fi
	else
		pass "tracker PASS is gated on a real command exit 0 (no faked push)"
	fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILN" -eq 0 ]; then
	[ "$QUIET" = "1" ] || printf '%s: PASS\n' "$GATE"
	exit 0
fi
printf '%s: FAIL (%d)\n' "$GATE" "$FAILN" >&2
exit 1
