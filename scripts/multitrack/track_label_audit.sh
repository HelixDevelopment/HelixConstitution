#!/bin/sh
# =============================================================================
# constitution/scripts/multitrack/track_label_audit.sh
#
# Purpose:
#   Audit a documentation tree for STALE toolkit-alias work-stream labels of the
#   form `(T<N>/<branch> - <alias>)` (constitution §11.4.182, composing §11.4.178
#   track-qualified identity). A label whose `<alias>` field disagrees with the
#   LIVE alias (the toolkit currently driving this checkout) is a stale label — a
#   §11.4.182 correctness defect that a toolkit-alias switch would otherwise leave
#   behind unnoticed. This tool catches each such `file:line` so a future alias
#   switch never silently leaves wrong labels in the docs.
#
#   It is PROJECT-AGNOSTIC (§11.4.177): it hardcodes no project path, no track
#   layout, no alias set. It derives the live alias the same deterministic way
#   the reference labeler does (CLAUDE_CONFIG_DIR basename `.claude-<alias>`), and
#   takes the doc tree(s) to scan + the format-doc allowlist as arguments/data.
#   Consumers invoke it BY REFERENCE from the constitution submodule; it is never
#   copied into a project.
#
#   Format-illustration docs (guides / script-docs / research records that show
#   example labels of the FORMAT, not real work-stream labels) are EXCLUDED two
#   ways: (a) a header marker comment `track-label-audit: format-doc` anywhere in
#   the file, or (b) a path-substring match in an `--allowlist <file>`.
#
# Usage:
#   track_label_audit.sh [options] <dir-or-file> [<dir-or-file> ...]
#
# Options:
#   --live-alias <a>    Override the live alias (default: derived from
#                       CLAUDE_CONFIG_DIR; `?` if unset/non-matching).
#   --allowlist <file>  File of path substrings (one per line, `#` comments ok);
#                       any scanned file whose path contains a listed substring is
#                       treated as a format-doc and skipped.
#   --ext <ext>         File extension to scan, no dot (default: `md` — the
#                       source-of-truth; derived .html/.pdf/.docx are not scanned).
#   --marker <str>      Header marker literal that marks a file as a format-doc
#                       (default: `track-label-audit: format-doc`).
#   -h | --help         Show this header.
#
# Inputs:
#   env CLAUDE_CONFIG_DIR (read-only) — source of the live `<alias>` when
#       --live-alias is not given.
#   The positional roots to scan; the optional allowlist file.
#
# Outputs:
#   stdout — one `MISMATCH <file>:<line>: alias '<found>' != live '<live>'` line
#            per stale label, then a summary line. `OK` summary when clean.
#
# Exit status:
#   0  no stale labels found (clean), OR live alias is unknown/`?` (cannot audit —
#      reported honestly per §11.4.6, never a false PASS-by-guess).
#   1  one or more stale labels found.
#   2  usage error.
#
# Side-effects: none. Read-only. Never mutates a file, never hangs.
#
# Dependencies: POSIX sh, grep (ERE), sed.
#
# Cross-references:
#   constitution/Constitution.md §11.4.182 (+ §11.4.178 / §11.4.177 / §11.4.6)
#   scripts/multitrack/track_branch_label.sh (the reference labeler — same alias
#     derivation; this tool is its `--verify`/audit companion)
#   docs/guides/TRACK_BRANCH_LABELING.md (the convention; a format-doc)
# =============================================================================

set -u

_tla_usage() {
    sed -n '2,72p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
}

# --- Derive the live toolkit alias from CLAUDE_CONFIG_DIR basename
#     `.claude-<alias>` (same rule as track_branch_label.sh). Unset / non-match
#     -> `?` (honest unknown per §11.4.6, never fabricated). ---
_tla_live_alias() {
    _cd="${CLAUDE_CONFIG_DIR:-}"
    [ -n "$_cd" ] || { printf '%s' '?'; return; }
    _base="${_cd%/}"
    _base="${_base##*/}"
    case "$_base" in
        .claude-?*) printf '%s' "${_base#.claude-}" ;;
        *)          printf '%s' '?' ;;
    esac
}

LIVE_ALIAS=""
ALLOWLIST=""
EXT="md"
MARKER="track-label-audit: format-doc"
ROOTS=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)     _tla_usage; exit 0 ;;
        --live-alias)  shift; LIVE_ALIAS="${1:-}" ;;
        --allowlist)   shift; ALLOWLIST="${1:-}" ;;
        --ext)         shift; EXT="${1:-md}" ;;
        --marker)      shift; MARKER="${1:-$MARKER}" ;;
        --)            shift; while [ $# -gt 0 ]; do ROOTS="$ROOTS $1"; shift; done; break ;;
        -*)            printf 'track_label_audit: unknown option: %s\n' "$1" >&2; exit 2 ;;
        *)             ROOTS="$ROOTS $1" ;;
    esac
    shift
done

[ -n "$ROOTS" ] || { printf 'track_label_audit: no <dir-or-file> given\n' >&2; _tla_usage >&2; exit 2; }

[ -n "$LIVE_ALIAS" ] || LIVE_ALIAS="$(_tla_live_alias)"

if [ "$LIVE_ALIAS" = "?" ]; then
    printf 'track_label_audit: live alias UNKNOWN (CLAUDE_CONFIG_DIR unset or not .claude-*);\n'
    printf '  cannot audit alias correctness without a known live alias (per-11.4.6, no guessing).\n'
    printf '  Pass --live-alias <a> to force. Exiting 0 (no false PASS-by-guess).\n'
    exit 0
fi

# ERE for an alias-bearing work-stream label. The alias field is a bare
# identifier (letter then word chars) — a literal `<alias>` placeholder (starts
# with `<`) does NOT match, so format placeholders are naturally skipped.
LABEL_RE='\(T[0-9][0-9]*/[^)]*- [A-Za-z][A-Za-z0-9_]*\)'

# Is this file a format-doc? (header marker, or allowlist path-substring)
_tla_is_format_doc() {
    _f="$1"
    grep -qF "$MARKER" "$_f" 2>/dev/null && return 0
    [ -n "$ALLOWLIST" ] && [ -f "$ALLOWLIST" ] || return 1
    while IFS= read -r _pat; do
        case "$_pat" in ''|\#*) continue ;; esac
        case "$_f" in *"$_pat"*) return 0 ;; esac
    done < "$ALLOWLIST"
    return 1
}

# Enumerate candidate files across the roots.
_tla_files() {
    for _r in $ROOTS; do
        if [ -f "$_r" ]; then
            printf '%s\n' "$_r"
        elif [ -d "$_r" ]; then
            find "$_r" -type f -name "*.$EXT" 2>/dev/null
        fi
    done
}

mismatches=0
scanned=0
skipped=0

for f in $(_tla_files); do
    [ -f "$f" ] || continue
    if _tla_is_format_doc "$f"; then
        skipped=$((skipped + 1))
        continue
    fi
    scanned=$((scanned + 1))
    # Each matching line may carry >=1 label; check every label's alias.
    grep -nE "$LABEL_RE" "$f" 2>/dev/null | while IFS= read -r hit; do
        lineno="${hit%%:*}"
        # Extract every label token on the line, one per line of output.
        printf '%s\n' "$hit" | grep -oE "$LABEL_RE" | while IFS= read -r label; do
            found="$(printf '%s' "$label" | sed -E 's/^.*- ([A-Za-z][A-Za-z0-9_]*)\)$/\1/')"
            if [ "$found" != "$LIVE_ALIAS" ]; then
                printf "MISMATCH %s:%s: alias '%s' != live '%s'  [%s]\n" \
                    "$f" "$lineno" "$found" "$LIVE_ALIAS" "$label"
            fi
        done
    done
    # Re-count mismatches for this file for the exit code (subshell above cannot
    # mutate $mismatches). Count real mismatches directly.
    _fmm="$(grep -oE "$LABEL_RE" "$f" 2>/dev/null | sed -E 's/^.*- ([A-Za-z][A-Za-z0-9_]*)\)$/\1/' | grep -vxF "$LIVE_ALIAS" | wc -l | tr -d ' ')"
    mismatches=$((mismatches + _fmm))
done

printf -- '---\n'
printf 'track_label_audit: live alias = %s | scanned %s file(s) (.%s) | format-docs skipped %s | stale labels %s\n' \
    "$LIVE_ALIAS" "$scanned" "$EXT" "$skipped" "$mismatches"

[ "$mismatches" -eq 0 ] && { printf 'OK: no stale alias labels.\n'; exit 0; }
printf 'FAIL: %s stale alias label(s) disagree with live alias %s.\n' "$mismatches" "$LIVE_ALIAS"
exit 1
