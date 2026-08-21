#!/bin/sh
# shell_mutation_engine.sh — a POSIX-shell MUTATION ENGINE (original work,
# §11.4.8) for feature 002-anti-slop-enforcement, task T408b.
#
# ── Why this exists at all ──────────────────────────────────────────────────
# Constitution Principle IV / §11.4.224(C) sets the bar at a MEASURED MUTATION
# SCORE over the changed lines. The project today ships one AUTHORED mutation
# per gate — a GUARD-VIABILITY RATIO, which is not a mutation score. CT-4
# recorded that gap honestly instead of relabelling the weaker metric.
#
# Adoption was checked before building (§11.4.8): measured on this host,
# `command -v` returns ABSENT for gremlins, mutmut, stryker, pitest, mull,
# cargo-mutants, universalmutator, mutate, bats, shellspec, shunit2 and kcov,
# while the SAME lookup returns a path for `bash` and `go` — so the absence was
# SEEN, not blind (§11.4.201(7)(b)). The project's own prior research records
# the same fact at docs/research/mutation_testing_submodule/P0_research.md:48
# ("Bash / shell | NONE dedicated (FACT — no shell mutation engine surfaced)").
# There is nothing to adopt, so this is original work.
#
# SCOPE. This is a FEATURE-SCOPED shell engine. It is deliberately NOT the
# eleven-language polyglot submodule described in INITIATIVE_SEED.md — CT-4
# rejected building that inside this feature, and this does not build it.
#
# ── The load-bearing idea: a zero must be earned ────────────────────────────
# "0 mutants killed" and "the kill command cannot detect anything" produce the
# IDENTICAL quiet number. Before this engine reports a low score it runs a
# SENTINEL mutant — a deliberately catastrophic edit that any working kill
# command must catch. If the sentinel SURVIVES, the engine reports
# KILLER_BLIND and refuses to emit a score at all. That is §11.4.201(7)(b)'s
# control needle applied to mutation scoring: an unproven instrument's zero is
# not evidence.
#
# ── Public API ──────────────────────────────────────────────────────────────
#   sme_operators                          -> prints the declared operator set
#   sme_changed_lines <diff> <path>        -> prints changed NEW-file line nums
#   sme_score <src> <lines-file> <workdir> <kill-cmd-template>
#        The template MUST contain the literal {mutant}; it is replaced with
#        the path of the file under test. The command is expected to exit 0 on
#        the ORIGINAL file and non-zero on a broken one.
#        Sets: SME_STATUS SME_GENERATED SME_KILLED SME_SURVIVED SME_INVALID
#              SME_SCORE_PCT SME_SURVIVORS
#        SME_STATUS is one of
#              OK | BASELINE_RED | KILLER_BLIND | NO_MUTANTS
#
# ── Side-effects ────────────────────────────────────────────────────────────
#   Writes ONLY inside the caller-supplied <workdir>. It NEVER edits the source
#   file and NEVER touches the working tree — a mutation run must not be able to
#   leave mutation residue behind (§11.4.84; the residue incident is exactly why
#   this engine works on copies).
#
# ── Honest boundary (§11.4.6) ───────────────────────────────────────────────
#   * A score is relative to the OPERATOR SET APPLIED. It is never a claim of
#     exhaustiveness; adding an operator can only lower a previously-reported
#     score, and that is the honest direction.
#   * EQUIVALENT MUTANTS (semantically identical to the original) are unkillable
#     by construction and are counted as survivors. The engine does not detect
#     them — no engine reliably does — so a score below 100% is a lead, not a
#     verdict.
#   * Mutants that do not PARSE are discarded as INVALID and excluded from the
#     denominator; counting them would inflate the score with free kills.
#   * Portability: written to POSIX sh, parses clean under `sh -n` and `bash -n`.
#     NO dash/busybox/ksh/mksh/posh exists on this host (measured), so
#     dash-portability is asserted by construction, not proven.
#
# ── Dependencies ────────────────────────────────────────────────────────────
#   POSIX sh, awk, sed, mktemp.

# ---------------------------------------------------------------------------
# The declared operator set. Finite, in-source, and printed on demand so a
# reported score always states what produced it.
# ---------------------------------------------------------------------------
sme_operators() {
    cat <<'EOO'
ROR   relational-operator swap   -eq<->-ne  -lt<->-ge  -gt<->-le
SOR   string-comparison swap     " = "<->" != "
LCR   logical-connector swap     &&<->||
EMP   empty-test swap            -z<->-n
RSC   return/exit status swap    exit N->exit 0, return N->return 0  (N!=0)
AOB   integer off-by-one         first bare integer literal -> +1
SDL   statement deletion         the line becomes `:` (a no-op)
EOO
}

# ---------------------------------------------------------------------------
# sme_changed_lines <unified-diff> <path-suffix>
# Prints the NEW-file line numbers added or modified for the file whose
# `+++ b/...` header ends with <path-suffix>.
# ---------------------------------------------------------------------------
sme_changed_lines() {
    awk -v want="$2" '
        function endswith(s, suf) {
            return length(s) >= length(suf) && substr(s, length(s) - length(suf) + 1) == suf
        }
        /^\+\+\+ /  {
            p = $2
            sub(/^b\//, "", p)
            active = endswith(p, want) ? 1 : 0
            next
        }
        /^--- /     { next }
        /^@@ /      {
            if (!active) next
            # @@ -a,b +c,d @@
            h = $0
            sub(/^@@ [^+]*\+/, "", h)
            split(h, f, / /)
            split(f[1], g, /,/)
            newline = g[1] + 0
            next
        }
        {
            if (!active) next
            c = substr($0, 1, 1)
            if (c == "+") { print newline; newline++ }
            else if (c == " ") { newline++ }
            # a "-" line consumes no NEW-file line number
        }
    ' "$1"
}

# ---------------------------------------------------------------------------
# _sme_mutate <src> <lineno> <op> <dest>  — writes one mutant, rc 0 if the
# operator actually changed the line, rc 1 if it did not apply.
# ---------------------------------------------------------------------------
_sme_mutate() {
    _sme_src=$1; _sme_ln=$2; _sme_op=$3; _sme_dst=$4
    awk -v ln="$_sme_ln" -v op="$_sme_op" '
        function swap(s, a, b,   t) {
            # swap a<->b in one pass using a sentinel no shell source contains
            t = "\001"
            gsub(a, t, s); gsub(b, a, s); gsub(t, b, s)
            return s
        }
        NR != ln { print; next }
        {
            orig = $0
            s = $0
            if (op == "ROR") {
                s = swap(s, "-eq", "-ne"); s = swap(s, "-lt", "-ge"); s = swap(s, "-gt", "-le")
            } else if (op == "SOR") {
                s = swap(s, " = ", " != ")
            } else if (op == "LCR") {
                s = swap(s, "&&", "||")
            } else if (op == "EMP") {
                s = swap(s, "-z", "-n")
            } else if (op == "RSC") {
                gsub(/exit[ \t]+[1-9][0-9]*/, "exit 0", s)
                gsub(/return[ \t]+[1-9][0-9]*/, "return 0", s)
            } else if (op == "AOB") {
                if (match(s, /[0-9]+/)) {
                    n = substr(s, RSTART, RLENGTH) + 1
                    s = substr(s, 1, RSTART - 1) n substr(s, RSTART + RLENGTH)
                }
            } else if (op == "SDL") {
                if (match(s, /^[ \t]*/)) indent = substr(s, 1, RLENGTH); else indent = ""
                s = indent ":"
            }
            if (s == orig) { changed = 0 } else { changed = 1 }
            print s
        }
        END { exit changed ? 0 : 1 }
    ' "$_sme_src" > "$_sme_dst"
    _sme_rc=$?
    return $_sme_rc
}

# ---------------------------------------------------------------------------
# _sme_run_kill <kill-cmd-template> <path>  — substitutes {mutant} and runs it.
# Sets _SME_RUN_RC.
# ---------------------------------------------------------------------------
_sme_run_kill() {
    _sme_cmd=$(printf '%s\n' "$1" | sed "s|{mutant}|$2|g")
    ( eval "$_sme_cmd" ) >/dev/null 2>&1
    _SME_RUN_RC=$?
    return 0
}

# ---------------------------------------------------------------------------
# sme_score <src> <lines-file> <workdir> <kill-cmd-template>
# ---------------------------------------------------------------------------
sme_score() {
    _s_src=$1; _s_lines=$2; _s_wd=$3; _s_kill=$4

    SME_STATUS=OK
    SME_GENERATED=0
    SME_KILLED=0
    SME_SURVIVED=0
    SME_INVALID=0
    SME_SCORE_PCT=0
    SME_SURVIVORS=""

    [ -f "$_s_src" ]   || { SME_STATUS=BASELINE_RED; return 2; }
    [ -f "$_s_lines" ] || { SME_STATUS=NO_MUTANTS;   return 0; }
    mkdir -p "$_s_wd"  || { SME_STATUS=BASELINE_RED; return 2; }

    case $_s_kill in
        *'{mutant}'*) : ;;
        *) SME_STATUS=KILLER_BLIND; return 2 ;;
    esac

    # (1) BASELINE — the kill command must PASS on the unmutated file.
    _sme_run_kill "$_s_kill" "$_s_src"
    if [ "$_SME_RUN_RC" -ne 0 ]; then
        SME_STATUS=BASELINE_RED
        return 1
    fi

    # (2) CONTROL NEEDLE — a catastrophic sentinel mutant MUST be killed.
    #     Without this, "nothing killed" and "nothing could be seen" are the
    #     same quiet zero (§11.4.201(7)(b)).
    _s_sent="$_s_wd/sentinel.sh"
    awk 'NR==1 { print; print "exit 42"; next } { print }' "$_s_src" > "$_s_sent"
    _sme_run_kill "$_s_kill" "$_s_sent"
    if [ "$_SME_RUN_RC" -eq 0 ]; then
        SME_STATUS=KILLER_BLIND
        return 1
    fi

    # (3) generate + run
    _s_i=0
    while IFS= read -r _s_ln; do
        case $_s_ln in
            ''|*[!0-9]*) continue ;;
        esac
        for _s_op in ROR SOR LCR EMP RSC AOB SDL; do
            _s_i=$((_s_i + 1))
            _s_mut="$_s_wd/mut_${_s_ln}_${_s_op}.sh"
            _sme_mutate "$_s_src" "$_s_ln" "$_s_op" "$_s_mut"
            _s_applied=$?
            if [ "$_s_applied" -ne 0 ]; then
                rm -f "$_s_mut"
                continue
            fi
            sh -n "$_s_mut" 2>/dev/null
            _s_parse=$?
            if [ "$_s_parse" -ne 0 ]; then
                SME_INVALID=$((SME_INVALID + 1))
                rm -f "$_s_mut"
                continue
            fi
            SME_GENERATED=$((SME_GENERATED + 1))
            _sme_run_kill "$_s_kill" "$_s_mut"
            if [ "$_SME_RUN_RC" -ne 0 ]; then
                SME_KILLED=$((SME_KILLED + 1))
            else
                SME_SURVIVED=$((SME_SURVIVED + 1))
                SME_SURVIVORS="$SME_SURVIVORS line $_s_ln op $_s_op;"
            fi
        done
    done < "$_s_lines"

    if [ "$SME_GENERATED" -eq 0 ]; then
        SME_STATUS=NO_MUTANTS
        return 0
    fi

    SME_SCORE_PCT=$(( (SME_KILLED * 100) / SME_GENERATED ))
    SME_STATUS=OK
    return 0
}
