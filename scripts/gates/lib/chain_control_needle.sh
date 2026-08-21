#!/bin/sh
# chain_control_needle.sh — shared CONTROL-NEEDLE helper for the evidence-chain
# gates (T324, §11.4.201(6)(7)).
#
# ── The rule this file mechanises ────────────────────────────────────────────
# §11.4.201(7)(b): a NULL IS NOT EVIDENCE until a control needle proves the
# instrument can see through the SAME path. Every absence a gate reports MUST
# cite a class-matched needle result. A zero with no needle is reported as
# INSTRUMENT_BLIND — never as a clean artifact.
#
# The null is the dangerous direction: a blind instrument and a genuinely clean
# artifact return the identical quiet zero, so "0 hits" alone can never
# distinguish "the thing is not there" from "I could not have seen it".
#
# ── Why a BARE-LITERAL needle is not enough ──────────────────────────────────
# §11.4.201(7)(b) requires the needle to share the certified query's
# LOAD-BEARING FEATURES. A literal needle certifies only the layers a literal
# crosses. Three traps MEASURED on this host (ugrep 7.8.4), each of which a
# literal needle sails straight through while the real query dies:
#
#   (1) ANCHORING.   `^\[PASS\]` counted 1 against a file holding THREE present
#                    `[PASS]` verdicts, because two of them were INDENTED. The
#                    zero-ish answer was an artifact of the anchor, not of the
#                    content.
#   (2) ERE DIALECT. `foo\|bar` counted 0 against a file holding both `foo` and
#                    `bar`: under ERE `\|` is a LITERAL pipe, so the query
#                    searched for a string nobody wrote. `foo|bar` counted 2.
#   (3) PIPELINE.    `grep -q X file | head -1` reports status 0 even when grep
#                    found nothing — a pipeline returns its LAST stage's status.
#
# So this library (a) classifies a pattern's structural features, (b) REFUSES a
# needle whose feature set does not cover the query's, and (c) never reads an
# exit status through a pipeline: every status is captured DIRECTLY into CN_RC
# on the line after the command that produced it.
#
# ── Honest boundary (§11.4.6) — read before trusting a certification ─────────
# A certified ABSENT means: this tool, with these flags, over these targets,
# COULD see a construct of the query's class, and still found none of the
# query. It does NOT mean the query expressed what its author intended. Trap
# (2) above is exactly that residue: `foo\|bar` is a perfectly visible literal
# query, so a class-matched needle can certify its zero honestly while the
# author's ALTERNATION intent was never searched for at all. Intent is a review
# question (§11.4.142/§11.4.194), not something a needle can decide.
#
# Nor does a certification say anything about whether the thing found is the
# THING or merely a CARRIER that mentions it (§11.4.201(7)(a)) — that is what
# cn_count_noncarrier and cn_certified_absence_noncarrier are for.
#
# ── Public API ───────────────────────────────────────────────────────────────
#   cn_pattern_class <pattern>              -> prints structural feature tokens
#   cn_needle_covers <query> <needle>       -> rc 0 iff needle covers query
#   cn_count <flags> <pattern> <target...>  -> CN_COUNT, CN_RC
#   cn_count_noncarrier <flags> <pattern> <target...>
#                                           -> CN_COUNT (comment lines excluded)
#   cn_certified_absence <flags> <needle> <pattern> <target...>
#   cn_certified_absence_noncarrier <flags> <needle> <pattern> <target...>
#        both set CN_RESULT to one of
#            PRESENT | ABSENT | INSTRUMENT_BLIND | NEEDLE_CLASS_MISMATCH
#        and return  0 (PRESENT/ABSENT) | 3 (blind) | 4 (class mismatch)
#   cn_reset / cn_pass / cn_fail / cn_blind / cn_skip / cn_summary
#   cn_verdict_of <file> <id>               -> prints one assertion's verdict
#
# ── Verdict line format (deliberately trap-proof) ────────────────────────────
#   CN-VERDICT<TAB><ID><TAB><PASS|FAIL|BLIND|SKIP><TAB><message>
# Always flush-left, never coloured, tab-separated. Trap (1) above is precisely
# what happens to a reader anchored at `^` when the emitter indents or colours,
# so this emitter does neither, and cn_verdict_of reads a specific assertion by
# ID rather than counting `[PASS]`-shaped text.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   . "$(dirname "$0")/lib/chain_control_needle.sh"     # source it
#   sh chain_control_needle.sh --selftest               # run its own fixtures
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only. --selftest writes ONLY inside a mktemp -d it removes on exit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, grep (ugrep-compatible), awk, mktemp.

CN_TAB=$(printf '\t')
CN_BS='\'

# ---------------------------------------------------------------------------
# Pattern classification
# ---------------------------------------------------------------------------

# _cn_strip_escaped_pipes <string> — removes every two-character `\|` sequence.
# Implemented with parameter expansion rather than sed on purpose: GNU sed's
# BRE treats `\|` as ALTERNATION, so using sed to reason about `\|` would
# reproduce trap (2) inside the very code meant to detect it.
_cn_strip_escaped_pipes() {
    _cn_s=$1
    _cn_esc="$CN_BS|"
    _cn_acc=''
    while :; do
        case $_cn_s in
            *"$_cn_esc"*)
                _cn_acc="$_cn_acc${_cn_s%%"$_cn_esc"*}"
                _cn_s=${_cn_s#*"$_cn_esc"}
                ;;
            *)
                _cn_acc="$_cn_acc$_cn_s"
                break
                ;;
        esac
    done
    printf '%s' "$_cn_acc"
}

# cn_pattern_class <pattern> — prints the pattern's structural feature tokens,
# space-separated, from the closed set:
#   anchor alternation group class escape quantifier literal
#
# Over-detection is the SAFE direction: claiming a feature the pattern does not
# use only makes the needle requirement stricter (§11.4.101 — the conservative
# choice is the reversible one). Under-detection would let a weak needle
# certify a query it never exercised, which is the failure this file exists to
# prevent.
cn_pattern_class() {
    _cn_p=$1
    _cn_c=''
    case $_cn_p in *'^'*|*'$'*) _cn_c="$_cn_c anchor" ;; esac

    # Bare `|` is ERE alternation; `\|` is a literal pipe and is NOT.
    _cn_bare=$(_cn_strip_escaped_pipes "$_cn_p")
    case $_cn_bare in *'|'*) _cn_c="$_cn_c alternation" ;; esac

    case $_cn_p in *'('*|*')'*) _cn_c="$_cn_c group" ;; esac
    case $_cn_p in *'['*|*']'*) _cn_c="$_cn_c class" ;; esac
    case $_cn_p in *"$CN_BS"*) _cn_c="$_cn_c escape" ;; esac
    case $_cn_p in *'*'*|*'+'*|*'?'*|*'{'*) _cn_c="$_cn_c quantifier" ;; esac

    if [ -z "$_cn_c" ]; then
        printf 'literal\n'
    else
        printf '%s\n' "${_cn_c# }"
    fi
}

# cn_needle_covers <query> <needle> — rc 0 iff every STRUCTURAL feature of the
# query also appears in the needle. `literal` imposes no requirement: any
# needle crosses the layers a bare literal crosses.
cn_needle_covers() {
    _cn_q=$(cn_pattern_class "$1")
    _cn_n=$(cn_pattern_class "$2")
    CN_QUERY_CLASS=$_cn_q
    CN_NEEDLE_CLASS=$_cn_n
    for _cn_f in $_cn_q; do
        [ "$_cn_f" = literal ] && continue
        case " $_cn_n " in
            *" $_cn_f "*) ;;
            *) CN_MISSING_CLASS=$_cn_f; return 1 ;;
        esac
    done
    CN_MISSING_CLASS=''
    return 0
}

# ---------------------------------------------------------------------------
# Counting — exit status captured DIRECTLY, never through a pipeline
# ---------------------------------------------------------------------------

# cn_count <flags> <pattern> <target...>
#   CN_RC    grep's own status: 0 matched, 1 no match, >=2 tool/target error
#   CN_COUNT total matching lines across all targets
cn_count() {
    _cn_flags=$1; shift
    _cn_pat=$1;   shift
    # Word-splitting of $_cn_flags is deliberate: it is a caller-supplied flag
    # list, not data.
    # shellcheck disable=SC2086
    _cn_out=$(grep $_cn_flags -h -c -e "$_cn_pat" "$@" 2>/dev/null)
    CN_RC=$?
    CN_COUNT=$(printf '%s\n' "$_cn_out" | awk '
        { n = $0; sub(/^.*:/, "", n); s += n + 0 }
        END { print s + 0 }')
    return 0
}

# cn_count_noncarrier <flags> <pattern> <target...>
#   As cn_count, but a match on a COMMENT line does not count. A comment that
#   MENTIONS a symbol is a CARRIER, not a use of it (§11.4.201(7)(a)) — this is
#   the difference between "the classifier is called" and "the classifier is
#   described in a doc comment".
cn_count_noncarrier() {
    _cn_flags=$1; shift
    _cn_pat=$1;   shift
    # shellcheck disable=SC2086
    _cn_out=$(grep $_cn_flags -h -e "$_cn_pat" "$@" 2>/dev/null)
    CN_RC=$?
    CN_COUNT=$(printf '%s\n' "$_cn_out" | awk '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (line == "")            next
            if (line ~ /^\/\//)        next   # Go / C++ line comment
            if (line ~ /^#/)           next   # shell / YAML comment
            if (line ~ /^\*/)          next   # continuation of a block comment
            if (line ~ /^\/\*/)        next   # block-comment opener
            n++
        }
        END { print n + 0 }')
    return 0
}

# ---------------------------------------------------------------------------
# The certification primitive
# ---------------------------------------------------------------------------

_cn_certify() {
    _cn_counter=$1; shift
    _cn_flags=$1;   shift
    _cn_needle=$1;  shift
    _cn_query=$1;   shift

    CN_RESULT=''
    CN_DETAIL=''
    CN_COUNT=0

    if ! cn_needle_covers "$_cn_query" "$_cn_needle"; then
        CN_RESULT=NEEDLE_CLASS_MISMATCH
        CN_DETAIL="needle class [$CN_NEEDLE_CLASS] does not cover query class [$CN_QUERY_CLASS] (missing: $CN_MISSING_CLASS); a needle that does not exercise the query's load-bearing features certifies nothing"
        return 4
    fi

    # The needle goes through the SAME tool, the SAME flags and the SAME
    # targets: the PATH is part of the instrument (§11.4.201(7)(c)).
    "$_cn_counter" "$_cn_flags" "$_cn_needle" "$@"
    _cn_nrc=$CN_RC
    _cn_ncount=$CN_COUNT

    if [ "$_cn_nrc" -ge 2 ]; then
        CN_RESULT=INSTRUMENT_BLIND
        CN_DETAIL="the instrument errored (rc=$_cn_nrc) on the needle; targets unreadable or tool failure — nothing was observed"
        return 3
    fi
    if [ "$_cn_ncount" -eq 0 ]; then
        CN_RESULT=INSTRUMENT_BLIND
        CN_DETAIL="control needle [$_cn_needle] returned 0 through this path; the instrument cannot see here, so a zero for the query says NOTHING about the artifact"
        return 3
    fi

    "$_cn_counter" "$_cn_flags" "$_cn_query" "$@"
    if [ "$CN_RC" -ge 2 ]; then
        CN_RESULT=INSTRUMENT_BLIND
        CN_DETAIL="the instrument errored (rc=$CN_RC) on the query although the needle was visible"
        return 3
    fi
    if [ "$CN_COUNT" -gt 0 ]; then
        CN_RESULT=PRESENT
        CN_DETAIL="$CN_COUNT match(es); needle saw $_cn_ncount"
        return 0
    fi
    CN_RESULT=ABSENT
    CN_DETAIL="0 matches, CERTIFIED by control needle [$_cn_needle] which returned $_cn_ncount through the same tool, flags and targets"
    return 0
}

# cn_certified_absence <flags> <needle> <query> <target...>
cn_certified_absence() { _cn_certify cn_count "$@"; }

# cn_certified_absence_noncarrier <flags> <needle> <query> <target...>
cn_certified_absence_noncarrier() { _cn_certify cn_count_noncarrier "$@"; }

# ---------------------------------------------------------------------------
# Verdict emission and tally
# ---------------------------------------------------------------------------

cn_reset() { CN_N_PASS=0; CN_N_FAIL=0; CN_N_BLIND=0; CN_N_SKIP=0; }

_cn_emit() { printf 'CN-VERDICT%s%s%s%s%s%s\n' "$CN_TAB" "$1" "$CN_TAB" "$2" "$CN_TAB" "$3"; }

cn_pass()  { CN_N_PASS=$((CN_N_PASS + 1));   _cn_emit "$1" PASS  "$2"; }
cn_fail()  { CN_N_FAIL=$((CN_N_FAIL + 1));   _cn_emit "$1" FAIL  "$2"; }
# A BLIND instrument is NOT a pass. It is an undecided result and it fails the
# gate: reporting "undecided" as "intact" is the exact bluff §11.4.201(6)
# forbids.
cn_blind() { CN_N_BLIND=$((CN_N_BLIND + 1)); _cn_emit "$1" BLIND "$2"; }
cn_skip()  { CN_N_SKIP=$((CN_N_SKIP + 1));   _cn_emit "$1" SKIP  "$2"; }

# cn_summary <gate-name> — rc 0 only when nothing FAILed and nothing was BLIND.
cn_summary() {
    printf 'CN-SUMMARY%s%s%sPASS=%s FAIL=%s BLIND=%s SKIP=%s\n' \
        "$CN_TAB" "$1" "$CN_TAB" "$CN_N_PASS" "$CN_N_FAIL" "$CN_N_BLIND" "$CN_N_SKIP"
    if [ "$CN_N_FAIL" -gt 0 ] || [ "$CN_N_BLIND" -gt 0 ]; then
        return 1
    fi
    return 0
}

# cn_verdict_of <file> <id> — prints the verdict recorded for exactly <id>.
#
# This is what a paired §1.1 mutation test reads, so that it can assert the
# mutation flipped its OWN named assertion rather than a neighbouring one
# (§11.4.194(6)(d)). It prints `ABSENT_ID` when the id is not in the file, and
# `AMBIGUOUS` when it appears more than once — never a silent empty string,
# which a caller would read as a clean result.
cn_verdict_of() {
    _cn_file=$1
    _cn_id=$2
    [ -f "$_cn_file" ] || { printf 'NO_FILE\n'; return 1; }
    _cn_v=$(awk -F'\t' -v id="$_cn_id" '
        $1 == "CN-VERDICT" && $2 == id { print $3; n++ }
        END { if (n > 1) print "AMBIGUOUS" }' "$_cn_file")
    case $_cn_v in
        '')          printf 'ABSENT_ID\n'; return 1 ;;
        *AMBIGUOUS*) printf 'AMBIGUOUS\n'; return 1 ;;
        *)           printf '%s\n' "$_cn_v"; return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Self-test (§11.4.107(10)): golden-good, golden-bad, and a carrier negative
# control. A helper whose own blindness detector is untested is exactly the
# unvalidated instrument it exists to forbid.
# ---------------------------------------------------------------------------

cn_selftest() {
    _st_fail=0
    _st_dir=$(mktemp -d "${TMPDIR:-/tmp}/cn_selftest.XXXXXX") || return 2
    # shellcheck disable=SC2064
    trap "rm -rf '$_st_dir'" EXIT INT TERM

    # Fixture A — verdicts, two of three INDENTED (the measured anchor trap).
    printf '  [PASS] indented one\n  [PASS] indented two\n[PASS] flush\n' > "$_st_dir/verdicts.txt"
    # Fixture B — a real (non-comment) use plus a comment CARRIER of the token.
    printf 'package p\n\nfunc f() { RequiresEntry(c) }\n' > "$_st_dir/real_use.go"
    printf 'package p\n\n// RequiresEntry is described here but never called.\nfunc g() {}\n' > "$_st_dir/carrier.go"
    # Fixture C — holds foo and bar but no literal pipe.
    printf 'foo\nbar\n' > "$_st_dir/fb.txt"

    _st() { # _st <id> <expected> <actual> <note>
        if [ "$2" = "$3" ]; then
            printf 'SELFTEST%sok  %s%s(%s)%s%s\n' "$CN_TAB" "$1" "$CN_TAB" "$3" "$CN_TAB" "$4"
        else
            printf 'SELFTEST%sBAD %s%sexpected=%s got=%s%s%s\n' \
                "$CN_TAB" "$1" "$CN_TAB" "$2" "$3" "$CN_TAB" "$4"
            _st_fail=$((_st_fail + 1))
        fi
    }

    # GG-1 golden-good: a present token must report PRESENT, never ABSENT.
    cn_certified_absence '-E' '\[PASS\] flush' '\[PASS\]' "$_st_dir/verdicts.txt"
    _st GG-1-present PRESENT "$CN_RESULT" 'present token reports PRESENT'

    # GG-2 golden-good: a genuinely absent token, needle visible -> ABSENT.
    cn_certified_absence '-E' '\[PASS\]' '\[NOSUCHVERDICT\]' "$_st_dir/verdicts.txt"
    _st GG-2-certified-absent ABSENT "$CN_RESULT" 'real absence is CERTIFIED, not guessed'

    # GB-1 golden-bad: THE measured anchor trap. `^\[PASS\]` misses the two
    # indented verdicts; a class-matched (anchor+class+escape) needle that is
    # genuinely present-but-indented also returns 0, so the helper MUST say
    # INSTRUMENT_BLIND. Reporting ABSENT here is the whole failure mode.
    # The needle names text that IS in the file ("[PASS] indented one") and is
    # anchored EXACTLY as the query is. Because the line is indented, the needle
    # returns 0 -- which is the anchor being exposed, not the file being clean.
    cn_certified_absence '-E' '^\[PASS\] indented one' '^\[PASS\] indented two' \
        "$_st_dir/verdicts.txt"
    _st GB-1-anchor-trap INSTRUMENT_BLIND "$CN_RESULT" 'anchored query over indented lines is BLIND, not clean'

    # GB-2 golden-bad: a bare-LITERAL needle may not certify an ALTERNATION
    # query — §11.4.201(7)(b), the clause a naive needle silently violates.
    cn_certified_absence '-E' 'foo' 'zzz|qqq' "$_st_dir/fb.txt"
    _st GB-2-class-mismatch NEEDLE_CLASS_MISMATCH "$CN_RESULT" 'literal needle refused for an alternation query'

    # GB-3 golden-bad: an unreadable target is blindness, never absence.
    cn_certified_absence '-E' 'foo' 'zzz' "$_st_dir/does_not_exist.txt"
    _st GB-3-missing-target INSTRUMENT_BLIND "$CN_RESULT" 'unreadable target is BLIND, not clean'

    # NEG-1 negative control (false-positive guard): a REAL use must still be
    # found once comment carriers are excluded. A carrier filter that hides
    # genuine uses would make every gate refuse healthy work (§11.4.201(1)).
    cn_certified_absence_noncarrier '-E' 'package' 'RequiresEntry' "$_st_dir/real_use.go"
    _st NEG-1-real-use-survives PRESENT "$CN_RESULT" 'genuine use survives the carrier filter'

    # NEG-2 carrier: the same token in a comment only must NOT count as a use.
    cn_certified_absence_noncarrier '-E' 'package' 'RequiresEntry' "$_st_dir/carrier.go"
    _st NEG-2-carrier-excluded ABSENT "$CN_RESULT" 'comment-only mention is a CARRIER, not a use'

    # NEG-3: the plain (carrier-blind) count DOES see it — proving NEG-2 was the
    # filter working, not the file being empty.
    cn_count '-E' 'RequiresEntry' "$_st_dir/carrier.go"
    if [ "$CN_COUNT" -ge 1 ]; then _st NEG-3-carrier-visible-unfiltered 1 1 'carrier is visible to an unfiltered scan'
    else _st NEG-3-carrier-visible-unfiltered 1 0 'carrier is visible to an unfiltered scan'; fi

    # CLS-1..3: the classifier itself, including the ERE literal-pipe fact.
    _st CLS-1-escaped-pipe-not-alternation 'escape' "$(cn_pattern_class 'foo\|bar')" 'ERE \| is a LITERAL pipe, not alternation'
    _st CLS-2-bare-pipe-is-alternation 'alternation' "$(cn_pattern_class 'foo|bar')" 'bare | is alternation'
    _st CLS-3-anchor-class-escape 'anchor class escape' "$(cn_pattern_class '^\[PASS\]')" 'anchor+class+escape detected'

    # VER-1/2: cn_verdict_of must read a NAMED assertion and must never return a
    # silent empty string for an id it did not find.
    cn_reset
    { cn_pass ALPHA 'a'; cn_fail BETA 'b'; } > "$_st_dir/verdicts.out"
    _st VER-1-named-read FAIL "$(cn_verdict_of "$_st_dir/verdicts.out" BETA)" 'reads the named assertion'
    _st VER-2-unknown-id ABSENT_ID "$(cn_verdict_of "$_st_dir/verdicts.out" NOSUCH)" 'unknown id is ABSENT_ID, not empty'

    printf 'SELFTEST-SUMMARY%sbad=%s\n' "$CN_TAB" "$_st_fail"
    [ "$_st_fail" -eq 0 ] || return 1
    return 0
}

case ${1:-} in
    --selftest) cn_selftest; exit $? ;;
esac
