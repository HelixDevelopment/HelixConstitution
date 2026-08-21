#!/usr/bin/env bash
# lib_claim_ledger.sh — shared claim-vs-reality LEDGER parsing engine
# (§11.4.266 — the ledger that enumerates every ADVERTISED capability as a row).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# One tabular parser shared by every §11.4.266 ledger gate, so the ledger's
# structural contract is defined ONCE and the sibling gates cannot drift apart
# (the same shape `lib_badge_row.sh` gives the three §11.4.259 badge gates).
#
# ── The structural contract this lib defines (and its honest boundary) ───────
# §11.4.266(B) fixes the bluff-type VOCABULARY verbatim and constitutionally.
# §11.4.266(A) and the anchor's Classification line leave the ledger's
# LOCATION and its row SHAPE to the consuming project as DATA (§11.4.35):
# "The corpus supplies no worked ledger row ... all three are consumer DATA".
#
# A type-checker cannot type a column it cannot find, so this lib declares the
# MINIMUM structural contract needed to check anything at all — deliberately
# the weakest one that still permits a STRUCTURAL (never substring) field
# read per §11.4.201(7)(a):
#
#   * the ledger is a header-bearing table, in EITHER tab-separated form OR
#     markdown pipe-table form (the two header-bearing tabular text formats
#     already used across this corpus's registries and summaries);
#   * the first non-blank, non-comment line is the HEADER naming the columns;
#   * `#`-prefixed and blank lines are inert; a markdown alignment row
#     (`|---|:--:|`) is inert;
#   * a column is addressed by its NORMALISED header name (lowercased, every
#     run of non-alphanumerics folded to `_`, leading/trailing `_` stripped).
#
# Anything looser cannot distinguish a row's TYPE cell from a row's NOTES cell,
# and a gate that cannot make that distinction is exactly the carrier-matching
# false-PASS §11.4.201(7)(a) forbids. A consumer whose ledger is neither form
# gets an honest BLIND (exit 2) from the calling gate — never a guessed green.
#
# ── Provided functions ───────────────────────────────────────────────────────
#   cl_norm_name <s>            -> normalised column name
#   cl_format <file>            -> tsv | md | empty | unknown
#   cl_rows <file>              -> normalised TSV (header first, cells trimmed)
#   cl_col_index <hdr> <alias>… -> 1-based column index, or empty if none match
#   cl_field <row> <index>      -> that row's cell (empty when short)
#   cl_control_needle           -> 0 iff the parser demonstrably SEES a known
#                                  ledger through this SAME code path
#                                  (§11.4.201(7)(b): a null is not evidence
#                                  until the instrument is proven to see)
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None, except `cl_control_needle`, which creates and removes its own
#   `mktemp` scratch file. Never writes to a caller-supplied path.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX awk + sed + tr. Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.266 (the ledger's mandate), §11.4.201(7)(a) structure-not-substring,
#   §11.4.201(7)(b) control needle, §11.4.35 (location + shape are consumer
#   DATA), lib_badge_row.sh (the sibling shared-engine precedent).
#
# Classification: universal (§11.4.17) — no project literal; every path is a
# caller-supplied argument.

# Deliberately `set -u` + `pipefail` WITHOUT `-e`: the calling gates walk every
# row and accumulate failures so the operator gets the COMPLETE per-row report.
# `-e` would abort that walk at the first non-zero probe and turn a full FAIL
# report into an opaque early exit — the §11.4.234(D) "opaque, not actionable"
# failure mode this corpus forbids. Every fallible call below is explicitly
# status-checked instead.
set -u
set -o pipefail

cl_norm_name() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//'
}

# cl__eligible: strips CR, drops blank + `#`-comment lines. Markdown alignment
# rows are dropped later (only meaningful once the format is known).
cl__eligible() {
    sed -e 's/\r$//' -- "$1" | awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        { print }
    '
}

cl_format() {
    local f="$1" first trimmed
    [ -r "$f" ] || { printf 'unknown'; return 0; }
    first="$(cl__eligible "$f" | awk 'NR==1{print; exit}')"
    if [ -z "$first" ]; then printf 'empty'; return 0; fi
    case "$first" in
        *"$(printf '\t')"*) printf 'tsv'; return 0 ;;
    esac
    trimmed="${first#"${first%%[![:space:]]*}"}"
    case "$trimmed" in
        '|'*) printf 'md'; return 0 ;;
    esac
    printf 'unknown'
}

# cl_rows <file>: normalised TSV on stdout — header line first, then data
# rows, every cell trimmed. Empty output means "no rows parsed"; the caller
# MUST needle before treating that as a real absence (§11.4.201(7)(b)).
cl_rows() {
    local f="$1" fmt
    fmt="$(cl_format "$f")"
    case "$fmt" in
        tsv)
            cl__eligible "$f" | awk -F '\t' '
                {
                    out = ""
                    for (i = 1; i <= NF; i++) {
                        c = $i
                        gsub(/^[[:space:]]+/, "", c); gsub(/[[:space:]]+$/, "", c)
                        out = (i == 1 ? c : out "\t" c)
                    }
                    print out
                }'
            ;;
        md)
            cl__eligible "$f" | awk '
                {
                    l = $0
                    t = l; gsub(/[[:space:]]/, "", t)
                    # markdown alignment row: only pipes, dashes and colons
                    if (t ~ /^\|?[-:|]+\|?$/) next
                    sub(/^[[:space:]]*\|/, "", l)
                    sub(/\|[[:space:]]*$/, "", l)
                    n = split(l, a, "|")
                    out = ""
                    for (i = 1; i <= n; i++) {
                        c = a[i]
                        gsub(/^[[:space:]]+/, "", c); gsub(/[[:space:]]+$/, "", c)
                        out = (i == 1 ? c : out "\t" c)
                    }
                    print out
                }'
            ;;
        *) : ;;
    esac
}

# cl_col_index <header-tsv-line> <alias> [<alias> ...] -> 1-based index.
# STRUCTURAL: matches the whole normalised header cell, never a substring, so
# a `challenge_notes` column can never be mistaken for `challenge`.
cl_col_index() {
    local hdr="$1"; shift
    local i=0 cell norm a n
    n="$(printf '%s' "$hdr" | awk -F '\t' '{print NF}')"
    [ -n "$n" ] || return 0
    while [ "$i" -lt "$n" ]; do
        i=$((i + 1))
        cell="$(printf '%s' "$hdr" | awk -F '\t' -v i="$i" '{ printf "%s", $i }')"
        norm="$(cl_norm_name "$cell")"
        for a in "$@"; do
            if [ "$norm" = "$a" ]; then printf '%s' "$i"; return 0; fi
        done
    done
    printf ''
}

cl_field() {
    local row="$1" idx="$2"
    [ -n "$idx" ] || { printf ''; return 0; }
    printf '%s' "$row" | awk -F '\t' -v i="$idx" '{ if (i <= NF) printf "%s", $i }'
}

# cl_control_needle: parses a KNOWN-present two-format fixture through the very
# same cl_rows()/cl_col_index() path the gate uses. Returns 0 only when both
# formats yield a header plus exactly one data row AND a named column resolves.
# A zero-row result from a real ledger is trustworthy only after this returns 0.
cl_control_needle() {
    local d hdr rows n idx rc=0
    d="$(mktemp -d)" || return 1
    printf 'capability\tbluff_type\tchallenge\n' > "$d/needle.tsv"
    printf 'needle-cap\tstubbed-core\ttests/needle.sh\n' >> "$d/needle.tsv"
    printf '| capability | bluff_type | challenge |\n' > "$d/needle.md"
    printf '|---|---|---|\n' >> "$d/needle.md"
    printf '| needle-cap | stubbed-core | tests/needle.sh |\n' >> "$d/needle.md"
    local f
    for f in "$d/needle.tsv" "$d/needle.md"; do
        rows="$(cl_rows "$f")"
        n="$(printf '%s\n' "$rows" | awk 'NF{c++} END{print c+0}')"
        [ "$n" = "2" ] || rc=1
        hdr="$(printf '%s\n' "$rows" | awk 'NR==1{print; exit}')"
        idx="$(cl_col_index "$hdr" bluff_type type)"
        [ -n "$idx" ] || rc=1
    done
    rm -rf "$d"
    return "$rc"
}
