#!/usr/bin/env bash
# =============================================================================
# test_credential_scan_lib.sh — self-validating fixtures for the project-agnostic
# credential-scan library (credential_scan_lib.sh). §11.4.201 / §11.4.107(10):
# a guard that false-POSITIVEs is a FAIL-bluff exactly as a false-NEGATIVE pass
# is a PASS-bluff — so this suite pins BOTH directions with golden fixtures.
#
# GOLDEN-GOOD (MUST all be CLEAN — no false positive on a legitimate carrier):
#   (a) a git@github.com:org/repo SSH remote line,
#   (b) a `user@1000.service was SIGKILLed (status=9/KILL)` §12 forensic note,
#   (c) an Android `clientId=...AudioManager@...AudioManager$$Synthetic...@hex`
#       logcat object reference,
#   (d) a BINARY `*.db` blob embedding an email + a password-shaped token
#       (proves the .db binary-skip prevents the detector-2 false positive).
# GOLDEN-BAD (MUST all be CAUGHT — real leaks):
#   (1) `user@company.com : S3cretPass99`  (email+password adjacency, lc TLD),
#   (2) `api_key=AKIA...`                    (known-token + keyword-assignment),
#   (3) `password: hunter2hunter2`           (keyword-anchored assignment),
#   (4) `-----BEGIN OPENSSH PRIVATE KEY-----`(private-key marker),
#   (5) `AIza<35 chars>`                     (Google-API-key format).
#
# A golden-bad that is NOT caught means the library WEAKENED the gate (a release
# blocker); a golden-good that IS caught means a §11.4.201 false-positive.
#
# Usage:        bash constitution/scripts/hooks/test_credential_scan_lib.sh
# Inputs:       none (builds fixtures in a mktemp dir; touches nothing tracked).
# Outputs:      one PASS/FAIL line per case; exit 0 iff EVERY case passes.
# Side-effects: creates + removes a mktemp dir (trap … EXIT).
# Dependencies: bash, grep, awk.
# Cross-refs:   credential_scan_lib.sh (system under test); §11.4.10 / §11.4.201 /
#               §11.4.107(10) / §1.1.
#
# SECURITY: uses ONLY SYNTHETIC fake credentials. NO real leaked value appears.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="$HERE/credential_scan_lib.sh"
if [ ! -f "$LIB" ]; then
    echo "FATAL: library under test not found: $LIB" >&2
    exit 2
fi
# §11.4.201(4) / §11.4.1 PARSE guard — an UNLOADABLE library must exit 2
# (harness-broken), NEVER 1 (a real fixture FAIL). A syntactically-broken
# library that sources anyway carries on and reports every golden-bad as
# MISSED — a §11.4.1 FAIL-bluff (the 2026-07-17 apostrophe-in-awk incident).
# bash -n BEFORE sourcing.
if ! bash -n "$LIB" 2>/dev/null; then
    echo "FATAL: library under test does not parse (bash -n): $LIB" >&2
    exit 2
fi
# shellcheck source=/dev/null
. "$LIB"
# §11.4.201(4) LOAD guard — both detectors MUST be non-empty after sourcing
# (a library that parsed but defined no HELIX_CRED_VALUE_PATTERN /
# HELIX_CRED_ADJACENCY_AWK is harness-broken, not a fixture regression).
# exit 2, NEVER 1.
if [ -z "${HELIX_CRED_VALUE_PATTERN:-}" ] || [ -z "${HELIX_CRED_ADJACENCY_AWK:-}" ]; then
    echo "FATAL: credential detectors empty after sourcing (HELIX_CRED_VALUE_PATTERN / HELIX_CRED_ADJACENCY_AWK): $LIB" >&2
    exit 2
fi

pass=0
fail=0
ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/credscan_lib_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# assert_clean <name> <path> : helix_cred_scan_file MUST return 1 (clean).
assert_clean() {
    if helix_cred_scan_file "$2"; then
        bad "$1 — FALSE POSITIVE (reported credential; expected clean)"
    else
        ok  "$1 — clean (no false positive)"
    fi
}
# assert_caught <name> <path> : helix_cred_scan_file MUST return 0 (found).
assert_caught() {
    if helix_cred_scan_file "$2"; then
        ok  "$1 — caught (real leak detected)"
    else
        bad "$1 — MISSED (expected credential caught; gate WEAKENED)"
    fi
}

echo "== credential_scan_lib.sh — self-validating golden fixtures =="
echo "   (throwaway dir: $WORK)"
echo ""

# --- GOLDEN-GOOD ------------------------------------------------------------
cat > "$WORK/good_a_git_remote.txt" <<'EOF'
# Git remotes
- github / upstream: git@github.com:ATMOSphere1234321/ATMOSphere-Android-15.git
- origin: git@github.com:vasic-digital/Android-15-AOSP.git
EOF
assert_clean "(a) git SSH remote URLs" "$WORK/good_a_git_remote.txt"

cat > "$WORK/good_b_systemd.txt" <<'EOF'
# Host-session safety incident
The developer's user@1000.service was again SIGKILLed (status=9/KILL) while a
Phase 17 AOSP rebuild was in flight. No kernel OOM kill in dmesg for this boot.
EOF
assert_clean "(b) systemd user@N.service forensic note" "$WORK/good_b_systemd.txt"

cat > "$WORK/good_c_java_ref.txt" <<'EOF'
07-16 10:30:00.123  MediaFocusControl: clientId=android.media.AudioManager@android.media.AudioManager$$ExternalSyntheticLambda13@a1b2c3 requested focus
EOF
assert_clean "(c) Android object reference @pkg.CamelCaseClass" "$WORK/good_c_java_ref.txt"

# (d) BINARY .db blob: embed an email adjacent to a password-shaped token AND
# real NUL bytes so the file is genuinely binary. If detector-2 ran on this as
# TEXT it WOULD fire — the .db binary-skip is what makes it clean, so this
# fixture proves the skip is load-bearing (§11.4.201).
printf 'SQLite format 3\000\000admin@example.com S3cretDbToken99\000\000rows\000' > "$WORK/good_d_binary.db"
assert_clean "(d) binary .db with embedded email+token (binary-skip)" "$WORK/good_d_binary.db"

# (e) §11.4.201 carrier-strip #5: a Markdown-emphasized plain WORD adjacent to an
# email in bug-report prose is emphasis, not a password. Forensic FP:
# docs/Issues.md:3794 "abkmusic64@gmail.com ... **BROWSERS**".
cat > "$WORK/good_e_markdown_word.txt" <<'EOF'
- **Bug 12** (`abkmusic64@gmail.com`) now logs in on **ALL BROWSERS** but *fails* on `code`.
EOF
assert_clean "(e) markdown-emphasized word near email (**BROWSERS**)" "$WORK/good_e_markdown_word.txt"

# (f) §11.4.201 carrier-strip #6: a long PROSE line where an email co-occurs with
# DISTANT technical tokens (config keys, code identifiers, product names) is not a
# credential — the password of a real email:pass leak is IMMEDIATELY adjacent.
# Forensic FP: docs/Issues.md:3794 attestation discussion.
cat > "$WORK/good_f_distant_tokens.txt" <<'EOF'
Tester abkmusic64@gmail.com now logs in on all browsers but still fails on D3; RK3588 verified_boot_state=UNVERIFIED device_locked=false Widevine-L3 Pixel-8 persist.atmosphere.attest.device_keybox=true remains the blocker.
EOF
assert_clean "(f) email + distant technical tokens (proximity window)" "$WORK/good_f_distant_tokens.txt"

# (g) detector-1 carrier-strip: a recognised secret KEYWORD followed by a
# separator whose VALUE is an XML/localization PLACEHOLDER (starts with '<' or
# '%') is a UI label, not a secret. Forensic FP: AOSP Settings
# "Wi-Fi password: <xliff:g id="password">%1$s</xliff:g>".
cat > "$WORK/good_g_xliff_placeholder.xml" <<'EOF'
    <string name="wifi_dpp_wifi_password">Wi-Fi password: <xliff:g id="password" example="my password">%1$s</xliff:g></string>
EOF
assert_clean "(g) keyword: <xliff placeholder> (UI label, not a secret)" "$WORK/good_g_xliff_placeholder.xml"

# (h) detector-1 carrier-strip: a recognised secret KEYWORD followed by a
# separator whose VALUE is a shell/jq VARIABLE REFERENCE (starts with '$') is a
# reference, never a literal secret. Forensic FP: docs prose quoting
# "password=$SMB_PASS" / "api_key:$ENV.CMA_TOK".
cat > "$WORK/good_h_var_ref.txt" <<'EOF'
SMB mount uses password=$SMB_PASS and the jq writer emits api_key:$ENV.CMA_TOK for the provider.
EOF
assert_clean "(h) keyword=\$VAR / keyword:\$ENV.x (variable reference, not a secret)" "$WORK/good_h_var_ref.txt"

echo ""
# --- GOLDEN-BAD -------------------------------------------------------------
cat > "$WORK/bad_1_email_pw.txt" <<'EOF'
Service login for the AVR test account:
  user@company.com : S3cretPass99
EOF
assert_caught "(1) email+password adjacency (lowercase TLD)" "$WORK/bad_1_email_pw.txt"

cat > "$WORK/bad_2_akia.txt" <<'EOF'
export api_key=AKIA1234567890ABCDEF
EOF
assert_caught "(2) AKIA + api_key= assignment" "$WORK/bad_2_akia.txt"

cat > "$WORK/bad_3_password.txt" <<'EOF'
db:
  password: hunter2hunter2
EOF
assert_caught "(3) keyword-anchored password: assignment" "$WORK/bad_3_password.txt"

cat > "$WORK/bad_4_privkey.txt" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB
-----END OPENSSH PRIVATE KEY-----
EOF
assert_caught "(4) OPENSSH PRIVATE KEY marker" "$WORK/bad_4_privkey.txt"

# Build the Google-API-key fixture: AIza + exactly 35 chars (39 total) so it
# matches AIza[0-9A-Za-z_-]{35}. Hand-typed literals risk an off-by-one that
# would silently WEAKEN the gate, so generate the 35-char run deterministically.
{ printf 'gmaps_key=AIza'; printf 'x%.0s' {1..35}; printf '\n'; } > "$WORK/bad_5_aiza.txt"
assert_caught "(5) AIza Google-API-key format (39 chars)" "$WORK/bad_5_aiza.txt"

# (6) proximity-window MUST NOT over-narrow: a real password IMMEDIATELY adjacent
# to an email (within the §11.4.201 carrier-strip #6 window) MUST still be caught.
# This pins that carrier-strip #6 tightened the scan WITHOUT weakening real-leak
# detection — the paired §1.1 mutation (widening the window to scan whole prose
# lines re-introduces the FP; narrowing it below the compact leak form fails THIS).
cat > "$WORK/bad_6_adjacent_pw.txt" <<'EOF'
AVR account: tester@company.com / Tr0ub4dor3Special!
EOF
assert_caught "(6) real password adjacent to email (window not over-narrow)" "$WORK/bad_6_adjacent_pw.txt"

echo ""
echo "== RESULT: ${pass} passed, ${fail} failed =="
[ "$fail" -eq 0 ]
