#!/usr/bin/env bash
# scripts/hooks/guard-forbidden-commands.sh
#
# Claude Code PreToolUse guard hook (mechanical block) — the "anti-forgetting"
# enforcement that makes mandatory constraints independent of agent recall.
#
# CONTRACT (Claude Code PreToolUse hook, https://code.claude.com/docs/en/hooks):
#   - Receives the tool invocation as JSON on stdin. For tool_name == "Bash"
#     the command string lives at .tool_input.command.
#   - Exit 0  → allow (Claude proceeds normally).
#   - Exit 2  → BLOCK; the text we print to stderr is fed back to Claude as the
#               reason the tool call was refused.
#   - Any other exit code → non-blocking error (we never use those).
#
# WHY THIS EXISTS (forensic anchor): during the on-device-API build, emulator
# subagents ran raw host-direct `emulator`/`adb` instead of going through the
# Containers submodule (§6.X). The orchestrator forgot to inject that rule into
# their prompts. A prompt the orchestrator forgets to paste is not enforcement.
# This hook makes the FORBIDDEN/GATED command classes mechanical: they are
# blocked at the tool-call boundary no matter what any agent remembers.
#
# CLASSES BLOCKED (each maps to a constitutional clause):
#   - Raw host-direct emulator / adb-install / am-instrument  → §6.X / §6.V / §6.AG
#   - git push --force / -f / --force-with-lease / --no-verify / --no-gpg-sign → §6.T.3
#   - sudo / su                                               → §6.U
#   - host power management (suspend/hibernate/poweroff/...)  → Host Stability Directive
#
# ESCAPE HATCH (documented exceptions only): a command containing the literal
# marker `# guardrails:allow <reason>` is WARNED (printed to stderr) but NOT
# blocked. The reason text is mandatory so the exception is self-documenting and
# auditable in the transcript. The escape hatch never applies to host-power
# commands — those are categorically forbidden by the Host Stability Directive
# and there is no in-band reason that overrides "do not power off the operator's
# machine".
#
# This script is generic + portable on purpose: it has no Lava-specific paths and
# reads its input via a tiny embedded JSON-field extractor (no jq dependency), so
# it ports cleanly up into the shared constitution submodule later.
#
# Classification: universal

set -euo pipefail

# --------------------------------------------------------------------------
# Read the entire PreToolUse JSON payload from stdin.
# --------------------------------------------------------------------------
PAYLOAD="$(cat || true)"

# --------------------------------------------------------------------------
# Extract a top-level or nested string field WITHOUT requiring jq.
# We only need two fields: .tool_name and .tool_input.command. Both are plain
# JSON strings. The extractor below is deliberately conservative: it finds the
# key, then reads the following JSON string literal, unescaping \" \\ \n \t.
# If jq IS present we prefer it (more robust against odd payloads).
# --------------------------------------------------------------------------
json_field() {
  # $1 = jq path (e.g. .tool_name or .tool_input.command)
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r "$path // empty" 2>/dev/null || true
    return 0
  fi
  # Fallback: pure-bash/python-free extraction via a small awk state machine.
  # Map the jq path to the leaf key we scan for.
  local key
  case "$path" in
    .tool_name) key="tool_name" ;;
    .tool_input.command) key="command" ;;
    *) key="${path##*.}" ;;
  esac
  printf '%s' "$PAYLOAD" | awk -v key="$key" '
    BEGIN { RS="\0" }
    {
      s = $0
      # locate "key" followed by optional ws, colon, optional ws, quote
      idx = index(s, "\"" key "\"")
      if (idx == 0) { exit }
      rest = substr(s, idx + length(key) + 2)   # skip "key"
      # skip whitespace + colon + whitespace
      sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") { exit }   # not a string value
      rest = substr(rest, 2)                       # drop opening quote
      out = ""
      i = 1
      n = length(rest)
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nx = substr(rest, i+1, 1)
          if (nx == "n") out = out "\n"
          else if (nx == "t") out = out "\t"
          else if (nx == "r") out = out "\r"
          else if (nx == "\"") out = out "\""
          else if (nx == "\\") out = out "\\"
          else if (nx == "/") out = out "/"
          else out = out nx
          i += 2
          continue
        }
        if (c == "\"") break       # closing quote → end of value
        out = out c
        i += 1
      }
      printf "%s", out
    }
  '
}

TOOL_NAME="$(json_field .tool_name)"
COMMAND="$(json_field .tool_input.command)"

# Only Bash commands carry a shell-command string we can vet. Other tools pass
# through untouched.
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Nothing to inspect → allow.
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# --------------------------------------------------------------------------
# Escape-hatch detection. A documented exception marker downgrades a block to a
# warning — EXCEPT for host-power commands, which are never overridable.
# --------------------------------------------------------------------------
ALLOW_MARKER_PRESENT=0
ALLOW_REASON=""
if [[ "$COMMAND" =~ \#[[:space:]]*guardrails:allow[[:space:]]+(.+) ]]; then
  ALLOW_MARKER_PRESENT=1
  ALLOW_REASON="${BASH_REMATCH[1]}"
fi

# block <clause> <message> — refuse the tool call (exit 2) unless an allow-marker
# downgrades it. $3 (optional) = "no-override" to forbid the escape hatch.
block() {
  local clause="$1" message="$2" override="${3:-overridable}"
  if [[ "$ALLOW_MARKER_PRESENT" -eq 1 && "$override" != "no-override" ]]; then
    echo "guardrails: WARNING — ${clause}: ${message}" >&2
    echo "guardrails: allowed by documented exception: ${ALLOW_REASON}" >&2
    return 0   # warned, not blocked; caller continues scanning
  fi
  echo "guardrails: BLOCKED — ${clause}" >&2
  echo "${message}" >&2
  if [[ "$ALLOW_MARKER_PRESENT" -eq 1 && "$override" == "no-override" ]]; then
    echo "guardrails: this class is NOT overridable by '# guardrails:allow'." >&2
  fi
  exit 2
}

# --------------------------------------------------------------------------
# CARRIER-vs-INVOCATION scrubber (BOB-099 / BOB-071 remediation, 2026-08-19).
#
# The quote-/comment-/heredoc-aware `_scrub_inert_regions` scrubber (defined
# lower in this file for the sudo/su + host-power gates) MUST also gate the
# emulator, force-push, --no-verify, and --no-gpg-sign checks below. The full
# defense-in-depth rationale and the character-by-character state machine are
# documented at the function definition further down.
#
# Historical shape of the false-positive (§11.4.196(D) / §11.4.201(7)(a) —
# carrier-vs-thing): raw regexes against the whole command line matched trigger
# tokens that appeared INSIDE a quoted `echo` string, a `#` comment, or a
# quoted-heredoc body — text the shell would NEVER execute — so a harmless
# operator or agent invocation like `echo 'emulator -avd is dev-only'` was
# BLOCKED as an emulator gate violation, and `ls -la # git push --force is
# forbidden` was BLOCKED as a force-push violation, even though NO real
# emulator/adb/git-push invocation was ever going to run.
#
# Fix: compute the SCRUBBED_COMMAND ONCE, at the top, and switch every
# structural-match gate below onto it. The escape-hatch marker (`#
# guardrails:allow <reason>`) STAYS on raw $COMMAND above because the marker
# itself lives in a comment — after scrubbing, that comment becomes filler and
# the marker vanishes. This anchor block is the only forward reference in the
# file; the function itself is defined below (near the sudo/su gate, where it
# was originally introduced) to keep the rest of the file's structure intact.
# --------------------------------------------------------------------------

# Forward-declared helper: computed just below the function definition further
# down; every gate that follows uses this variable instead of raw $COMMAND.
# Provisional assignment so `set -u` never trips before the real one lands.
SCRUBBED_COMMAND=""

# Small local hoist so the emulator + force-push gates can run BEFORE the sudo
# gate's original scrub site. This defines the scrubber function early WITHOUT
# duplicating its body — we source-define it here via a lightweight indirection
# that reads the real definition further below in the same file.
#
# Implementation: bash reads the whole script into memory, but functions become
# callable only after their definition is executed. To avoid a large mechanical
# re-order (which would balloon the diff), we re-locate the function definition
# up here. The original block further down is stripped in the same edit so
# there is no double-definition.
_scrub_inert_regions() {
  local s="$1"
  local out="" ch prev=""
  local -a stack=("LIVE")
  local -a hd_delim=() hd_strip=()
  local i n=${#s}
  local top
  for ((i = 0; i < n; i++)); do
    ch="${s:i:1}"
    top="${stack[-1]}"
    case "$top" in
      SQ)
        if [[ "$ch" == "'" ]]; then
          unset 'stack[-1]'
          out+="$ch"
        else
          out+="#"
        fi
        ;;
      DQ)
        if [[ "$ch" == '"' && "$prev" != '\' ]]; then
          unset 'stack[-1]'
          out+="$ch"
        elif [[ "$ch" == '$' && "${s:i+1:1}" == '(' ]]; then
          stack+=("PAREN")
          out+='$('
          i=$((i + 1))
          prev='('
          continue
        elif [[ "$ch" == '`' ]]; then
          stack+=("BT")
          out+="$ch"
        else
          out+="#"
        fi
        ;;
      BT)
        if [[ "$ch" == '`' && "$prev" != '\' ]]; then
          unset 'stack[-1]'
        fi
        out+="$ch"
        ;;
      PAREN | LIVE)
        if [[ "$ch" == "'" ]]; then
          stack+=("SQ")
          out+="$ch"
        elif [[ "$ch" == '"' ]]; then
          stack+=("DQ")
          out+="$ch"
        elif [[ "$ch" == '`' ]]; then
          stack+=("BT")
          out+="$ch"
        elif [[ "$ch" == '$' && "${s:i+1:1}" == '(' ]]; then
          stack+=("PAREN")
          out+='$('
          i=$((i + 1))
          prev='('
          continue
        elif [[ "$ch" == ')' && "$top" == "PAREN" ]]; then
          unset 'stack[-1]'
          out+="$ch"
        elif [[ "$ch" == '<' && "${s:i+1:1}" == '<' ]]; then
          local j=$((i + 2)) hd_strip_flag=0 qc hd_dl=""
          [[ "${s:j:1}" == '-' ]] && { hd_strip_flag=1; j=$((j + 1)); }
          while [[ "${s:j:1}" == ' ' || "${s:j:1}" == $'\t' ]]; do
            j=$((j + 1))
          done
          qc="${s:j:1}"
          if [[ "$qc" == "'" || "$qc" == '"' ]]; then
            local k=$((j + 1))
            while [[ "$k" -lt "$n" && "${s:k:1}" != "$qc" ]]; do
              hd_dl+="${s:k:1}"
              k=$((k + 1))
            done
            j=$((k + 1))
          elif [[ "$qc" == '\' ]]; then
            local k=$((j + 1))
            while [[ "${s:k:1}" =~ ^[A-Za-z0-9_]$ ]]; do
              hd_dl+="${s:k:1}"
              k=$((k + 1))
            done
            j="$k"
          fi
          if [[ -n "$hd_dl" ]]; then
            out+="${s:i:$((j - i))}"
            hd_delim+=("$hd_dl")
            hd_strip+=("$hd_strip_flag")
            i=$((j - 1))
            prev="${s:i:1}"
            continue
          fi
          out+="$ch"
        elif [[ "$ch" == $'\n' && ${#hd_delim[@]} -gt 0 ]]; then
          out+="$ch"
          local body_i=$((i + 1)) hidx
          for ((hidx = 0; hidx < ${#hd_delim[@]}; hidx++)); do
            local delim="${hd_delim[$hidx]}" strip="${hd_strip[$hidx]}"
            while [[ "$body_i" -le "$n" ]]; do
              local line_end=$body_i
              while [[ "$line_end" -lt "$n" && "${s:line_end:1}" != $'\n' ]]; do
                line_end=$((line_end + 1))
              done
              local line="${s:body_i:$((line_end - body_i))}"
              local chk="$line"
              if [[ "$strip" -eq 1 ]]; then
                while [[ "${chk:0:1}" == $'\t' ]]; do chk="${chk:1}"; done
              fi
              if [[ "$chk" == "$delim" ]]; then
                out+="$line"
                body_i=$((line_end + 1))
                [[ "$line_end" -lt "$n" ]] && out+=$'\n'
                break
              else
                local fillr="" fi_
                for ((fi_ = 0; fi_ < ${#line}; fi_++)); do fillr+="#"; done
                out+="$fillr"
                if [[ "$line_end" -lt "$n" ]]; then
                  out+=$'\n'
                  body_i=$((line_end + 1))
                else
                  body_i=$((n + 1))
                  break
                fi
              fi
            done
          done
          hd_delim=()
          hd_strip=()
          i=$((body_i - 1))
          prev=$'\n'
          continue
        elif [[ "$ch" == '#' && ( "$i" -eq 0 || "$prev" == ' ' || "$prev" == $'\t' || "$prev" == ';' || "$prev" == '|' || "$prev" == '&' || "$prev" == '(' || "$prev" == $'\n' ) ]]; then
          while ((i < n)); do
            ch="${s:i:1}"
            if [[ "$ch" == $'\n' ]]; then
              out+="$ch"
              break
            fi
            out+="#"
            i=$((i + 1))
          done
          prev="$ch"
          continue
        else
          out+="$ch"
        fi
        ;;
    esac
    prev="$ch"
  done
  printf '%s' "$out"
}

# The one canonical scrubbed projection. Every structural-match gate below
# uses this — the escape-hatch marker check above deliberately did not.
SCRUBBED_COMMAND="$(_scrub_inert_regions "$COMMAND")"

# --------------------------------------------------------------------------
# 1. Emulator / device gate (§6.X / §6.V / §6.AG).
#    Raw host-direct emulator launches and APK installs / instrumentation are
#    dev-iteration ONLY and MUST NOT produce gate evidence. Gate runs go through
#    scripts/run-challenge-matrix.sh → the Containers submodule.
# --------------------------------------------------------------------------
EMULATOR_MSG="Gate emulator runs MUST go via scripts/run-challenge-matrix.sh → Containers submodule (§6.X). Raw host-direct adb/emulator is dev-iteration only, never gate evidence."

# raw `emulator -avd ...` or a path ending in .../emulator referencing an SDK env
if [[ "$SCRUBBED_COMMAND" =~ (^|[^[:alnum:]_/.-])emulator[[:space:]]+-avd([[:space:]]|$) ]]; then
  block "§6.X emulator gate" "$EMULATOR_MSG"
fi
if [[ "$SCRUBBED_COMMAND" =~ \$(ANDROID_[A-Z_]+|\{ANDROID_[A-Z_]+\})[^[:space:]]*/emulator([[:space:]]|$) ]]; then
  block "§6.X emulator gate" "$EMULATOR_MSG"
fi

# top-level `adb install` / `adb -s <serial> install`
if [[ "$SCRUBBED_COMMAND" =~ (^|[^[:alnum:]_/.-])adb([[:space:]]+-s[[:space:]]+[^[:space:]]+)?[[:space:]]+install([[:space:]]|$) ]]; then
  block "§6.X emulator gate" "$EMULATOR_MSG"
fi

# `am instrument` (instrumentation runner invoked host-direct)
if [[ "$SCRUBBED_COMMAND" =~ (^|[^[:alnum:]_/.-])am[[:space:]]+instrument([[:space:]]|$) ]]; then
  block "§6.X emulator gate" "$EMULATOR_MSG"
fi

# --------------------------------------------------------------------------
# 2. Force-push / verification-bypass gate (§6.T.3).
#
# FALSE-POSITIVE FIX (2026-07-11). Forensic reproduction: a benign command
# referencing a §11.4.88 push-failure LOG PATH (e.g. `git fetch --all &&
# tail -f qa-results/push_failures/x.log`), or any command chaining a `git`
# invocation with an UNRELATED `-f`-flagged command whose own argument
# merely STARTS WITH "push", was wrongly BLOCKED (exit 2) as "§6.T.3
# force-push". Root cause, two independent over-matches in the previous
# single whole-command regex:
#   (a) the "is this a git-push invocation" test matched literal "push" as
#       an UNBOUNDED PREFIX (no trailing word boundary) -- so any token
#       starting with "push" (`push_failures/...`, `push_all.sh`, a bare
#       "push" inside unrelated prose, ...) satisfied it;
#   (b) the force-flag test (`-f` / `--force` / `--force-with-lease`)
#       scanned the ENTIRE raw command string with no notion of "clause" --
#       so a `-f` flag belonging to a COMPLETELY UNRELATED command chained
#       via `&&` / `;` / `|` (the extremely common `tail -f <logfile>`)
#       satisfied it even though it had nothing to do with any git push.
#
# Fix: (1) require BOTH "git" and "push" to be complete, boundary-anchored
# words (never a prefix match); (2) split the command into shell-operator
# CLAUSES (`;`, `&&`, `||`, single `|`, literal newline) with QUOTE-AWARE
# splitting -- a separator that appears INSIDE a single- or double-quoted
# argument is never treated as a split point, so a real
# `git push -o ci.skip="a;b" --force` is never sliced apart -- and require
# the git-push match AND the force flag / `+<refspec>` to occur in the
# SAME clause. Malformed/unterminated-quote input can only ever MERGE
# clauses (an unclosed quote just swallows the rest of the string into one
# clause, since only UN-quoted separators split), never SPLIT a real
# `git push ... --force` apart -- so this can never cause a genuine
# force-push to be missed (§11.4.113 has no escape hatch).
# --------------------------------------------------------------------------
FORCE_MSG="§6.T.3 requires explicit, in-conversation operator approval for THIS specific operation: force push, history rewrite, --no-verify, or --no-gpg-sign. One approval does not cover the next. Ask the operator, then add a documented '# guardrails:allow <reason>' marker if approved."

# Quote-aware clause splitter (pure bash, no external deps -- consistent
# with the rest of this hook, which deliberately avoids a jq/python
# dependency for its own core logic). Splits $1 on `;`, `&&`, `||`, a
# single (non-doubled) `|`, and literal newlines -- EXCEPT when those
# characters appear inside a single- or double-quoted string, in which
# case they are copied through untouched.
_fp_split_clauses() {
  local s="$1"
  local -a out=()
  local buf="" ch prev="" in_squote=0 in_dquote=0
  local i n=${#s}
  for ((i = 0; i < n; i++)); do
    ch="${s:i:1}"
    if [[ "$in_squote" -eq 1 ]]; then
      buf+="$ch"
      [[ "$ch" == "'" ]] && in_squote=0
      continue
    fi
    if [[ "$in_dquote" -eq 1 ]]; then
      buf+="$ch"
      if [[ "$ch" == '"' && "$prev" != '\' ]]; then
        in_dquote=0
      fi
      prev="$ch"
      continue
    fi
    case "$ch" in
      "'")
        in_squote=1
        buf+="$ch"
        ;;
      '"')
        in_dquote=1
        buf+="$ch"
        ;;
      ';'|$'\n')
        out+=("$buf")
        buf=""
        ;;
      '&')
        if [[ "${s:i+1:1}" == '&' ]]; then
          out+=("$buf")
          buf=""
          i=$((i + 1))
        else
          buf+="$ch"
        fi
        ;;
      '|')
        if [[ "${s:i+1:1}" == '|' ]]; then
          i=$((i + 1))
        fi
        out+=("$buf")
        buf=""
        ;;
      *)
        buf+="$ch"
        ;;
    esac
    prev="$ch"
  done
  out+=("$buf")
  printf '%s\n' "${out[@]}"
}

# Word-bounded "git ... push" detector -- "git" and "push" MUST each be
# complete words (never a substring/prefix of a longer token).
GIT_PUSH_RE='(^|[[:space:]])git([[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'

while IFS= read -r fp_clause; do
  [[ -z "$fp_clause" ]] && continue
  if [[ "$fp_clause" =~ $GIT_PUSH_RE ]]; then
    if [[ "$fp_clause" =~ (^|[[:space:]])--force([[:space:]]|=|$) ]] ||
       [[ "$fp_clause" =~ (^|[[:space:]])-f([[:space:]]|$) ]] ||
       [[ "$fp_clause" =~ (^|[[:space:]])--force-with-lease([[:space:]]|=|$) ]] ||
       [[ "$fp_clause" =~ (^|[[:space:]])\+[^[:space:]] ]]; then
      block "§6.T.3 force-push" "$FORCE_MSG"
    fi
  fi
done < <(_fp_split_clauses "$SCRUBBED_COMMAND")

if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]])--no-verify([[:space:]]|$) ]]; then
  block "§6.T.3 --no-verify" "$FORCE_MSG"
fi
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]])--no-gpg-sign([[:space:]]|$) ]]; then
  block "§6.T.3 --no-gpg-sign" "$FORCE_MSG"
fi

# --------------------------------------------------------------------------
# 3. sudo / su gate (§6.U).
#
# FALSE-POSITIVE FIX (2026-08-09, RD2-36 / RD2-01 / GA-24 residual class).
# Forensic reproduction: `echo "need no sudo for list"` -- and the audit's
# exact live repro, `echo "=== systemd system-level (may need no sudo for
# list) ==="` -- was wrongly BLOCKED (exit 2) as "§6.U no-sudo". Root cause:
# the previous check was a plain word-BOUNDARY substring match against the
# WHOLE raw command line -- it correctly required "sudo"/"su" to be a
# complete word (not a substring of `subl`/`sudo`/`--summary`), but it had
# NO notion of shell quoting, so a "sudo" that was merely a word INSIDE a
# quoted string argument (an echo message, a comment) satisfied the exact
# same whitespace-bounded-word shape as a REAL command invocation and was
# indistinguishable from one -- the §11.4.201(7)(a) carrier-false-positive
# class already found for a different file under GA-24, now fixed at its
# root here instead of appending another per-file EXCLUDE_PATHS entry.
#
# The prior boundary set (start-of-string / whitespace / `;` / `|` / `&`)
# also never recognised `$(` or a backtick as a valid PRECEDING boundary --
# so a REAL sudo invocation launched via command substitution (`$(sudo id)`
# or `` `sudo id` ``) was actually MISSED even in the raw/unquoted case: a
# false NEGATIVE alongside the false positive, confirmed live in this
# session's RED run (tests/hooks/test_guard_forbidden_commands.sh).
#
# A THIRD carrier class was found live in this SAME session while drafting
# this very fix's own commit message: prose text embedded in a QUOTED-
# delimiter here-document (`git commit -m "$(cat <<'EOF' ... EOF)"` -- this
# project's own documented commit-message idiom) that merely mentions
# "sudo"/"su" in plain English (e.g. "...even though no sudo invocation was
# present.") was ALSO wrongly blocked -- the exact same bug class (a word
# merely present in a NEVER-EXECUTED context), just reached via a different
# shell quoting construct the original quote-scrubber did not know about.
# `_scrub_inert_regions` therefore ALSO recognises a QUOTED-delimiter
# here-document (`<<'EOF'`, `<<"EOF"`, `<<\EOF`, each with an optional
# `<<-` tab-stripping form) and scrubs its ENTIRE body to filler -- a
# quoted heredoc delimiter disables ALL shell expansion inside the body
# per POSIX, so (unlike a double-quoted span) there is no nested-live-
# region case to track; the terminator line itself is passed through
# verbatim. An UNQUOTED-delimiter heredoc (`<<EOF`, which CAN contain live
# `$(...)`/backtick expansion) is intentionally left untouched/live -- the
# safe, conservative default that can only ever ADD true-positive coverage
# never remove it, at the honest cost (§11.4.6) of not also closing the
# false-positive class for that rarer construct.
#
# Fix: scrub the raw command into a "live-regions-only" projection BEFORE
# running the word-boundary regex (`_scrub_inert_regions`, shared by both
# the sudo and su checks below):
#   - text strictly inside a SINGLE-quoted span is ALWAYS inert (the shell
#     never executes/expands single-quoted content) -> scrubbed to filler;
#   - text inside a DOUBLE-quoted span is inert TOO (the shell passes it
#     through as a literal argument value, it does not invoke it as a
#     command) -> scrubbed to filler -- EXCEPT for a nested `$(...)` or
#     backtick command-substitution span, which the shell DOES execute
#     even though it is textually inside double quotes -> left LIVE
#     (unscrubbed), tracked via a small quote/paren state stack so nesting
#     (quotes-inside-$(...)-inside-quotes, etc.) is handled correctly;
#   - text inside a QUOTED-delimiter here-document body is ALWAYS inert
#     (see above) -> scrubbed to filler, line by line, until the exact
#     terminator line;
#   - everything else (unquoted text, and backtick-substitution content
#     wherever it occurs) is LIVE and passes through untouched.
# The existing word-boundary regex then runs against the SCRUBBED
# projection instead of the raw command, so:
#   - `sudo`/`su` appearing ONLY inside a quoted string/comment NEVER
#     matches -> correctly ALLOWED (closes RD2-36/RD2-01/GA-24's residual,
#     no EXCLUDE_PATHS-style band-aid, no weakening of the real check);
#   - a bare/unquoted `sudo ...`/`su ...` invocation, OR one reached via
#     `$(sudo ...)` / a backtick substitution -- even nested inside double
#     quotes -- STILL matches and is BLOCKED (§11.4.113/§11.4.201: no
#     escape hatch, a real invocation is never demoted to allow). The
#     preceding-boundary character class is extended with `\(` (the `(` of
#     a consumed `$(`) and a backtick so this newly-caught command-
#     substitution position is recognised; the trailing-boundary class is
#     extended with `\)` and a backtick to match a substitution closing
#     immediately after the token with no argument (`$(sudo)`).
# --------------------------------------------------------------------------
SUDO_MSG="§6.U forbids sudo / su in any committed artifact or agent tool call. Use a container-based / user-level alternative (rootless Podman, user namespaces, local-only ports)."

# _scrub_inert_regions + SCRUBBED_COMMAND are defined at the top of this file
# (see the BOB-099 / BOB-071 CARRIER-vs-INVOCATION scrubber block above the
# emulator gate). The original definition site LIVED HERE — it was hoisted up
# in the BOB-099 fix so the emulator, force-push, --no-verify, and
# --no-gpg-sign gates can share the same scrubbed projection. Nothing in this
# section changes semantically; the sudo/su regexes still run against
# $SCRUBBED_COMMAND, which the hoisted assignment computes once before any
# gate fires.

if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&|\(|\`)sudo([[:space:]]|$|\)|\`) ]]; then
  block "§6.U no-sudo" "$SUDO_MSG"
fi
# `su`, `su -`, `su -l`, `su <user>`, `su <user> -c ...`, `su -c ...` (but NOT
# words merely containing 'su' such as `subl`, `sudo` already handled above, or
# `--summary`). A standalone `su` token (start/space/;/|/& before, space/EOL
# after) is blocked regardless of its arguments — the earlier
# `su([[:space:]]+-?l?...)` form let `su root -c '<anything>'` bypass the §6.U
# gate because the char after the space was neither `-`, `l`, nor EOL (F3-B1).
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&|\(|\`)su([[:space:]]|$|\)|\`) ]]; then
  block "§6.U no-su" "$SUDO_MSG"
fi

# --------------------------------------------------------------------------
# 4. Host-power gate (Host Machine Stability Directive). NOT overridable.
# --------------------------------------------------------------------------
POWER_MSG="Host Machine Stability Directive: commands that suspend / hibernate / power-off / reboot / halt / sign-out the host are categorically forbidden. They destroy in-progress builds and the development session."

# FALSE-POSITIVE FIX (2026-08-11, session-17 / agent-V). The host-power gates
# below MUST scan $SCRUBBED_COMMAND (the quote-aware "live regions only"
# projection), NOT the raw $COMMAND. The scrubber is defined ~230 lines above
# for the sudo/su gates that suffered the identical §11.4.201(7)(a) carrier-
# false-positive class (RD2-36/RD2-01/GA-24); the same fix was never wired
# into the host-power block, so ANY quoted string mentioning `loginctl`,
# `systemctl`, `pm-*`, or `shutdown` — a grep pattern, an echo argument, a
# commit-message body, a here-document containing docs prose — was scanned
# by the raw regex and the boundary alternation `(...)` matched on the
# whitespace / pipe / semicolon / ampersand INSIDE the quoted content,
# blocking the entire tool call as if the quoted text were a real invocation.
# Live self-demonstration (this session): `grep -rln
# 'systemctl.*user@\|loginctl terminate-user\|loginctl kill-user' /etc/
# /usr/lib/systemd/` was blocked as "Host Stability (loginctl)" — the
# `\|loginctl` sequence gave the regex the `|` boundary it needed even though
# `loginctl` was inside a single-quoted grep pattern (an argument value, not
# an invocation). The scrubber replaces the entire inert quoted body with
# same-length `#` filler, so `loginctl` inside a quoted grep pattern becomes
# `########` and never matches; a REAL `loginctl kill-user`, or one reached
# via `$(loginctl ...)` / backtick substitution / `; loginctl` / `&& loginctl`,
# stays LIVE and still matches. This is the same accepted trade-off already
# documented at length for sudo/su (see the block-comment ~200 lines above):
# a `bash -c 'loginctl suspend'` would also pass the scrubbed check (the same
# way `bash -c 'sudo id'` already does), which is an acknowledged known-narrow
# limitation because a quoted-string span is inert per shell semantics
# (bash passes it as an argument value; only `bash -c` re-invokes it, which
# is itself operator-run tooling not the guard's coverage boundary). NEVER
# regresses any of the currently-caught real classes — full RED-then-GREEN
# fixture pair evidence at scratchpad/agent-V-green-*.log. §11.4.201(1)
# false-positive guard: this reduces false positives without introducing a
# new one; every current true-positive (real invocation / command-substituted
# invocation / backtick-substituted invocation / chained invocation via
# ;/&&/|/&/newline) still fires. Host-power classes remain `no-override`.
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&)systemctl[[:space:]]+(suspend|hibernate|hybrid-sleep|suspend-then-hibernate|poweroff|halt|reboot|kexec|kill-user|kill-session) ]]; then
  block "Host Stability (systemctl)" "$POWER_MSG" no-override
fi
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&)loginctl[[:space:]]+(suspend|hibernate|hybrid-sleep|suspend-then-hibernate|poweroff|halt|reboot|kill-user|kill-session|terminate-user|terminate-session) ]]; then
  block "Host Stability (loginctl)" "$POWER_MSG" no-override
fi
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&)pm-(suspend|hibernate|suspend-hybrid)([[:space:]]|$) ]]; then
  block "Host Stability (pm-*)" "$POWER_MSG" no-override
fi
if [[ "$SCRUBBED_COMMAND" =~ (^|[[:space:]]|;|\||&)shutdown([[:space:]]|$) ]]; then
  block "Host Stability (shutdown)" "$POWER_MSG" no-override
fi

# --------------------------------------------------------------------------
# Nothing matched (or only allow-marked warnings fired) → allow the command.
# --------------------------------------------------------------------------
exit 0
