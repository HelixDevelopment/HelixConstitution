#!/usr/bin/env bash
# scripts/action_prefix_lib.sh
#
# Shared library for the universal "ACTION_NAME ::" prompt-prefix system
# (§11.4.140). The pure, agent-agnostic engine reused by THREE consumers:
#   (a) scripts/hooks/action_prefix_expand.sh   — Claude Code UserPromptSubmit hook
#   (b) the §11.4.140 test harnesses             — unit + integration tests
#   (c) scripts/generate_agent_prefix_commands.sh — per-agent slash-command gen
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Parse a first-line "ACTION_NAME ::" prefix, look the token up in the action
# registry (actions/registry.yaml or $HELIX_ACTION_REGISTRY), and expand the
# prompt by replacing the prefix with the action's registered expansion text.
#
# ── Public API ───────────────────────────────────────────────────────────────
#   apx_registry_path                  → echoes the resolved registry path
#   apx_validate_registry              → exit 0 if registry parses + has schema
#                                        + at least one action; non-zero otherwise
#   apx_lookup_expansion <NAME>        → echoes the action's expansion text;
#                                        exit 0 if found, 1 if not found
#   apx_lookup_subsystem <TOKEN>       → echoes a SUB-SYSTEM context expansion for
#                                        a UNIQUE, non-action, uppercase-exact
#                                        sub-system / submodule token (§11.4.140
#                                        extension); exit 0 if resolved, 1 if not.
#                                        Two sources: the registry `subsystems:`
#                                        catalogue + recursive .gitmodules
#                                        discovery from the invoking project root.
#   apx_list_actions                   → echoes one action name per line
#   apx_parse_prefix <PROMPT>          → echoes the first-line action token if the
#                                        prompt matches the grammar; exit 0 if a
#                                        grammar-shaped token is present, 1 if not.
#                                        (Presence of the token, NOT registry
#                                        membership — membership is a later step.)
#   apx_expand_prompt <PROMPT>         → echoes a JSON object describing the result
#                                        ({matched, verdict, action, namespace,
#                                        form, expansion, residual, emitted,
#                                        closest, kind}). `kind` ∈ {action,
#                                        subsystem} distinguishes a behavioral
#                                        action from a sub-system reference. The
#                                        single source of truth for both layers +
#                                        tests.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   $HELIX_ACTION_REGISTRY   (optional) path to the registry YAML; defaults to
#                            <this-lib-dir>/../actions/registry.yaml
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Functions echo to stdout; no files written; no global state mutated beyond
#   the readonly helpers below.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None. Pure read-only library.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   Prefers python3 (+ PyYAML) for robust YAML parsing. Falls back to a
#   documented awk/sed reader for the narrow registry shape this project emits
#   (block-scalar `expansion:` + simple `name:` keys) when python3 is absent.
#   The fallback is honest about its narrower coverage (see apx__yaml_*).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (the mandate), §11.4.28 (decoupling — no project data),
#   §11.4.6 (no-guessing — unknown token ⇒ ASK, never invent),
#   §11.4.66 / §11.4.105 (clarify on unknown), §11.4.67 (sh -n + bash -n clean).
#
# Classification: universal (§11.4.17)

# Resolve this library's own directory (works when sourced).
apx__lib_dir() {
  # shellcheck disable=SC2128
  local src="${BASH_SOURCE[0]:-$0}"
  local dir
  dir="$(cd "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  printf '%s' "$dir"
}

# ── Registry path resolution ─────────────────────────────────────────────────
apx_registry_path() {
  if [ -n "${HELIX_ACTION_REGISTRY:-}" ]; then
    printf '%s' "$HELIX_ACTION_REGISTRY"
    return 0
  fi
  local libdir
  libdir="$(apx__lib_dir)"
  printf '%s' "$libdir/../actions/registry.yaml"
}

# ── YAML-reader dependency selection ─────────────────────────────────────────
apx__have_python_yaml() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import yaml' >/dev/null 2>&1 || return 1
  return 0
}

# Embedded python helper: prints a tab-separated stream "name<TAB>expansion"
# (expansion newline-collapsed to single spaces, exactly as a YAML folded scalar
# resolves) for every action; or a control token for validation.
apx__py() {
  # $1 = mode: validate | list | expansion | dump
  # $2 = registry path
  # $3 = (expansion mode only) action name
  python3 - "$@" <<'PYEOF'
import sys, yaml
mode = sys.argv[1]
path = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
except Exception as e:
    sys.stderr.write("apx: registry parse error: %s\n" % e)
    sys.exit(3)
if not isinstance(doc, dict):
    sys.stderr.write("apx: registry root is not a mapping\n")
    sys.exit(3)
actions = doc.get("actions")
if mode == "validate":
    if "schema_version" not in doc:
        sys.stderr.write("apx: missing schema_version\n"); sys.exit(3)
    grammar = doc.get("grammar") or {}
    if not grammar.get("prefix_regex"):
        sys.stderr.write("apx: missing grammar.prefix_regex\n"); sys.exit(3)
    if not isinstance(actions, list) or len(actions) == 0:
        sys.stderr.write("apx: no actions defined\n"); sys.exit(3)
    for a in actions:
        if not isinstance(a, dict) or not a.get("name") or a.get("expansion") is None:
            sys.stderr.write("apx: action missing name or expansion\n"); sys.exit(3)
    sys.exit(0)
if not isinstance(actions, list):
    actions = []
def norm(s):
    # YAML folded scalars already collapse newlines; normalise any residual
    # whitespace runs to single spaces and strip ends.
    return " ".join(str(s).split())
if mode == "list":
    for a in actions:
        if isinstance(a, dict) and a.get("name"):
            print(a["name"])
    sys.exit(0)
if mode == "expansion":
    want = sys.argv[3]
    for a in actions:
        if isinstance(a, dict) and a.get("name") == want:
            sys.stdout.write(norm(a.get("expansion", "")))
            sys.exit(0)
    sys.exit(1)
sys.exit(4)
PYEOF
}

# ── awk fallback (no python3 / PyYAML) ───────────────────────────────────────
# Handles the narrow registry shape this project emits: top-level keys
# `schema_version:` and `grammar:` with a `prefix_regex:` child, plus an
# `actions:` list whose items carry `- name: NAME` and a `expansion: >-` folded
# block scalar followed by indented continuation lines. Honest scope: this is
# NOT a general YAML parser. It targets exactly the registry.yaml format above.
apx__awk_list() {
  local path="$1"
  awk '
    /^[[:space:]]*-[[:space:]]+name:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      gsub(/["'\'']/, "", line)
      if (line != "") print line
    }
  ' "$path"
}

apx__awk_validate() {
  local path="$1"
  grep -Eq '^[[:space:]]*schema_version:' "$path" || { echo "apx: missing schema_version" >&2; return 3; }
  grep -Eq '^[[:space:]]*prefix_regex:' "$path" || { echo "apx: missing grammar.prefix_regex" >&2; return 3; }
  local n
  n="$(apx__awk_list "$path" | grep -c . || true)"
  [ "$n" -ge 1 ] || { echo "apx: no actions defined" >&2; return 3; }
  return 0
}

# Extract a single action's expansion folded scalar via awk.
apx__awk_expansion() {
  local path="$1" want="$2"
  # NOTE on awk semantics: `exit` STILL runs the END block, so we never `print`
  # mid-rule. We accumulate into `acc`, freeze it into `captured` the moment the
  # expansion block ends, and emit EXACTLY ONCE in END. `done` stops any further
  # accumulation after the target's expansion has been fully captured.
  awk -v want="$want" '
    function flush_collapse(s,   t) {
      t=s
      gsub(/[[:space:]]+/, " ", t)
      sub(/^[[:space:]]+/, "", t)
      sub(/[[:space:]]+$/, "", t)
      return t
    }
    BEGIN { in_target=0; in_exp=0; exp_indent=-1; acc=""; cur=""; done=0; captured="" }
    done { next }
    # action item start: "- name: X"
    /^[[:space:]]*-[[:space:]]+name:[[:space:]]*/ {
      # a new item ends any in-progress expansion capture for the target item
      if (in_target && in_exp) { captured=flush_collapse(acc); done=1; next }
      line=$0
      sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      gsub(/["'\'']/, "", line)
      cur=line
      in_target=(cur==want)?1:0
      in_exp=0; exp_indent=-1; acc=""
      next
    }
    {
      if (!in_target) next
      # detect the expansion key line within the target item
      if (!in_exp) {
        if ($0 ~ /^[[:space:]]*expansion:[[:space:]]*[>|][-+]?[[:space:]]*$/) {
          in_exp=1; exp_indent=-1; acc=""
          next
        }
        if ($0 ~ /^[[:space:]]*expansion:[[:space:]]*/) {
          # inline (non-block) expansion value
          v=$0
          sub(/^[[:space:]]*expansion:[[:space:]]*/, "", v)
          gsub(/^["'\'']/, "", v); gsub(/["'\'']$/, "", v)
          captured=flush_collapse(v); done=1; next
        }
        next
      }
      # in_exp: capture continuation lines more-indented than the key
      ind=match($0, /[^ ]/)
      if ($0 ~ /^[[:space:]]*$/) { acc=acc " "; next }
      if (exp_indent==-1) exp_indent=ind
      if (ind < exp_indent) { captured=flush_collapse(acc); done=1; next }
      l=$0
      sub(/^[[:space:]]+/, "", l)
      acc=acc " " l
      next
    }
    END {
      if (done) { if (captured != "") print captured }
      else if (in_target && in_exp) print flush_collapse(acc)
    }
  ' "$path"
}

# ── Public: registry validation ──────────────────────────────────────────────
apx_validate_registry() {
  local path
  path="$(apx_registry_path)"
  [ -f "$path" ] || { echo "apx: registry not found: $path" >&2; return 2; }
  if apx__have_python_yaml; then
    apx__py validate "$path"
    return $?
  fi
  apx__awk_validate "$path"
  return $?
}

# ── Public: list action names ────────────────────────────────────────────────
apx_list_actions() {
  local path
  path="$(apx_registry_path)"
  [ -f "$path" ] || { echo "apx: registry not found: $path" >&2; return 2; }
  if apx__have_python_yaml; then
    apx__py list "$path"
    return $?
  fi
  apx__awk_list "$path"
}

# ── Public: lookup one action's expansion ────────────────────────────────────
apx_lookup_expansion() {
  local name="$1"
  local path
  path="$(apx_registry_path)"
  [ -f "$path" ] || { echo "apx: registry not found: $path" >&2; return 2; }
  if apx__have_python_yaml; then
    apx__py expansion "$path" "$name"
    return $?
  fi
  local out
  out="$(apx__awk_expansion "$path" "$name")"
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  return 1
}

# ── Internal: first non-blank line of a prompt ───────────────────────────────
apx__first_nonblank_line() {
  local prompt="$1" first="" line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *[!$' \t']*) first="$line"; break ;;
      *) continue ;;
    esac
  done <<APXEOF
$prompt
APXEOF
  [ -n "$first" ] || return 1
  printf '%s' "$first"
}

# ── Public: parse first-line prefix token across all 5 grammar forms ─────────
# GRAMMAR_ADDENDUM (§11.4.140, 2026-06-09; arrow form 2026-07-02) — five
# equivalent forms:
#   (1) `ACTION :: rest`           bare `::`            → DEFAULT  ACTION  rest  colon
#   (2) `PREFIX::ACTION :: rest`   namespaced `::`      → PREFIX   ACTION  rest  colon
#   (3) `/ACTION rest`             bare slash           → DEFAULT  ACTION  rest  slash
#   (4) `/PREFIX::ACTION rest`     namespaced slash     → PREFIX   ACTION  rest  slash
#   (5) `ACTION ---> rest`         bare arrow           → DEFAULT  ACTION  rest  arrow
#       `PREFIX::ACTION ---> rest` namespaced arrow     → PREFIX   ACTION  rest  arrow
#
# Echoes a TAB-separated 4-tuple "namespace<TAB>action<TAB>rest<TAB>matched_form"
# (namespace is the literal PREFIX or `DEFAULT` when absent; matched_form is one
# of `colon` / `slash` / `arrow`). Returns 0 with the tuple on ANY grammar match, 1 (no
# output) otherwise. Presence of a grammar-shaped token, NOT registry membership
# (membership is a later step in apx_expand_prompt). Escape handling lives in
# apx_expand_prompt — this parser sees the de-escaped line.
#
# The `::`-form, slash-form, and arrow-form anchored ERE patterns are kept
# byte-identical between the python and the awk paths (the addendum warns the
# awk END-block double-emit bug already bit once; both paths share these exact
# regexes via apx__parse_via_python / apx__parse_via_awk so they can never
# drift). The arrow branch FALLS THROUGH to the colon check on an invalid
# leading token so `A :: B ---> C` parses identically in both paths.
apx_parse_prefix() {
  local prompt="$1"
  local first
  first="$(apx__first_nonblank_line "$prompt")" || return 1

  # Prefer python3 for the anchored capture-group parse; awk fallback otherwise.
  # BOTH implement the SAME three anchored regexes (slash first — `/` is
  # unambiguous — then arrow ` ---> `, then `::`) and emit the SAME 4-tuple, so
  # the paths are byte-identical (the §11.4.50 determinism + addendum-warned
  # awk-parity check).
  local tuple
  if apx__have_python_yaml; then
    tuple="$(apx__parse_via_python "$first")" || return 1
  else
    tuple="$(apx__parse_via_awk "$first")" || return 1
  fi
  [ -n "$tuple" ] || return 1
  printf '%s' "$tuple"
  return 0
}

# python parse path — anchored slash-form then arrow-form then `::`-form, capture (ns,action,rest).
apx__parse_via_python() {
  python3 - "$1" <<'PYEOF'
import re, sys
line = sys.argv[1]
# Forms 3+4: /[PREFIX::]ACTION<space(s)>rest  — slash leader makes it unambiguous.
m = re.match(r'^/(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*)\s+(.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\t%s\t%s\t%s" % (ns, m.group(2), m.group(3), "slash"))
    sys.exit(0)
# Form 5: [PREFIX::]ACTION ---> rest  (arrow body separator ' ---> ', one space
# on each side). Anchored, so the arrow must sit immediately after the leading
# token — a mid-prose ' ---> ' after a colon token never matches here.
m = re.match(r'^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*) ---> (.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\t%s\t%s\t%s" % (ns, m.group(2), m.group(3), "arrow"))
    sys.exit(0)
# Forms 1+2: [PREFIX::]ACTION :: rest  (exactly one space each side of `::`).
m = re.match(r'^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*) :: (.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\t%s\t%s\t%s" % (ns, m.group(2), m.group(3), "colon"))
    sys.exit(0)
# Form 6 (§11.4.202): [PREFIX::]ACTION: rest  — single colon, NO space before it,
# exactly one space after. Checked LAST so `A :: B` / `A ---> B` / `/A B` keep
# their meaning. REGISTERED-ACTION-ONLY downstream: an unknown single-colon token
# is a NO-OP (ordinary prose like `NOTE: …` / `TODO: …` never asks — §11.4.6).
m = re.match(r'^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*): (.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\t%s\t%s\t%s" % (ns, m.group(2), m.group(3), "single_colon"))
    sys.exit(0)
sys.exit(1)
PYEOF
}

# awk parse path — byte-identical 4-tuple to the python path. awk ERE has no
# non-capturing groups, so each form is matched then dissected by literal
# `match`/`substr`; the same two anchored shapes (slash first, then `::`) and the
# same DEFAULT-namespace default are applied. Single emit point per branch (no
# END block) so the addendum-warned double-emit cannot recur.
apx__parse_via_awk() {
  printf '%s' "$1" | awk '
    {
      line = $0
      # ── Forms 3+4: ^/[PREFIX::]ACTION<space(s)>rest ──────────────────────
      if (line ~ /^\/[A-Z][A-Z0-9_]*[ \t]+/ || line ~ /^\/[A-Z][A-Z0-9_]*::[A-Z][A-Z0-9_]*[ \t]+/) {
        body = substr(line, 2)                       # drop leading "/"
        # split token vs rest at the first run of whitespace
        sp = match(body, /[ \t]/)
        if (sp == 0) { exit 1 }
        tok  = substr(body, 1, sp - 1)
        rest = substr(body, sp)
        sub(/^[ \t]+/, "", rest)                     # one-or-more spaces collapse to the boundary
        ns = "DEFAULT"; action = tok
        ci = index(tok, "::")
        if (ci > 0) {
          ns     = substr(tok, 1, ci - 1)
          action = substr(tok, ci + 2)
        }
        if (ns !~ /^[A-Z][A-Z0-9_]*$/ || action !~ /^[A-Z][A-Z0-9_]*$/) { exit 1 }
        printf "%s\t%s\t%s\t%s", ns, action, rest, "slash"
        exit 0
      }
      # ── Form 5: ^[PREFIX::]ACTION ---> rest (arrow body separator " ---> ") ──
      # anchor on the FIRST " ---> " (space-3hyphen-gt-space). A leading token
      # that is a valid [PREFIX::]ACTION means the arrow sits immediately after
      # the token (the python-anchored semantics). If the token is INVALID
      # (contains spaces / an interior " :: "), the " ---> " is mid-prose → FALL
      # THROUGH to the colon check (do NOT exit) so `A :: B ---> C` still parses
      # as the colon form — byte-identical to the python path.
      ai = index(line, " ---> ")
      if (ai > 0) {
        atok  = substr(line, 1, ai - 1)
        arest = substr(line, ai + 6)                 # skip the 6-char " ---> "
        ans = "DEFAULT"; aaction = atok
        aci = index(atok, "::")
        if (aci > 0) {
          ans     = substr(atok, 1, aci - 1)
          aaction = substr(atok, aci + 2)
        }
        if (ans ~ /^[A-Z][A-Z0-9_]*$/ && aaction ~ /^[A-Z][A-Z0-9_]*$/) {
          printf "%s\t%s\t%s\t%s", ans, aaction, arest, "arrow"
          exit 0
        }
      }
      # ── Forms 1+2: ^[PREFIX::]ACTION :: rest (exactly " :: ") ─────────────
      # anchor on the body separator " :: " (space-colon-colon-space).
      si = index(line, " :: ")
      if (si > 0) {
        tok  = substr(line, 1, si - 1)
        rest = substr(line, si + 4)                  # skip the 4-char " :: " separator
        ns = "DEFAULT"; action = tok
        ci = index(tok, "::")
        if (ci > 0) {
          ns     = substr(tok, 1, ci - 1)
          action = substr(tok, ci + 2)
        }
        if (ns !~ /^[A-Z][A-Z0-9_]*$/ || action !~ /^[A-Z][A-Z0-9_]*$/) { exit 1 }
        printf "%s\t%s\t%s\t%s", ns, action, rest, "colon"
        exit 0
      }
      # ── Form 6 (§11.4.202): ^[PREFIX::]ACTION: rest (single colon + ONE space) ──
      # byte-identical to the python single_colon branch. Checked LAST. An INVALID
      # leading token falls through to exit 1 (no match), exactly like python.
      if (line ~ /^[A-Z][A-Z0-9_]*: / || line ~ /^[A-Z][A-Z0-9_]*::[A-Z][A-Z0-9_]*: /) {
        ki   = index(line, ": ")
        ktok = substr(line, 1, ki - 1)
        krest = substr(line, ki + 2)               # skip the 2-char ": " separator
        kns = "DEFAULT"; kaction = ktok
        kci = index(ktok, "::")
        if (kci > 0) {
          kns     = substr(ktok, 1, kci - 1)
          kaction = substr(ktok, kci + 2)
        }
        if (kns !~ /^[A-Z][A-Z0-9_]*$/ || kaction !~ /^[A-Z][A-Z0-9_]*$/) { exit 1 }
        printf "%s\t%s\t%s\t%s", kns, kaction, krest, "single_colon"
        exit 0
      }
      exit 1
    }
  '
}

# ── JSON string escaper (no jq dependency) ───────────────────────────────────
apx__json_escape() {
  # Reads stdin, emits a JSON-escaped string body (no surrounding quotes).
  local s
  s="$(cat)"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Replace literal newlines and tabs.
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# Levenshtein-free "closest" helper: returns the registered action name sharing
# the longest common prefix with $1 (cheap, dependency-free; good enough to name
# a likely typo without claiming certainty — §11.4.6 we ASK, never auto-expand).
apx__closest_action() {
  local want="$1"
  local best="" best_score=-1
  local a score i ca cb
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    score=0; i=1
    while :; do
      ca="$(printf '%s' "$want" | cut -c"$i" 2>/dev/null)"
      cb="$(printf '%s' "$a" | cut -c"$i" 2>/dev/null)"
      [ -n "$ca" ] && [ "$ca" = "$cb" ] || break
      score=$((score+1)); i=$((i+1))
    done
    if [ "$score" -gt "$best_score" ]; then best_score="$score"; best="$a"; fi
  done <<APXEOF
$(apx_list_actions 2>/dev/null)
APXEOF
  # Only suggest when there is at least one shared leading char.
  [ "$best_score" -ge 1 ] && printf '%s' "$best"
}

# ── Sub-system / submodule shortcut resolution (§11.4.140 extension) ─────────
# A grammar-shaped UPPERCASE token that is NOT a registered behavioral action MAY
# still name an incorporated SUB-SYSTEM / submodule. Resolution has TWO data
# sources feeding ONE engine (this code carries NO project literal — §11.4.28 /
# §11.4.177; it reads the INVOKING project's own graph, never a hardcoded name):
#   (a) a NAMED Helix-ecosystem catalogue — the `subsystems:` list in the
#       registry — giving curated human aliases (e.g. HXOTA → HelixOTA) for
#       well-known sub-systems that may not be a submodule of every project;
#   (b) RECURSIVE .gitmodules discovery from the invoking project's root — EVERY
#       submodule anywhere in the graph gets auto-derived alias tokens (uppercase
#       name / snake / camel-split / abbreviation), so a NEWLY-added submodule is
#       covered out-of-box with NO hand-maintained list.
# Determinism + no-guessing (§11.4.6): duplicate checkouts of the SAME submodule
# (same canonical URL) collapse to ONE sub-system (fan-out convergence); a token
# that maps to >1 sub-system, or that collides with a registered behavioral
# action, is DROPPED (never silently mis-expanded) → it falls through to ASK.
# HONEST BOUNDARY (§11.4.6): this tier requires python3 (+ PyYAML). Without it,
# resolution returns NOMATCH and the token falls to ASK exactly as before —
# behavioral actions (which have an awk fallback) are unaffected.

# Resolve the invoking PROJECT ROOT: $HELIX_PROJECT_ROOT, else the nearest
# ancestor of $PWD containing a .gitmodules, else $PWD. (§11.4.177 — operate on
# the invocation directory, never a hardcoded project path.)
apx__project_root() {
  if [ -n "${HELIX_PROJECT_ROOT:-}" ]; then printf '%s' "$HELIX_PROJECT_ROOT"; return 0; fi
  local d
  d="$(pwd -P 2>/dev/null || pwd)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/.gitmodules" ]; then printf '%s' "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  pwd -P 2>/dev/null || pwd
}

# Embedded resolver: argv = <registry_path> <project_root> <query_token>.
# Prints the templated sub-system expansion + exit 0 on a UNIQUE, non-action,
# uppercase-exact match; exit 1 (no output) on no-match / ambiguous / missing
# deps. The alias-derivation + collision-drop logic is byte-identical to the
# §11.4.140 sub-system-shortcut test fixtures so the two can never drift.
apx__py_subsystem() {
  apx__have_python_yaml || return 1
  python3 - "$@" <<'PYEOF'
import sys, os, re
try:
    import yaml
except Exception:
    sys.exit(1)
if len(sys.argv) < 4:
    sys.exit(1)
REG, ROOT, QUERY = sys.argv[1], sys.argv[2], sys.argv[3].strip()
MAX_DEPTH = 6

def parse_gitmodules(path):
    if not os.path.isfile(path):
        return []
    subs, cur = {}, None
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line[0] in '#;':
                    continue
                ms = re.match(r'^\[submodule\s+"(.+?)"\]$', line)
                if ms:
                    cur = ms.group(1); subs.setdefault(cur, {}); continue
                mk = re.match(r'^(path|url|branch)\s*=\s*(.*)$', line)
                if mk and cur is not None:
                    v = mk.group(2).strip()
                    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                        v = v[1:-1]
                    subs[cur][mk.group(1)] = v
    except Exception:
        return []
    return [(d.get('path', ''), d.get('url', ''), d.get('branch', '')) for d in subs.values()]

def canon_url(url):
    u = re.sub(r'\.git$', '', url.strip())
    m = re.match(r'^[a-zA-Z0-9._-]+@([^:]+):(.+)$', u)
    if m:
        u = m.group(1) + '/' + m.group(2)
    else:
        u = re.sub(r'^[a-z]+://', '', u)
    u = re.sub(r':\d+/', '/', u)
    return u.lower().strip('/')

def org_of(cu):
    p = cu.split('/'); return p[1] if len(p) >= 3 else (p[0] if p else '')

def repo_of(cu):
    return cu.split('/')[-1] if cu else ''

def normalize(s):
    t = re.sub(r'[^A-Za-z0-9]+', '_', s).upper().strip('_')
    t = re.sub(r'_+', '_', t)
    return t if re.match(r'^[A-Z][A-Z0-9_]*$', t or '') else None

def camel_snake(s):
    s2 = re.sub(r'[^A-Za-z0-9]+', '_', s)
    s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s2)
    s2 = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', s2)
    return normalize(s2)

def initials(tok):
    w = [x for x in tok.split('_') if x]
    return normalize(''.join(x[0] for x in w)) if len(w) >= 2 else None

def walk(root):
    seen, out = set(), []
    def rec(base, prefix, depth):
        if depth > MAX_DEPTH:
            return
        for path, url, branch in parse_gitmodules(os.path.join(base, '.gitmodules')):
            if not url or not path:
                continue
            full = os.path.join(prefix, path) if prefix else path
            key = (canon_url(url), full)
            if key in seen:
                continue
            seen.add(key)
            out.append((full, url))
            child = os.path.join(base, path)
            if os.path.isdir(child):
                rec(child, full, depth + 1)
    rec(root, '', 0)
    return out

try:
    with open(REG, 'r', encoding='utf-8') as fh:
        doc = yaml.safe_load(fh) or {}
except Exception:
    doc = {}
catalogue = doc.get('subsystems') or []
action_names = set()
for a in (doc.get('actions') or []):
    if isinstance(a, dict) and a.get('name'):
        action_names.add(str(a['name']).upper())

subs = {}
for c in catalogue:
    if not isinstance(c, dict) or not c.get('name') or not c.get('url'):
        continue
    cu = canon_url(c['url'])
    s = subs.setdefault(cu, {'url': c['url'], 'org': c.get('org') or org_of(cu),
                             'paths': [], 'display': c['name'], 'aliases': set(),
                             'external': True})
    s['display'] = c['name']
    for a in [c['name']] + list(c.get('aliases') or []):
        n = normalize(str(a))
        if n:
            s['aliases'].add(n)
    cs = camel_snake(c['name'])
    if cs:
        s['aliases'].add(cs)

for full, url in walk(ROOT):
    cu = canon_url(url)
    base = os.path.basename(full)
    repo = repo_of(cu)
    s = subs.setdefault(cu, {'url': url, 'org': org_of(cu), 'paths': [],
                             'display': base, 'aliases': set(), 'external': False})
    s['external'] = False
    if full not in s['paths']:
        s['paths'].append(full)
    for cand in (base, repo):
        for fn in (normalize, camel_snake):
            n = fn(cand)
            if n:
                s['aliases'].add(n)
        n = normalize(cand)
        if n:
            ab = initials(n)
            if ab:
                s['aliases'].add(ab)

tokmap = {}
for cu, s in subs.items():
    for tok in s['aliases']:
        tokmap.setdefault(tok, set()).add(cu)

if QUERY in action_names:
    sys.exit(1)
cus = tokmap.get(QUERY)
if not cus or len(cus) != 1:
    sys.exit(1)
s = subs[next(iter(cus))]
if s['paths']:
    where = 'checked out at: ' + ', '.join(sorted(s['paths']))
else:
    where = 'not currently a submodule of this project — external Helix-ecosystem sub-system'
disp = s['display']
exp = (
    'SUB-SYSTEM REFERENCE (§11.4.140 sub-system shortcut) — the remainder of this '
    'prompt concerns the "{disp}" incorporated sub-system (repository {url}; org '
    '{org}; {where}). Treat it as an EQUAL part of this project\'s codebase '
    '(§11.4.28(A)); keep it fully decoupled + project-agnostic + reusable '
    '(§11.4.28(B)); access its dependencies from the project root (§11.4.28(C)); '
    'fetch-before-edit every remote first (§11.4.37); commit + push to ALL '
    'upstreams (§2.1) and NEVER force-push — merge onto latest main (§11.4.113); '
    'apply the FULL constitution when working on it (§11.4.183) with anti-bluff '
    'captured evidence (§11.4 / §11.4.69). Now perform the following on the '
    '"{disp}" sub-system:'
).format(disp=disp, url=s['url'], org=s['org'], where=where)
sys.stdout.write(exp)
sys.exit(0)
PYEOF
}

# ── Public: resolve a sub-system shortcut token ──────────────────────────────
# apx_lookup_subsystem <TOKEN> → echoes the sub-system expansion text (exit 0)
# for a UNIQUE, non-action, uppercase-exact match; exit 1 (no output) otherwise.
apx_lookup_subsystem() {
  local token="$1" reg root
  [ -n "$token" ] || return 1
  reg="$(apx_registry_path)"
  [ -f "$reg" ] || return 1
  root="$(apx__project_root)"
  apx__py_subsystem "$reg" "$root" "$token"
}

# ── Public: the single expander ──────────────────────────────────────────────
# Emits a JSON object. Fields:
#   matched   : true|false  — did a REGISTERED action expand?
#   verdict   : "expand" | "noop" | "escape" | "ask"
#   action    : the matched/registered action name ("" if none)
#   namespace : the resolved namespace (DEFAULT when the form carried none; "" if no match)
#   form      : the matched grammar form ("colon" | "slash" | "arrow" |
#               "single_colon" (§11.4.202); "" if no match)
#   expansion : the registered expansion text ("" if none)
#   residual  : the remainder of the FIRST line after the prefix, plus any
#               following lines ("" if no match)
#   emitted   : the prompt the agent should act on:
#                 expand → "<expansion>\n\n<residual+rest>"
#                 escape → the prompt with the single leading backslash stripped
#                 noop/ask → the original prompt unchanged
#   closest   : on verdict=ask, the closest registered action name (may be "")
#
# All FIVE grammar forms (GRAMMAR_ADDENDUM §11.4.140 + arrow form) resolve to the
# same action + same expansion: `ACTION :: x` ≡ `DEFAULT::ACTION :: x` ≡
# `/ACTION x` ≡ `/DEFAULT::ACTION x` ≡ `ACTION ---> x` ≡ `DEFAULT::ACTION ---> x`.
# Escape (leading `\`) is honored for the `::`, arrow, and slash forms.
apx_expand_prompt() {
  local prompt="$1"

  local first
  first="$(apx__first_nonblank_line "$prompt")" || {
    # empty / all-blank prompt → no-op
    apx__emit_json "false" "noop" "" "" "" "" "" "$prompt" ""
    return 0
  }

  # ----- Escape handling: a leading backslash on the first non-blank line makes
  # the prefix literal, for the `::` form (`\TOKEN :: `, `\PREFIX::TOKEN :: `),
  # the arrow form (`\TOKEN ---> `, `\PREFIX::TOKEN ---> `), AND the slash form
  # (`\/TOKEN `, `\/PREFIX::TOKEN `). Strip exactly the first
  # leading backslash when it guards a grammar-shaped prefix; leave the rest
  # literal (NO expansion). POSIX ERE has no non-capturing group `(?:..)`, so the
  # optional `PREFIX::` is expressed by alternating the with/without-prefix shapes.
  if printf '%s' "$first" | grep -Eq '^\\[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)? :: ' \
     || printf '%s' "$first" | grep -Eq '^\\[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)? ---> ' \
     || printf '%s' "$first" | grep -Eq '^\\[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)?: ' \
     || printf '%s' "$first" | grep -Eq '^\\/[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)?[[:space:]]'; then
    local emitted
    emitted="$(apx__replace_first_nonblank "$prompt" "$(printf '%s' "$first" | sed -E 's/^\\//')")"
    apx__emit_json "false" "escape" "" "" "" "" "" "$emitted" ""
    return 0
  fi

  # Grammar-shaped prefix? Parse all 5 forms → namespace, action, rest, form.
  local tuple namespace token rest form
  if ! tuple="$(apx_parse_prefix "$prompt")"; then
    apx__emit_json "false" "noop" "" "" "" "" "" "$prompt" ""
    return 0
  fi
  namespace="$(printf '%s' "$tuple" | cut -f1)"
  token="$(printf '%s' "$tuple" | cut -f2)"
  rest="$(printf '%s' "$tuple" | cut -f3-)"
  # cut -f3- re-joins the trailing form with a TAB; split that final TAB off.
  form="${rest##*$'\t'}"
  local first_residual="${rest%$'\t'*}"

  # Build residual-and-rest ONCE (shared by the action + sub-system expand
  # branches): first-line residual + the remaining lines after the first
  # non-blank line.
  local tail residual_all
  tail="$(apx__rest_after_first_nonblank "$prompt")"
  if [ -n "$tail" ]; then
    residual_all="$first_residual"$'\n'"$tail"
  else
    residual_all="$first_residual"
  fi

  # ── Resolution order (first match wins) ──────────────────────────────────
  # (1) registered behavioral ACTION (BACKGROUND / REMINDER). Lookup is by
  #     action NAME — all five grammar forms of the same action share one
  #     expansion; the namespace is recorded but the action is registered under
  #     DEFAULT. A registered action ALWAYS wins over a sub-system shortcut of
  #     the same token (the sub-system resolver drops action-colliding tokens).
  local expansion
  if expansion="$(apx_lookup_expansion "$token")"; then
    apx__emit_expand "$token" "$namespace" "$form" "$expansion" "$residual_all" "action"
    return 0
  fi

  # (1b) §11.4.202 single-colon form is REGISTERED-ACTION-ONLY. The token was NOT
  #      a registered action (branch (1) fell through), so this line is ordinary
  #      prose that merely shares the `WORD: text` shape (`NOTE:` / `TODO:` /
  #      `WARNING:` / `FIXME:` / `NOTA BENE:` …). Emit a NO-OP: never ASK (that
  #      would question every such sentence), never resolve a sub-system (the
  #      shape is far too common in prose to carry a shortcut). The other four
  #      forms keep their ASK-on-unknown behaviour — their shapes do not occur in
  #      ordinary prose (§11.4.6: an unknown token is never silently EXPANDED;
  #      here it is simply not a prefix at all).
  if [ "$form" = "single_colon" ]; then
    apx__emit_json "false" "noop" "" "" "" "" "" "$prompt" ""
    return 0
  fi

  # (2) incorporated SUB-SYSTEM / submodule shortcut (§11.4.140 extension). The
  #     token is a UNIQUE, non-action alias of a sub-system in the registry's
  #     `subsystems:` catalogue OR of a submodule auto-discovered from the
  #     invoking project's recursive .gitmodules graph. Ambiguous / action-
  #     colliding / lowercase tokens do NOT resolve here (§11.4.6 no-guessing) —
  #     they fall through to the ASK path (3).
  local sub_expansion
  if sub_expansion="$(apx_lookup_subsystem "$token" 2>/dev/null)" && [ -n "$sub_expansion" ]; then
    apx__emit_expand "$token" "$namespace" "$form" "$sub_expansion" "$residual_all" "subsystem"
    return 0
  fi

  # (3) grammar-shaped but UNKNOWN token → ASK (§11.4.6 / §11.4.66 / §11.4.105).
  local closest
  closest="$(apx__closest_action "$token")"
  apx__emit_json "false" "ask" "$token" "$namespace" "$form" "" "$first_residual" "$prompt" "$closest"
  return 0
}

# ── Internal: rebuild helpers ────────────────────────────────────────────────
# Replace the first non-blank line of $1 with $2 (preserving leading blank lines).
apx__replace_first_nonblank() {
  local prompt="$1" replacement="$2"
  local out="" seen=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$seen" -eq 0 ]; then
      case "$line" in
        *[!$' \t']*) out="$out$replacement"$'\n'; seen=1; continue ;;
      esac
    fi
    out="$out$line"$'\n'
  done <<APXEOF
$prompt
APXEOF
  # Drop the single trailing newline we always append.
  printf '%s' "${out%$'\n'}"
}

# Echo every line AFTER the first non-blank line (the "rest").
apx__rest_after_first_nonblank() {
  local prompt="$1"
  local out="" seen=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$seen" -eq 0 ]; then
      case "$line" in
        *[!$' \t']*) seen=1; continue ;;
        *) continue ;;
      esac
    fi
    out="$out$line"$'\n'
  done <<APXEOF
$prompt
APXEOF
  printf '%s' "${out%$'\n'}"
}

# ── Internal: emit the result JSON ───────────────────────────────────────────
apx__emit_json() {
  # $1 matched $2 verdict $3 action $4 namespace $5 form $6 expansion
  # $7 residual $8 emitted $9 closest  ${10} kind (default "action")
  #
  # `kind` (§11.4.140 sub-system-shortcut extension) distinguishes an expansion
  # of a registered behavioral ACTION (BACKGROUND / REMINDER) from an expansion
  # of an incorporated SUB-SYSTEM / submodule reference. It is APPENDED as the
  # last field so every pre-existing field read (verdict/action/…/closest) is
  # byte-stable — the field order of the first nine keys never changes. Callers
  # that pass only nine args get kind="action" (the correct default for the
  # noop / escape / ask verdicts, where kind is informational).
  printf '{'
  printf '"matched":%s,' "$1"
  printf '"verdict":"%s",' "$2"
  printf '"action":"%s",' "$(printf '%s' "$3" | apx__json_escape)"
  printf '"namespace":"%s",' "$(printf '%s' "$4" | apx__json_escape)"
  printf '"form":"%s",' "$(printf '%s' "$5" | apx__json_escape)"
  printf '"expansion":"%s",' "$(printf '%s' "$6" | apx__json_escape)"
  printf '"residual":"%s",' "$(printf '%s' "$7" | apx__json_escape)"
  printf '"emitted":"%s",' "$(printf '%s' "$8" | apx__json_escape)"
  printf '"closest":"%s",' "$(printf '%s' "$9" | apx__json_escape)"
  printf '"kind":"%s"' "$(printf '%s' "${10:-action}" | apx__json_escape)"
  printf '}\n'
}

# ── Internal: build + emit an EXPAND result (shared by the action + sub-system
# branches of apx_expand_prompt) ─────────────────────────────────────────────
# Reproduces the stacked-prefix recursion exactly (outer-to-inner): if the
# residual's own first non-blank line is itself a grammar-shaped REGISTERED
# prefix (action OR sub-system), it is expanded too and the emitted text nests
# outer-expansion + blank line + inner-emitted.
apx__emit_expand() {
  # $1 token $2 namespace $3 form $4 expansion $5 residual_all $6 kind
  local token="$1" namespace="$2" form="$3" expansion="$4" residual_all="$5" kind="$6"
  local inner_json inner_verdict inner_emitted emitted
  inner_json="$(apx_expand_prompt "$residual_all")"
  inner_verdict="$(apx__json_get "$inner_json" verdict)"
  if [ "$inner_verdict" = "expand" ]; then
    inner_emitted="$(apx__json_get "$inner_json" emitted)"
    emitted="$expansion"$'\n\n'"$inner_emitted"
  else
    emitted="$expansion"$'\n\n'"$residual_all"
  fi
  apx__emit_json "true" "expand" "$token" "$namespace" "$form" "$expansion" "$residual_all" "$emitted" "" "$kind"
}

# ── Internal: read a string field out of our own emitted JSON ────────────────
# Narrow: only used on apx__emit_json output, which we control. Prefers jq.
apx__json_get() {
  local json="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
    return 0
  fi
  # Fallback: extract "field":"...". Unescape \n \t \" \\.
  printf '%s' "$json" | sed -n "s/.*\"$field\":\"\\(\\([^\"\\\\]\\|\\\\.\\)*\\)\".*/\\1/p" \
    | sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\r/\r/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}
