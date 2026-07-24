#!/usr/bin/env bash
# =============================================================================
# test_multitrack_cwd_hook_owner_guard.sh — §11.4.119 cwd-hook checkout-owner
#                                           advisory check (ATM-833).
# -----------------------------------------------------------------------------
# Purpose:
#   PROVE two things about the checkout-owner check added to
#   `multitrack_cwd_hook.sh`:
#
#     (A) IT CAN NEVER BREAK A SESSION. The hook is invoked by the toolkit as
#         `cd "$(hook <alias>)" 2>/dev/null || true`, so the ONLY ways it could
#         harm a session are (i) printing a wrong path, (ii) hanging, or
#         (iii) failing to print the worktree when it should. This suite drives
#         the hook through EVERY failure condition that can be constructed —
#         tool absent, tool unreadable, tool crashing, tool returning an
#         unexpected exit code, tool hanging, lock dir unwritable, owner process
#         dead, owner process alive, resolver missing, resolver silent,
#         malformed policy value — and asserts the hook ALWAYS exits 0 and
#         ALWAYS behaves as it did before the check existed (except in the one
#         deliberate `enforce`-on-contention case).
#
#     (B) IT IS NOT DECORATIVE. The golden-bad case (a REAL live owner holding
#         the REAL checkout-owner lock, including via the symlink alias) MUST
#         produce the warning, and under `enforce` MUST withhold the worktree.
#         The negative control (a genuinely free checkout) MUST stay silent, so
#         a warn-everything hook cannot pass.
#
#   §11.4.107(10) self-validating oracle: golden-good + golden-bad + negative
#   control. §1.1 paired mutation: blinding the probe (a SEMANTIC change, not a
#   grepped-literal deletion) MUST make the golden-bad case fail.
#
# Usage:   test_multitrack_cwd_hook_owner_guard.sh            # full suite
#          test_multitrack_cwd_hook_owner_guard.sh --no-slow  # skip the hang test
#
# Inputs (env): none required. Fully hermetic — every run builds its own engine
#               dir, stub resolver, lock dir and log under a fresh mktemp -d.
# Outputs:      per-case PASS/FAIL lines; exit 0 iff every case passed.
# Side-effects: writes ONLY under its own temp dir (removed on every exit path
#               per §11.4.14); starts + reaps its own short-lived lock holders.
# Dependencies: bash, flock, readlink, sha256sum, mktemp (same set the tool
#               under test needs).
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_cwd_hook.sh   (unit under test)
#   scripts/multitrack/multitrack_checkout_owner_lock.sh     (the lock tool)
#   docs/research/multitrack_duplicate_supervisors_20260722/DIAGNOSIS.md
#
# Constitution: §11.4.119 §11.4.111 §11.4.180 §11.4.201 §11.4.107(10) §11.4.6
#               §11.4.14 §11.4.67 §11.4.177 §1.1
# =============================================================================
set -u

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
HOOK_SRC="$SELF_DIR/multitrack_cwd_hook.sh"
RUN_SLOW=1
[ "${1:-}" = "--no-slow" ] && RUN_SLOW=0

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

TMP=""
cleanup() {
    # Reap any holder we started, then remove the sandbox (§11.4.14).
    [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null
    wait 2>/dev/null
    [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

# --- locate the checkout-owner-lock tool -------------------------------------
# Sibling first (post-promotion), then the consumer layout relative to the repo
# root this engine is vendored into. Resolved as FACT; absent => honest skip.
_find_lock_tool() {
    local c
    c="$SELF_DIR/multitrack_checkout_owner_lock.sh"; [ -r "$c" ] && { printf '%s' "$c"; return 0; }
    c="$(cd -P "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)/scripts/multitrack/multitrack_checkout_owner_lock.sh"
    [ -r "$c" ] && { printf '%s' "$c"; return 0; }
    return 1
}

# --- sandbox -----------------------------------------------------------------
TMP="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
ENGINE="$TMP/engine"; mkdir -p "$ENGINE"
REAL_WT="$TMP/mount/project-t9"; mkdir -p "$REAL_WT"
ALIAS_WT="$TMP/mount/project"; ln -s "project-t9" "$ALIAS_WT"   # the symlink-alias topology
LOCKDIR="$TMP/locks"
LOG="$TMP/guard.log"

cp "$HOOK_SRC" "$ENGINE/multitrack_cwd_hook.sh" || { echo "cannot copy hook"; exit 1; }

# Stub resolver: prints $STUB_WT for `resolve`, a fixed id for `track`.
cat > "$ENGINE/multitrack_resolve_worktree.sh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    resolve) [ -n "${STUB_WT:-}" ] && printf '%s\n' "$STUB_WT" ;;
    track)   [ -n "${STUB_WT:-}" ] && printf 'track-9\n' ;;
esac
exit 0
STUB
chmod +x "$ENGINE/multitrack_resolve_worktree.sh"

LOCK_TOOL="$(_find_lock_tool)" || {
    echo "SKIP: checkout-owner-lock tool not found (reason: tool_absent) — cannot run the golden-bad cases honestly (§11.4.3)" >&2
    exit 2
}
cp "$LOCK_TOOL" "$ENGINE/multitrack_checkout_owner_lock.sh"
chmod +x "$ENGINE/multitrack_checkout_owner_lock.sh"

# --- driver ------------------------------------------------------------------
# Runs the hook exactly as cma_run does (capturing stdout only) with a fully
# controlled environment. Sets OUT / ERR / RC / WARNED.
run_hook() {
    local errf="$TMP/err.$$"
    : > "$LOG"
    OUT="$(
        env -u MT_CHECKOUT_OWNER_LOCK -u MT_CHECKOUT_OWNER_POLICY \
            -u MULTITRACK_AUTOMATED -u MULTITRACK_DISABLE \
            STUB_WT="${T_WT-}" \
            MT_CHECKOUT_LOCK_DIR="$LOCKDIR" \
            MT_CHECKOUT_OWNER_LOG="$LOG" \
            ${T_POLICY+MT_CHECKOUT_OWNER_POLICY="$T_POLICY"} \
            ${T_AUTOMATED+MULTITRACK_AUTOMATED="$T_AUTOMATED"} \
            ${T_TOOL+MT_CHECKOUT_OWNER_LOCK="$T_TOOL"} \
            bash "$ENGINE/multitrack_cwd_hook.sh" alias2 2>"$errf"
    )"
    RC=$?
    ERR="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
    if grep -q 'already owned by another live agent' "$LOG" 2>/dev/null; then WARNED=1; else WARNED=0; fi
    return 0
}

# Acquire the checkout lock as a real, live, external holder.
HOLDER_PID=""
hold_lock() {   # $1 = path to claim (real or symlink alias)
    bash "$ENGINE/multitrack_checkout_owner_lock.sh" run "$1" rival_holder -- sleep 120 \
        >/dev/null 2>&1 &
    HOLDER_PID=$!
    local i=0
    while [ "$i" -lt 50 ]; do
        MT_CHECKOUT_LOCK_DIR="$LOCKDIR" bash "$ENGINE/multitrack_checkout_owner_lock.sh" \
            check "$1" >/dev/null 2>&1 || return 0     # rc 3 = BUSY => holder is up
        i=$((i+1)); sleep 0.1
    done
    return 1
}
release_lock() { [ -n "$HOLDER_PID" ] && kill "$HOLDER_PID" 2>/dev/null; wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""; sleep 0.2; return 0; }

# The holder must see the same lock dir.
export MT_CHECKOUT_LOCK_DIR="$LOCKDIR"

echo "=== §11.4.119 cwd-hook checkout-owner guard — hook: $HOOK_SRC"
echo "--- A. FAIL-OPEN PROOF (the hook must NEVER withhold the worktree on any error path)"

# ---- N1 golden-good: free checkout, default policy --------------------------
T_WT="$REAL_WT"; unset T_POLICY T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "0" ] \
    && ok "N1 golden-good: free checkout -> worktree printed, exit 0, silent" \
    || bad "N1 golden-good" "rc=$RC out='$OUT' warned=$WARNED"

# ---- N2 negative control: free checkout under ENFORCE -----------------------
T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "0" ] \
    && ok "N2 NEGATIVE CONTROL: free checkout + enforce -> worktree printed, silent" \
    || bad "N2 negative control (a warn-everything hook fails here)" "rc=$RC out='$OUT' warned=$WARNED"

# ---- F1 tool absent ---------------------------------------------------------
mv "$ENGINE/multitrack_checkout_owner_lock.sh" "$TMP/tool.hidden"
T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
    && ok "F1 fail-open: lock tool ABSENT -> worktree still printed" \
    || bad "F1 tool absent" "rc=$RC out='$OUT'"
mv "$TMP/tool.hidden" "$ENGINE/multitrack_checkout_owner_lock.sh"

# ---- F2 tool unreadable -----------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    ok "F2 fail-open: tool UNREADABLE -> SKIPPED (running as root; chmod 000 is not enforced) [reason: topology_unsupported]"
else
    chmod 000 "$ENGINE/multitrack_checkout_owner_lock.sh"
    T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
    run_hook
    [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
        && ok "F2 fail-open: lock tool UNREADABLE -> worktree still printed" \
        || bad "F2 tool unreadable" "rc=$RC out='$OUT'"
    chmod 755 "$ENGINE/multitrack_checkout_owner_lock.sh"
fi

# ---- F3 tool crashes / F4 unexpected exit code ------------------------------
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/tool_crash.sh"; chmod +x "$TMP/tool_crash.sh"
T_WT="$REAL_WT"; T_POLICY="enforce"; T_TOOL="$TMP/tool_crash.sh"; unset T_AUTOMATED
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
    && ok "F3 fail-open: tool exits 1 (crash) -> worktree still printed" \
    || bad "F3 tool crash" "rc=$RC out='$OUT'"

printf '#!/usr/bin/env bash\necho garbage\nexit 7\n' > "$TMP/tool_rc7.sh"; chmod +x "$TMP/tool_rc7.sh"
T_TOOL="$TMP/tool_rc7.sh"
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
    && ok "F4 fail-open: tool exits 7 (unexpected rc) -> worktree still printed" \
    || bad "F4 unexpected rc" "rc=$RC out='$OUT'"
unset T_TOOL

# ---- F5 lock dir unwritable -------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    ok "F5 fail-open: lock dir UNWRITABLE -> SKIPPED (running as root) [reason: topology_unsupported]"
else
    mkdir -p "$TMP/nowrite"; chmod 500 "$TMP/nowrite"
    T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
    OUT="$(env -u MT_CHECKOUT_OWNER_LOCK MT_CHECKOUT_LOCK_DIR="$TMP/nowrite/locks" \
             MT_CHECKOUT_OWNER_POLICY=enforce MT_CHECKOUT_OWNER_LOG="$LOG" \
             STUB_WT="$REAL_WT" bash "$ENGINE/multitrack_cwd_hook.sh" alias2 2>/dev/null)"
    RC=$?
    [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
        && ok "F5 fail-open: lock dir UNWRITABLE -> worktree still printed" \
        || bad "F5 lock dir unwritable" "rc=$RC out='$OUT'"
    chmod 755 "$TMP/nowrite"
fi

# ---- F6 owner process DEAD (stale metadata) ---------------------------------
bash "$ENGINE/multitrack_checkout_owner_lock.sh" run "$REAL_WT" dead_holder -- true >/dev/null 2>&1
T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "0" ] \
    && ok "F6 owner process DEAD -> checkout read as FREE, worktree printed, silent" \
    || bad "F6 dead owner (must NOT be read as busy)" "rc=$RC out='$OUT' warned=$WARNED"

# ---- F7 resolver missing entirely -------------------------------------------
mv "$ENGINE/multitrack_resolve_worktree.sh" "$TMP/resolver.hidden"
T_WT="$REAL_WT"; unset T_POLICY T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ -z "$OUT" ] \
    && ok "F7 fail-open: resolver MISSING -> nothing printed, exit 0 (pre-existing behaviour)" \
    || bad "F7 resolver missing" "rc=$RC out='$OUT'"
mv "$TMP/resolver.hidden" "$ENGINE/multitrack_resolve_worktree.sh"

# ---- F8 resolver silent (conductor / unmapped) ------------------------------
T_WT=""; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
run_hook
[ "$RC" = "0" ] && [ -z "$OUT" ] && [ "$WARNED" = "0" ] \
    && ok "F8 conductor path: no worktree resolved -> no owner check, nothing printed" \
    || bad "F8 conductor path" "rc=$RC out='$OUT' warned=$WARNED"

# ---- F9/F10 need a live owner ----------------------------------------------
if ! hold_lock "$ALIAS_WT"; then
    bad "hold_lock (via symlink alias) could not acquire the checkout lock" "cannot run contention cases"
else
    # ---- GB1 GOLDEN-BAD, default policy (warn) ------------------------------
    T_WT="$REAL_WT"; unset T_POLICY T_AUTOMATED T_TOOL
    run_hook
    [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "1" ] \
        && ok "GB1 GOLDEN-BAD (warn): live owner via symlink alias -> WARNED, worktree still printed (human never blocked)" \
        || bad "GB1 golden-bad warn" "rc=$RC out='$OUT' warned=$WARNED"

    # ---- GB2 GOLDEN-BAD, enforce -------------------------------------------
    T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
    run_hook
    [ "$RC" = "0" ] && [ -z "$OUT" ] && [ "$WARNED" = "1" ] \
        && ok "GB2 GOLDEN-BAD (enforce): live owner -> WARNED + worktree WITHHELD, exit 0 (session still starts)" \
        || bad "GB2 golden-bad enforce" "rc=$RC out='$OUT' warned=$WARNED"

    # ---- GB3 automation marker selects enforce ------------------------------
    T_WT="$REAL_WT"; unset T_POLICY T_TOOL; T_AUTOMATED="1"
    run_hook
    [ "$RC" = "0" ] && [ -z "$OUT" ] && [ "$WARNED" = "1" ] \
        && ok "GB3 MULTITRACK_AUTOMATED=1 selects enforce -> worktree withheld" \
        || bad "GB3 automation marker" "rc=$RC out='$OUT' warned=$WARNED"

    # ---- F9 policy=off escape hatch ----------------------------------------
    T_WT="$REAL_WT"; T_POLICY="off"; unset T_AUTOMATED T_TOOL
    run_hook
    [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "0" ] \
        && ok "F9 escape hatch: policy=off with a live owner -> no check, worktree printed" \
        || bad "F9 policy=off" "rc=$RC out='$OUT' warned=$WARNED"

    # ---- F10 malformed policy falls back to the PERMISSIVE default ----------
    T_WT="$REAL_WT"; T_POLICY="bogus-typo"; unset T_AUTOMATED T_TOOL
    run_hook
    [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] \
        && ok "F10 fail-open: malformed policy value -> permissive 'warn', worktree printed" \
        || bad "F10 malformed policy" "rc=$RC out='$OUT'"

    # ---- MUTATION (§1.1): blind the probe, GB2 must break ------------------
    cp "$ENGINE/multitrack_cwd_hook.sh" "$TMP/hook.orig"
    # SEMANTIC mutation: the probe now always reports "free" (a blind guard).
    # This deletes no literal the check greps for — it changes what the
    # mechanism DOES (§11.4.115(F): a string-deletion mutation is a tautology).
    perl -0pi -e 's/(_cwh_owner_busy\(\) \{\n)/$1    return 0\n/' "$ENGINE/multitrack_cwd_hook.sh" 2>/dev/null \
        || sed -i 's/^_cwh_owner_busy() {$/_cwh_owner_busy() {\n    return 0/' "$ENGINE/multitrack_cwd_hook.sh"
    if bash -n "$ENGINE/multitrack_cwd_hook.sh" 2>/dev/null && \
       grep -A1 '^_cwh_owner_busy() {$' "$ENGINE/multitrack_cwd_hook.sh" | grep -q 'return 0'; then
        T_WT="$REAL_WT"; T_POLICY="enforce"; unset T_AUTOMATED T_TOOL
        run_hook
        if [ "$OUT" = "$REAL_WT" ] && [ "$WARNED" = "0" ]; then
            ok "MUT §1.1: blinded probe -> GB2 breaks (guard is load-bearing, not decorative)"
        else
            bad "MUT §1.1: blinded probe still detected contention" "out='$OUT' warned=$WARNED — the guard is NOT load-bearing"
        fi
    else
        bad "MUT §1.1: could not apply the semantic mutation" "mutation harness defect"
    fi
    cp "$TMP/hook.orig" "$ENGINE/multitrack_cwd_hook.sh"

    release_lock
fi

# ---- F11 tool hangs -> bounded, fail open -----------------------------------
if [ "$RUN_SLOW" = "1" ]; then
    printf '#!/usr/bin/env bash\nsleep 60\n' > "$TMP/tool_hang.sh"; chmod +x "$TMP/tool_hang.sh"
    T_WT="$REAL_WT"; T_POLICY="enforce"; T_TOOL="$TMP/tool_hang.sh"; unset T_AUTOMATED
    _t0=$(date +%s)
    run_hook
    _t1=$(date +%s)
    if [ "$RC" = "0" ] && [ "$OUT" = "$REAL_WT" ] && [ $((_t1-_t0)) -lt 20 ]; then
        ok "F11 fail-open: HANGING tool -> bounded ($((_t1-_t0))s) and worktree still printed"
    else
        bad "F11 hanging tool" "rc=$RC out='$OUT' elapsed=$((_t1-_t0))s"
    fi
    unset T_TOOL
else
    echo "  SKIP  F11 hanging-tool bound (--no-slow) [reason: operator_attended]"
fi

echo
echo "--- B. RESULT"
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
