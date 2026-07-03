#!/usr/bin/env bash
# =============================================================================
# multitrack_cwd_hook.sh
#
# Purpose:
#   The thin, project-specific adapter that the (generic) Claude-Toolkit `cma_run`
#   wrapper invokes on every alias session start to learn WHICH directory the
#   alias should work in. Given the alias label (claude1/claude2/claude3) it
#   prints the alias's bound track worktree (/mnt/trackN/<project>) on stdout,
#   or prints NOTHING when there is no valid worktree — in which case `cma_run`
#   leaves the session in the shared /home checkout (safe fallback).
#
#   This is the "hook" half of the permanent multi-track switch. The toolkit
#   knows nothing about tracks/<project>; it only `cd`s into whatever real
#   directory this hook prints (see cma_run's CMA_CWD_HOOK integration).
#
#   Contract with the toolkit (MUST stay stable):
#     * invoked as:   claude-cwd-hook <alias-label>
#     * on success:   print ONE absolute directory path on stdout, exit 0
#     * otherwise:    print nothing (any exit) -> toolkit stays on /home
#     * MUST be fast, read-only, and NEVER hang/fail a session.
#
# Usage:
#   multitrack_cwd_hook.sh <alias>        # hook mode: print worktree or nothing
#   multitrack_cwd_hook.sh --install      # symlink ~/.local/bin/claude-cwd-hook -> here
#   multitrack_cwd_hook.sh --uninstall    # remove that symlink (only if ours)
#   multitrack_cwd_hook.sh --status       # show symlink + per-alias resolution
#   multitrack_cwd_hook.sh -h | --help
#
# Inputs (env):
#   MULTITRACK_DISABLE=1   Escape hatch: print nothing, exit 0 (switch off).
#   CMA_CWD_HOOK           (read by the toolkit) path the toolkit calls; --install
#                          points ~/.local/bin/claude-cwd-hook at this script.
#   (all resolver env vars are honored, e.g. MT_CONFIG_DIR / MT_ALIAS_DIR)
#
# Outputs: stdout = one worktree path (hook mode) or human text (--status).
# Side-effects: --install/--uninstall create/remove ONE symlink under ~/.local/bin.
#               Hook mode is read-only.
#
# Dependencies: bash; multitrack_resolve_worktree.sh (sibling).
#
# Cross-references:
#   scripts/multitrack/multitrack_resolve_worktree.sh   (the resolver it wraps)
#   claude_toolkit scripts/lib.sh  (cma_run CMA_CWD_HOOK integration)
#   docs/guides/MULTITRACK_PERMANENT_SWITCH.md
#   §11.4.28 decoupling (toolkit stays generic; <project> logic lives here)
# =============================================================================

_cwh_self() {
    local src="${BASH_SOURCE[0]:-$0}"
    while [ -h "$src" ]; do
        local dir; dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
    done
    # Absolutize: a relative invocation (e.g. `bash multitrack_cwd_hook.sh`)
    # leaves $src relative, which would make --install write a broken symlink.
    local d; d="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    printf '%s/%s' "$d" "$(basename "$src")"
}

CWH_SELF="$(_cwh_self)"
CWH_DIR="$(cd -P "$(dirname "$CWH_SELF")" >/dev/null 2>&1 && pwd)"
CWH_RESOLVER="$CWH_DIR/multitrack_resolve_worktree.sh"
CWH_LINK="${CMA_CWD_HOOK:-$HOME/.local/bin/claude-cwd-hook}"

# Hook mode: print the alias's worktree (or nothing). Never fail a session.
_cwh_hook() {
    local alias="$1"
    [ -n "$alias" ] || return 0
    [ "${MULTITRACK_DISABLE:-0}" = "1" ] && return 0
    [ -r "$CWH_RESOLVER" ] || return 0
    # The resolver already guards mount+worktree validity and prints nothing on
    # failure; we simply relay its stdout. Errors are swallowed (fall back /home).
    bash "$CWH_RESOLVER" resolve "$alias" 2>/dev/null || true
    return 0
}

_cwh_install() {
    mkdir -p "$(dirname "$CWH_LINK")" 2>/dev/null || true
    if [ -L "$CWH_LINK" ]; then
        local cur; cur="$(readlink "$CWH_LINK" 2>/dev/null)"
        if [ "$cur" = "$CWH_SELF" ]; then
            echo "already installed: $CWH_LINK -> $CWH_SELF"; return 0
        fi
        rm -f "$CWH_LINK"
    elif [ -e "$CWH_LINK" ]; then
        echo "refusing to overwrite non-symlink: $CWH_LINK" >&2; return 1
    fi
    ln -s "$CWH_SELF" "$CWH_LINK" && echo "installed: $CWH_LINK -> $CWH_SELF"
}

_cwh_uninstall() {
    if [ -L "$CWH_LINK" ]; then
        local cur; cur="$(readlink "$CWH_LINK" 2>/dev/null)"
        if [ "$cur" = "$CWH_SELF" ]; then rm -f "$CWH_LINK" && echo "removed: $CWH_LINK"; return 0; fi
        echo "not ours (leaving): $CWH_LINK -> $cur" >&2; return 1
    fi
    echo "no symlink at $CWH_LINK"; return 0
}

_cwh_status() {
    printf 'hook script : %s\n' "$CWH_SELF"
    printf 'resolver    : %s\n' "$CWH_RESOLVER"
    if [ -L "$CWH_LINK" ]; then
        printf 'installed   : %s -> %s\n' "$CWH_LINK" "$(readlink "$CWH_LINK" 2>/dev/null)"
    else
        printf 'installed   : NO (%s absent)\n' "$CWH_LINK"
    fi
    printf 'MULTITRACK_DISABLE=%s\n\n' "${MULTITRACK_DISABLE:-0}"
    bash "$CWH_RESOLVER" map 2>/dev/null || true
}

case "${1:-}" in
    --install)   _cwh_install ;;
    --uninstall) _cwh_uninstall ;;
    --status)    _cwh_status ;;
    -h|--help)   grep -E '^#( |$)' "$CWH_SELF" | sed 's/^# \{0,1\}//' | head -40 ;;
    '')          exit 0 ;;                 # no label -> nothing (safe)
    *)           _cwh_hook "$1" ;;         # treat arg as the alias label
esac
