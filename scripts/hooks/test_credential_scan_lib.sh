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
#       (proves the .db binary-skip prevents the detector-2 false positive),
#   (i) a `PASSWORD=CHANGE_ME` / `api_key=PLACEHOLDER` config-template line
#       (carrier-strip #8a placeholder-value allowlist),
#   (j) a `SECRET=…must_not_leak…` test-fixture sentinel (carrier-strip #8a),
#   (k) a `data:image/png;base64,<blob>` whose base64 image bytes randomly
#       contain an AKIA-shaped run (carrier-strip #8b base64-image data-URI).
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
Tester abkmusic64@gmail.com now logs in on all browsers but still fails on D3; MYSOC1 verified_boot_state=UNVERIFIED device_locked=false DRM-L3 Handset-8 persist.myvendor.attest.device_keybox=true remains the blocker.
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

# (i) §11.4.201 carrier-strip #8a: a recognised secret KEYWORD whose VALUE is a
# config-template placeholder (CHANGE_ME / PLACEHOLDER) is a template token, not a
# secret. Origin carrier: CONFIG_TEMPLATES.md "PASSWORD=CHANGE_ME".
cat > "$WORK/good_i_placeholder.env" <<'EOF'
# config template — fill these in per deployment
PASSWORD=CHANGE_ME
JWT_SECRET=CHANGE_ME
api_key=PLACEHOLDER
DB_PASSWORD=changeme
EOF
assert_clean "(i) keyword=CHANGE_ME / PLACEHOLDER (config-template placeholder)" "$WORK/good_i_placeholder.env"

# (j) §11.4.201 carrier-strip #8a: a test-fixture marker value (…must_not_leak…) is
# never a real secret. Origin carrier: test_helix_code_phase1_unit.sh "must_not_leak".
cat > "$WORK/good_j_must_not_leak.txt" <<'EOF'
# unit-test fixtures — synthetic sentinel values, never real credentials
SECRET=supersecret_must_not_leak
password: must_not_leak_dummy_value
EOF
assert_clean "(j) keyword=...must_not_leak... (test-fixture sentinel marker)" "$WORK/good_j_must_not_leak.txt"

# (k) §11.4.201 carrier-strip #8b: a base64 image data-URI blob RANDOMLY contains a
# token-shaped substring (here an AKIA[0-9A-Z]{16} run embedded in the base64 image
# bytes). Without the data-URI strip detector-1 WOULD flag it — the strip is what
# makes it clean, so this fixture proves the strip is load-bearing (§11.4.201).
# Origin carrier: DEEP_HELIXOTA base64 avatar/image data-URI. The blob is built
# deterministically so the embedded AKIA token is exactly the right shape.
{ printf 'avatar_data: data:image/png;base64,'
  printf 'iVBORw0KGgoAAAANSUhEUg'      # ordinary base64 image-header bytes
  printf 'AKIA0123456789ABCDEF'        # AKIA + 16 [0-9A-Z] chars, embedded in blob
  printf 'moreImageBytesHere+/=='      # trailing base64 image bytes
  printf '\n'
} > "$WORK/good_k_base64_image.txt"
assert_clean "(k) data:image/png;base64,<blob with token-shaped substring> (image data)" "$WORK/good_k_base64_image.txt"

# (m) §11.4.201 carrier-strip #9: the `sk-` OpenAI-key sub-pattern is only TWO
# letters + a hyphen, so WITHOUT a left token boundary it matches the TAIL of any
# identifier ending in "sk" that is followed by '-' and 20+ alphanumerics. Forensic
# FP: an Android `pm path` capture line
# ".../com.example.mediakiosk-<install-token>==/base.apk" — the "sk" is the tail
# of the package name "mediakio[sk]" and the base64url install-token supplies the
# 20+ chars. Any package ending in "…sk" (kiosk, disk, task, desk) trips it. The
# left-boundary `(^|[^0-9A-Za-z])` is what makes this clean, so this fixture proves
# the boundary is load-bearing (§11.4.201(7)(a) carrier-vs-thing).
cat > "$WORK/good_m_pkgpath_sk.txt" <<'EOF'
package:/data/app/~~U4OsJn3zzcMyh-sRkefkGQ==/com.example.mediakiosk-qz5gs3AbCdEfGhIjKlMnOp==/base.apk
package:/data/app/~~U4OsJn3zzcMyh-sRkefkGQ==/com.example.clouddisk-Zx9WvUt7SrQpOnMlKjIh==/split_config.en.apk
EOF
assert_clean "(m) Android pm-path '…mediakiosk-<token>' (sk- left-boundary carrier)" "$WORK/good_m_pkgpath_sk.txt"

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

# (l) §11.4.201(1) MID-LINE placeholder (the raw-grep-bypass forensic, 2026-07-28):
# a recognised secret KEYWORD=PLACEHOLDER appearing MID-LINE inside a doc / JSONL
# registry / tracker-item that QUOTES it as the example (a self-referential
# carrier — the credscan-fix tracker item quotes `PASSWORD=CHANGE_ME`). detector-1
# uses `grep -Eio`, so the EXTRACTED MATCH is `PASSWORD=CHANGE_ME` (not the whole
# line) and #8a strips it — MUST be CLEAN. The prior hook/commit_all raw
# `grep -Eiq value_pattern` bypassed #8a and false-positive-REFUSED this; the fix
# routes both through helix_cred_detector1_real_hit_stream.
cat > "$WORK/good_l_midline_placeholder.txt" <<'EOF'
{"ts":"2026-07-27T21:50:46Z","event":"complete","label":"(T1/main - claude4) credscan false-positive on legit PASSWORD=CHANGE_ME example"}
The task quotes the placeholder api_key=PLACEHOLDER in prose to describe the fix.
EOF
assert_clean "(l) MID-LINE keyword=PLACEHOLDER in doc/registry prose (self-referential carrier)" "$WORK/good_l_midline_placeholder.txt"

echo ""
# (7) FALSE-NEGATIVE GUARD (§11.4.201(2)): a line carrying BOTH a real secret AND a
# placeholder MUST still be CAUGHT — the mid-line #8a strip removes ONLY the
# placeholder match; the real-secret match survives. If this ever MISSES, the fix
# WEAKENED the gate (a release blocker). This is the paired guard for (l).
cat > "$WORK/bad_7_real_plus_placeholder.txt" <<'EOF'
db: password: hunter2hunter2realleak  note: fill PASSWORD=CHANGE_ME in prod
EOF
assert_caught "(7) real secret + placeholder on ONE line (mid-line strip must not leak the real one)" "$WORK/bad_7_real_plus_placeholder.txt"

# (8) FALSE-NEGATIVE GUARD for carrier-strip #9 (§11.4.201(2)): a REAL `sk-` key
# ALWAYS stands at a token boundary — the character immediately before `sk-` is
# NON-ALPHANUMERIC (or the key is at line start). The shipped left-boundary is the
# CLASS `(^|[^0-9A-Za-z])`, so this guard pins the CLASS BY CONSTRUCTION rather
# than by a hand-picked sample: the fixture set is PROGRAMMATICALLY ENUMERATED
# over EVERY printable-ASCII non-alphanumeric byte (0x20..0x7E minus [0-9A-Za-z]
# = space + the 32 punctuation/symbol characters), plus line-start, plus a literal
# TAB, plus a control character and a high-byte (UTF-8 «) form. A hand-typed list
# could only ever be a SAMPLE, and a mutation narrowing the shipped class to
# exactly the sampled characters would survive it — the precise regression this
# guard exists to catch (§11.4.115(F): the fixtures must catch the boundary's own
# negation, not merely agree with it). Because the ASCII sweep is generated, ANY
# narrowing of the printable-ASCII class now fails BY CONSTRUCTION — the reviewer's
# M-R1 `(^|[ ="_])`, M-F1 `(^|[<TAB> ="'_:/,(.;>-])` (the exact prior fixture list)
# and M-F2 `(^|[[:punct:][:space:]])` mutations ALL make this suite FAIL.
# HONEST BOUNDARY (§11.4.6): the sweep is exhaustive over PRINTABLE ASCII only.
# The non-printable + high-byte domain is NOT exhaustively enumerated (it is
# unbounded and locale-dependent); it is covered by the two REPRESENTATIVE forms
# below — a C0 control byte (neither [:punct:] nor [:space:] in ANY locale, so it
# is the universal M-F2 killer) and a UTF-8 high-byte guillemet (which additionally
# escapes `[[:punct:]]` under LC_ALL=C). Every form MUST still be CAUGHT. If any
# MISSES, the left-boundary WEAKENED the gate (a release blocker). This is the
# paired guard for (m); a fix that makes (m) clean by dropping the `sk-`
# alternative entirely dies HERE.
_SK_KEY='sk-qz5gs3AbCdEfGhIjKlMnOp'
: > "$WORK/bad_8_sk_boundary.txt"
# form 1 — line start (the `^` branch of the shipped alternation).
printf '%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# forms 2..34 — EVERY printable-ASCII non-alphanumeric byte, generated. The
# alphanumeric skip-set is spelled out CHARACTER BY CHARACTER (never the ranges
# `[0-9A-Za-z]`) because a bracket RANGE in a case-glob is collation-dependent in
# a UTF-8 locale and could silently skip a punctuation byte — a locale-dependent
# hole in the very sweep that proves the class (§11.4.201(7)(c): the path is part
# of the instrument).
_sk_c=32
while [ "$_sk_c" -le 126 ]; do
    _sk_ch=$(printf "\\$(printf '%03o' "$_sk_c")")
    case "$_sk_ch" in
        [0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz])
            _sk_c=$((_sk_c + 1)); continue ;;
    esac
    printf '%s%s\n' "$_sk_ch" "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
    _sk_c=$((_sk_c + 1))
done
# form 35 — literal TAB, emitted via printf (NEVER a heredoc) so the separator
# stays a REAL tab: an editor that re-indents a fixture file silently converts an
# in-heredoc tab into spaces, degrading this form into the already-covered space
# form — a silent class-coverage loss the suite could not see (§11.4.201(6)).
printf '\t%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# form 36 — C0 control byte (0x01). Non-printable, so outside the generated sweep;
# it is neither [:punct:] nor [:space:] in ANY locale, making it the form that
# kills a `[[:punct:][:space:]]` narrowing everywhere.
printf '\001%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
# form 37 — high-byte UTF-8 guillemet « (0xC2 0xAB). Outside the ASCII sweep; under
# LC_ALL=C its lead byte is not [:punct:] either, so it kills the same narrowing
# in the C locale even where the UTF-8 locale would classify « as punctuation.
printf '\302\253%s\n' "$_SK_KEY" >> "$WORK/bad_8_sk_boundary.txt"
assert_caught "(8) real sk- key at token boundary, non-alphanumeric CLASS spread (boundary must not weaken)" "$WORK/bad_8_sk_boundary.txt"
# Per-form guard: assert_caught passes if ANY line hits, so pin EACH form
# individually — a boundary that only catches 1 of N must not read as GREEN.
# (8b) pins the FILE-level contract (helix_cred_scan_file = detector-1 OR
# detector-2); (8c) pins the SAME forms at the DETECTOR-1 layer, where the
# left-boundary actually lives — without (8c) a future broadening of detector-2
# (email-adjacency) could start catching these lines for an unrelated reason and
# silently mask a detector-1 boundary regression (§11.4.115(F) unvalidated
# instrumentation: the assertion must remain load-bearing on the thing it names).
_sk_form_n=0; _sk_form_miss=0; _sk_d1_miss=0
while IFS= read -r _sk_line; do
    _sk_form_n=$((_sk_form_n + 1))
    printf '%s\n' "$_sk_line" > "$WORK/bad_8_form_$_sk_form_n.txt"
    helix_cred_scan_file "$WORK/bad_8_form_$_sk_form_n.txt" || _sk_form_miss=$((_sk_form_miss + 1))
    printf '%s\n' "$_sk_line" | helix_cred_detector1_real_hit_stream || _sk_d1_miss=$((_sk_d1_miss + 1))
done < "$WORK/bad_8_sk_boundary.txt"
# (8a) GENERATOR SELF-CHECK (§11.4.201(6) false-null guard). (8b)/(8c) below
# assert "zero MISSES", which a generator emitting ZERO forms would satisfy
# VACUOUSLY — a blind instrument returning the same quiet zero as a healthy one.
# Pin the exact expected form count so a silently-empty or silently-truncated
# sweep FAILS here instead of passing everything downstream:
#   1 line-start
# + 33 printable-ASCII non-alphanumeric (0x20..0x7E is 95 chars, minus the 62
#      alphanumerics = 33: the space plus the 32 punctuation/symbol characters)
# + 1 TAB + 1 C0 control byte + 1 high-byte UTF-8 guillemet
# = 37 forms.
_sk_form_expected=37
if [ "$_sk_form_n" -eq "$_sk_form_expected" ]; then
    ok  "(8a) boundary-form generator emitted all $_sk_form_expected forms (sweep not empty/truncated)"
else
    bad "(8a) boundary-form generator emitted $_sk_form_n forms, expected $_sk_form_expected (sweep BROKEN — (8b)/(8c) below would pass vacuously)"
fi
if [ "$_sk_form_miss" -eq 0 ]; then
    ok  "(8b) each of the $_sk_form_n real sk- boundary forms caught individually (file scanner)"
else
    bad "(8b) $_sk_form_miss/$_sk_form_n real sk- boundary forms MISSED (gate WEAKENED)"
fi
if [ "$_sk_d1_miss" -eq 0 ]; then
    ok  "(8c) each of the $_sk_form_n real sk- boundary forms caught by DETECTOR-1 (left-boundary class)"
else
    bad "(8c) $_sk_d1_miss/$_sk_form_n real sk- boundary forms MISSED by detector-1 (left-boundary WEAKENED)"
fi

echo ""
# --- STREAM DETECTOR CONTRACT (the function the hook + commit_all call directly) --
# helix_cred_detector1_real_hit_stream reads STDIN. Exit 1 = clean, 0 = hit. The
# file scanner delegates to it, but the hook/commit_all call it on a `git show`
# stream — pin its contract directly so a regression in either path is caught.
if printf 'note PASSWORD=CHANGE_ME in a captured prompt\n' | helix_cred_detector1_real_hit_stream; then
    bad "(stream-good) mid-line PASSWORD=CHANGE_ME — FALSE POSITIVE (stream reported credential; expected clean)"
else
    ok "(stream-good) mid-line PASSWORD=CHANGE_ME stream — clean"
fi
if printf 'password: hunter2hunter2realleak\n' | helix_cred_detector1_real_hit_stream; then
    ok "(stream-bad) real secret stream — caught"
else
    bad "(stream-bad) real secret stream — MISSED (stream detector WEAKENED)"
fi
# (stream-bad-B1 §11.4.115/§11.4.201(2), Fable-review 2026-07-28): a LARGE dump of
# real secrets (>~64 KB of matches) under `set -o pipefail` — the pre-fix verdict
# `printf … | grep -Eiv CARRIER | grep -q '[^space]'` short-circuited at the first
# survivor, SIGPIPE-killed the upstream grep, and the pipeline exited 141 → wrongly
# CLEAN (a credential DUMP is the highest-value leak). BOTH new consumers run
# pipefail (pre-commit:15 `set -uo pipefail`, commit_all.sh:98 `set -euo pipefail`),
# so reproduce under pipefail exactly as those seams do. The fix captures survivors
# into a variable (no pipe short-circuit) + a case-glob non-whitespace test.
if ( set -o pipefail
     awk 'BEGIN{for (i = 0; i < 60000; i++) print "password: hunter2hunter2realleak"}' \
       | helix_cred_detector1_real_hit_stream ); then
    ok "(stream-bad-B1) 60k-line real-secret dump under pipefail — caught"
else
    bad "(stream-bad-B1) 60k-line dump under pipefail — MISSED (pipefail SIGPIPE false negative)"
fi
# (stream-bad-B2 §11.4.115/§11.4.201(2), Fable-review 2026-07-28): a BINARY stream
# (NUL bytes) carrying a plaintext secret — the pre-fix `grep -Eio` (no `-a`) on
# binary emits "binary file matches" to STDERR with EMPTY stdout → extracted
# nothing → wrongly CLEAN at the pre-commit seam (`git show | stream_fn`, NULs
# intact), where the old raw `grep -Eiq` had caught it. The fix adds `-a` to the
# extraction so a .db/.so/.apk with an embedded plaintext secret is still caught.
if printf 'BIN\000\001\002 password: hunter2hunter2realsecret \000\377 more\n' \
     | helix_cred_detector1_real_hit_stream; then
    ok "(stream-bad-B2) binary stream with plaintext secret — caught"
else
    bad "(stream-bad-B2) binary stream with plaintext secret — MISSED (binary -o false negative)"
fi

echo ""
echo "== RESULT: ${pass} passed, ${fail} failed =="
[ "$fail" -eq 0 ]
