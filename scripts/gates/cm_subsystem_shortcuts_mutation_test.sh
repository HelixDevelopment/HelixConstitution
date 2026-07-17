#!/usr/bin/env bash
# cm_subsystem_shortcuts_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-SUBSYSTEM-SHORTCUTS (§11.4.140 sub-system-shortcut extension).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-SUBSYSTEM-SHORTCUTS is a GENUINE, non-bluff gate: a stripped or
# mis-registered sub-system shortcut MUST make the gate FAIL. Each mutation is
# applied to a COPY of the real lib/registry in a temp dir and the gate is
# pointed at the copies via --lib/--registry, so the REAL tree is never mutated
# (§11.4.84 quiescence by construction — no in-place edit, no trap-restore race).
#
# Sub-cases (each: expected verdict):
#   CTRL — pristine copies                          → gate PASSes (baseline).
#   M1   — registry with the `subsystems:` block    → PRESENCE FAILs.
#          stripped
#   M2   — lib with the apx_lookup_subsystem CALL    → WIRING FAILs (+ FUNCTIONAL
#          in apx_expand_prompt renamed away             catalogue/discovery FAIL).
#   M3   — registry with a lowercase alias injected  → GRAMMAR-HONOUR FAILs.
#   M4   — lib with apx_lookup_subsystem() neutered  → FUNCTIONAL FAILs (proves
#          to return 1 (WIRING call still present)       the runtime check is not a
#                                                        grep-only bluff, §11.4.108).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_subsystem_shortcuts_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real lib/registry.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, sed, awk, the sibling cm_subsystem_shortcuts.sh gate. Parses clean
#   under bash -n + sh -n (§11.4.67).
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.140 (sub-system extension), §11.4.84
#   (quiescence — copies, never in-place), §11.4.108 (FUNCTIONAL not grep-only),
#   §11.4.67 (parse-clean).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected PASS/FAIL verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (gate / lib / registry missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_subsystem_shortcuts.sh"
REAL_LIB="${SCRIPT_DIR}/../action_prefix_lib.sh"
REAL_REG="${SCRIPT_DIR}/../../actions/registry.yaml"

for f in "$GATE" "$REAL_LIB" "$REAL_REG"; do
    [ -f "$f" ] || { echo "META: required file missing: $f" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_subsys_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
run_gate() { bash "$GATE" --lib "$1" --registry "$2" --quiet >/dev/null 2>&1; }
expect_pass() { local d="$1"; shift; if run_gate "$@"; then note "✅ META OK:   ${d} — gate PASSed"; else note "❌ META FAIL: ${d} — gate FAILed unexpectedly (false alarm)"; rc=1; fi; }
expect_fail() { local d="$1"; shift; if run_gate "$@"; then note "❌ META FAIL: ${d} — gate PASSed on a planted mutation (BLUFF GATE)"; rc=1; else note "✅ META OK:   ${d} — gate correctly FAILed on the mutation"; fi; }

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-SUBSYSTEM-SHORTCUTS (§11.4.140)"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- CTRL: pristine copies → PASS -------------------------------------------
C_LIB="$TMP/ctrl_lib.sh"; C_REG="$TMP/ctrl_reg.yaml"
cp "$REAL_LIB" "$C_LIB"; cp "$REAL_REG" "$C_REG"
expect_pass "CTRL (pristine copies)" "$C_LIB" "$C_REG"

# --- M1: strip the subsystems: catalogue → PRESENCE FAILs -------------------
M1_REG="$TMP/m1_reg.yaml"
sed '/^subsystems:[[:space:]]*$/,$d' "$C_REG" > "$M1_REG"
expect_fail "M1 (subsystems: catalogue stripped → PRESENCE)" "$C_LIB" "$M1_REG"

# --- M2: rename the wiring CALL away → WIRING (+ FUNCTIONAL) FAILs -----------
M2_LIB="$TMP/m2_lib.sh"
sed 's/apx_lookup_subsystem "\$token"/apx_lookup_subsystem_DISABLED "$token"/' "$C_LIB" > "$M2_LIB"
expect_fail "M2 (apx_lookup_subsystem call renamed → WIRING)" "$M2_LIB" "$C_REG"

# --- M3: inject a lowercase alias → GRAMMAR-HONOUR FAILs --------------------
M3_REG="$TMP/m3_reg.yaml"
sed 's/aliases: \[HXOTA\]/aliases: [HXOTA, lowercasebad]/' "$C_REG" > "$M3_REG"
expect_fail "M3 (lowercase alias injected → GRAMMAR-HONOUR)" "$C_LIB" "$M3_REG"

# --- M4: neuter apx_lookup_subsystem() (WIRING call still present) →
#         FUNCTIONAL FAILs (proves the runtime check is not a grep-only bluff) -
M4_LIB="$TMP/m4_lib.sh"
sed 's/^apx_lookup_subsystem() {/apx_lookup_subsystem() { return 1 #MUT/' "$C_LIB" > "$M4_LIB"
expect_fail "M4 (resolver neutered, call intact → FUNCTIONAL not a grep-bluff)" "$M4_LIB" "$C_REG"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-SUBSYSTEM-SHORTCUTS is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-SUBSYSTEM-SHORTCUTS failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
