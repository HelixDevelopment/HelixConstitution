#!/usr/bin/env bash
# scripts/multitrack/track_branch_label.sh
#
# Purpose : Emit the §11.4.182 track+branch+alias+model work-stream identity
#           label `(T<N>/<branch> - <alias> - <model>)` for the CURRENT
#           checkout + live session, deterministically derived (never
#           guessed, §11.4.6). This is the reference labeler the §11.4.182
#           guard hook (guard-track-branch-label.sh) points operators at,
#           and the canonical source for the prefix every agent/subagent
#           dispatch + operator-facing work-stream reference MUST start with.
# Usage   : bash constitution/scripts/multitrack/track_branch_label.sh
#           (run from within the checkout whose label you want)
# Inputs  : cwd (for /mnt/track<N> track detection + the native-alias
#           session-transcript lookup below), git HEAD (branch),
#           CLAUDE_CONFIG_DIR env (alias + native-alias transcript root),
#           CLAUDE_CODE_SESSION_ID env (native-alias transcript file),
#           HOME env (provider-registry root, see <model> CASE B below).
# Outputs : one line on stdout: `(T<N>/<branch> - <alias> - <model>)`
#           + trailing newline.
# Side-effects: none (read-only; §11.4.128-safe). The native-alias model
#           lookup reads at most the last 500 LINES of the live session
#           transcript (bounded, fast even on multi-thousand-line files).
# Deps    : bash, git (optional — falls back to '?' branch if absent), sed.
#           `jq` used WHEN PRESENT for the native-alias model lookup
#           (structural, order-independent JSON parse — the preferred,
#           robust path); its absence degrades to a documented,
#           line-anchored `sed`/`grep` fallback rather than failing.
# Cross-refs: §11.4.182 (label mandate), §11.4.178 (track-qualified identity),
#           §11.4.187 (multitrack engine), guard-track-branch-label.sh.
# Decoupling (§11.4.177): project-agnostic — derives everything from the
#           invocation context + HOST/PLATFORM tooling conventions (the
#           Claude Code CLI's own `<config-dir>/projects/<slug>/<session>.jsonl`
#           transcript layout, and the host's claude-multi-account toolkit
#           provider registry — a cross-project, host-level convention, not a
#           project literal); carries NO project literal. A host lacking
#           either convention simply yields the honest '?' fallback for
#           <model> — the mechanism never assumes a project-specific layout
#           and degrades gracefully everywhere else.
# Classification: universal.
#
# Derivation (all deterministic; honest '?' fallbacks are never a guess §11.4.6):
#   <N>     : from cwd '/mnt/track<N>/...'  else '?'
#   <branch>: git rev-parse --abbrev-ref HEAD  else '?'
#   <alias> : CLAUDE_CONFIG_DIR basename '.claude-<alias>' -> '<alias>'  else '?'
#   <model> : the model CURRENTLY answering for <alias> — a closed two-case
#             split on the SHAPE of <alias> (empirically confirmed against
#             this host's actual claude-multi-account toolkit layout — full
#             investigation + evidence in
#             docs/research/model_in_label_20260726/DESIGN.md):
#
#             CASE A — native alias (<alias> matches 'claude[0-9]*', e.g.
#               claude1..claude5): these talk to the real Anthropic API with
#               NO fixed model — Claude Code itself chooses/switches the
#               serving model per turn (Opus/Sonnet/Haiku/Fable), and that
#               choice is NOT exposed via any persistent env var. The only
#               live, real-time source is the CURRENT session's OWN
#               transcript: `$CLAUDE_CONFIG_DIR/projects/<slug>/
#               $CLAUDE_CODE_SESSION_ID.jsonl`, where <slug> is the cwd with
#               every non-alphanumeric character replaced by '-' (the exact
#               project-slug algorithm the Claude Code CLI itself uses for
#               that directory layout). The LAST `"type":"assistant"` entry's
#               `message.model` field in that transcript is the live model,
#               mapped to a short native name by case-insensitive substring
#               match against {opus,sonnet,haiku,fable} (covers every
#               observed id shape: claude-opus-4-8, claude-sonnet-5[1m],
#               claude-3-5-haiku, claude-fable-5, ...). An id matching none of
#               the four is printed VERBATIM (never silently dropped to '?'
#               when real data WAS obtained). Missing
#               CLAUDE_CODE_SESSION_ID / CLAUDE_CONFIG_DIR / an unreadable or
#               model-less transcript -> <model> is '?'.
#
#               HONEST, EMPIRICALLY-CONFIRMED LIMITATION (§11.4.6 — stated,
#               never hidden): validated live from the CONDUCTOR's own shell
#               (the context this guard hook actually runs in, at
#               Agent/Task/TaskCreate dispatch time) — reliably returns the
#               real, current model id there. Invoked from INSIDE an
#               already-dispatched background subagent process, it was
#               observed to return the DISPATCHING conductor's model rather
#               than the subagent's own — the two processes were found to
#               share the same $CLAUDE_CODE_SESSION_ID / transcript file on
#               this host's multitrack ruler (§11.4.187), with no
#               `isSidechain` marker distinguishing them. Resolving that gap
#               needs deeper access to the multitrack ruler's subagent-
#               session-id assignment than this script can reach — an open,
#               honestly-scoped follow-up (see DESIGN.md), never silently
#               "fixed" by guessing.
#
#             CASE B — provider alias (everything else, e.g. `deepseek`,
#               `xiaomi`, `kimi-for-coding`, `opencode`, or the raw
#               `prov-<id>` form some CLAUDE_CONFIG_DIR basenames yield): the
#               real serving model is HOST CONFIG DATA, already declared in
#               `$HOME/.local/share/claude-multi-account/providers/<id>.env`
#               as `CMA_PROVIDER_MODEL='<real-model-id>'` — the exact value
#               the claude-multi-account launcher itself exports as
#               `ANTHROPIC_MODEL` when that alias launches. This script reads
#               that value directly (single source of truth — no duplicated
#               model list). If <alias> doesn't resolve to a provider file
#               directly, a leading `prov-` is stripped and retried once.
#               Unresolvable -> <model> is '?'.

set -uo pipefail

# --- track number from the checkout path -----------------------------------
_dir="$(pwd -P 2>/dev/null || pwd)"
case "$_dir" in
  /mnt/track[0-9]*)
    _n="${_dir#/mnt/track}"; _n="${_n%%/*}"
    case "$_n" in ''|*[!0-9]*) _n='?' ;; esac
    ;;
  *) _n='?' ;;
esac

# --- branch from git --------------------------------------------------------
_br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ -n "$_br" ]] || _br='?'

# --- alias from CLAUDE_CONFIG_DIR basename '.claude-<alias>' -----------------
_al='?'
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  _cfgbase="$(basename "$CLAUDE_CONFIG_DIR" 2>/dev/null || true)"
  case "$_cfgbase" in
    .claude-?*) _al="${_cfgbase#.claude-}" ;;
  esac
fi

# --- CASE A model lookup: native alias --------------------------------------
# Reads the LAST assistant entry's model field from the current session's
# own transcript. See the header comment block ("CASE A") for the full
# derivation + honest limitation.
_native_model() {
  local sid cfgd slug transcript raw
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  [[ -n "$sid" ]] || { printf '%s' '?'; return; }
  cfgd="${CLAUDE_CONFIG_DIR:-}"
  [[ -n "$cfgd" ]] || { printf '%s' '?'; return; }
  # Same project-slug algorithm the Claude Code CLI itself uses for its
  # per-project transcript directory layout — reused verbatim, never
  # re-derived independently.
  slug="$(printf '%s' "$_dir" | sed 's/[^A-Za-z0-9]/-/g')"
  transcript="$cfgd/projects/$slug/$sid.jsonl"
  [[ -r "$transcript" ]] || { printf '%s' '?'; return; }

  raw=""
  if command -v jq >/dev/null 2>&1; then
    raw="$(tail -n 500 "$transcript" 2>/dev/null \
      | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null \
      | tail -n1)"
  fi
  if [[ -z "$raw" ]]; then
    # Portable fallback (no jq). Each JSONL line is one complete, standalone
    # top-level object beginning at column 1 of that physical line (JSON
    # escapes embedded newlines, so no fragment of a quoted string value can
    # spoof a bare line-start match). Filter to lines mentioning the
    # assistant type, then pull the model value out of the
    # (order-unconstrained across schema versions) "message":{"model": key.
    # KNOWN, DOCUMENTED LIMITATION (§11.4.6 — never hidden): this is a
    # substring match, not a structural parse — installing `jq` closes this
    # gap entirely (preferred path above).
    raw="$(tail -n 500 "$transcript" 2>/dev/null \
      | grep '"type":"assistant"' \
      | sed -n 's/.*"message":{"model":"\([^"]*\)".*/\1/p' \
      | tail -n1)"
  fi
  [[ -n "$raw" ]] || { printf '%s' '?'; return; }

  case "$raw" in
    *[Oo][Pp][Uu][Ss]*)         printf '%s' 'opus' ;;
    *[Ss][Oo][Nn][Nn][Ee][Tt]*) printf '%s' 'sonnet' ;;
    *[Hh][Aa][Ii][Kk][Uu]*)     printf '%s' 'haiku' ;;
    *[Ff][Aa][Bb][Ll][Ee]*)     printf '%s' 'fable' ;;
    *)                          printf '%s' "$raw" ;;  # real-but-unrecognised id: honest verbatim, never dropped to '?'
  esac
}

# --- CASE B model lookup: provider alias ------------------------------------
# Reads CMA_PROVIDER_MODEL from the claude-multi-account provider registry
# (host config, single source of truth — the same value the launcher itself
# exports at launch).
_provider_model() {
  local al="$1" pdir pid envf m
  pdir="${HOME:-}/.local/share/claude-multi-account/providers"
  pid="$al"
  envf="$pdir/$pid.env"
  if [[ ! -r "$envf" ]]; then
    # Some CLAUDE_CONFIG_DIR basenames are literally '.claude-prov-<id>', so
    # the raw <alias> field can carry a 'prov-' prefix the provider
    # registry's filenames do not. Strip once and retry.
    case "$al" in
      prov-*) pid="${al#prov-}"; envf="$pdir/$pid.env" ;;
    esac
  fi
  [[ -r "$envf" ]] || { printf '%s' '?'; return; }
  m="$(sed -n "s/^CMA_PROVIDER_MODEL='\([^']*\)'.*/\1/p" "$envf" 2>/dev/null | head -n1)"
  [[ -n "$m" ]] || { printf '%s' '?'; return; }
  printf '%s' "$m"
}

# --- top-level <model> dispatch: closed two-case split on the shape of
#     <alias> (native 'claude<N>' vs everything else = provider). -----------
_mo='?'
case "$_al" in
  ''|'?') _mo='?' ;;
  claude[0-9]*) _mo="$(_native_model)" ;;
  *) _mo="$(_provider_model "$_al")" ;;
esac

printf '(T%s/%s - %s - %s)\n' "$_n" "$_br" "$_al" "$_mo"
