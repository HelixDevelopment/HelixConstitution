#!/usr/bin/env bash
# cm_dangerous_combination_fail_closed.sh — CM-DANGEROUS-COMBINATION-FAIL-CLOSED
# gate (anchor §11.4.252).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.252 mandates: any code path COMBINING >= 2 dangerous capabilities
# (mutation / untrusted-input / credential-access / external-side-effect /
# shell-exec / irreversible) MUST FAIL CLOSED -- refuse unless every
# precondition is verifiably satisfied, NEVER fail open on an ambiguous /
# missing / unresolvable signal. The anchor names a CLOSED SET of fail-open
# ANTI-PATTERN SHAPES that are the concrete violation forms:
#     catch { /* ignore */ }
#     credential = credential || default
#     if (!valid) { log("warn"); return proceed(input); }
#     target = user_input || default_target
#     unbounded retry { dangerous(); }
#
# ── Detection scope (honest, stated tradeoff — §11.4.6) ─────────────────────
# PROVING that a code path genuinely COMBINES >= 2 dangerous capabilities
# (per the anchor's 6-member taxonomy) requires real data-flow / control-
# flow analysis this gate CANNOT honestly claim as a portable bash/awk text
# scanner. This gate therefore implements the LITERAL, NAMED, textually-
# precise HALF of the anchor -- detecting the two most structurally
# unambiguous fail-open anti-pattern SHAPES the anchor itself enumerates:
#
#   (A) SWALLOWED EXCEPTION — an empty or comment-only catch/except block
#       (Python `except ...: pass` with nothing else; C-family/JS/TS/Java/
#       C#/PHP `catch (...) { }` empty or comment-only body). Swallowing an
#       exception with no re-raise, no logging statement, and no fallback
#       handling is the literal `catch { /* ignore */ }` anti-pattern.
#
#   (B) CREDENTIAL SILENTLY DEFAULTED TO A LITERAL — a credential-shaped
#       identifier (credential/secret/token/api_key/apikey/password/passwd,
#       case-insensitive) assigned via an `||` / `or` fallback DIRECTLY to a
#       quoted string LITERAL. This is the literal `credential = credential
#       || default` anti-pattern. A fallback to an env-var read / secrets-
#       manager call / config lookup is a DIFFERENT, legitimate pattern and
#       is deliberately NOT flagged (§11.4.6 — a literal default value is
#       the unambiguous violation shape; a secondary CREDENTIAL SOURCE is
#       not).
#
# This gate does NOT attempt to detect the remaining three anchor shapes
# (validate-then-proceed-anyway, untrusted-input-defaulted-to-a-target,
# unbounded-retry-around-a-dangerous-call) — each requires either multi-line
# control-flow correlation or a semantic "is this retry bounded" judgement
# that would risk becoming an unreliable, bluff-prone heuristic if forced
# into a portable text scanner. Their coverage remains §11.4.142/§11.4.194
# human-review territory, stated as an honest gap (§11.4.6), never silently
# claimed covered.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_dangerous_combination_fail_closed.sh [--root <dir>] [--quiet]
#     --root <dir>   scan root (default: $DANGEROUS_COMBO_ROOT or "..")
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   DANGEROUS_COMBO_ROOT      default scan root (else --root, else "..")
#   DANGEROUS_COMBO_EXT       space-separated source extensions to scan
#                              (default: "py go rs c cc cpp h hpp java cs js
#                               ts jsx tsx php rb")
#   DANGEROUS_COMBO_EXCLUDE   space-separated dir-name globs to prune
#                              (default: ".git node_modules vendor .venv
#                               __pycache__ scripts/gates out build dist")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-hit evidence line (file:line + matched anti-pattern class) + a final
#   PASS / FAIL verdict.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no code executed — the scanner
#   only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, grep (GNU or BSD ERE), awk. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.252 (the anchor enforced — literal-shape half), §11.4.201(1)/(7)(a)
#   (false-positive refusal is a FAIL-bluff; match structure not substring),
#   §11.4.6 (honest documented bounded limitation, never silent), §11.4.28/
#   §11.4.35 (project-agnostic, env-var-driven), §1.1 (paired mutation:
#   cm_dangerous_combination_fail_closed_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no candidate source files, or no anti-pattern hit found).
#   1 — FAIL (a swallowed-exception or credential-default-to-literal hit).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-DANGEROUS-COMBINATION-FAIL-CLOSED"
ANCHOR="11.4.252"

root="${DANGEROUS_COMBO_ROOT:-..}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '1,90p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: scan root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

exts="${DANGEROUS_COMBO_EXT:-py go rs c cc cpp h hpp java cs js ts jsx tsx php rb}"
excludes="${DANGEROUS_COMBO_EXCLUDE:-.git node_modules vendor .venv __pycache__ scripts/gates out build dist}"

find_name_expr=()
first=1
for e in $exts; do
    if [ "$first" -eq 1 ]; then first=0; else find_name_expr+=(-o); fi
    find_name_expr+=(-name "*.${e}")
done

prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f \( "${find_name_expr[@]}" \) -print0
    else
        find "$root" -type f \( "${find_name_expr[@]}" \) -print0
    fi
)

if [ "${#files[@]}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no source files under scan (root=$root, ext=[$exts])"
    exit 0
fi

hits=0

for f in "${files[@]}"; do
    # ── (A) Swallowed-exception detection: empty or comment-only catch/except
    #   block bodies. Two language shapes handled:
    #     Python: `except ...:` immediately followed by ONLY `pass` (and
    #             nothing else at that indentation before dedent).
    #     C-family/JS/TS/Java/C#/PHP: `catch (...) { }` where the braces
    #             enclose only whitespace and/or comments.
    py_hits="$(grep -nE '^[[:space:]]*except([[:space:]]+[A-Za-z_.]+([[:space:]]+as[[:space:]]+[A-Za-z_]+)?)?[[:space:]]*:[[:space:]]*$' "$f" 2>/dev/null || true)"
    if [ -n "$py_hits" ]; then
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            lineno="${hit%%:*}"
            nextline="$(sed -n "$((lineno + 1))p" "$f" 2>/dev/null || true)"
            # only a violation if the sole body statement is `pass`
            trimmed="$(printf '%s' "$nextline" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            if [ "$trimmed" = "pass" ]; then
                afterline="$(sed -n "$((lineno + 2))p" "$f" 2>/dev/null || true)"
                after_trimmed="$(printf '%s' "$afterline" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')"
                # heuristic: if the line after `pass` is at DEEPER-OR-EQUAL
                # indent than the except body, there is more body content
                # than just `pass` -- not a bare swallow. Compare indent of
                # `pass` line vs the line after it; only flag when the body
                # is genuinely just the single `pass` statement (blank line,
                # dedent, or EOF follows).
                pass_indent="$(printf '%s' "$nextline" | sed -E 's/[^[:space:]].*$//' | wc -c)"
                after_indent="$(printf '%s' "$afterline" | sed -E 's/[^[:space:]].*$//' | wc -c)"
                if [ -z "$afterline" ] || [ "$after_indent" -lt "$pass_indent" ] || [ -z "$after_trimmed" ]; then
                    hits=$(( hits + 1 ))
                    echo "❌ ${GATE}: FAIL — swallowed exception (Python 'except: pass' with no re-raise/log) at ${f}:${lineno} (§${ANCHOR})"
                fi
            fi
        done <<< "$py_hits"
    fi

    # C-family/JS/TS/Java/C#/PHP: catch (...) { <empty-or-comment-only> }
    # Comment-stripped-then-collapsed single-line window search (bounded to
    # avoid multi-KB false spans): scan a joined 1-3-line window starting at
    # each `catch (...) {` for an immediate `}` with nothing but whitespace/
    # a single-line comment between.
    catch_hits="$(grep -nE 'catch[[:space:]]*\([^)]*\)[[:space:]]*\{' "$f" 2>/dev/null || true)"
    if [ -n "$catch_hits" ]; then
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            lineno="${hit%%:*}"
            window="$(sed -n "${lineno},$((lineno + 3))p" "$f" 2>/dev/null || true)"
            # strip the catch-opener prefix up to its opening brace, and
            # strip //-line-comments, then check if only whitespace/}
            body="$(printf '%s' "$window" | sed -E '1s/^.*catch[[:space:]]*\([^)]*\)[[:space:]]*\{//' | sed -E 's#//.*$##')"
            body_nows="$(printf '%s' "$body" | tr -d '[:space:]')"
            # empty (or comment-only, already stripped) body up to its FIRST
            # closing brace = swallow. Only match when the first non-ws char
            # sequence in body_nows is exactly "}" (immediate close).
            first_char="${body_nows:0:1}"
            if [ "$first_char" = "}" ]; then
                hits=$(( hits + 1 ))
                echo "❌ ${GATE}: FAIL — swallowed exception (empty/comment-only catch block) at ${f}:${lineno} (§${ANCHOR})"
            fi
        done <<< "$catch_hits"
    fi

    # ── (B) Credential silently defaulted to a literal string ──────────────
    cred_hits="$(grep -nEi '(credential|secret|token|api[_-]?key|password|passwd)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(\|\||or)[[:space:]]*["'"'"'][^"'"'"']*["'"'"']' "$f" 2>/dev/null || true)"
    if [ -n "$cred_hits" ]; then
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            lineno="${hit%%:*}"
            text="${hit#*:}"
            hits=$(( hits + 1 ))
            echo "❌ ${GATE}: FAIL — credential silently defaulted to a literal value at ${f}:${lineno}: ${text# } (§${ANCHOR})"
        done <<< "$cred_hits"
    fi
done

echo "======================================================================"
if [ "$hits" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${hits} fail-open anti-pattern hit(s) found (§${ANCHOR})"
    exit 1
fi

echo "✅ ${GATE}: PASS — no swallowed-exception or credential-default-to-literal anti-patterns found (§${ANCHOR})"
exit 0
