#!/usr/bin/env bash
# =============================================================================
# multitrack_registry.sh — safe GET/SET accessor for the multi-track stream
#                          registry (.ws_state/streams.tsv) with flock
#                          serialization (§11.4.167 K / §11.4.116 / §9.2 / §11.4.6).
# -----------------------------------------------------------------------------
# Purpose:
#   Small, robust, dependency-light helper that reads and writes INDIVIDUAL
#   columns of the multi-track registry TSV (.ws_state/streams.tsv — the
#   §11.4.167 K "is this track owed / what state is it in?" single source of
#   truth) under an flock so concurrent multi-track streams never corrupt it.
#   It NEVER mounts / unmounts / formats a drive and NEVER touches a physical
#   NVMe device — it only edits the plain-text registry row.
#
#   SET is restricted to the four MUTABLE state columns
#   (mount_state / ws_state / last_main_merge / merge_approved) so a caller can
#   never clobber a track's IDENTITY columns (track / role / branch /
#   drive_serial / mount) by accident (§11.4.133 fail-safe). GET / row read any
#   named column.
#
# Usage:
#   multitrack_registry.sh get      <track> <column>
#   multitrack_registry.sh set      <track> <column> <value>
#   multitrack_registry.sh row      <track>
#   multitrack_registry.sh tracks
#   multitrack_registry.sh columns
#   multitrack_registry.sh help
#
#   Columns : track role branch drive_serial mount prep_state mount_state
#             ws_state last_main_merge merge_approved notes
#   SET-able : mount_state ws_state last_main_merge merge_approved
#
# Inputs:
#   Env MT_STREAMS_TSV    registry path (default <repo>/.ws_state/streams.tsv)
#   Env MT_REPO_ROOT      repo-root override (default: resolved from script dir)
#   Env MT_REGISTRY_LOCK  flock target (default runtime tmpfs path — keeps the
#                         tracked working tree clean; ephemeral like the device
#                         leases documented in .ws_state/README.md)
#   Env MT_LOCK_WAIT      flock -w seconds (default 10)
#
# Outputs:
#   get -> the column value on stdout (exit 0). set -> a confirmation line.
#   row -> the whole tab-separated row. tracks / columns -> one per line.
#
# Exit codes: 0 ok · 2 usage · 3 track-not-found · 4 unknown/forbidden column ·
#             5 malformed value (tab / newline / empty) · 1 internal error.
#
# Side-effects:
#   SET rewrites MT_STREAMS_TSV ATOMICALLY (temp + mv), preserving comments,
#   column order, and every non-target row byte-for-byte. Creates the flock file
#   (runtime tmpfs by default) — NEVER writes under the repo unless
#   MT_REGISTRY_LOCK is pointed there. NEVER a device, NEVER a disk.
#
# Dependencies: bash (POSIX-clean body), awk, mv, mkdir, wc, tr; flock (OPTIONAL
#   — degrades to unlocked single-process operation with a stderr warning if
#   absent, so a plain GET never hard-fails on a host without util-linux).
#
# Cross-references:
#   .ws_state/streams.tsv (schema header) · .ws_state/README.md ·
#   scripts/multitrack/multitrack.sh (the entrypoint that consumes this) ·
#   docs/scripts/multitrack.md · §11.4.167 feature work-stream lifecycle.
# =============================================================================

set -euo pipefail

REG_SELF=$0
case "$REG_SELF" in
    */*) REG_DIR=${REG_SELF%/*} ;;
    *)   REG_DIR=. ;;
esac

REPO_ROOT=${MT_REPO_ROOT:-$(cd "$REG_DIR/../.." 2>/dev/null && pwd || printf '.')}
MT_STREAMS_TSV=${MT_STREAMS_TSV:-$REPO_ROOT/.ws_state/streams.tsv}
MT_REGISTRY_LOCK=${MT_REGISTRY_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/$(basename "$REPO_ROOT")/multitrack/registry.lock}
MT_LOCK_WAIT=${MT_LOCK_WAIT:-10}
REG_TAB=$(printf '\t')

# canonical column order — MUST match the .ws_state/streams.tsv header row.
REG_COLUMNS="track role branch drive_serial mount prep_state mount_state ws_state last_main_merge merge_approved notes"
REG_SETTABLE="mount_state ws_state last_main_merge merge_approved"

_die() { echo "multitrack_registry: $1" >&2; exit "${2:-1}"; }

usage() {
cat <<'EOF'
multitrack_registry.sh — flock-guarded accessor for .ws_state/streams.tsv

  get <track> <column>          print a column value (any known column)
  set <track> <column> <value>  set a MUTABLE column (atomic; flock-guarded)
  row <track>                   print the whole tab-separated row
  tracks                        list track ids
  columns                       list column names
  help

  Columns  : track role branch drive_serial mount prep_state mount_state
             ws_state last_main_merge merge_approved notes
  SET-able : mount_state ws_state last_main_merge merge_approved

Env : MT_STREAMS_TSV  MT_REPO_ROOT  MT_REGISTRY_LOCK  MT_LOCK_WAIT
Exit: 0 ok · 2 usage · 3 no-such-track · 4 bad/forbidden column · 5 bad value · 1 error
EOF
}

# column name -> 1-based index on stdout (0 = unknown). Never fails.
_col_index() {
    _ci_want=$1; _ci_i=0; _ci_out=0
    for _ci_c in $REG_COLUMNS; do
        _ci_i=$((_ci_i + 1))
        if [ "$_ci_c" = "$_ci_want" ]; then _ci_out=$_ci_i; break; fi
    done
    printf '%s' "$_ci_out"
}

_is_settable() {
    for _st_c in $REG_SETTABLE; do
        [ "$_st_c" = "$1" ] && return 0
    done
    return 1
}

_ensure_lock() {
    _el_dir=${MT_REGISTRY_LOCK%/*}
    [ "$_el_dir" = "$MT_REGISTRY_LOCK" ] && _el_dir=.
    mkdir -p "$_el_dir" 2>/dev/null || true
    [ -e "$MT_REGISTRY_LOCK" ] || : > "$MT_REGISTRY_LOCK" 2>/dev/null || true
}

# Run "$@" while holding the registry flock. Degrades to an UNLOCKED run (with a
# stderr warning) if flock is unavailable or the lock file cannot be created —
# a plain GET must never hard-fail merely because util-linux is missing.
_run_locked() {
    _ensure_lock
    if command -v flock >/dev/null 2>&1 && [ -e "$MT_REGISTRY_LOCK" ]; then
        {
            flock -w "$MT_LOCK_WAIT" 9 || _die "registry lock busy (waited ${MT_LOCK_WAIT}s)" 1
            "$@"
        } 9<"$MT_REGISTRY_LOCK"
    else
        [ -e "$MT_REGISTRY_LOCK" ] || \
            echo "multitrack_registry: WARNING no lock file '$MT_REGISTRY_LOCK' — running UNLOCKED" >&2
        "$@"
    fi
}

cmd_get() {
    [ -r "$MT_STREAMS_TSV" ] || _die "registry not readable: $MT_STREAMS_TSV" 1
    _g_track=$1; _g_col=$2
    _g_ci=$(_col_index "$_g_col")
    [ "$_g_ci" -ne 0 ] || _die "unknown column '$_g_col' (known: $REG_COLUMNS)" 4
    _g_out=$(awk -F'\t' -v t="$_g_track" -v c="$_g_ci" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==t { print $c; found=1; exit }
        END   { if (!found) exit 7 }
    ' "$MT_STREAMS_TSV") || _die "track '$_g_track' not found in $MT_STREAMS_TSV" 3
    printf '%s\n' "$_g_out"
}

cmd_row() {
    [ -r "$MT_STREAMS_TSV" ] || _die "registry not readable: $MT_STREAMS_TSV" 1
    _r_track=$1
    _r_out=$(awk -F'\t' -v t="$_r_track" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==t { print; found=1; exit }
        END   { if (!found) exit 7 }
    ' "$MT_STREAMS_TSV") || _die "track '$_r_track' not found in $MT_STREAMS_TSV" 3
    printf '%s\n' "$_r_out"
}

cmd_tracks() {
    [ -r "$MT_STREAMS_TSV" ] || _die "registry not readable: $MT_STREAMS_TSV" 1
    awk -F'\t' '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { print $1 }
    ' "$MT_STREAMS_TSV"
}

cmd_columns() {
    printf '%s\n' "$REG_COLUMNS" | tr ' ' '\n'
}

cmd_set() {
    [ -r "$MT_STREAMS_TSV" ] || _die "registry not readable: $MT_STREAMS_TSV" 1
    _s_track=$1; _s_col=$2; _s_val=$3
    _is_settable "$_s_col" || _die "column '$_s_col' is NOT set-able (allowed: $REG_SETTABLE)" 4
    [ -n "$_s_val" ] || _die "empty value rejected (use an explicit token)" 5
    case "$_s_val" in
        *"$REG_TAB"*) _die "value contains a TAB — would corrupt the TSV" 5 ;;
    esac
    if [ "$(printf '%s' "$_s_val" | wc -l | tr -d ' ')" != "0" ]; then
        _die "value contains a newline — rejected" 5
    fi
    _s_ci=$(_col_index "$_s_col")
    _s_dir=${MT_STREAMS_TSV%/*}
    [ "$_s_dir" = "$MT_STREAMS_TSV" ] && _s_dir=.
    [ -w "$MT_STREAMS_TSV" ] || _die "registry file not writable: $MT_STREAMS_TSV" 1
    [ -w "$_s_dir" ]         || _die "registry directory not writable: $_s_dir" 1
    _s_tmp="$MT_STREAMS_TSV.reg.$$"
    # Atomic rewrite: comments + blank lines + non-target rows print verbatim
    # ($0 is only rebuilt for the matched row, whose single field we reassign).
    if ! awk -F'\t' -v OFS='\t' -v t="$_s_track" -v c="$_s_ci" -v val="$_s_val" '
        /^[[:space:]]*#/ { print; next }
        /^[[:space:]]*$/ { print; next }
        $1==t { $c=val; found=1 }
        { print }
        END { if (!found) exit 7 }
    ' "$MT_STREAMS_TSV" > "$_s_tmp"; then
        rm -f "$_s_tmp"
        _die "track '$_s_track' not found in $MT_STREAMS_TSV (nothing set)" 3
    fi
    chmod --reference="$MT_STREAMS_TSV" "$_s_tmp" 2>/dev/null || true
    mv -f "$_s_tmp" "$MT_STREAMS_TSV"
    printf 'SET %s.%s = %s\n' "$_s_track" "$_s_col" "$_s_val"
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
REG_CMD=$1; shift
case "$REG_CMD" in
    get)     [ $# -eq 2 ] || _die "usage: get <track> <column>" 2;         _run_locked cmd_get "$@" ;;
    set)     [ $# -eq 3 ] || _die "usage: set <track> <column> <value>" 2; _run_locked cmd_set "$@" ;;
    row)     [ $# -eq 1 ] || _die "usage: row <track>" 2;                  _run_locked cmd_row "$@" ;;
    tracks)  [ $# -eq 0 ] || _die "usage: tracks" 2;                       _run_locked cmd_tracks ;;
    columns) cmd_columns ;;
    help|--help|-h) usage ;;
    *) echo "multitrack_registry: unknown command '$REG_CMD'" >&2; usage >&2; exit 2 ;;
esac
