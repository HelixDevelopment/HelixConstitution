#!/usr/bin/env bash
# Independent per-language translation REVIEW driver (HelixConstitution mandate).
# For each translated article in <site>/_article_src/<lang>/, runs an independent
# reviewer model (different from the translator) against the English source and
# records a strict PASS/FAIL/ERROR verdict + evidence JSON. Aggregates a report.
#
# Usage: review-translations.sh <site-root> <lang> [<lang> ...]
# Env:   REVIEW_PROVIDER (default groq), REVIEW_MODEL (optional)
set -uo pipefail
PY=/Volumes/T7/Projects/vasic/_tools/review_translation.py
root="${1:?site-root required}"; shift
site="$(basename "$root")"
EVID="/Volumes/T7/Projects/vasic/_tests/evidence/translate/review/$site"
REPORT="$EVID/REVIEW-REPORT.md"
mkdir -p "$EVID"
PROV="${REVIEW_PROVIDER:-groq}"
echo "# Translation review — $site (independent reviewer: $PROV)" > "$REPORT"
echo "" >> "$REPORT"; echo "| lang | slug | verdict | acc | flu | comp | script | issues |" >> "$REPORT"
echo "|---|---|---|---|---|---|---|---|" >> "$REPORT"
pass=0; fail=0; err=0
for lang in "$@"; do
  for md in "$root/_article_src/$lang/"*.md; do
    [ -e "$md" ] || continue
    slug="$(basename "$md" .md)"
    src="$root/_article_src/en/$slug.md"
    [ -f "$src" ] || { echo "| $lang | $slug | ERROR(no-en-src) | | | | | |" >>"$REPORT"; err=$((err+1)); continue; }
    out="$EVID/$lang/$slug.json"
    json="$(REVIEW_PROVIDER="$PROV" python3 "$PY" --src "$src" --translated "$md" --lang "$lang" --article --out "$out" 2>/dev/null)"
    v=$(printf '%s' "$json" | python3 -c "import sys,json;d=json.load(sys.stdin);print('%s|%s|%s|%s|%s|%s|%s'%(d.get('verdict'),d.get('accuracy',''),d.get('fluency',''),d.get('completeness',''),d.get('script_ok',''),('; '.join(d.get('issues',[]))[:80]).replace('|','/'),''))" 2>/dev/null || echo "ERROR|||||parse|")
    IFS='|' read -r verdict acc flu comp scr iss _ <<<"$v"
    echo "| $lang | $slug | $verdict | $acc | $flu | $comp | $scr | $iss |" >>"$REPORT"
    case "$verdict" in PASS) pass=$((pass+1));; FAIL) fail=$((fail+1));; *) err=$((err+1));; esac
  done
done
echo "" >> "$REPORT"
echo "**Totals: PASS=$pass FAIL=$fail ERROR=$err**" >> "$REPORT"
echo "REVIEW DONE site=$site PASS=$pass FAIL=$fail ERROR=$err -> $REPORT"
