#!/usr/bin/env bash
# cm_feature_directive_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-FEATURE-DIRECTIVE (§11.4.213 FEATURE research-scheduling directive).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-FEATURE-DIRECTIVE is a GENUINE, non-bluff gate: breaking any
# load-bearing invariant MUST make it FAIL. Every mutation is applied to a COPY
# in a temp dir and the gate is pointed at the copies via --lib/--registry/
# --engine, so the REAL tree is NEVER mutated (§11.4.84 quiescence by
# construction — no in-place edit, no trap-restore race, no §11.4.84 residue).
#
# Sub-cases (each: expected gate verdict):
#   CTRL — pristine copies                                  → gate PASSes (baseline).
#   M1   — registry with the FEATURE action row removed     → PRESENCE FAILs.
#   M2   — registry with single_colon_registered_only        → PRESENCE FAILs (prose
#          flipped to false                                     'feature: ...' would be questioned).
#   M3   — lib with the single_colon branch stripped from    → FUNCTIONAL FAILs
#          the python parse path                                 ('FEATURE:' stops expanding).
#   M4   — engine with a project literal injected            → DECOUPLING FAILs.
#          (a hardcoded track checkout path)
#   M5   — engine's delegation to report_item.sh replaced    → DELEGATION FAILs
#          with a stub (no longer invokes the shared engine)     (reimplementation risk).
#   M6   — engine's durable feature_queue.md append removed  → QUEUE FAILs
#                                                                 (a scheduled request could be dropped).
#   M7   — registry with the "EXECUTED LATER" scheduling-    → SCHEDULING-NOT-SYNCHRONOUS
#          not-synchronous framing sentence stripped from        FAILs (the anchor clause-5 claim
#          the FEATURE expansion (§11.4.213 clause 1/2)          that this mutation is caught,
#                                                                 proven — F2 remediation).
#   M8   — engine with a syntax-error line appended          → ENGINE parseability FAILs
#                                                                 (bash -n AND sh -n both catch it;
#                                                                 F2 remediation).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_feature_directive_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real lib / registry / engine.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, sed, python3, the sibling cm_feature_directive.sh gate.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation) · §11.4.213 · §11.4.84 (copies, never in-place) ·
#   §11.4.108 (FUNCTIONAL, not grep-only) · §11.4.67 (parse-clean).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected verdict (the gate is genuine).
#   1 — a mutation did NOT make the gate FAIL (the gate is a BLUFF), or the
#       pristine control did not PASS.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
CONST_DIR=$(cd "$SELF_DIR/../.." && pwd)
GATE="$SELF_DIR/cm_feature_directive.sh"

SRC_LIB="$CONST_DIR/scripts/action_prefix_lib.sh"
SRC_REG="$CONST_DIR/actions/registry.yaml"
SRC_ENG="$CONST_DIR/scripts/feature/schedule_feature_research.sh"

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
	cp "$SRC_ENG" "$WORK/$1/schedule_feature_research.sh"
	chmod +x "$WORK/$1/schedule_feature_research.sh"
}
run_gate() { # $1 = case dir
	"$GATE" --quiet \
		--lib "$WORK/$1/action_prefix_lib.sh" \
		--registry "$WORK/$1/registry.yaml" \
		--engine "$WORK/$1/schedule_feature_research.sh" >/dev/null 2>&1
}

# ── CTRL — pristine copies must PASS (else every FAIL below is meaningless) ──
fresh ctrl
run_gate ctrl; report "CTRL" pass $?

# ── M1 — remove the FEATURE action row from the registry ─────────────────────
fresh m1
python3 - "$WORK/m1/registry.yaml" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# Drop the `- name: FEATURE` block (up to the next top-level list item / comment at the same indent).
s = re.sub(r'\n  - name: FEATURE\n(?:.*?)(?=\n  - name: |\n# )', '\n', s, flags=re.S)
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

# ── M4 — engine couples itself to one project (a hardcoded track checkout) ───
fresh m4
sed -i 's|^PROJECT_ROOT=\$(find_project_root)|PROJECT_ROOT=/mnt/track1/atmosphere-t1|' "$WORK/m4/schedule_feature_research.sh"
run_gate m4; report "M4" fail $?

# ── M5 — engine's delegation to report_item.sh replaced with a stub ─────────
fresh m5
python3 - "$WORK/m5/schedule_feature_research.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    'RI_OUT=$(bash "$REPORT_ITEM" "$@" 2>&1)',
    'RI_OUT=\'{"item_id":"STUB-000","sync":{"verdict":"PASS","reason":""},"trackers":[]}\''
)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m5; report "M5" fail $?

# ── M6 — engine's durable feature_queue.md append removed ────────────────────
fresh m6
python3 - "$WORK/m6/schedule_feature_research.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'FEATURE_QUEUE="\$PROJECT_ROOT/docs/requests/feature_queue\.md".*?\n(?=\n# -{5,}\n# captured evidence)', '', s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m6; report "M6" fail $?

# ── M7 — registry: strip the "EXECUTED LATER" scheduling-not-synchronous ─────
# framing sentence from the FEATURE expansion (§11.4.213 clause 1/2). Proves
# the gate's clause-5 SCHEDULING-NOT-SYNCHRONOUS invariant is genuinely
# load-bearing, not merely an unproven claim in the anchor text (F2).
fresh m7
python3 - "$WORK/m7/registry.yaml" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# Word-wrapped YAML folded scalar: match across the line-wraps with \s+
# rather than literal single spaces.
pattern = re.compile(
    r'THEN\s+—\s+the\s+scheduled\s+research/planning/documentation\s+work\s+'
    r'itself\s+is\s+EXECUTED\s+LATER.*?NEVER\s+left\s+un-wired\s+in\s+the\s+'
    r'backlog\.\n',
    re.S,
)
assert pattern.search(s), "M7 fixture text not found in registry.yaml — source drifted"
s = pattern.sub('\n', s, count=1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
run_gate m7; report "M7" fail $?

# ── M8 — engine: append a syntax-error line (parseability) ──────────────────
# Proves the gate's ENGINE invariant genuinely parses the file under BOTH
# bash -n and sh -n rather than merely checking for the file's existence (F2).
fresh m8
printf '\necho "unterminated string for M7/M8 parseability mutation\n' >> "$WORK/m8/schedule_feature_research.sh"
run_gate m8; report "M8" fail $?

if [ "$RC" -eq 0 ]; then
	printf 'cm_feature_directive_mutation_test: PASS (gate is genuine — every mutation caught)\n'
else
	printf 'cm_feature_directive_mutation_test: FAIL (gate is a BLUFF for >=1 mutation)\n' >&2
fi
exit "$RC"
