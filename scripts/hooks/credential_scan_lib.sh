# shellcheck shell=bash
# =============================================================================
# credential_scan_lib.sh — project-AGNOSTIC shared credential-leak scan library
# (§11.4.10 credentials-handling + §11.4.75 mechanical enforcement Layer 1 +
#  §11.4.201 guards-assert-the-real-condition — carrier-strips prevent the
#  FALSE-POSITIVE refusal that is itself a FAIL-bluff).
#
# Purpose:
#   Provides the two credential detectors + the binary-skip helper + a
#   convenience whole-file scanner, so any consuming project's pre-commit hook
#   can INHERIT the detectors BY REFERENCE (§11.4.28 / §11.4.177) instead of
#   copying them. Detector-1 = keyword-anchored / known-token-format value
#   patterns WITH two §11.4.201 carrier-strips — #7 (value-starts-with a
#   $ / < / % / { sigil, baked into the pattern) and #8 (placeholder-value
#   allowlist + base64-image data-URI, applied by _helix_cred_detector1_real_hit)
#   so a `PASSWORD=CHANGE_ME` template line, a `SECRET=…must_not_leak` fixture
#   marker, and a `data:image/png;base64,…` blob are NOT flagged while a genuine
#   `password: hunter2hunter2` / `AKIA…` leak still is. Detector-2 =
#   email+password-shape adjacency heuristic WITH four
#   §11.4.201 carrier-strips (git SSH remotes, systemd `@N.service` units,
#   Java/Android object references `@pkg.CamelCaseClass`, Java `$$`-synthetic
#   tokens) that assert the REAL condition — a genuine `user@company.com : <pw>`
#   leak is UNTOUCHED, so both a false-positive refusal AND a false-negative
#   pass are mechanically prevented.
#
#   ZERO project literals: no credential SoT path, no project / vendor name,
#   no device serial, no region endpoint. The consumer supplies the allowlist
#   filter + the REFUSED message; this library supplies only the detectors.
#
# Usage:
#   . "$REPO_ROOT/constitution/scripts/hooks/credential_scan_lib.sh"
#   # Then either use the exported patterns directly against STAGED content:
#   if git show ":$f" | grep -Eiq "$HELIX_CRED_VALUE_PATTERN"; then hit=1; fi
#   if ! helix_cred_is_binary_skip "$f"; then
#     if awk "$HELIX_CRED_ADJACENCY_AWK" < <(git show ":$f"); then hit=1; fi
#   fi
#   # ...or scan a file on disk end-to-end:
#   helix_cred_scan_file "$path" && echo "credential found" || echo "clean"
#
# Inputs:
#   Sourced into a bash shell. helix_cred_is_binary_skip / helix_cred_scan_file
#   take a single path argument.
#
# Outputs / return codes:
#   HELIX_CRED_VALUE_PATTERN     — ERE for detector-1 (grep -Ei).
#   HELIX_CRED_ADJACENCY_AWK     — awk program for detector-2. Exit 0 = an
#                                  offending line found, exit 1 = clean.
#   helix_cred_is_binary_skip P  — returns 0 if P's extension is a binary blob
#                                  that MUST NOT be text-scanned by detector-2,
#                                  else 1.
#   helix_cred_scan_file P        — returns 0 if a credential is found, 1 if
#                                  clean. Runs detector-1 then (if P is not a
#                                  binary-skip extension) detector-2.
#
# Side-effects:
#   None. Sourcing sets read-only-by-convention pattern variables + defines
#   two functions. It does NOT change shell options (safe to source from any
#   hook regardless of its `set` flags).
#
# Dependencies:
#   bash, grep (ERE, -i, -q), awk.
#
# Cross-references:
#   Self-validating fixtures:  constitution/scripts/hooks/test_credential_scan_lib.sh
#   Reference consumer:        <project>/scripts/git_hooks/pre-commit
#   Constitution:              §11.4.10 / §11.4.10.A / §11.4.75 / §11.4.201 /
#                              §11.4.28 / §11.4.177 / §11.4.107(10) / §1.1.
# =============================================================================

# --- Detector 1: keyword-anchored value / known-token-format patterns --------
# Conservative set covering common API-token / key / secret / password
# assignment forms. Used with `grep -Ei`.
HELIX_CRED_VALUE_PATTERN='(AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|gho_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk-[0-9A-Za-z]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:]"'"'"'$<%{][^[:space:]"'"'"']{7,})'

# --- Detector 1 carrier-strip #8: placeholder-value + base64-image data-URI ---
# §11.4.201 carrier-strip #8a (placeholder-value allowlist). A recognised secret
# KEYWORD whose VALUE is a config-template placeholder / test-fixture marker
# (CHANGE_ME / CHANGEME / PLACEHOLDER / EXAMPLE / DUMMY / REDACTED / TODO / TBD /
# FIXME / xxx+ / your[_-]... / ...must_not_leak...) is a template or fixture
# token, NEVER a real secret. (Values that start with $ / < / % / { are ALREADY
# excluded by carrier-strip #7 in HELIX_CRED_VALUE_PATTERN, so <xliff…> / $VAR /
# %1$s never reach detector-1 — this strip covers the remaining literal
# placeholders that DO start with a normal character.) A real secret is NEVER a
# literal placeholder token, so the strip is TIGHT — it cannot weaken real-secret
# detection: a value that is anything OTHER than a whole placeholder token (e.g.
# hunter2hunter2, AKIA…, xxxsecret1) survives and is still flagged. Applied by
# _helix_cred_detector1_real_hit, which drops any detector-1 match whose whole
# "keyword<sep>value" reads as keyword + placeholder-value. Proven by golden-good
# scenarios (i)/(j) + every golden-bad in test_credential_scan_lib.sh (§11.4.107(10)).
HELIX_CRED_PLACEHOLDER_CARRIER='^(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*["'"'"']?(change_?me|placeholder|example|dummy|redacted|todo|tbd|fixme|xxx+|your[_-][a-z0-9._-]*|[a-z0-9._-]*must_not_leak[a-z0-9._-]*)["'"'"']?$'

# §11.4.201 carrier-strip #8b (base64-image data-URI). A data:image/…;base64,<blob>
# embeds a long base64 run of image bytes that can RANDOMLY contain a token-shaped
# substring (AKIA… / AIza… / sk-…). The blob is image data, never a credential.
# The whole data-URI region is BLANKED before detector-1 runs (mirrors the detector-2
# gsub strips), so an incidental token-shape inside the blob is not flagged while a
# real token OUTSIDE any data-URI on the same line is untouched. Covers base64
# (+ / =) and base64url (- _) alphabets. Proven by golden-good (k).
HELIX_CRED_BASE64_IMAGE_CARRIER='data:image/[^;]*;base64,[A-Za-z0-9+/=_-]+'

# --- Detector 2: email-adjacency plaintext-credential heuristic --------------
# The keyword-anchored detector-1 only sees a recognised secret KEYWORD followed
# by a value; it CANNOT see a password committed as a bare token adjacent to an
# email/username (e.g. "email@x.com / <password>" or "email@x.com:<password>")
# because there the "key" is an email, not a keyword. This awk detector closes
# that class GENERICALLY: an email address on a line, followed (after separators)
# by a password-SHAPED token — length 6..128, contains a letter AND (a digit OR a
# strong special), NOT itself an email/phone/filename/redaction-placeholder.
# No real secret value is embedded; the shape heuristic is validated against a
# golden-good / golden-bad fixture pair in test_credential_scan_lib.sh (§11.4.107(10)).
# Exit 0 = an offending line found, exit 1 = clean.
HELIX_CRED_ADJACENCY_AWK='
{
  line = $0
  # §11.4.201 carrier-strip #1: a git SSH remote URL (form git@<host>:<org>/<repo>[.git])
  # is NOT an email+password adjacency — its "email" is the conventional git@<host>
  # SSH user and its "password-shaped" token is an org/repo name that may contain
  # digits (real forensic false-positive: a repo remote list in a doc). Blank the
  # whole remote-URL substring BEFORE the email match so the heuristic asserts the
  # REAL condition. The org/repo "/" is REQUIRED, so a genuine git@<host>:<secret>
  # with no slash is still scanned and detector-1 (value-pattern) is untouched.
  # Proven by golden-good scenario (a) in test_credential_scan_lib.sh.
  gsub("git@[A-Za-z0-9.-]+:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+", " ", line)
  # §11.4.201 carrier-strip #2: a systemd user-instance unit name (form
  # user@<uid>.service / <name>@<N>.service) is email-SHAPED (local@digits.service,
  # ".service" reads as a TLD) but is NOT an email — it appears verbatim in every
  # §12 host-session-safety forensic note ("user@1000.service was SIGKILLed
  # (status=9/KILL)"), where the adjacent "status=9" (letter+digit+"=") looks like
  # a password to the heuristic. A systemd unit is never a credential carrier, so
  # blank the whole unit token BEFORE the email match (mirrors the git@ strip).
  # A real email lands on a real TLD, so genuine "user@company.com : <pw>" is
  # untouched. Proven by golden-good scenario (b) in test_credential_scan_lib.sh.
  gsub("[A-Za-z0-9._%+-]+@[0-9]+\\.service", " ", line)
  # §11.4.201 carrier-strip #3: a Java/Android object reference (form
  # <pkg.Class>@<pkg>.<CamelCaseClass>[$$SyntheticLambda<N>][@<hex-hashcode>])
  # is email-SHAPED — its "@<pkg>.Class" reads as local@domain.TLD where the
  # "TLD" is a CamelCase ClassName (AudioManager, ExternalSyntheticLambda). These
  # appear verbatim in every captured logcat (MediaFocusControl clientId=...),
  # in agent task-notification quotes, and in a request-history log (§11.4.208).
  # The distinguishing feature vs a real email is the final dotted component:
  # a Java ClassName is CamelCase ("[A-Z][a-z]..."), a real email TLD is lowercase
  # (.com) or all-caps (.COM) — neither matches [A-Z][a-z]. Blank the whole ref
  # BEFORE the email match so the heuristic asserts the REAL condition. A genuine
  # "user@company.com : <pw>" (lowercase TLD) is UNTOUCHED. Proven by golden-good
  # scenario (c) + golden-bad (email+password) in test_credential_scan_lib.sh.
  gsub("[A-Za-z0-9._%+$-]+@[A-Za-z0-9._$-]*\\.[A-Z][a-z][A-Za-z0-9_$]*", " ", line)
  # §11.4.201 carrier-strip #4: any Java synthetic token ("...$$ExternalSyntheticLambda13")
  # is never a credential — blank $$-bearing tokens outright.
  gsub("[A-Za-z0-9_$.]*\\$\\$[A-Za-z0-9_$.]*", " ", line)
  if (match(line, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/)) {
    rest = substr(line, RSTART + RLENGTH)
    # §11.4.201 carrier-strip #6: an email-adjacency credential (email:pass,
    # email / pass, email  pass) has the password IMMEDIATELY adjacent to the
    # email — every documented leak form and every golden-bad fixture places the
    # password within ~25 chars. A long PROSE line where an email co-occurs with
    # DISTANT technical tokens (config keys, code identifiers, product names in a
    # bug report) is NOT a credential. Restrict the scan to a compact adjacency
    # window after the email; a genuine leaked password fits well within it
    # (proven by the golden-bad fixtures), while the docs/Issues.md line 3794
    # attestation discussion — email at col 169 then RK3588 / Play-Integrity /
    # verified_boot_state config tokens far beyond it — falls outside. Detector-1
    # (keyword-value) is
    # untouched and still catches a widely-separated keyword=value leak.
    rest = substr(rest, 1, 48)
    n = split(rest, toks, "[[:space:]/:|,;()]+")
    for (i = 1; i <= n; i++) {
      t = toks[i]
      if (length(t) < 6 || length(t) > 128) continue
      if (tolower(t) ~ /redacted|changeme|placeholder|yourpassword|your-password|your_password|xxxxxxxx|dummy/) continue
      if (t ~ /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/) continue
      if (t ~ /^[-+0-9(). _]+$/) continue
      if (t ~ /\.(md|html|pdf|docx|sh|txt|json|ya?ml|xml|png|jpe?g|gif|svg|log|go|py|kt|java|cpp|ts|js|tsv|csv|db|c|h)$/) continue
      # §11.4.201 carrier-strip #5: a Markdown-emphasized plain WORD (**BROWSERS**,
      # *note*, `code`) is prose emphasis in a doc, NOT a password. The ** / * / `
      # emphasis runs make the "hasSpec" test below read an ordinary word as
      # password-shaped. Strip leading/trailing * and backtick runs; if what
      # remains is a pure ASCII word (all letters, NO digit, NO non-markdown
      # special), it is not password-shaped. A real password near an email carries
      # a digit or a non-markdown special (Passw0rd!, **MyP@ss1**) and SURVIVES this
      # strip (its de-emphasized form is not pure-alpha), so detector-2 still
      # refuses it — detector-1 is untouched. Forensic FP: docs/Issues.md:3794
      # bug-report line "abkmusic64@gmail.com ... **BROWSERS**". Proven by
      # golden-good scenario (e) + the (real-password-near-email) golden-bad in
      # test_credential_scan_lib.sh (§11.4.107(10)).
      tclean = t
      gsub(/^[*`]+/, "", tclean); gsub(/[*`]+$/, "", tclean)
      if (tclean ~ /^[A-Za-z]+$/) continue
      hasLetter = (t ~ /[A-Za-z]/)
      hasDigit  = (t ~ /[0-9]/)
      hasSpec   = (t ~ /[!#$%^&*()=+_]/)
      if (hasLetter && (hasDigit || hasSpec)) { found = 1; exit }
    }
  }
}
END { exit(found ? 0 : 1) }
'

# --- Binary-skip helper ------------------------------------------------------
# Returns 0 (skip detector-2) if the path extension is a binary blob that MUST
# NOT be text-scanned by the adjacency detector (they do not tokenise as text;
# DOCX/PDF are compressed anyway). Includes SQLite DB extensions (db/sqlite/
# sqlite3/db-wal/db-shm) — feeding a binary .db to awk as TEXT is a §11.4.201
# false-positive vector (random bytes adjacent to an embedded email/username
# match the password-shape heuristic). Detector-1 (grep) still runs on these;
# only the adjacency detector is skipped.
helix_cred_is_binary_skip() {
  case "$1" in
    *.pdf|*.docx|*.png|*.jpg|*.jpeg|*.gif|*.ico|*.zip|*.tar|*.xz|*.gz|*.bz2|*.woff|*.woff2|*.ttf|*.otf|*.so|*.bin|*.img|*.apk|*.jar|*.class|*.dll|*.dylib|*.mp4|*.mkv|*.wav|*.mp3|*.webp|*.pyc|*.db|*.sqlite|*.sqlite3|*.db-wal|*.db-shm)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# --- Detector-1 real-hit test (applies carrier-strip #8) ---------------------
# Returns 0 iff a TEXT file contains a detector-1 (keyword / known-token-format)
# match that is a REAL secret — i.e. one that SURVIVES carrier-strip #8: base64
# image data-URIs (#8b) are blanked first, then every detector-1 match is checked
# and any placeholder-value carrier (#8a) is dropped; a surviving non-placeholder
# match is a real hit. Binary blobs do NOT use this path (helix_cred_scan_file
# runs the raw grep for them — the #8 carriers are text constructs, and running
# sed/grep -o over a binary is a §11.4.201 false-positive vector).
_helix_cred_detector1_real_hit() {
  _helix_cred_d1_matches="$(
    sed -E "s#${HELIX_CRED_BASE64_IMAGE_CARRIER}# #g" "$1" 2>/dev/null \
      | grep -Eio "$HELIX_CRED_VALUE_PATTERN" 2>/dev/null
  )"
  # No detector-1 match at all (after #8b) → not a real hit.
  [ -n "$_helix_cred_d1_matches" ] || return 1
  # Drop #8a placeholder-value carriers; a surviving match line is a real secret.
  # The final `grep -q` (not the middle grep -v) determines the verdict, so an
  # all-carriers input (middle grep -v prints nothing, exits 1) yields a non-zero
  # pipeline exit under pipefail AND a non-match final grep -q — both mean "clean".
  printf '%s\n' "$_helix_cred_d1_matches" \
    | grep -Eiv "$HELIX_CRED_PLACEHOLDER_CARRIER" 2>/dev/null \
    | grep -q '[^[:space:]]'
}

# --- Whole-file convenience scanner ------------------------------------------
# Scans a file ON DISK end-to-end. Returns 0 if a credential is found, 1 if
# clean (or the path is unreadable). Runs detector-1 (grep value-pattern), then
# — only if the path is NOT a binary-skip extension — detector-2 (adjacency awk).
# The consuming pre-commit hook scans STAGED content via `git show` and therefore
# uses the exported patterns + helix_cred_is_binary_skip directly rather than
# this helper; this helper is for on-disk scans (golden fixtures, ad-hoc checks).
helix_cred_scan_file() {
  _helix_cred_path="$1"
  [ -f "$_helix_cred_path" ] || return 1
  # Binary blobs: detector-1 raw grep ONLY (carrier-strip #8 covers text
  # constructs, and detector-2 is skipped for binaries as before).
  if helix_cred_is_binary_skip "$_helix_cred_path"; then
    grep -Eiq "$HELIX_CRED_VALUE_PATTERN" "$_helix_cred_path" 2>/dev/null && return 0
    return 1
  fi
  # (1) keyword-anchored / known-token-format value scan WITH carrier-strip #8
  #     (placeholder-value + base64-image data-URI carriers removed).
  if _helix_cred_detector1_real_hit "$_helix_cred_path"; then
    return 0
  fi
  # (2) email-adjacency heuristic. awk exit 0 = offending line found.
  if awk "$HELIX_CRED_ADJACENCY_AWK" "$_helix_cred_path" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
