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
if [ -z "$CMD" ]; then
  # FAIL-CLOSED on our OWN parse failure (§11.4.6 — never allow-because-
  # unverifiable; contrast the DB-unreadable hard block below). If the payload
  # DOES carry a non-empty command field we failed to extract (jq absent + the
  # awk fallback mis-parses), fall back to the raw payload text: BLOCK only when
  # it shows a feature/* branch-create shape we could not parse; a non-create
  # unparseable Bash call is still allowed (bounded availability). A genuinely
  # absent / empty command field passes through.
  if printf '%s' "$PAYLOAD" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]'; then
    if printf '%s' "$PAYLOAD" | grep -qE 'git[^"]*(checkout[[:space:]]+-[bB]|checkout[[:space:]]+--branch|switch[[:space:]]+-[cC]|switch[[:space:]]+--create|branch|worktree[[:space:]]+add|fetch|push)[^"]*feature/'; then
      echo "guardrails: BLOCKED — §11.4.181: a Bash command containing a possible feature/* branch create could not be parsed for verification (fail-closed, §11.4.6). Re-issue via 'workable-items group branch <group_id>' or append '# guardrails:allow <reason>'." >&2
      exit 2
    fi
  fi
  exit 0
fi

# --------------------------------------------------------------------------
# Detect feature-branch CREATE forms + capture the target name(s).
# INTENT-aware (NOT a raw whole-text scan): the command is split into shell
# segments (on ; && || | and newlines); a create form is honoured ONLY when the
# segment's executable is `git` — so `echo …` / `grep …` / a leading `#` comment
# that merely MENTIONS a create no longer over-blocks. Covered create forms are
# broadened to close the argv-vs-text bypass: checkout -b/-B/--branch, switch
# -c/-C/--create, branch [-f] <name>, `worktree add … -b <name>`, and fetch/push
# refspec `SRC:[refs/heads/]feature/…` creates (a bare-src `:dst` delete refspec
# is excluded). Two fail-closed cases (§11.4.6) can never be resolved against the
# registry and so BLOCK: (a) a git-create whose NAME is a dynamic command-
# substitution / variable — `git checkout -b $(…)`; (b) a create embedded inside
# a `$(…)` / backtick substitution that WILL execute — `echo $(git checkout -b
# feature/x)`. Quotes are stripped first so `… 'feature/x'` matches the bare
# form. RESIDUAL (intended fail-safe, documented): because the quote strip loses
# quote context, a contrived MENTION that literally contains `$(git … feature/…)`
# inside quotes (e.g. `grep '$(git checkout -b feature/x)'`) fail-closes to BLOCK;
# clear it with `# guardrails:allow <reason>`. The L1/L2 DETECTIVE pre-build gate
# remains the backstop for anything argv-parsing misses.
# --------------------------------------------------------------------------
CMD_NOQUOTES="$(printf '%s' "$CMD" | tr -d "\"'")"

_bnc_detect() {
  printf '%s' "$1" | awk '
    function classify(name, seg) {
      if (name ~ /^feature\//) {
        gsub(/[^A-Za-z0-9._\/-].*$/, "", name)
        if (name != "") print "LIT " name
      } else if (name ~ /[$`]/ && seg ~ /feature\//) {
        print "DYN"
      }
    }
    function tokafter(seg, re,   rest, t) {
      if (match(seg, re)) {
        rest = substr(seg, RSTART + RLENGTH); sub(/^[ \t]+/, "", rest)
        t = rest; sub(/[ \t].*$/, "", t); return t
      }
      return ""
    }
    {
      # (b) create embedded in a substitution that WILL execute -> fail-closed
      if ($0 ~ /(\$\(|`)[^)`]*git[ \t]+(checkout[ \t]+-[bB]|checkout[ \t]+--branch|switch[ \t]+-[cC]|switch[ \t]+--create|branch[ \t]|worktree[ \t]+add|fetch[ \t]|push[ \t])[^)`]*feature\//)
        print "DYN"
      n = split($0, seg, /&&|\|\||;|\|/)
      for (i = 1; i <= n; i++) {
        s = seg[i]; sub(/^[ \t]+/, "", s)
        if (s ~ /^#/) continue
        chg = 1
        while (chg) {
          chg = 0
          if (s ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) { sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", s); chg = 1 }
          if (s ~ /^(sudo|env|command|nohup|time|nice|ionice)[ \t]+/) { sub(/^(sudo|env|command|nohup|time|nice|ionice)[ \t]+/, "", s); chg = 1 }
        }
        first = s; sub(/[ \t].*$/, "", first); sub(/^.*\//, "", first)
        if (first != "git") continue
        if (s ~ /^([^ \t]*\/)?git[ \t]+checkout[ \t]+(-[bB]|--branch)[ \t]/) {
          classify(tokafter(s, "checkout[ \t]+(-[bB]|--branch)[ \t]+"), s)
        } else if (s ~ /^([^ \t]*\/)?git[ \t]+switch[ \t]+(-[cC]|--create)[ \t]/) {
          classify(tokafter(s, "switch[ \t]+(-[cC]|--create)[ \t]+"), s)
        } else if (s ~ /^([^ \t]*\/)?git[ \t]+worktree[ \t]+add[ \t].*-[bB][ \t]/) {
          classify(tokafter(s, "-[bB][ \t]+"), s)
        } else if (s ~ /^([^ \t]*\/)?git[ \t]+branch([ \t]|$)/) {
          if (s ~ /[ \t](-d|-D|--delete|-m|-M|--move|-c|-C|--copy|--list|-a|--all|-r|--remotes|--merged|--no-merged|--contains|--points-at|--edit-description|--show-current|--set-upstream-to|-u|--unset-upstream|--track|--no-track)([ \t=]|$)/) continue
          bn = s; sub(/^([^ \t]*\/)?git[ \t]+branch[ \t]+/, "", bn)
          while (bn ~ /^(-f|--force)[ \t]/) sub(/^(-f|--force)[ \t]+/, "", bn)
          sub(/[ \t].*$/, "", bn)
          if (bn ~ /^-/) continue
          classify(bn, s)
        } else if (s ~ /^([^ \t]*\/)?git[ \t]+(fetch|push)([ \t]|$)/) {
          m = split(s, tk, /[ \t]+/)
          for (j = 2; j <= m; j++) {
            t = tk[j]; ci = index(t, ":")
            if (ci <= 1) continue
            dst = substr(t, ci + 1); sub(/^refs\/heads\//, "", dst)
            if (dst ~ /^feature\//) { gsub(/[^A-Za-z0-9._\/-].*$/, "", dst); if (dst != "") print "LIT " dst }
          }
        }
      }
    }'
}

_BNC_DETECT="$(_bnc_detect "$CMD_NOQUOTES")"
CANDIDATES="$(printf '%s\n' "$_BNC_DETECT" | sed -n 's/^LIT //p')"
BNC_UNVERIFIABLE=""
printf '%s\n' "$_BNC_DETECT" | grep -qx 'DYN' && BNC_UNVERIFIABLE=1

# No feature-branch CREATE anywhere in this command -> not our business.
[ -n "$CANDIDATES" ] || [ -n "$BNC_UNVERIFIABLE" ] || exit 0

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

# Unverifiable feature-branch create -> fail-closed (§11.4.6). A create whose
# name is a dynamic command-substitution / variable, OR a create embedded inside
# a will-execute $(…)/backtick substitution, cannot be resolved to a concrete
# name, so it cannot be proven registered. Blocked BEFORE the registry check
# (which has no name to look up). The sanctioned mint helper (line above) and the
# `# guardrails:allow` escape both run earlier, so a legitimate dynamic create
# still has an audited path.
if [ -n "$BNC_UNVERIFIABLE" ]; then
  emit_block "a feature/* branch is being created from a dynamic command-substitution / variable name (or inside a will-execute \$(…)/backtick substitution) that cannot be resolved and verified against the registry (§11.4.6 fail-closed)."
fi

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
