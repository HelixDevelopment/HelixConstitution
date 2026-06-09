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
#   apx_list_actions                   → echoes one action name per line
#   apx_parse_prefix <PROMPT>          → echoes the first-line action token if the
#                                        prompt matches the grammar; exit 0 if a
#                                        grammar-shaped token is present, 1 if not.
#                                        (Presence of the token, NOT registry
#                                        membership — membership is a later step.)
#   apx_expand_prompt <PROMPT>         → echoes a JSON object describing the result
#                                        ({matched, verdict, action, expansion,
#                                        residual, emitted, closest}). The single
#                                        source of truth for both layers + tests.
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

# ── Public: parse first-line prefix token across all 4 grammar forms ─────────
# GRAMMAR_ADDENDUM (§11.4.140, 2026-06-09) — four equivalent forms:
#   (1) `ACTION :: rest`           bare `::`            → DEFAULT  ACTION  rest  colon
#   (2) `PREFIX::ACTION :: rest`   namespaced `::`      → PREFIX   ACTION  rest  colon
#   (3) `/ACTION rest`             bare slash           → DEFAULT  ACTION  rest  slash
#   (4) `/PREFIX::ACTION rest`     namespaced slash     → PREFIX   ACTION  rest  slash
#
# Echoes a TAB-separated 4-tuple "namespace<TAB>action<TAB>rest<TAB>matched_form"
# (namespace is the literal PREFIX or `DEFAULT` when absent; matched_form is one
# of `colon` / `slash`). Returns 0 with the tuple on ANY grammar match, 1 (no
# output) otherwise. Presence of a grammar-shaped token, NOT registry membership
# (membership is a later step in apx_expand_prompt). Escape handling lives in
# apx_expand_prompt — this parser sees the de-escaped line.
#
# The `::`-form and slash-form anchored ERE patterns are kept byte-identical
# between the python and the awk paths (the addendum warns the awk END-block
# double-emit bug already bit once; both paths share these exact regexes via
# apx__parse_via_python / apx__parse_via_awk so they can never drift).
apx_parse_prefix() {
  local prompt="$1"
  local first
  first="$(apx__first_nonblank_line "$prompt")" || return 1

  # Prefer python3 for the anchored capture-group parse; awk fallback otherwise.
  # BOTH implement the SAME two anchored regexes (slash first — `/` is
  # unambiguous — then `::`) and emit the SAME 4-tuple, so the paths are
  # byte-identical (the §11.4.50 determinism + addendum-warned awk-parity check).
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

# python parse path — anchored slash-form then `::`-form, capture (ns,action,rest).
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
# Forms 1+2: [PREFIX::]ACTION :: rest  (exactly one space each side of `::`).
m = re.match(r'^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*) :: (.*)$', line)
if m:
    ns = m.group(1) or "DEFAULT"
    sys.stdout.write("%s\t%s\t%s\t%s" % (ns, m.group(2), m.group(3), "colon"))
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

# ── Public: the single expander ──────────────────────────────────────────────
# Emits a JSON object. Fields:
#   matched   : true|false  — did a REGISTERED action expand?
#   verdict   : "expand" | "noop" | "escape" | "ask"
#   action    : the matched/registered action name ("" if none)
#   namespace : the resolved namespace (DEFAULT when the form carried none; "" if no match)
#   form      : the matched grammar form ("colon" | "slash"; "" if no match)
#   expansion : the registered expansion text ("" if none)
#   residual  : the remainder of the FIRST line after the prefix, plus any
#               following lines ("" if no match)
#   emitted   : the prompt the agent should act on:
#                 expand → "<expansion>\n\n<residual+rest>"
#                 escape → the prompt with the single leading backslash stripped
#                 noop/ask → the original prompt unchanged
#   closest   : on verdict=ask, the closest registered action name (may be "")
#
# All FOUR grammar forms (GRAMMAR_ADDENDUM §11.4.140) resolve to the same action
# + same expansion: `ACTION :: x` ≡ `DEFAULT::ACTION :: x` ≡ `/ACTION x` ≡
# `/DEFAULT::ACTION x`. Escape (leading `\`) is honored for BOTH the `::` and the
# slash form.
apx_expand_prompt() {
  local prompt="$1"

  local first
  first="$(apx__first_nonblank_line "$prompt")" || {
    # empty / all-blank prompt → no-op
    apx__emit_json "false" "noop" "" "" "" "" "" "$prompt" ""
    return 0
  }

  # ----- Escape handling: a leading backslash on the first non-blank line makes
  # the prefix literal, for BOTH the `::` form (`\TOKEN :: `, `\PREFIX::TOKEN :: `)
  # AND the slash form (`\/TOKEN `, `\/PREFIX::TOKEN `). Strip exactly the first
  # leading backslash when it guards a grammar-shaped prefix; leave the rest
  # literal (NO expansion). POSIX ERE has no non-capturing group `(?:..)`, so the
  # optional `PREFIX::` is expressed by alternating the with/without-prefix shapes.
  if printf '%s' "$first" | grep -Eq '^\\[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)? :: ' \
     || printf '%s' "$first" | grep -Eq '^\\/[A-Z][A-Z0-9_]*(::[A-Z][A-Z0-9_]*)?[[:space:]]'; then
    local emitted
    emitted="$(apx__replace_first_nonblank "$prompt" "$(printf '%s' "$first" | sed -E 's/^\\//')")"
    apx__emit_json "false" "escape" "" "" "" "" "" "$emitted" ""
    return 0
  fi

  # Grammar-shaped prefix? Parse all 4 forms → namespace, action, rest, form.
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

  # Look the token up in the registry (namespace is recorded but the BACKGROUND
  # action is registered under DEFAULT; lookup is by action NAME — all four forms
  # of the same action share one expansion).
  local expansion
  if expansion="$(apx_lookup_expansion "$token")"; then
    # Registered → expand. Build residual-and-rest: first-line residual + the
    # remaining lines of the prompt after the first non-blank line.
    local tail residual_all
    tail="$(apx__rest_after_first_nonblank "$prompt")"
    if [ -n "$tail" ]; then
      residual_all="$first_residual"$'\n'"$tail"
    else
      residual_all="$first_residual"
    fi

    # Stacked-prefix recursion: if the residual's first non-blank line is itself
    # a grammar-shaped registered prefix (any of the 4 forms), expand it too
    # (outer-to-inner).
    local inner_json inner_verdict inner_emitted
    inner_json="$(apx_expand_prompt "$residual_all")"
    inner_verdict="$(apx__json_get "$inner_json" verdict)"
    if [ "$inner_verdict" = "expand" ]; then
      inner_emitted="$(apx__json_get "$inner_json" emitted)"
      local emitted="$expansion"$'\n\n'"$inner_emitted"
      apx__emit_json "true" "expand" "$token" "$namespace" "$form" "$expansion" "$residual_all" "$emitted" ""
      return 0
    fi

    local emitted="$expansion"$'\n\n'"$residual_all"
    apx__emit_json "true" "expand" "$token" "$namespace" "$form" "$expansion" "$residual_all" "$emitted" ""
    return 0
  fi

  # Grammar-shaped but UNKNOWN token → ASK (§11.4.6 / §11.4.66 / §11.4.105).
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
  # $7 residual $8 emitted $9 closest
  printf '{'
  printf '"matched":%s,' "$1"
  printf '"verdict":"%s",' "$2"
  printf '"action":"%s",' "$(printf '%s' "$3" | apx__json_escape)"
  printf '"namespace":"%s",' "$(printf '%s' "$4" | apx__json_escape)"
  printf '"form":"%s",' "$(printf '%s' "$5" | apx__json_escape)"
  printf '"expansion":"%s",' "$(printf '%s' "$6" | apx__json_escape)"
  printf '"residual":"%s",' "$(printf '%s' "$7" | apx__json_escape)"
  printf '"emitted":"%s",' "$(printf '%s' "$8" | apx__json_escape)"
  printf '"closest":"%s"' "$(printf '%s' "$9" | apx__json_escape)"
  printf '}\n'
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
