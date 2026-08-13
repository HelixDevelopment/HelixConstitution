#!/usr/bin/env bash
# SOL-06 — anchor-block integrity checker (the propagation-gate SHAPE fix).
# A presence>=1 gate cannot see duplication or divergence (M13: two anchors
# duplicated verbatim-divergently in ALL FOUR mirrors while every propagation
# gate stayed GREEN). This gate counts BLOCK-STARTS per anchor per file and
# hashes block content across the lockstep set.
#
# Block-start STRUCTURE (never a bare literal — a citation is a carrier):
#   line begins  **§11.4.N —    or    ### §11.4.N
#
# Usage: anchor_integrity.sh <lockstep-file...>
# Exit: 0 clean | 1 findings (each named) | 2 blind
set -u
[ $# -ge 1 ] || { echo "usage: anchor_integrity.sh <file...>"; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FINDINGS=0

# Extract (anchor, block-hash) pairs per file. A block runs from its start line
# to the next block-start or EOF; content is whitespace-normalized before hashing.
extract() { # $1=file  -> writes "$T/<basename>.blocks" lines: anchor<TAB>hash
  awk '
    function flush() {
      if (cur != "") {
        gsub(/[ \t\n]+/, " ", buf)
        print cur "\t" buf
      }
      cur=""; buf=""
    }
    /^(\*\*|###[ ])?§11\.4\.[0-9]+/ {
      # structural start only: **§11.4.N — ...  or  ### §11.4.N
      # Anchor id captures the FULL dotted id incl. sub-anchors (§11.4.10.A):
      # the live run proved a bare-prefix match false-flags §11.4.10.A as a
      # duplicate of §11.4.10 — the §11.4.201(1) false-positive class.
      if ($0 ~ /^\*\*§11\.4\.[0-9]+(\.[A-Za-z0-9]+)* —/ || $0 ~ /^### §11\.4\.[0-9]+(\.[A-Za-z0-9]+)*/) {
        flush()
        match($0, /§11\.4\.[0-9]+(\.[A-Za-z0-9]+)*/)
        cur = substr($0, RSTART, RLENGTH)
        buf = $0
        next
      }
    }
    { if (cur != "") buf = buf "\n" $0 }
    END { flush() }
  ' "$1"
}

declare -A SEEN_HASH SEEN_FILE
for f in "$@"; do
  [ -r "$f" ] || { echo "BLIND: cannot read $f"; exit 2; }
  b="$T/$(basename "$f").blocks"
  extract "$f" > "$b"
  # Per-file duplicate block-starts
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    echo "DUPLICATE-BLOCK: $a appears as a block-start more than once in $f"
    FINDINGS=$((FINDINGS+1))
  done < <(cut -f1 "$b" | sort | uniq -d)
  # Cross-file divergence over the lockstep set
  while IFS=$'\t' read -r a body; do
    [ -n "$a" ] || continue
    h=$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)
    if [ -n "${SEEN_HASH[$a]:-}" ] && [ "${SEEN_HASH[$a]}" != "$h" ]; then
      echo "DIVERGENT-MIRRORS: $a differs between ${SEEN_FILE[$a]} and $f"
      FINDINGS=$((FINDINGS+1))
    else
      SEEN_HASH[$a]="$h"; SEEN_FILE[$a]="$f"
    fi
  done < "$b"
done

# Control needle: if NO block was extracted from ANY input, the extractor may be
# blind (dialect/anchoring) — report blindness, never a clean pass (§11.4.201(7)(b)).
total_blocks=$(cat "$T"/*.blocks 2>/dev/null | grep -c . || true)
if [ "${total_blocks:-0}" -eq 0 ]; then
  echo "BLIND-OR-EMPTY: zero anchor blocks extracted from $# file(s) — a clean verdict over nothing certifies nothing"
  exit 2
fi

echo "ANCHOR-INTEGRITY: files=$# blocks=$total_blocks findings=$FINDINGS"
[ "$FINDINGS" -eq 0 ]
