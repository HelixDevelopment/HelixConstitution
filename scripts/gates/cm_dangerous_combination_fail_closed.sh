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
# flow analysis this gate CANNOT honestly claim. This gate therefore
# implements the LITERAL, NAMED, structurally-precise HALF of the anchor --
# detecting the two most structurally unambiguous fail-open anti-pattern
# SHAPES the anchor itself enumerates:
#
#   (A) SWALLOWED EXCEPTION — a handler that neither re-raises, nor logs, nor
#       performs any fallback work. Two concrete, decidable body shapes:
#         (A1) SWALLOW          the sole body statement is `pass` (or `...`)
#         (A2) SILENT DEFAULT   the sole body statement returns a TRIVIAL
#                               LITERAL (bare `return`, a constant, or an
#                               EMPTY container). Handing the caller a
#                               plausible-looking value that carries zero
#                               information about the failure is the same
#                               fail-open defect as `pass` -- arguably worse,
#                               because the caller cannot tell it happened.
#       For C-family/JS/TS/Java/C#/PHP the analogue is an empty or
#       comment-only `catch (...) { }` body.
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
# ── Why Python is analysed STRUCTURALLY, not textually (§11.4.201(7)(a)) ────
# Shape (A) is a property of the PARSE TREE, not of the source text, and a
# text scanner gets it wrong in BOTH directions -- each direction a §11.4
# bluff in its own right:
#
#   FALSE NEGATIVES (a §11.4.201(6) false-null: the gate returns a confident
#   number that is a FLOOR, not a census) — a line-anchored regex cannot see
#     * `except Exception:  # noqa: S110`   (a trailing comment; the sites a
#       human consciously reviewed and annotated are exactly the ones the
#       scanner goes blind to)
#     * `except (OSError, ValueError):`     (a tuple clause)
#     * a comment sitting between `except` and `pass` (so a reviewer ADDING
#       an explanatory comment silently deletes the site from the report)
#     * `except: return None`               (the (A2) silent-default shape)
#
#   FALSE POSITIVES (a §11.4.201(1) FAIL-bluff: refusing healthy code) — a
#   text scanner fires on a CARRIER: a docstring, comment, or string literal
#   that merely MENTIONS `except: pass`, such as a style guide documenting
#   the anti-pattern, or this gate's own test fixtures.
#
# A parser is immune to both by construction: a string literal is not a
# `Try` node, and a comment is not a statement. Python files are therefore
# analysed with the stdlib `ast` module when a Python 3 interpreter is
# available. When one is NOT available the gate falls back to a hardened
# text scan and says so LOUDLY on stdout -- a degraded instrument that
# announces its degradation, never a silent floor reported as a census
# (§11.4.6 / §11.4.201(6)).
#
# This gate does NOT attempt to detect the remaining three anchor shapes
# (validate-then-proceed-anyway, untrusted-input-defaulted-to-a-target,
# unbounded-retry-around-a-dangerous-call) — each requires either multi-line
# control-flow correlation or a semantic "is this retry bounded" judgement
# that would risk becoming an unreliable, bluff-prone heuristic. Their
# coverage remains §11.4.142/§11.4.194 human-review territory, stated as an
# honest gap (§11.4.6), never silently claimed covered. Likewise a handler
# body of TWO OR MORE statements is deliberately NOT flagged: it is doing
# SOMETHING, and deciding whether that something constitutes genuine
# fallback handling is a judgement, not a decidable structural fact.
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
#   DANGEROUS_COMBO_PYTHON    Python 3 interpreter used for AST analysis of
#                              .py files (default: python3, then python).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-hit evidence line (file:line + matched anti-pattern class) + a final
#   PASS / FAIL verdict. Degraded-mode and unparseable-file NOTEs when the
#   structural analysis could not be applied.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). The AST analyser PARSES Python sources; it never
#   IMPORTS or EXECUTES them (`ast.parse` runs no user code).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, grep (GNU or BSD ERE), sed, awk. OPTIONALLY a Python 3
#   interpreter for structural analysis of .py files (absence is handled
#   honestly, never silently). Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.252 (the anchor enforced — literal-shape half), §11.4.201(1)/(6)/
#   (7)(a) (false-positive refusal is a FAIL-bluff; a null is not evidence;
#   match structure not substring), §11.4.6 (honest documented bounded
#   limitation, never silent), §11.4.28/§11.4.35 (project-agnostic, env-var-
#   driven), §1.1 (paired mutation:
#   cm_dangerous_combination_fail_closed_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no candidate source files, or no anti-pattern hit found).
#   1 — FAIL (a swallowed-exception, silent-default-return, or credential-
#       default-to-literal hit).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-DANGEROUS-COMBINATION-FAIL-CLOSED"
ANCHOR="11.4.252"
HEADER_LINES=133

root="${DANGEROUS_COMBO_ROOT:-..}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n "1,${HEADER_LINES}p" "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ── Python interpreter discovery for the structural analyser ────────────────
# Resolved by REAL capability, not by name alone: the candidate must actually
# run and import `ast` (§11.4.201 — assert the real condition, and take the
# conservative-safe path, announced, when the signal is unresolvable).
py_bin=""
py_usable() { # $1=candidate -> 0 when it really runs and can import ast
    command -v "$1" >/dev/null 2>&1 || return 1
    "$1" -c 'import sys, ast; sys.exit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1
}
if [ -n "${DANGEROUS_COMBO_PYTHON:-}" ]; then
    # An EXPLICIT operator pin is authoritative: if it does not resolve to a
    # working Python 3 the gate degrades LOUDLY rather than silently
    # substituting a different interpreter behind the operator's back
    # (§11.4.6 / §11.4.201 — say what actually happened).
    if py_usable "$DANGEROUS_COMBO_PYTHON"; then
        py_bin="$DANGEROUS_COMBO_PYTHON"
    else
        echo "⚠ ${GATE}: NOTE — DANGEROUS_COMBO_PYTHON='${DANGEROUS_COMBO_PYTHON}' is not a usable Python 3; NOT substituting another interpreter. Python files fall back to the TEXT scanner (a FLOOR, not a census — §11.4.6/§11.4.201(6))."
    fi
else
    for cand in python3 python; do
        if py_usable "$cand"; then py_bin="$cand"; break; fi
    done
fi

# ── Text-scan fallback for Python (used only when no interpreter is present,
#    or for a file the parser could not read). Hardened relative to the
#    original line-anchored form so the degraded mode is a HIGHER floor:
#    it now tolerates a tuple clause and a trailing comment on the `except`
#    line, and skips comment/blank lines inside the handler body. It still
#    cannot see string-literal carriers, which is exactly why it is the
#    fallback and not the primary. ──────────────────────────────────────────
scan_py_text() { # $1=file  -> echoes one "lineno" per swallowed handler
    local f="$1"
    awk '
        function indent_of(s,   t) { t = s; sub(/[^ \t].*$/, "", t); return length(t) }
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        {
            lines[NR] = $0
        }
        END {
            for (i = 1; i <= NR; i++) {
                line = lines[i]
                # `except`, optional clause (may contain a tuple / dotted name /
                # `as` binding), colon, optional trailing comment.
                if (line !~ /^[ \t]*except([ \t]+[^:#]+)?[ \t]*:[ \t]*(#.*)?$/) continue
                exc_indent = indent_of(line)
                # first REAL statement of the handler body: skip blank and
                # comment-only lines (a comment must not hide the body).
                body_i = 0
                for (j = i + 1; j <= NR; j++) {
                    t = trim(lines[j])
                    if (t == "" || substr(t, 1, 1) == "#") continue
                    body_i = j
                    break
                }
                if (body_i == 0) continue
                body = trim(lines[body_i])
                is_swallow = 0
                if (body == "pass" || body == "...") {
                    is_swallow = 1
                } else if (body ~ /^return[ \t]*$/) {
                    is_swallow = 1                 # bare `return`
                } else if (body ~ /^return[ \t]+/) {
                    # Silent default: `return <trivial literal>` only. The
                    # value is compared as a STRING rather than matched by
                    # regex so no quote character has to be escaped through
                    # the bash -> awk -> ERE layers (§11.4.201(7)(c): the
                    # quoting path is part of the instrument).
                    val = body
                    sub(/^return[ \t]+/, "", val)
                    sub(/[ \t]+$/, "", val)
                    q = sprintf("%c", 39)          # apostrophe, unquotable inline
                    if (val == "None" || val == "True" || val == "False" ||
                        val == "[]" || val == "{}" || val == "()" ||
                        val ~ /^-?[0-9]+(\.[0-9]+)?$/) {
                        is_swallow = 1
                    } else if (val ~ /^"[^"]*"$/ || val ~ ("^" q "[^" q "]*" q "$")) {
                        # A plain quoted string constant (`return "NotFound"`).
                        # An f-string / concatenation does NOT match, because the
                        # value would not START with the quote character - those
                        # compute something and are fallback handling, not a
                        # silent default.
                        is_swallow = 1
                    }
                }
                if (!is_swallow) continue
                # the handler body must consist of that ONE statement: the next
                # real line must dedent out of the body (or the file ends).
                nxt = 0
                for (j = body_i + 1; j <= NR; j++) {
                    t = trim(lines[j])
                    if (t == "" || substr(t, 1, 1) == "#") continue
                    nxt = j
                    break
                }
                if (nxt != 0 && indent_of(lines[nxt]) > exc_indent) continue
                print i
            }
        }
    ' "$f" 2>/dev/null || true
}

# ── (A) Python: STRUCTURAL analysis via the stdlib ast module ───────────────
# The analyser receives the file list NUL-separated on stdin and reports hits
# by ARRAY INDEX, never by path, so a path containing a tab or newline can
# never corrupt the protocol.
py_files=()
for f in "${files[@]}"; do
    case "$f" in *.py) py_files+=("$f") ;; esac
done

py_text_fallback_files=()

if [ "${#py_files[@]}" -gt 0 ]; then
    if [ -n "$py_bin" ]; then
        ast_out="$(printf '%s\0' "${py_files[@]}" | "$py_bin" -c '
import ast, sys

# Shape (A) is decided from the PARSE TREE. A comment is not a statement and
# a string literal is not a Try node, so trailing comments, tuple clauses,
# comments inside the body, and documentation carriers are all handled by
# construction rather than by an accumulating stack of regex epicycles.

TRY_TYPES = tuple(
    t for t in (getattr(ast, "Try", None), getattr(ast, "TryStar", None))
    if t is not None
)


def is_docstring(stmt):
    return (
        isinstance(stmt, ast.Expr)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    )


def is_trivial_literal(value):
    """True for a value that carries ZERO information about the failure.

    A populated container or any computed expression is deliberately NOT
    trivial: it is doing work, which is fallback handling rather than a
    silent default (§11.4.6 — flag only the decidable shape).
    """
    if value is None:                       # bare `return`
        return True
    if isinstance(value, ast.Constant):     # None / True / False / 0 / "" ...
        return True
    if isinstance(value, (ast.List, ast.Tuple, ast.Set)) and not value.elts:
        return True
    if isinstance(value, ast.Dict) and not value.keys:
        return True
    return False


def classify(handler):
    body = [s for s in handler.body if not is_docstring(s)]
    # Two or more statements means the handler is doing something; whether
    # that something is adequate is a review judgement, not a structural fact.
    if len(body) != 1:
        return None
    stmt = body[0]
    if isinstance(stmt, ast.Pass):
        return "swallow"
    if (isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant)
            and stmt.value.value is Ellipsis):
        return "swallow"
    if isinstance(stmt, ast.Return) and is_trivial_literal(stmt.value):
        return "default"
    return None


data = sys.stdin.buffer.read().split(b"\0")
paths = [p for p in data if p]
for idx, raw in enumerate(paths):
    path = raw.decode("utf-8", "surrogateescape")
    try:
        with open(path, "rb") as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (SyntaxError, ValueError, OSError, UnicodeDecodeError) as exc:
        # Never a silent skip: hand the file back for the text fallback and
        # report why the structural read failed (§11.4.201(6)).
        reason = type(exc).__name__
        sys.stdout.write("UNPARSED\t%d\t%s\n" % (idx, reason))
        continue
    for node in ast.walk(tree):
        if not isinstance(node, TRY_TYPES):
            continue
        for handler in getattr(node, "handlers", []):
            kind = classify(handler)
            if kind:
                sys.stdout.write("HIT\t%s\t%d\t%d\n" % (kind, idx, handler.lineno))
' 2>/dev/null)"
        ast_rc=$?
        if [ "$ast_rc" -ne 0 ]; then
            # The analyser itself failed. Do NOT report a clean number from a
            # broken instrument (§11.4.201(6)); degrade loudly to text.
            echo "⚠ ${GATE}: NOTE — the Python AST analyser exited ${ast_rc}; falling back to the TEXT scanner for all Python files. Python results below are a FLOOR, not a census (§11.4.6/§11.4.201(6))."
            py_text_fallback_files=("${py_files[@]}")
        else
            while IFS=$'\t' read -r tag a b c; do
                case "$tag" in
                    HIT)
                        f="${py_files[$b]}"
                        if [ "$a" = "default" ]; then
                            echo "❌ ${GATE}: FAIL — silent default return (exception handler returns a trivial literal with no re-raise/log) at ${f}:${c} (§${ANCHOR})"
                        else
                            echo "❌ ${GATE}: FAIL — swallowed exception (handler body is only 'pass' with no re-raise/log) at ${f}:${c} (§${ANCHOR})"
                        fi
                        hits=$(( hits + 1 ))
                        ;;
                    UNPARSED)
                        f="${py_files[$a]}"
                        echo "⚠ ${GATE}: NOTE — ${f} could not be parsed as Python 3 (${b}); analysed by the TEXT fallback, whose result for this file is a FLOOR (§11.4.6)."
                        py_text_fallback_files+=("$f")
                        ;;
                esac
            done <<< "$ast_out"
        fi
    else
        echo "⚠ ${GATE}: NOTE — no Python 3 interpreter found (tried \$DANGEROUS_COMBO_PYTHON, python3, python); Python files analysed by the TEXT scanner, whose results are a FLOOR, not a census (§11.4.6/§11.4.201(6)). Set DANGEROUS_COMBO_PYTHON to enable structural analysis."
        py_text_fallback_files=("${py_files[@]}")
    fi
fi

# Text fallback for any Python file the parser could not cover.
if [ "${#py_text_fallback_files[@]}" -gt 0 ]; then
    for f in "${py_text_fallback_files[@]}"; do
        while IFS= read -r lineno; do
            [ -n "$lineno" ] || continue
            hits=$(( hits + 1 ))
            echo "❌ ${GATE}: FAIL — swallowed exception (Python fail-open handler, text scan) at ${f}:${lineno} (§${ANCHOR})"
        done < <(scan_py_text "$f")
    done
fi

for f in "${files[@]}"; do
    # ── (A) C-family/JS/TS/Java/C#/PHP: catch (...) { <empty-or-comment-only> }
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

echo "✅ ${GATE}: PASS — no swallowed-exception, silent-default-return or credential-default-to-literal anti-patterns found (§${ANCHOR})"
exit 0
