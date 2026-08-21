#!/bin/sh
# =============================================================================
# control_needle.sh — E4 CONTROL-RESULT evaluator (T219, FR-005 / FR-006).
#
# ── What this file is, and what it is NOT ────────────────────────────────────
# This library evaluates a RECORDED control result — the E4 artifact
# {needle, needle_hits, query_class_match, needle_command} that a producer
# writes alongside a null finding. Its question is: "does this recorded
# certification actually certify the zero it is attached to?"
#
# It is deliberately NOT a second copy of the live pattern/target scanner.
# `chain_control_needle.sh` already owns that layer (cn_pattern_class,
# cn_needle_covers, cn_count) and this file SOURCES it rather than forking it —
# §11.4.251 refuses the near-identical fork, and a second, drifting copy of the
# ERE-dialect classifier is precisely the bug that classifier exists to catch.
#
#   chain_control_needle.sh : live  — run a needle NOW over real targets
#   control_needle.sh (this): recorded — judge a needle result written earlier
#
# ── Public API (the contract T216 asserts) ───────────────────────────────────
#   cn_record <out.json> <needle> <needle_hits> <query_class_match> <needle_command>
#         Write an E4 control result verbatim from caller-supplied values.
#
#   cn_record_live <out.json> <grep-flags> <needle> <query> <target...>
#         The HONEST form: actually RUN the needle through cn_count and DERIVE
#         query_class_match from cn_needle_covers, so neither field is a claim
#         the caller simply asserted. Prefer this over cn_record.
#
#   cn_evaluate <control_result.json>       -> prints SIGHTED|BLIND + reason
#                                              rc 0 = certifies, 1 = does not
#   cn_assert_same_path <control_result.json> <certified_query_command>
#                                           -> rc 0 = same path, 1 = not
#
# ── Why cn_assert_same_path is the load-bearing half of FR-005 ───────────────
# FR-005 says the instrument must prove it can see "through the same code
# path". A needle executed through a DIFFERENT command string, dialect or
# redirection crossed different layers, so it certifies nothing about the
# query's zero. Measured on this host: `grep -q X f | head -1` reports the
# PAGER's status, so a needle run without the pipe and a query run with it are
# not the same instrument even though the pattern is identical.
#
# ── Refusal discipline (§11.4.6, §11.4.201(6)) ───────────────────────────────
# Every field is REFUSED when absent or unparseable. A missing needle_hits is
# never defaulted to a hit; an unreadable control result is BLIND, never
# SIGHTED. The quiet zero of a broken instrument and the quiet zero of a clean
# artifact are indistinguishable, so only a positive certification counts.
#
# ── Parsing note (measured trap class 5) ─────────────────────────────────────
# Fields are extracted with shell parameter expansion, NOT `sed 's/.*"k".../'`.
# A leading greedy `.*` binds to the LAST occurrence of the key on the line, so
# a row carrying the key twice would be read from the wrong one. `${v#*"k":}`
# always takes the FIRST.
#
# Usage : . constitution/scripts/gates/lib/control_needle.sh
#         sh constitution/scripts/gates/lib/control_needle.sh --selftest
# Deps  : POSIX sh, grep (via chain_control_needle.sh). No sed, no awk.
# Xref  : data-model.md E4 · §11.4.201(6)(7) · §11.4.251 · FR-005 · FR-006
# =============================================================================

set -u

CN_E4_LIB_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
# When this file is SOURCED, "$0" is the caller, so resolve the sibling helper
# relative to a path we can verify rather than trusting the caller's cwd.
if [ ! -f "${CN_E4_LIB_DIR}/chain_control_needle.sh" ]; then
    CN_E4_LIB_DIR="${CN_E4_SELF_DIR:-}"
fi
if [ -z "${CN_E4_LIB_DIR}" ] || [ ! -f "${CN_E4_LIB_DIR}/chain_control_needle.sh" ]; then
    for _cne_cand in \
        "$(dirname -- "$0")/lib" \
        "$(dirname -- "$0")/../lib" \
        "$(dirname -- "$0")/../gates/lib"
    do
        if [ -f "${_cne_cand}/chain_control_needle.sh" ]; then
            CN_E4_LIB_DIR=$(CDPATH='' cd -- "$_cne_cand" && pwd); break
        fi
    done
fi

# Sourcing with the caller's positional parameters still set would hand our own
# "$1" to the helper, whose tail runs `case ${1:-} in --selftest) ... exit`.
# A caller invoked as `... --selftest` would therefore silently run the OTHER
# library's selftest and exit. Clear the parameters across the source and put
# them back afterwards.
if [ -n "${CN_E4_LIB_DIR:-}" ] && [ -f "${CN_E4_LIB_DIR}/chain_control_needle.sh" ]; then
    _cne_argv_saved=$*
    _cne_argc=$#
    set --
    # shellcheck disable=SC1091
    . "${CN_E4_LIB_DIR}/chain_control_needle.sh"
    if [ "$_cne_argc" -gt 0 ]; then
        # shellcheck disable=SC2086
        set -- $_cne_argv_saved
    fi
    CN_E4_SHARED=1
else
    CN_E4_SHARED=0
fi

# --- field extraction (parameter expansion only; no greedy transform) --------

# _cn_e4_raw <line> <key> — the raw token after "<key>": up to the next
# delimiter. Takes the FIRST occurrence of the key, never the last.
_cn_e4_raw() {
    _cne_l=$1
    _cne_k="\"$2\""
    case $_cne_l in
        *"$_cne_k"*) : ;;
        *) printf ''; return 1 ;;
    esac
    _cne_v=${_cne_l#*"$_cne_k"}          # everything after the first "key"
    _cne_v=${_cne_v#*:}                  # drop the colon
    # strip one leading run of spaces/tabs
    while :; do
        case $_cne_v in
            " "*) _cne_v=${_cne_v# } ;;
            "	"*) _cne_v=${_cne_v#	} ;;
            *) break ;;
        esac
    done
    printf '%s' "$_cne_v"
    return 0
}

# _cn_e4_str <line> <key> — a quoted string value.
_cn_e4_str() {
    _cne_r=$(_cn_e4_raw "$1" "$2") || return 1
    case $_cne_r in
        '"'*) : ;;
        *) return 1 ;;
    esac
    _cne_r=${_cne_r#\"}
    printf '%s' "${_cne_r%%\"*}"
    return 0
}

# _cn_e4_bare <line> <key> — an unquoted value (number or true/false), read up
# to the first comma or closing brace.
_cn_e4_bare() {
    _cne_r=$(_cn_e4_raw "$1" "$2") || return 1
    _cne_r=${_cne_r%%,*}
    _cne_r=${_cne_r%%\}*}
    # trim trailing whitespace
    while :; do
        case $_cne_r in
            *" ") _cne_r=${_cne_r% } ;;
            *"	") _cne_r=${_cne_r%	} ;;
            *) break ;;
        esac
    done
    printf '%s' "$_cne_r"
    return 0
}

_cn_e4_is_uint() {
    case ${1:-} in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# --- public API --------------------------------------------------------------

cn_record() {  # <out> <needle> <hits> <query_class_match> <needle_command>
    [ $# -ge 5 ] || { printf 'cn_record: usage: <out> <needle> <hits> <qcm> <command>\n' >&2; return 2; }
    printf '{"needle":"%s","needle_hits":%s,"query_class_match":%s,"needle_command":"%s"}\n' \
        "$2" "$3" "$4" "$5" > "$1"
}

# cn_record_live <out> <grep-flags> <needle> <query> <target...>
# Runs the needle for real and derives query_class_match structurally. Both
# fields become MEASURED facts rather than caller assertions (§11.4.6).
cn_record_live() {
    [ $# -ge 5 ] || { printf 'cn_record_live: usage: <out> <flags> <needle> <query> <target...>\n' >&2; return 2; }
    if [ "${CN_E4_SHARED:-0}" -ne 1 ]; then
        printf 'cn_record_live: chain_control_needle.sh not resolved — refusing to reimplement its classifier (SS11.4.251)\n' >&2
        return 2
    fi
    _cne_out=$1; shift
    _cne_flags=$1; shift
    _cne_needle=$1; shift
    _cne_query=$1; shift
    CN_COUNT=0; CN_RC=0
    cn_count "$_cne_flags" "$_cne_needle" "$@"
    _cne_hits=$CN_COUNT
    _cne_qcm=false
    if cn_needle_covers "$_cne_query" "$_cne_needle"; then _cne_qcm=true; fi
    _cne_cmd="grep $_cne_flags -h -c -e $_cne_needle $*"
    cn_record "$_cne_out" "$_cne_needle" "$_cne_hits" "$_cne_qcm" "$_cne_cmd"
}

# cn_evaluate <control_result.json>
#   rc 0 -> SIGHTED: this control certifies the zero it is attached to
#   rc 1 -> BLIND:   it does not, and the reason is named
cn_evaluate() {
    if [ -z "${1:-}" ] || [ ! -r "$1" ]; then
        printf 'BLIND control result unreadable: %s\n' "${1:-<none>}"
        return 1
    fi
    _cne_line=$(head -n 1 -- "$1")
    if [ -z "$_cne_line" ]; then
        printf 'BLIND control result empty: %s — an empty certification certifies nothing\n' "$1"
        return 1
    fi

    _cne_h=$(_cn_e4_bare "$_cne_line" needle_hits) || _cne_h=''
    if [ -z "$_cne_h" ]; then
        printf 'BLIND needle_hits ABSENT — an absent hit count is never read as a hit\n'
        return 1
    fi
    if ! _cn_e4_is_uint "$_cne_h"; then
        printf 'BLIND needle_hits UNPARSEABLE (%s) — refused rather than defaulted to success\n' "$_cne_h"
        return 1
    fi
    if [ "$_cne_h" -eq 0 ]; then
        printf 'BLIND needle_hits=0 — the instrument did not find what it was told is present, so its zero for the query says NOTHING\n'
        return 1
    fi

    _cne_q=$(_cn_e4_bare "$_cne_line" query_class_match) || _cne_q=''
    case $_cne_q in
        true) : ;;
        false)
            printf 'BLIND query_class_match=false — the needle does not exercise the query load-bearing features (hits alone certify nothing)\n'
            return 1 ;;
        '')
            printf 'BLIND query_class_match ABSENT — an unrecorded class match is not a match\n'
            return 1 ;;
        *)
            printf 'BLIND query_class_match UNPARSEABLE (%s) — refused rather than defaulted to true\n' "$_cne_q"
            return 1 ;;
    esac

    _cne_n=$(_cn_e4_str "$_cne_line" needle) || _cne_n=''
    printf 'SIGHTED needle_hits=%s query_class_match=%s needle=%s\n' "$_cne_h" "$_cne_q" "${_cne_n:-<unnamed>}"
    return 0
}

# cn_assert_same_path <control_result.json> <certified_query_command>
cn_assert_same_path() {
    if [ -z "${1:-}" ] || [ ! -r "$1" ]; then
        printf 'BLIND control result unreadable: %s\n' "${1:-<none>}"
        return 1
    fi
    _cne_line=$(head -n 1 -- "$1")
    _cne_nc=$(_cn_e4_str "$_cne_line" needle_command) || _cne_nc=''
    if [ -z "$_cne_nc" ]; then
        printf 'BLIND needle_command not recorded — the path the needle crossed is unknown, so it cannot be shown to be the same one\n'
        return 1
    fi
    if [ "$_cne_nc" = "${2:-}" ]; then
        printf 'SAME-PATH needle_command matches the certified query command: %s\n' "$_cne_nc"
        return 0
    fi
    printf 'DIFFERENT-PATH needle ran as [%s] but the certified query is [%s] — a needle through another path certifies nothing (FR-005)\n' \
        "$_cne_nc" "${2:-<none>}"
    return 1
}

# --- selftest: golden-good / golden-bad / negative-control -------------------
cn_e4_selftest() {
    _st_d=$(mktemp -d) || return 2
    _st_bad=0
    _st() {  # <id> <expect rc> <actual rc> <what>
        if [ "$2" -eq "$3" ]; then printf 'SELFTEST %-34s ok   (%s)\n' "$1" "$4"
        else printf 'SELFTEST %-34s BAD  expected rc=%s got rc=%s (%s)\n' "$1" "$2" "$3" "$4"; _st_bad=$((_st_bad + 1)); fi
    }

    QC="grep -Ec 'alpha|beta' corpus.txt"

    cn_record "$_st_d/good.json"  known-present 5 true  "$QC"
    cn_evaluate "$_st_d/good.json" >/dev/null 2>&1; _st GG-sighted-certifies 0 $? 'golden-good: hits>0 + class match'

    cn_record "$_st_d/bad0.json"  known-present 0 true  "$QC"
    cn_evaluate "$_st_d/bad0.json" >/dev/null 2>&1; _st GB-zero-hits-blind 1 $? 'golden-bad: needle_hits=0'

    cn_record "$_st_d/badq.json"  plain_literal 7 false "$QC"
    cn_evaluate "$_st_d/badq.json" >/dev/null 2>&1; _st GB-class-mismatch-blind 1 $? 'golden-bad: query_class_match=false'

    printf '{"needle":"n","query_class_match":true,"needle_command":"%s"}\n' "$QC" > "$_st_d/nohits.json"
    cn_evaluate "$_st_d/nohits.json" >/dev/null 2>&1; _st GB-absent-hits-blind 1 $? 'golden-bad: needle_hits absent'

    printf '{"needle":"n","needle_hits":"many","query_class_match":true,"needle_command":"%s"}\n' "$QC" > "$_st_d/nan.json"
    cn_evaluate "$_st_d/nan.json" >/dev/null 2>&1; _st GB-unparseable-hits-blind 1 $? 'golden-bad: needle_hits unparseable'

    printf '{"needle":"n","needle_hits":3,"needle_command":"%s"}\n' "$QC" > "$_st_d/noqcm.json"
    cn_evaluate "$_st_d/noqcm.json" >/dev/null 2>&1; _st GB-absent-qcm-blind 1 $? 'golden-bad: query_class_match absent'

    cn_evaluate "$_st_d/no_such_file.json" >/dev/null 2>&1; _st GB-unreadable-blind 1 $? 'golden-bad: unreadable control result'

    cn_assert_same_path "$_st_d/good.json" "$QC" >/dev/null 2>&1; _st NC-same-path-certifies 0 $? 'negative control: identical command certifies'
    cn_assert_same_path "$_st_d/good.json" 'grep -c alpha corpus.txt' >/dev/null 2>&1; _st GB-different-path-refused 1 $? 'golden-bad: different command string'

    # DIFFERENTIAL: blind and sighted must not produce the same verdict text.
    _g=$(cn_evaluate "$_st_d/good.json" 2>&1)
    _b=$(cn_evaluate "$_st_d/bad0.json" 2>&1)
    if [ "$_g" = "$_b" ]; then
        printf 'SELFTEST %-34s BAD  identical verdict for blind and sighted (inert evaluator)\n' DIFF-blind-vs-sighted
        _st_bad=$((_st_bad + 1))
    else
        printf 'SELFTEST %-34s ok   (blind and sighted verdicts differ)\n' DIFF-blind-vs-sighted
    fi

    # Reuse proof: the shared classifier must be the one deciding class match.
    if [ "${CN_E4_SHARED:-0}" -eq 1 ]; then
        printf 'SELFTEST %-34s ok   (chain_control_needle.sh sourced; classifier NOT forked)\n' REUSE-shared-classifier
    else
        printf 'SELFTEST %-34s BAD  shared classifier not resolved\n' REUSE-shared-classifier
        _st_bad=$((_st_bad + 1))
    fi

    rm -rf "$_st_d"
    printf 'SELFTEST-SUMMARY bad=%s\n' "$_st_bad"
    [ "$_st_bad" -eq 0 ] || return 1
    return 0
}

case ${1:-} in
    --selftest) cn_e4_selftest; exit $? ;;
esac
