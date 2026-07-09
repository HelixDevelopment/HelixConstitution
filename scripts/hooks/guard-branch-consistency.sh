#!/usr/bin/env bash
# scripts/hooks/guard-branch-consistency.sh
#
# Claude Code PreToolUse guard hook (mechanical block) enforcing constitution
# §11.4.181 (consistent controlled feature-branch naming) at CREATE TIME — the
# PREVENTIVE layer. The pre-build gate CM-BRANCH-NAME-CONSISTENCY is DETECTIVE
# (it catches a divergent branch AFTER it already exists); this hook makes an
# ad-hoc, unregistered feature/* branch IMPOSSIBLE TO CREATE in the first place
# (the operator's "this cannot NEVER happen" ask). §11.4.109-class anti-forgetting
# hook: enforcement independent of any agent's recall — a rule the orchestrator
# forgets to paste is not enforcement.
#
# CONTRACT (Claude Code PreToolUse hook):
#   - Receives the tool invocation as JSON on stdin. For tool_name == "Bash" the
#     command string lives at .tool_input.command.
#   - Exit 0  -> allow (Claude proceeds).
#   - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal reason.
#   - Any other exit -> non-blocking error (never used).
#
# WHAT IT BLOCKS: a manual git feature-branch CREATE whose name is NOT a
# registered logic_groups.destination in the workable-items DB — i.e. an ad-hoc
# DIVERGENT name (§11.4.181's exact defect). The three create forms:
#     git checkout -b|-B feature/<name>
#     git switch   -c|-C feature/<name>
#     git branch [-f|--force] feature/<name>
# A DELETE (`git branch -d/-D`), a plain LIST, or any non-feature branch is
# untouched (exit 0) — reconciliation (§11.4.181(4)) merges + deletes, never
# force-creates, so those paths stay open.
#
# WHAT IT ALLOWS:
#   - The SANCTIONED MINT PATH `workable-items group branch <group_id>` (which
#     resolves feature/<slug> from the registry and creates it INSIDE the Go
#     binary — that internal git call is not a Bash tool-call, so it never
#     reaches this hook anyway; the invocation string is allowed explicitly).
#   - A create whose name IS a registered destination (correct outcome).
#   - A `# guardrails:allow <reason>` documented-exception marker (mirrors the
#     sibling guard-forbidden-commands.sh escape hatch; auditable in transcript).
#   - Every non-create / non-feature / non-Bash tool call.
#
# FAIL-CLOSED (§11.4.6, no fail-open): when the registry cannot be read (no
# sqlite3 OR no DB found) a manual feature-branch CREATE is BLOCKED with a
# pointer to the mint helper — never allowed-because-unverifiable. The mint
# helper (CGO-bundled sqlite) works without a system sqlite3, so the sanctioned
# path is always available even when this guard cannot verify.
#
# DECOUPLING (§11.4.177): lives in the constitution submodule, inherited BY
# REFERENCE (never copied). Project-agnostic — the workable-items DB path
# `docs/workable_items.db` is a §11.4.93/§11.4.95 UNIVERSAL convention (not a
# project literal like a device serial); discovered relative to the git toplevel
# or overridable via $WI_DB.
#
# Classification: universal.

set -uo pipefail

PAYLOAD="$(cat || true)"

# --------------------------------------------------------------------------
# Extract a JSON string field WITHOUT requiring jq (prefer jq if present).
# Leaf keys we need: tool_name, command.
# --------------------------------------------------------------------------
json_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r "$path // empty" 2>/dev/null || true
    return 0
  fi
  local key
  case "$path" in
    .tool_name)             key="tool_name" ;;
    .tool_input.command)    key="command" ;;
    *)                      key="${path##*.}" ;;
  esac
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }
      rest = substr(rest, 2)
      out = ""
      i = 1
      n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nx = substr(rest, i+1, 1)
          if (nx == "n") out = out "\n"
          else if (nx == "t") out = out "\t"
          else if (nx == "r") out = out "\r"
          else if (nx == "\"") out = out "\""
          else if (nx == "\\") out = out "\\"
          else if (nx == "/") out = out "/"
          else out = out nx
          i += 2
          continue
        }
        if (c == "\"") break
        out = out c
        i += 1
      }
      printf "%s", out
    }
  '
}

TOOL_NAME="$(json_field .tool_name)"

# Only Bash carries a command string to inspect. Everything else passes through.
case "$TOOL_NAME" in
  Bash) ;;
  *) exit 0 ;;
esac

CMD="$(json_field .tool_input.command)"
[ -n "$CMD" ] || exit 0

# --------------------------------------------------------------------------
# Detect feature-branch CREATE forms + capture the target name(s).
# Strip quotes first so `git checkout -b 'feature/foo'` matches like the bare
# form. The three alternations below match ONLY create forms (a `-d`/`-D`
# delete breaks the `branch feature/` adjacency, so deletes are not captured).
# --------------------------------------------------------------------------
CMD_NOQUOTES="$(printf '%s' "$CMD" | tr -d "\"'")"

CREATE_RE='git[[:space:]]+checkout[[:space:]]+(-[bB]|--branch)[[:space:]]+feature/[A-Za-z0-9._/-]+|git[[:space:]]+switch[[:space:]]+(-[cC]|--create)[[:space:]]+feature/[A-Za-z0-9._/-]+|git[[:space:]]+branch[[:space:]]+(-f[[:space:]]+|--force[[:space:]]+)?feature/[A-Za-z0-9._/-]+'

CANDIDATES="$(printf '%s' "$CMD_NOQUOTES" | grep -oE "$CREATE_RE" 2>/dev/null | grep -oE 'feature/[A-Za-z0-9._/-]+' 2>/dev/null || true)"

# No feature-branch CREATE anywhere in this command -> not our business.
[ -n "$CANDIDATES" ] || exit 0

# --------------------------------------------------------------------------
# Sanctioned mint-helper invocation is always allowed (defensive: it never
# actually matches CREATE_RE, but an operator running the resolved form through
# the helper must never be blocked). `workable-items group branch ...`.
# --------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -qE 'workable-items[^|;&]*group[[:space:]]+branch([[:space:]]|$)' 2>/dev/null; then
  exit 0
fi

# --------------------------------------------------------------------------
# Documented-exception escape hatch (mirrors guard-forbidden-commands.sh):
# `# guardrails:allow <reason>` downgrades the block to an audited WARN.
# --------------------------------------------------------------------------
if [[ "$CMD" =~ \#[[:space:]]*guardrails:allow[[:space:]]+(.+) ]]; then
  echo "guardrails: feature-branch create allowed by documented exception: ${BASH_REMATCH[1]}" >&2
  exit 0
fi

# --------------------------------------------------------------------------
# Resolve the workable-items DB (registry SoT). $WI_DB overrides; else the
# §11.4.93/§11.4.95 convention path relative to the git toplevel or cwd.
# --------------------------------------------------------------------------
GIT_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
WI_DB_PATH=""
for _cand in \
    "${WI_DB:-}" \
    "${GIT_TOP:+$GIT_TOP/docs/workable_items.db}" \
    "docs/workable_items.db" \
    "${GIT_TOP:+$GIT_TOP/docs/.workable_items.db}" \
    "docs/.workable_items.db"; do
  [ -n "$_cand" ] || continue
  if [ -f "$_cand" ]; then WI_DB_PATH="$_cand"; break; fi
done

emit_block() {
  {
    echo "guardrails: BLOCKED — §11.4.181 feature-branch consistency (create-time)"
    echo "  Refused feature-branch CREATE for: $(printf '%s' "$CANDIDATES" | tr '\n' ' ')"
    echo "  Reason: $1"
    echo "  Use the ONLY sanctioned path — it resolves the canonical name from the"
    echo "  registry (never invents one), so a divergent name cannot happen:"
    echo "      workable-items group branch <group_id> --db docs/workable_items.db"
    echo "  (register the group first: workable-items group add <group_id> feature:<slug> <priority> --title <T> --db ...)"
    echo "  Genuine one-off exception: append '# guardrails:allow <reason>' to the command."
  } >&2
  exit 2
}

# FAIL-CLOSED when the registry cannot be read (§11.4.6 — never fail-open).
if ! command -v sqlite3 >/dev/null 2>&1; then
  emit_block "cannot verify the branch name against logic_groups (sqlite3 unavailable); a manual feature-branch create is blocked — the mint helper (CGO-bundled sqlite) works without system sqlite3."
fi
if [ -z "$WI_DB_PATH" ]; then
  emit_block "cannot verify the branch name against logic_groups (workable-items DB not found; set \$WI_DB or run from the project tree)."
fi

REGISTERED="$(sqlite3 "$WI_DB_PATH" "SELECT REPLACE(destination,'feature:','feature/') FROM logic_groups WHERE destination LIKE 'feature:%';" 2>/dev/null || true)"

UNREG=""
while IFS= read -r _name; do
  [ -n "$_name" ] || continue
  printf '%s\n' "$REGISTERED" | grep -qxF "$_name" || UNREG="${UNREG} ${_name}"
done <<EOF
$CANDIDATES
EOF

if [ -n "$UNREG" ]; then
  emit_block "the name(s)${UNREG} are NOT a registered logic_groups.destination (§11.4.181: one feature/group ⇒ exactly ONE canonical, registered branch name)."
fi

# Every captured name is a registered canonical destination → correct outcome.
exit 0
