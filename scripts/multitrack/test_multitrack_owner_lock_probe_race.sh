#!/usr/bin/env bash
# =============================================================================
# test_multitrack_owner_lock_probe_race.sh — probe-vs-acquire race guard
#                                            (ATM-833 harness flake root cause).
# -----------------------------------------------------------------------------
# Purpose:
#   PROVE that a TRANSIENT lock holder (the exact shape of the `check` probe,
#   which transiently acquires the exclusive flock for the fork+exec window of
#   `true`) can NEVER permanently refuse a REAL owner's `run` acquisition —
#   while a GENUINE live owner still refuses it (bounded).
#
#   Root cause (captured 2026-07-23): `run` used single-shot `flock -n`; a
#   would-be owner whose acquire landed inside a concurrent probe's held-window
#   was PERMANENTLY refused, quoting the STALE .holder metadata (a dead pid) as
#   its "owner". Measured on the pre-fix tool: 2/30 stress iterations + 1/3
#   full ATM-833 suite runs (§11.4.50 nondeterminism; §11.4.201(1)
#   false-positive refusal). Fix: `run` acquires with `flock -w 2` — probe
#   windows are microseconds, real owners hold for the session lifetime.
#
#   §11.4.107(10) oracle shape:
#     T1 golden-good      transient holder (0.5s) -> run MUST acquire.
#     T2 negative-control genuine live owner      -> run MUST still be refused
#                         (the guard is not "never refuse anything").
#     T3 §1.1 mutation    revert `-w 2` -> `-n` in a COPY -> T1's case MUST
#                         fail on the mutated copy (the bound is load-bearing).
#
# Usage:   test_multitrack_owner_lock_probe_race.sh
# Inputs (env): none. Hermetic — everything under a fresh mktemp -d.
# Outputs: per-case PASS/FAIL lines; exit 0 iff every case passed.
# Side-effects: writes ONLY under its own temp dir (removed on exit, §11.4.14);
#               starts + reaps its own short-lived lock holders.
# Dependencies: bash, flock (util-linux), readlink, sha256sum, mktemp.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_checkout_owner_lock.sh (UUT)
#   constitution/scripts/multitrack/test_multitrack_cwd_hook_owner_guard.sh
#     (the suite whose hold_lock flake exposed the race)
#
# Constitution: §11.4.201(1) §11.4.50 §11.4.115 §11.4.119 §11.4.14 §11.4.67 §1.1
# =============================================================================
set -u

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
UUT="$SELF_DIR/multitrack_checkout_owner_lock.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TMP="$(mktemp -d)" || exit 1
HOLDER_PID=""
cleanup() {
    [ -n "$HOLDER_PID" ] && kill "$HOLDER_PID" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

[ -r "$UUT" ] || { echo "SKIP: UUT absent (reason: tool_absent)"; exit 2; }

CO="$TMP/checkout"; mkdir -p "$CO"
export MT_CHECKOUT_LOCK_DIR="$TMP/locks"

echo "=== owner-lock probe-vs-acquire race guard — UUT: $UUT"

LF="$(bash "$UUT" lockfile "$CO")" || { echo "FAIL: cannot resolve lockfile"; exit 1; }

# ---- T1 golden-good: TRANSIENT holder must not refuse a real owner ----------
# Exaggerated probe: hold the exclusive flock for 0.5s (a real `check` probe
# holds it for the microseconds-to-milliseconds fork+exec of `true`; 0.5s is a
# strictly HARDER case). A bounded-wait acquirer (-w 2) MUST ride it out.
flock "$LF" -c 'sleep 0.5' &
TRANSIENT_PID=$!
sleep 0.1   # ensure the transient holder is actually holding
if bash "$UUT" run "$CO" real_owner -- true >/dev/null 2>&1; then
    ok "T1 golden-good: transient (0.5s) holder ridden out — real owner acquired"
else
    bad "T1 golden-good" "run refused during a transient probe window — §11.4.201(1) false-positive refusal"
fi
wait "$TRANSIENT_PID" 2>/dev/null

# ---- T2 negative-control: a GENUINE live owner still refuses ----------------
bash "$UUT" run "$CO" genuine_owner -- sleep 15 >/dev/null 2>&1 &
HOLDER_PID=$!
i=0; up=0
while [ "$i" -lt 50 ]; do
    bash "$UUT" check "$CO" >/dev/null 2>&1 || { up=1; break; }
    i=$((i+1)); sleep 0.1
done
if [ "$up" != "1" ]; then
    bad "T2 negative-control setup" "genuine owner never established"
else
    t0=$(date +%s)
    if bash "$UUT" run "$CO" rival -- true >/dev/null 2>&1; then
        bad "T2 negative-control" "rival acquired past a LIVE owner — guard not load-bearing"
    else
        t1=$(date +%s)
        if [ $((t1 - t0)) -le 8 ]; then
            ok "T2 negative-control: genuine live owner still refused (bounded, $((t1-t0))s)"
        else
            bad "T2 negative-control" "refusal unbounded ($((t1-t0))s)"
        fi
    fi
fi
kill "$HOLDER_PID" 2>/dev/null; wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
sleep 0.3

# ---- T3 §1.1 mutation: revert the bound -> T1 must break --------------------
MUT="$TMP/uut_mutated.sh"
sed 's/flock -w 2 8/flock -n 8/' "$UUT" > "$MUT"
if grep -q 'flock -n 8' "$MUT" && bash -n "$MUT" 2>/dev/null; then
    export MT_CHECKOUT_LOCK_DIR="$TMP/locks_mut"
    CO2="$TMP/checkout2"; mkdir -p "$CO2"
    LF2="$(bash "$MUT" lockfile "$CO2")"
    flock "$LF2" -c 'sleep 0.5' &
    TP=$!
    sleep 0.1
    if bash "$MUT" run "$CO2" real_owner -- true >/dev/null 2>&1; then
        bad "T3 MUT §1.1: single-shot -n survived the transient holder" "mutation did not break T1 — the bound is NOT proven load-bearing"
    else
        ok "T3 MUT §1.1: reverting -w 2 -> -n reproduces the false refusal (bound IS load-bearing)"
    fi
    wait "$TP" 2>/dev/null
    export MT_CHECKOUT_LOCK_DIR="$TMP/locks"
else
    bad "T3 MUT §1.1" "mutation harness defect (could not apply/parse)"
fi

echo "--- RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
