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
#               Hook mode: relays the resolver's worktree on stdout AND fires a
#               §4.1 bind-on-start (PWU-3) — a BEST-EFFORT, NON-FATAL, FULLY
#               DETACHED `orchestrator bind --alias A --track T` for the alias's
#               resolved track. The detach (all fds -> /dev/null before `&`) makes
#               it impossible for the bind to corrupt the stdout dir line OR block
#               the toolkit's `cd "$(hook ...)"` command substitution. The
#               conductor alias resolves to no track and is therefore NEVER bound.
#
# Dependencies: bash; multitrack_resolve_worktree.sh (sibling, `resolve`+`track`);
#               multitrack_alias_orchestrator.sh (sibling, `bind`).
#
# Cross-references:
#   scripts/multitrack/multitrack_resolve_worktree.sh   (the resolver it wraps)
#   scripts/multitrack/multitrack_alias_orchestrator.sh (bind-on-start target)
#   claude_toolkit scripts/lib.sh  (cma_run CMA_CWD_HOOK integration)
#   docs/guides/MULTITRACK_PERMANENT_SWITCH.md
#   §11.4.28 decoupling (toolkit stays generic; <project> logic lives here)
#   §11.4.177 auto bind-on-start + auto-conductor
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
    # 1) Resolve + relay the worktree (unchanged, load-bearing: cma_run cd's into
    #    whatever single dir this prints). The resolver guards mount+worktree
    #    validity and prints nothing on failure; errors -> fall back /home.
    bash "$CWH_RESOLVER" resolve "$alias" 2>/dev/null || true
    # 2) §4.1 bind-on-start (PWU-3): engage/refresh the alias<->track lease so the
    #    (existing) fallback machinery tracks the alias<->track binding. BEST-EFFORT,
    #    NON-FATAL, FULLY DETACHED — see _cwh_bind_start for why this can NEVER
    #    block, slow, or fail shell startup. Only a REAL track binds (the conductor
    #    resolves to no track, so it is never bound).
    _cwh_bind_start "$alias"
    return 0
}

# Fire the bind FULLY DETACHED so it can never harm shell startup. Two dangers,
# both eliminated by redirecting ALL of the subshell's std fds to /dev/null
# BEFORE backgrounding:
#   (a) cma_run captures this hook via `cd "$("$CMA_CWD_HOOK" <alias>)"` — any
#       byte the bind writes to fd 1 would CORRUPT the cd target. The detached
#       bind inherits /dev/null (never the hook's stdout), so it cannot.
#   (b) command substitution `$(...)` blocks until EVERY process holding the
#       write end of the captured pipe exits — a child inheriting fd 1 would HANG
#       shell startup until the bind finished. With fds -> /dev/null the bind
#       holds NO copy of the hook's stdout, so `cd "$(...)"` returns the instant
#       the foreground `resolve` finishes, regardless of the bind still running.
# The `( ... & )` returns immediately (does not wait on `&`); the child is
# reparented away. `|| true` keeps the whole thing non-fatal.
_cwh_bind_start() {
    local alias="$1"
    ( _cwh_bind_async "$alias" & ) >/dev/null 2>&1 </dev/null || true
}

# Determine the alias's resolved track (binding-aware; empty for conductor /
# unmapped / unmounted — the resolver's `track` verb is validate-gated, so a
# track prints IFF a real cd-able worktree resolved) and engage/refresh its
# lease. Read-only + idempotent; any failure is swallowed. Runs detached (all
# fds already redirected by _cwh_bind_start), so it never touches the hook's
# stdout contract. Inherits the hook's env (MT_REPO_ROOT / MT_CONFIG / MT_ALIAS_DIR)
# so it resolves the SAME config the foreground `resolve` used.
_cwh_bind_async() {
    local alias="$1" orch track
    orch="$CWH_DIR/multitrack_alias_orchestrator.sh"
    [ -r "$orch" ] || return 0
    track="$(bash "$CWH_RESOLVER" track "$alias" 2>/dev/null || true)"
    [ -n "$track" ] || return 0     # conductor / no valid track -> NO bind
    bash "$orch" bind --alias "$alias" --track "$track" >/dev/null 2>&1 || true
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
