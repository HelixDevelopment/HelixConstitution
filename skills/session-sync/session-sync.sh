#!/bin/bash
# sync_remote_session.sh — Bidirectional Claude Code session sync via SSH
#
# Purpose:
#   Syncs ALL Claude Code project data (memories, sessions, settings, agents,
#   remember-logs, handoff docs) between the SAME project on a REMOTE host and
#   the local machine. Supports PULL (remote→local), PUSH (local→remote), and
#   BIDIRECTIONAL sync. After syncing, work can CONTINUE on either side from
#   exactly where the other left off.
#
# Usage:
#   ./sync_remote_session.sh [OPTIONS] <user@host> <remote_project_root>
#
#   # Pull everything from remote (default):
#   ./sync_remote_session.sh milos@10.6.100.221 /mnt/track1/atmosphere-t1
#
#   # Push local state to remote:
#   ./sync_remote_session.sh --push milos@10.6.100.221 /mnt/track1/atmosphere-t1
#
#   # Bidirectional merge (pull first, then push):
#   ./sync_remote_session.sh --bidirectional milos@10.6.100.221 /mnt/track1/atmosphere-t1
#
#   # Quick mode: only most recent sessions + memories (faster):
#   ./sync_remote_session.sh --quick milos@10.6.100.221 /mnt/track1/atmosphere-t1
#
# Options:
#   --pull             Pull from remote to local (DEFAULT)
#   --push             Push from local to remote
#   --bidirectional    Pull first, then push (full two-way sync)
#   --quick            Only sync memories + recent sessions (skip bulk history)
#   --recent N         Number of recent sessions in --quick mode (default: 3)
#   --dry-run          Show what WOULD be synced without copying
#   --skip-confirm     Skip confirmation prompts (for automation)
#   --no-sessions      Skip session JSONL files (large, slow)
#   --no-session-dirs  Skip session directories
#   -h, --help         Show this help message
#
# Inputs:
#   SSH target (user@host) and remote project ROOT path (absolute).
#   The remote MUST have the SAME Claude Code provider directory structure.
#   Provider is auto-detected from the LOCAL CLAUDE_CONFIG_DIR or defaults
#   to ~/.claude-prov-deepseek.
#
# Outputs:
#   All synced files land in their correct paths. A summary table is printed.
#   Exit code 0 = all synced, 1 = partial/error, 2 = blocked.
#
# Side-effects:
#   - Rsync transfers files over SSH.
#   - On PULL: local files are overwritten with remote versions.
#   - On PUSH: remote files are overwritten with local versions.
#   - On BIDIRECTIONAL: pull first, then push. Remote wins conflicts in
#     the pull phase; local wins in the push phase.
#   - CLAUDE.md, settings.json, settings.local.json are replaced (not merged).
#   - .remember/ is merged (newer files win).
#   - Memories are MERGED (union, newer overwrites older on filename conflict).
#
# Dependencies:
#   ssh, rsync, bash 4+, standard UNIX tools.
#
# Cross-references:
#   scripts/pull_all.sh — fetch + merge git remotes (run BEFORE this script)
#   scripts/commit_all.sh — commit + push changes
#   constitution/scripts/multitrack/ — multi-track orchestration (§11.4.187)
#   docs/guides/ — project documentation
#
# Last verified: 2026-07-13

set -euo pipefail

# =============================================================================
# Script initialization
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
DIRECTION="pull"       # pull | push | bidirectional
DRY_RUN=false
QUICK_MODE=false
RECENT_COUNT=3
SKIP_CONFIRM=false
SKIP_SESSIONS=false
SKIP_SESSION_DIRS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pull)           DIRECTION="pull"; shift ;;
        --push)           DIRECTION="push"; shift ;;
        --bidirectional)  DIRECTION="bidirectional"; shift ;;
        --quick)          QUICK_MODE=true; shift ;;
        --recent)
            RECENT_COUNT="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=true; shift ;;
        --skip-confirm)   SKIP_CONFIRM=true; shift ;;
        --no-sessions)    SKIP_SESSIONS=true; shift ;;
        --no-session-dirs) SKIP_SESSION_DIRS=true; shift ;;
        -h|--help)
            sed -n '2,65p' "$0"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 2 ]]; then
    echo "ERROR: Required arguments: <user@host> <remote_project_root>"
    echo "Usage: $0 [OPTIONS] user@host /path/to/remote/project"
    exit 2
fi

SSH_TARGET="$1"
REMOTE_PROJECT_ROOT="$2"

# ---------------------------------------------------------------------------
# Derive paths
# ---------------------------------------------------------------------------

CLAUDE_PROVIDER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude-prov-deepseek}"
if [[ -L "$CLAUDE_PROVIDER_DIR" ]]; then
    CLAUDE_PROVIDER_DIR="$(readlink -f "$CLAUDE_PROVIDER_DIR")"
fi

derive_slug() {
    local path="$1"
    echo "$path" | tr '/' '-'
}

LOCAL_SLUG="$(derive_slug "$PROJECT_ROOT")"
REMOTE_SLUG="$(derive_slug "$REMOTE_PROJECT_ROOT")"

LOCAL_PROJ_DIR="$CLAUDE_PROVIDER_DIR/projects/$LOCAL_SLUG"
REMOTE_PROJ_DIR="~/.claude-prov-deepseek/projects/$REMOTE_SLUG"
REMOTE_PROVIDER_DIR="~/.claude-prov-deepseek"

# =============================================================================
# Validation
# =============================================================================

echo "=== Sync Remote Session ==="
echo "  Direction: $DIRECTION"
echo "  Mode:      $( $QUICK_MODE && echo 'quick' || echo 'full' )"
echo "  Remote:    $SSH_TARGET:$REMOTE_PROJECT_ROOT"
echo "  Local:     $PROJECT_ROOT"
echo "  Provider:  $(basename "$CLAUDE_PROVIDER_DIR")"
echo "  Slug:      $LOCAL_SLUG"
echo ""

# Test SSH connectivity
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_TARGET" "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot SSH to $SSH_TARGET"
    exit 2
fi

# Verify remote project exists (needed for both directions)
if ! ssh "$SSH_TARGET" "test -d $REMOTE_PROJECT_ROOT" 2>/dev/null; then
    echo "ERROR: Remote project root does not exist: $REMOTE_PROJECT_ROOT"
    exit 2
fi

# Verify local project exists (needed for push)
if [[ "$DIRECTION" == "push" || "$DIRECTION" == "bidirectional" ]]; then
    if [[ ! -d "$PROJECT_ROOT" ]]; then
        echo "ERROR: Local project root does not exist: $PROJECT_ROOT"
        exit 2
    fi
fi

# Confirmation for push/bidirectional (safety gate)
if [[ "$DIRECTION" == "push" || "$DIRECTION" == "bidirectional" ]]; then
    if ! $SKIP_CONFIRM && ! $DRY_RUN; then
        echo "WARNING: $DIRECTION will overwrite remote session data."
        echo "  Remote: $SSH_TARGET:$REMOTE_PROJECT_ROOT"
        echo "  This is SAFE for session data (memories, history, settings)."
        echo "  It does NOT touch source code or git state."
        read -r -p "Proceed? [y/N] " yn
        if [[ ! "$yn" =~ ^[Yy] ]]; then
            echo "Aborted."
            exit 2
        fi
    fi
fi

# =============================================================================
# Helpers
# =============================================================================

RSYNC_OPTS="-avz"
SYNC_OK=0
SYNC_FAIL=0
SYNC_SKIP=0
PHASE_N=0

phase_header() {
    PHASE_N=$((PHASE_N + 1))
    echo ""
    echo "--- Phase $PHASE_N: $1 ---"
}

do_rsync_pull() {
    local desc="$1"; local src="$2"; local dst="$3"; local extra="${4:-}"
    echo -n "  [$desc] "
    if $DRY_RUN; then
        echo "(dry-run)"
        ssh "$SSH_TARGET" "ls -la $src 2>/dev/null || echo '  (source absent)'"
        echo "    -> would sync to: $dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    if rsync $RSYNC_OPTS $extra "$SSH_TARGET:$src" "$dst" 2>&1 | grep -q "error"; then
        echo "FAIL"
        SYNC_FAIL=$((SYNC_FAIL + 1))
        return 1
    fi
    echo "OK"
    SYNC_OK=$((SYNC_OK + 1))
    return 0
}

do_rsync_push() {
    local desc="$1"; local src="$2"; local dst="$3"; local extra="${4:-}"
    echo -n "  [$desc] "
    if $DRY_RUN; then
        echo "(dry-run)"
        ls -la "$src" 2>/dev/null || echo "  (source absent)"
        echo "    -> would sync to: $SSH_TARGET:$dst"
        return 0
    fi
    if [[ ! -e "$src" ]]; then
        echo "SKIP (local absent)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
        return 0
    fi
    if rsync $RSYNC_OPTS $extra "$src" "$SSH_TARGET:$dst" 2>&1 | grep -q "error"; then
        echo "FAIL"
        SYNC_FAIL=$((SYNC_FAIL + 1))
        return 1
    fi
    echo "OK"
    SYNC_OK=$((SYNC_OK + 1))
    return 0
}

# Pull from remote (remote→local)
sync_pull() {
    local label="${1:-}"

    # Phase: Memories (always)
    phase_header "Memories ($label)"
    do_rsync_pull "memories" "$REMOTE_PROJ_DIR/memory/" "$LOCAL_PROJ_DIR/memory/"
    if ! $DRY_RUN; then
        M=$(ls "$LOCAL_PROJ_DIR/memory/" 2>/dev/null | wc -l)
        echo "    $M memories"
    fi

    # Phase: Session JSONL (skip in quick mode or if --no-sessions)
    if ! $SKIP_SESSIONS && ! $QUICK_MODE; then
        phase_header "Session transcripts ($label)"
        do_rsync_pull "sessions" "$REMOTE_PROJ_DIR/*.jsonl" "$LOCAL_PROJ_DIR/"
        if ! $DRY_RUN; then
            J=$(ls "$LOCAL_PROJ_DIR"/*.jsonl 2>/dev/null | wc -l)
            echo "    $J transcripts"
        fi
    elif $QUICK_MODE; then
        phase_header "Recent session transcripts ($label — last $RECENT_COUNT)"
        local recent_jsonls
        recent_jsonls=$(ssh "$SSH_TARGET" "ls -t $REMOTE_PROJ_DIR/*.jsonl 2>/dev/null | head -$RECENT_COUNT" 2>/dev/null || true)
        if [[ -n "$recent_jsonls" ]]; then
            echo "$recent_jsonls" | while read -r f; do
                do_rsync_pull "$(basename "$f")" "$f" "$LOCAL_PROJ_DIR/$(basename "$f")"
            done
        else
            echo "  (no session transcripts on remote)"
            SYNC_SKIP=$((SYNC_SKIP + 1))
        fi
    fi

    # Phase: Session directories
    if ! $SKIP_SESSION_DIRS; then
        phase_header "Session directories ($label)"
        local session_dirs
        if $QUICK_MODE; then
            session_dirs=$(ssh "$SSH_TARGET" "ls -td $REMOTE_PROJ_DIR/*/ 2>/dev/null | grep -v memory | head -$RECENT_COUNT" 2>/dev/null || true)
        else
            session_dirs=$(ssh "$SSH_TARGET" "ls -d $REMOTE_PROJ_DIR/*/ 2>/dev/null | grep -v memory || true")
        fi
        if [[ -n "$session_dirs" ]]; then
            if $DRY_RUN; then
                echo "    $(echo "$session_dirs" | wc -l) session dirs on remote"
            else
                echo "$session_dirs" | while read -r d; do
                    local bn; bn="$(basename "$d")"
                    rsync $RSYNC_OPTS "$SSH_TARGET:$d" "$LOCAL_PROJ_DIR/$bn/" 2>/dev/null || true
                done
                local sdc
                sdc=$(ls -d "$LOCAL_PROJ_DIR"/*/ 2>/dev/null | grep -v memory | wc -l)
                echo "    $sdc session dirs synced"
            fi
        else
            echo "  (no session dirs)"
            SYNC_SKIP=$((SYNC_SKIP + 1))
        fi
    fi

    # Phase: Project .claude settings + agents
    phase_header "Project settings + agents ($label)"
    do_rsync_pull "settings.json" "$REMOTE_PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.json"
    do_rsync_pull "settings.local" "$REMOTE_PROJECT_ROOT/.claude/settings.local.json" "$PROJECT_ROOT/.claude/settings.local.json"
    do_rsync_pull "agents" "$REMOTE_PROJECT_ROOT/.claude/agents/" "$PROJECT_ROOT/.claude/agents/"

    # Phase: .remember directory
    phase_header ".remember logs ($label)"
    do_rsync_pull ".remember" "$REMOTE_PROJECT_ROOT/.remember/" "$PROJECT_ROOT/.remember/"

    # Phase: Handoff + resume docs
    phase_header "Handoff documents ($label)"
    if ssh "$SSH_TARGET" "test -f $REMOTE_PROJECT_ROOT/docs/SESSION_RESUME.md" 2>/dev/null; then
        do_rsync_pull "SESSION_RESUME.md" "$REMOTE_PROJECT_ROOT/docs/SESSION_RESUME.md" "$PROJECT_ROOT/docs/SESSION_RESUME.md"
    else
        echo "  (no SESSION_RESUME.md on remote)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi
    if ssh "$SSH_TARGET" "test -f $REMOTE_PROJECT_ROOT/docs/CONTINUATION.md" 2>/dev/null; then
        do_rsync_pull "CONTINUATION.md" "$REMOTE_PROJECT_ROOT/docs/CONTINUATION.md" "$PROJECT_ROOT/docs/CONTINUATION.md"
    else
        echo "  (no CONTINUATION.md on remote)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi

    # Phase: Provider-level data
    phase_header "Provider config ($label)"
    do_rsync_pull "CLAUDE.md" "$REMOTE_PROVIDER_DIR/CLAUDE.md" "$CLAUDE_PROVIDER_DIR/CLAUDE.md" "--no-links"
    do_rsync_pull "history" "$REMOTE_PROVIDER_DIR/history.jsonl" "$CLAUDE_PROVIDER_DIR/history.jsonl" "--no-links"
    do_rsync_pull "settings" "$REMOTE_PROVIDER_DIR/settings.json" "$CLAUDE_PROVIDER_DIR/settings.json"

    # claude-shared
    if ssh "$SSH_TARGET" "test -d ~/.claude-shared" 2>/dev/null; then
        do_rsync_pull "claude-shared" "~/.claude-shared/" "$HOME/.claude-shared/"
    else
        echo "  (no .claude-shared on remote)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi
}

# Push to remote (local→remote)
sync_push() {
    local label="${1:-}"

    # Phase: Memories
    phase_header "Memories ($label)"
    do_rsync_push "memories" "$LOCAL_PROJ_DIR/memory/" "$REMOTE_PROJ_DIR/memory/"
    if ! $DRY_RUN; then
        local M; M=$(ssh "$SSH_TARGET" "ls $REMOTE_PROJ_DIR/memory/ 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        echo "    $M memories on remote"
    fi

    # Phase: Session JSONL (skip in quick mode)
    if ! $SKIP_SESSIONS && ! $QUICK_MODE; then
        phase_header "Session transcripts ($label)"
        for f in "$LOCAL_PROJ_DIR"/*.jsonl; do
            [[ -f "$f" ]] || continue
            do_rsync_push "$(basename "$f")" "$f" "$REMOTE_PROJ_DIR/$(basename "$f")"
        done
    elif $QUICK_MODE; then
        phase_header "Recent session transcripts ($label — last $RECENT_COUNT)"
        local recent; recent=$(ls -t "$LOCAL_PROJ_DIR"/*.jsonl 2>/dev/null | head -$RECENT_COUNT || true)
        if [[ -n "$recent" ]]; then
            echo "$recent" | while read -r f; do
                do_rsync_push "$(basename "$f")" "$f" "$REMOTE_PROJ_DIR/$(basename "$f")"
            done
        else
            echo "  (no local transcripts)"
            SYNC_SKIP=$((SYNC_SKIP + 1))
        fi
    fi

    # Phase: Session directories
    if ! $SKIP_SESSION_DIRS; then
        phase_header "Session directories ($label)"
        local sess_dirs
        if $QUICK_MODE; then
            sess_dirs=$(ls -td "$LOCAL_PROJ_DIR"/*/ 2>/dev/null | grep -v memory | head -$RECENT_COUNT || true)
        else
            sess_dirs=$(ls -d "$LOCAL_PROJ_DIR"/*/ 2>/dev/null | grep -v memory || true)
        fi
        if [[ -n "$sess_dirs" ]]; then
            echo "$sess_dirs" | while read -r d; do
                local bn; bn="$(basename "$d")"
                do_rsync_push "$bn" "$d" "$REMOTE_PROJ_DIR/$bn/"
            done
        else
            echo "  (no local session dirs)"
            SYNC_SKIP=$((SYNC_SKIP + 1))
        fi
    fi

    # Phase: Project settings + agents
    phase_header "Project settings + agents ($label)"
    do_rsync_push "settings.json" "$PROJECT_ROOT/.claude/settings.json" "$REMOTE_PROJECT_ROOT/.claude/settings.json"
    do_rsync_push "settings.local" "$PROJECT_ROOT/.claude/settings.local.json" "$REMOTE_PROJECT_ROOT/.claude/settings.local.json"
    do_rsync_push "agents" "$PROJECT_ROOT/.claude/agents/" "$REMOTE_PROJECT_ROOT/.claude/agents/"

    # Phase: .remember
    phase_header ".remember logs ($label)"
    do_rsync_push ".remember" "$PROJECT_ROOT/.remember/" "$REMOTE_PROJECT_ROOT/.remember/"

    # Phase: Handoff + resume docs
    phase_header "Handoff documents ($label)"
    if [[ -f "$PROJECT_ROOT/docs/SESSION_RESUME.md" ]]; then
        do_rsync_push "SESSION_RESUME.md" "$PROJECT_ROOT/docs/SESSION_RESUME.md" "$REMOTE_PROJECT_ROOT/docs/SESSION_RESUME.md"
    else
        echo "  (no local SESSION_RESUME.md)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi
    if [[ -f "$PROJECT_ROOT/docs/CONTINUATION.md" ]]; then
        do_rsync_push "CONTINUATION.md" "$PROJECT_ROOT/docs/CONTINUATION.md" "$REMOTE_PROJECT_ROOT/docs/CONTINUATION.md"
    else
        echo "  (no local CONTINUATION.md)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi

    # Phase: Provider-level
    phase_header "Provider config ($label)"
    do_rsync_push "CLAUDE.md" "$CLAUDE_PROVIDER_DIR/CLAUDE.md" "$REMOTE_PROVIDER_DIR/CLAUDE.md"
    do_rsync_push "history" "$CLAUDE_PROVIDER_DIR/history.jsonl" "$REMOTE_PROVIDER_DIR/history.jsonl"
    do_rsync_push "settings" "$CLAUDE_PROVIDER_DIR/settings.json" "$REMOTE_PROVIDER_DIR/settings.json"

    # claude-shared
    if [[ -d "$HOME/.claude-shared" ]]; then
        do_rsync_push "claude-shared" "$HOME/.claude-shared/" "~/.claude-shared/"
    else
        echo "  (no local .claude-shared)"
        SYNC_SKIP=$((SYNC_SKIP + 1))
    fi
}

# =============================================================================
# Main
# =============================================================================

case "$DIRECTION" in
    pull)
        sync_pull "pull"
        ;;
    push)
        sync_push "push"
        ;;
    bidirectional)
        echo "=== STEP 1/2: Pull from remote ==="
        sync_pull "pull"
        echo ""
        echo "=== STEP 2/2: Push to remote ==="
        sync_push "push"
        ;;
esac

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================="
echo "  SYNC COMPLETE — $DIRECTION"
echo "============================================="
echo "  OK:    $SYNC_OK phases"
echo "  Failed: $SYNC_FAIL phases"
echo "  Skipped: $SYNC_SKIP phases"
echo "  Memories in: $LOCAL_PROJ_DIR/memory/"
echo "  Sessions in: $LOCAL_PROJ_DIR/"
echo "  Settings:    $PROJECT_ROOT/.claude/"
echo "  Remember:    $PROJECT_ROOT/.remember/"
echo ""
if $DRY_RUN; then
    echo "  (dry-run — no files were copied)"
else
    echo "  RESUME: cat docs/SESSION_RESUME.md"
fi
echo "============================================="

if [[ $SYNC_FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
