#!/usr/bin/env bash
# cm_reporting_directives_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-REPORTING-DIRECTIVES (§11.4.202 reporting directives).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-REPORTING-DIRECTIVES is a GENUINE, non-bluff gate: breaking any
# load-bearing invariant MUST make it FAIL. Every mutation is applied to a COPY
# in a temp dir and the gate is pointed at the copies via --lib/--registry/
# --engine, so the REAL tree is NEVER mutated (§11.4.84 quiescence by
# construction — no in-place edit, no trap-restore race, no §11.4.84 residue).
#
# Sub-cases (each: expected gate verdict):
#   CTRL — pristine copies                                → gate PASSes (baseline).
#   M1   — registry with the BUG action row removed       → PRESENCE FAILs.
#   M2   — registry with single_colon_registered_only     → PRESENCE FAILs (prose
#          flipped to false                                  would be questioned).
#   M3   — lib with the single_colon branch stripped from → FUNCTIONAL FAILs
#          the python parse path                             (`BUG:` stops expanding).
#   M4   — lib with the registered-only NO-OP branch      → FUNCTIONAL FAILs
#          removed                                           (`NOTE:` starts ASKing).
#   M5   — engine with the honest-skip reasons replaced   → NO-FAKED-PUSH FAILs.
#          by an unconditional tracker PASS
#   M6   — engine with a project literal injected         → DECOUPLING FAILs.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_reporting_directives_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real lib / registry / engine.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, sed, python3, the sibling cm_reporting_directives.sh gate.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation) · §11.4.202 · §11.4.84 (copies, never in-place) ·
#   §11.4.108 (FUNCTIONAL, not grep-only) · §11.4.67 (parse-clean).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected verdict (the gate is genuine).
#   1 — a mutation did NOT make the gate FAIL (the gate is a BLUFF), or the
#       pristine control did not PASS.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)
GATE="$SELF_DIR/cm_reporting_directives.sh"

SRC_LIB="$CONST_DIR/scripts/action_prefix_lib.sh"
SRC_REG="$CONST_DIR/actions/registry.yaml"
SRC_ENG="$CONST_DIR/scripts/reporting/report_item.sh"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

RC=0
report() { # $1 label, $2 expected(pass|fail), $3 actual_rc
	if [ "$2" = "pass" ] && [ "$3" -eq 0 ]; then
		printf '  OK    %-4s gate PASSed as expected\n' "$1"
	elif [ "$2" = "fail" ] && [ "$3" -ne 0 ]; then
		printf '  OK    %-4s gate FAILed as expected (mutation caught)\n' "$1"
	else
		printf '  BLUFF %-4s expected gate to %s, but it exited %d\n' "$1" "$2" "$3" >&2
		RC=1
	fi
}

fresh() { # $1 = case dir → copies of all three artefacts
	mkdir -p "$WORK/$1"
	cp "$SRC_LIB" "$WORK/$1/action_prefix_lib.sh"
	cp "$SRC_REG" "$WORK/$1/registry.yaml"
	cp "$SRC_ENG" "$WORK/$1/report_item.sh"
	chmod +x "$WORK/$1/report_item.sh"
}
run_gate() { # $1 = case dir
	"$GATE" --quiet \
		--lib "$WORK/$1/action_prefix_lib.sh" \
		--registry "$WORK/$1/registry.yaml" \
		--engine "$WORK/$1/report_item.sh" >/dev/null 2>&1
}

# ── CTRL — pristine copies must PASS (else every FAIL below is meaningless) ──
fresh ctrl
run_gate ctrl; report "CTRL" pass $?

# ── M1 — remove the BUG action row from the registry ─────────────────────────
fresh m1
python3 - "$WORK/m1/registry.yaml" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# Drop the `- name: BUG` block (up to the next top-level list item at the same indent).
s = re.sub(r'\n  - name: BUG\n(?:.*?)(?=\n  - name: |\n# )', '\n', s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m1; report "M1" fail $?

# ── M2 — flip single_colon_registered_only to false ──────────────────────────
fresh m2
sed -i 's/single_colon_registered_only: true/single_colon_registered_only: false/' "$WORK/m2/registry.yaml"
run_gate m2; report "M2" fail $?

# ── M3 — strip the single_colon branch from the python parse path ────────────
fresh m3
python3 - "$WORK/m3/action_prefix_lib.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('''m = re.match(r'^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*): (.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\\t%s\\t%s\\t%s" % (ns, m.group(2), m.group(3), "single_colon"))
    sys.exit(0)
''', '')
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m3; report "M3" fail $?

# ── M4 — remove the registered-only NO-OP branch (prose would start ASKing) ──
fresh m4
python3 - "$WORK/m4/action_prefix_lib.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'\n  if \[ "\$form" = "single_colon" \]; then\n.*?\n  fi\n', '\n', s, count=1, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m4; report "M4" fail $?

# ── M5 — engine fakes a tracker push (honest SKIP reasons removed) ───────────
fresh m5
sed -i 's/credentials_absent: unset env:\$MISSING/pushed (no creds needed)/; s/T_VERDICT="SKIP"/T_VERDICT="PASS"/g; s/tracker_client_absent: no command configured for/pushed ok for/' "$WORK/m5/report_item.sh"
run_gate m5; report "M5" fail $?

# ── M6 — engine couples itself to one project (a hardcoded track checkout) ───
fresh m6
sed -i 's|^PROJECT_ROOT=\$(find_project_root)|PROJECT_ROOT=/mnt/track1/atmosphere-t1|' "$WORK/m6/report_item.sh"
run_gate m6; report "M6" fail $?

if [ "$RC" -eq 0 ]; then
	printf 'cm_reporting_directives_mutation_test: PASS (gate is genuine — every mutation caught)\n'
else
	printf 'cm_reporting_directives_mutation_test: FAIL (gate is a BLUFF for >=1 mutation)\n' >&2
fi
exit "$RC"
