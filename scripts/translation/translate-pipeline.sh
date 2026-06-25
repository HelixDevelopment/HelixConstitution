#!/usr/bin/env bash
# =============================================================================
# translate-pipeline.sh — Universal, reusable Markdown translation pipeline.
#
# Translates a Markdown file to Russian (ru) or Serbian (sr) using the
# HelixTranslate "unified-translator" engine. Two modes:
#
#   * plain  (default): translate the WHOLE file.
#   * article (--article): the source has YAML frontmatter
#                 ( ---\n key: val ...\n--- ) followed by a body. The
#                 frontmatter is kept BYTE-IDENTICAL (slugs/repos/tech/title/
#                 teaser are proper nouns / URLs / language-neutral and must
#                 survive so links + rendering keep working). ONLY the body
#                 (everything after the closing '---') is translated; then the
#                 output is reassembled as: original-frontmatter + translated-body.
#
# Language -> script mapping:
#   ru -> cyrillic    sr -> latin
#
# Engine + provider (verified working, with balance):
#   provider groq, model llama-3.3-70b-versatile.
#   On rate-limit / error: retry up to 3x with backoff, then fall back to
#   provider mistral, model mistral-large-latest. The provider that actually
#   produced the output is recorded in the per-file log.
#
# Idempotent + re-runnable: each invocation recomputes the output from the
# source and overwrites the destination. Logs (evidence) are appended per run
# under _tests/evidence/translate/.
#
# Usage:
#   translate-pipeline.sh --in <src.md> --out <dst.md> --lang <ru|sr> [--article]
#
# Exit status: 0 on a real, engine-produced translation; non-zero on failure
# (the destination is NOT written on failure, so callers can detect it).
# =============================================================================
set -euo pipefail

# ---- Configuration ----------------------------------------------------------
ENGINE="${HELIX_TRANSLATE_BIN:-/Volumes/T7/Projects/helix_translate/build/unified-translator}"
EVIDENCE_DIR="${TRANSLATE_EVIDENCE_DIR:-/Volumes/T7/Projects/vasic/_tests/evidence/translate}"
SOURCE_LANG="en"
PRIMARY_PROVIDER="groq"
PRIMARY_MODEL="llama-3.3-70b-versatile"
FALLBACK_PROVIDER="mistral"
FALLBACK_MODEL="mistral-large-latest"
MAX_RETRIES=3

# ---- Arg parsing ------------------------------------------------------------
IN="" OUT="" LANG="" ARTICLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --in)      IN="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    --lang)    LANG="$2"; shift 2 ;;
    --article) ARTICLE=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$IN" ]   || { echo "ERROR: --in required" >&2; exit 2; }
[ -n "$OUT" ]  || { echo "ERROR: --out required" >&2; exit 2; }
[ -n "$LANG" ] || { echo "ERROR: --lang required" >&2; exit 2; }
[ -f "$IN" ]   || { echo "ERROR: input not found: $IN" >&2; exit 2; }
[ -x "$ENGINE" ] || { echo "ERROR: engine not executable: $ENGINE" >&2; exit 2; }

case "$LANG" in
  ru) SCRIPT="cyrillic" ;;
  sr) SCRIPT="latin" ;;
  *)  echo "ERROR: --lang must be ru or sr (got: $LANG)" >&2; exit 2 ;;
esac

mkdir -p "$EVIDENCE_DIR"
ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
LOG="$EVIDENCE_DIR/$(basename "${OUT%.md}").${LANG}.log"

log() { echo "[$(ts)] $*" | tee -a "$LOG" >&2; }

log "=== translate-pipeline run ==="
log "in=$IN out=$OUT lang=$LANG script=$SCRIPT article=$ARTICLE"

# ---- Engine call with retry + fallback --------------------------------------
# run_engine <in_file> <out_file>  -> sets PROVIDER_USED on success
PROVIDER_USED=""
run_engine() {
  local in_f="$1" out_f="$2"
  local attempt provider model
  # Primary provider with retries, then fallback.
  for provider_pair in "$PRIMARY_PROVIDER:$PRIMARY_MODEL" "$FALLBACK_PROVIDER:$FALLBACK_MODEL"; do
    provider="${provider_pair%%:*}"; model="${provider_pair##*:}"
    attempt=1
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
      log "engine attempt: provider=$provider model=$model try=$attempt/$MAX_RETRIES"
      rm -f "$out_f"
      if "$ENGINE" -i "$in_f" -o "$out_f" \
            -provider "$provider" -model "$model" \
            -source-lang "$SOURCE_LANG" -target-lang "$LANG" -script "$SCRIPT" \
            >>"$LOG" 2>&1 && [ -s "$out_f" ]; then
        PROVIDER_USED="$provider:$model"
        log "engine SUCCESS via $PROVIDER_USED (output $(wc -c <"$out_f") bytes)"
        return 0
      fi
      log "engine FAILED (provider=$provider try=$attempt)"
      sleep $(( attempt * 5 ))   # linear backoff: 5s,10s,15s
      attempt=$(( attempt + 1 ))
    done
    log "provider=$provider exhausted; trying next provider"
  done
  return 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "$ARTICLE" -eq 1 ]; then
  # ---- Article mode: split frontmatter (byte-identical) + body --------------
  # Frontmatter is the first '---' line through the next '---' line.
  if [ "$(head -1 "$IN")" != "---" ]; then
    log "ERROR: --article given but no leading '---' frontmatter in $IN"
    echo "ERROR: $IN has no YAML frontmatter" >&2
    exit 3
  fi
  # Byte offset of the SECOND '---' line's end (closing fence).
  # Extract frontmatter (inclusive of both fences) and body separately.
  awk 'BEGIN{f=0} NR==1{print;f=1;next} f==1{print; if($0=="---"){exit}}' "$IN" > "$TMP_DIR/front.md"
  # Body = everything after the closing fence.
  awk 'BEGIN{s=0} s==2{print} /^---[[:space:]]*$/{s++}' "$IN" > "$TMP_DIR/body.md"

  if [ ! -s "$TMP_DIR/body.md" ]; then
    log "ERROR: empty body extracted from $IN"
    echo "ERROR: empty body for $IN" >&2
    exit 3
  fi

  if ! run_engine "$TMP_DIR/body.md" "$TMP_DIR/body.out.md"; then
    log "TRANSLATION FAILED for $IN -> $OUT (all providers exhausted)"
    echo "TRANSLATION FAILED: $IN" >&2
    exit 1
  fi

  # Reassemble: original frontmatter + blank line + translated body.
  mkdir -p "$(dirname "$OUT")"
  { cat "$TMP_DIR/front.md"; echo; cat "$TMP_DIR/body.out.md"; } > "$OUT"
  log "wrote $OUT (frontmatter preserved + translated body) provider=$PROVIDER_USED"
else
  # ---- Plain mode: translate whole file -------------------------------------
  if ! run_engine "$IN" "$TMP_DIR/whole.out.md"; then
    log "TRANSLATION FAILED for $IN -> $OUT (all providers exhausted)"
    echo "TRANSLATION FAILED: $IN" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$OUT")"
  cp "$TMP_DIR/whole.out.md" "$OUT"
  log "wrote $OUT (whole file) provider=$PROVIDER_USED"
fi

# Emit provider used to stdout for the driver to capture.
echo "PROVIDER_USED=$PROVIDER_USED OUT=$OUT"
log "=== done ==="
