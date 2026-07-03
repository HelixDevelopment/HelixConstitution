#!/usr/bin/env bash
#
# search_requests.sh
# -----------------------------------------------------------------------------
# Search every Claude Code prompt ever executed for THIS project and save the
# matches (as full, multi-line prompts) to a Markdown report.
#
# Location (fixed):  <project-root>/constitution/scripts/search_requests.sh
# Usage:             ./constitution/scripts/search_requests.sh "SEARCH STRING"
# Output:            <project-root>/docs/requests/search/<snake_case_query>/Results.md
#
# The search is a literal (case-sensitive) substring match — the query is NOT
# treated as a regex, so strings like "C++", "a.b" or "<tag>" are matched as-is.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- 0. Resolve the search string (all args joined, so quoting is optional) ---
if [[ $# -lt 1 || -z "${*// /}" ]]; then
  echo "Usage: $(basename "$0") \"search string\"" >&2
  echo "Searches all executed Claude Code prompts for this project." >&2
  exit 1
fi
QUERY="$*"

# --- 1. Locate the project root from THIS script's fixed location ------------
# Script always lives at <root>/constitution/scripts/, so root is two levels up.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- 2. Locate Claude Code's history (honour CLAUDE_CONFIG_DIR if set) -------
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# --- 3. Build the snake_case slug: letters, numbers and "_" only ------------
SLUG="$(printf '%s' "$QUERY" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//' \
        | cut -c1-100)"
[[ -z "$SLUG" ]] && SLUG="query"   # fallback if the query had no valid chars

OUT_DIR="$PROJECT_ROOT/docs/requests/search/$SLUG"
OUT_FILE="$OUT_DIR/Results.md"
mkdir -p "$OUT_DIR"

# --- 4. Pick an extraction engine: jq preferred, python3 as fallback --------
engine=""
if command -v jq >/dev/null 2>&1; then
  engine="jq"
elif command -v python3 >/dev/null 2>&1; then
  engine="python3"
else
  echo "Error: neither 'jq' nor 'python3' is available; cannot parse history." >&2
  echo "Install one, e.g.  sudo apt-get install jq  /  brew install jq" >&2
  exit 2
fi

# --- 5. Extract matching prompts into a temp body file ----------------------
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

if [[ -d "$PROJECTS_DIR" ]]; then
  if [[ "$engine" == "jq" ]]; then
    # -R: read each line as a raw string; -n + inputs: consume the whole stream.
    find "$PROJECTS_DIR" -type f -name '*.jsonl' -print0 \
      | xargs -0 cat 2>/dev/null \
      | jq -Rrn --arg root "$PROJECT_ROOT" --arg needle "$QUERY" '
          [ inputs
            | fromjson?
            | select(.type == "user"
                     and ((.cwd // "") == $root
                          or ((.cwd // "") | startswith($root + "/"))))
            | { ts:   (.timestamp // "unknown"),
                sid:  (.sessionId // "?"),
                text: ((.message.content) as $c
                       | if   ($c | type) == "string" then $c
                         elif ($c | type) == "array"  then
                              ($c | map(select(.type == "text") | .text) | join("\n"))
                         else "" end) }
            | select(.text | contains($needle))
          ]
          | sort_by(.ts)[]
          | "### " + .ts + "  \u00b7  session " + .sid + "\n\n" + .text + "\n"
        ' > "$BODY" || true
  else
    NEEDLE="$QUERY" ROOT="$PROJECT_ROOT" PROJECTS_DIR="$PROJECTS_DIR" \
    python3 - > "$BODY" <<'PY' || true
import json, glob, os

needle = os.environ["NEEDLE"]
root   = os.environ["ROOT"]
pdir   = os.environ["PROJECTS_DIR"]

rows = []
for f in glob.glob(os.path.join(pdir, "**", "*.jsonl"), recursive=True):
    try:
        fh = open(f, encoding="utf-8")
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("type") != "user":
                continue
            cwd = e.get("cwd", "") or ""
            if not (cwd == root or cwd.startswith(root + "/")):
                continue
            c = e.get("message", {}).get("content")
            if isinstance(c, str):
                text = c
            elif isinstance(c, list):
                text = "\n".join(b.get("text", "") for b in c
                                 if isinstance(b, dict) and b.get("type") == "text")
            else:
                text = ""
            if needle in text:
                rows.append((e.get("timestamp", "unknown"),
                             e.get("sessionId", "?"), text))

rows.sort(key=lambda r: r[0])
for ts, sid, text in rows:
    print(f"### {ts}  \u00b7  session {sid}\n\n{text}\n")
PY
  fi
fi

# --- 6. Assemble the final report -------------------------------------------
COUNT="$(grep -c '^### ' "$BODY" || true)"
GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "# Prompt search results"
  echo
  echo "- **Query:** \`${QUERY}\`"
  echo "- **Matches:** ${COUNT}"
  echo "- **Project:** ${PROJECT_ROOT}"
  echo "- **History source:** ${PROJECTS_DIR}"
  echo "- **Generated:** ${GENERATED}"
  echo
  echo "---"
  echo
  if [[ "${COUNT}" -gt 0 ]]; then
    cat "$BODY"
  else
    echo "_No matching prompts found in this project's history._"
  fi
} > "$OUT_FILE"

echo "Found ${COUNT} matching prompt(s)."
echo "Saved to: ${OUT_FILE}"
