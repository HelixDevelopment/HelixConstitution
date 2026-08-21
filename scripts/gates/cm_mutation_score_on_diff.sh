#!/bin/sh
# cm_mutation_score_on_diff.sh — CM-MUTATION-SCORE-ON-DIFF gate
# (feature 002-anti-slop-enforcement, task T408b; tracked as ATM-1023;
# closes the owed-work half of CT-4).
#
# ── What it measures ────────────────────────────────────────────────────────
# killed / generated over the CHANGED LINES of a supplied diff, using the
# POSIX-shell mutation engine at lib/shell_mutation_engine.sh, compared to a
# threshold read from protected configuration.
#
# This is a MUTATION SCORE — mechanically generated mutants over the diff.
# It is NOT the guard-viability ratio (one authored mutation per gate) that
# the §1.1 discipline produces. CT-4 recorded that the two are different
# metrics and refused to relabel the weaker one; this gate exists so the
# stronger one can eventually be measured rather than claimed.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   cm_mutation_score_on_diff.sh --diff <file> [--threshold-file <p>]
#                                [--map <p>] [--workdir <p>] [--quiet]
#   cm_mutation_score_on_diff.sh --selftest
#
#     --diff <file>        unified diff whose NEW-file changed lines are scored.
#                          Paths inside the diff are resolved RELATIVE TO THE
#                          CURRENT DIRECTORY, so run this from the repo root
#                          (a mapped file that does not resolve is reported
#                          UNSCORED and named, never silently skipped).
#     --threshold-file <p> default: mutation_score_threshold.txt beside this file
#     --map <p>            default: mutation_score_kill_map.tsv beside this file
#     --workdir <p>        scratch dir for mutants (default: a mktemp -d,
#                          removed on exit)
#     --quiet              suppress per-file lines; verdicts always print
#     --selftest           run golden-TRUE / golden-FALSE / blind-control
#                          fixtures in a mktemp dir, removed on exit
#
# ── Exit codes ──────────────────────────────────────────────────────────────
#   0  PASS (score at/above threshold) or honest SKIP (threshold unset, no
#      changed shell file, or nothing mapped)
#   1  FAIL (score below threshold, or a measurement that cannot be trusted:
#      BASELINE_RED / KILLER_BLIND)
#   2  usage / unreadable input
#
# ── Why an untrustworthy measurement FAILS rather than SKIPs ────────────────
# BASELINE_RED means the kill command already fails on the UNMUTATED source, so
# every mutant would be "killed" and the score would be a free 100%.
# KILLER_BLIND means the sentinel mutant survived, so the kill command cannot
# detect anything and the score would be a meaningless 0%. Both directions
# fabricate a number, so both refuse. That is the point: the failure mode this
# gate exists to prevent is a score that reads well and measures nothing.
#
# ── Side-effects ────────────────────────────────────────────────────────────
#   Read-only against the repository. Mutants are written ONLY inside the
#   workdir (a mktemp -d unless --workdir is given) and the source file is
#   never edited — a mutation run must not leave residue in a tracked tree
#   (§11.4.84).
#
# ── Honest boundary (§11.4.6) ───────────────────────────────────────────────
#   A mutation score measures whether the tests DETECT changed behaviour on the
#   changed lines. It does not prove the change correct, does not replace
#   §11.4.108 four-layer verification, and does not replace §11.4.185 manual QA.
#   The score is relative to the engine's declared operator set and counts
#   equivalent mutants as survivors. The threshold's own validity as a gating
#   metric is owed under §11.4.201(8) — see the operator brief.
#   Portability: POSIX sh; parses clean under `sh -n` and `bash -n`. No
#   dash/busybox/ksh/mksh/posh exists on this host (measured), so
#   dash-portability is asserted by construction, not proven.

set -u

PROG=$(basename "$0")
SELF_DIR=$(cd "$(dirname "$0")" && pwd)

DIFF_FILE=""
THRESH_FILE="$SELF_DIR/mutation_score_threshold.txt"
MAP_FILE="$SELF_DIR/mutation_score_kill_map.tsv"
WORKDIR=""
QUIET=0
SELFTEST=0
ENGINE="$SELF_DIR/lib/shell_mutation_engine.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }
verdict() { printf 'MUT-VERDICT\t%s\t%s\t%s\n' "$1" "$2" "$3"; }

while [ $# -gt 0 ]; do
    case $1 in
        --diff)           shift; [ $# -gt 0 ] || die "--diff needs a value"; DIFF_FILE=$1 ;;
        --threshold-file) shift; [ $# -gt 0 ] || die "--threshold-file needs a value"; THRESH_FILE=$1 ;;
        --map)            shift; [ $# -gt 0 ] || die "--map needs a value"; MAP_FILE=$1 ;;
        --workdir)        shift; [ $# -gt 0 ] || die "--workdir needs a value"; WORKDIR=$1 ;;
        --engine)         shift; [ $# -gt 0 ] || die "--engine needs a value"; ENGINE=$1 ;;
        --quiet)          QUIET=1 ;;
        --selftest)       SELFTEST=1 ;;
        -h|--help)        sed -n '2,60p' "$0"; exit 0 ;;
        *)                die "unknown argument: $1" ;;
    esac
    shift
done

[ -f "$ENGINE" ] || die "mutation engine not found: $ENGINE"
# shellcheck source=lib/shell_mutation_engine.sh
. "$ENGINE"

threshold_value() {
    [ -f "$1" ] || return 0
    awk '
        /^[ \t]*#/ { next }
        /^[ \t]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $0); print; exit }
    ' "$1"
}

map_lookup() {
    [ -f "$2" ] || return 0
    awk -F'\t' -v want="$1" '
        /^[ \t]*#/ { next }
        /^[ \t]*$/ { next }
        $1 == want { print $2; exit }
    ' "$2"
}

diff_shell_files() {
    awk '
        /^\+\+\+ / {
            p = $2
            sub(/^b\//, "", p)
            if (p == "/dev/null") next
            if (p ~ /\.sh$/) print p
        }
    ' "$1" | sort -u
}

# ---------------------------------------------------------------------------
run_gate() {
    _g_diff=$1; _g_thresh=$2; _g_map=$3; _g_wd=$4

    _tv=$(threshold_value "$_g_thresh")
    if [ -z "$_tv" ]; then
        verdict "THRESHOLD" "SKIP" "threshold file absent or empty: $_g_thresh"
        return 0
    fi
    if [ "$_tv" = "OPERATOR_DECISION_PENDING" ]; then
        verdict "THRESHOLD" "SKIP" "operator_decision_pending (§11.4.66) — the threshold is the operator's to set; the gate refuses to invent an un-validated gating metric (§11.4.201(8))"
        return 0
    fi
    case $_tv in
        ''|*[!0-9]*) verdict "THRESHOLD" "FAIL" "threshold is not an integer 0-100: '$_tv'"; return 1 ;;
    esac
    [ "$_tv" -le 100 ] || { verdict "THRESHOLD" "FAIL" "threshold above 100: '$_tv'"; return 1; }

    [ -f "$_g_diff" ] || { verdict "DIFF" "FAIL" "diff not readable: $_g_diff"; return 2; }

    _files=$(diff_shell_files "$_g_diff")
    if [ -z "$_files" ]; then
        verdict "SCOPE" "SKIP" "no shell source file in the diff — nothing in this gate's declared scope"
        return 0
    fi

    mkdir -p "$_g_wd" || { verdict "WORKDIR" "FAIL" "cannot create workdir: $_g_wd"; return 2; }

    _tot_gen=0
    _tot_kill=0
    _unscored=0
    _untrusted=0
    _scored=0

    for _f in $_files; do
        _kill=$(map_lookup "$_f" "$_g_map")
        if [ -z "$_kill" ]; then
            _unscored=$((_unscored + 1))
            [ "$QUIET" -eq 1 ] || printf '  UNSCORED  %s  (no kill command in %s)\n' "$_f" "$_g_map"
            continue
        fi
        if [ ! -f "$_f" ]; then
            _unscored=$((_unscored + 1))
            [ "$QUIET" -eq 1 ] || printf '  UNSCORED  %s  (mapped but not present in the tree)\n' "$_f"
            continue
        fi
        _lf="$_g_wd/lines.$(printf '%s' "$_f" | tr '/.' '__')"
        sme_changed_lines "$_g_diff" "$_f" > "$_lf"
        sme_score "$_f" "$_lf" "$_g_wd/m.$(printf '%s' "$_f" | tr '/.' '__')" "$_kill"
        _sc_rc=$?
        case $SME_STATUS in
            OK)
                _scored=$((_scored + 1))
                _tot_gen=$((_tot_gen + SME_GENERATED))
                _tot_kill=$((_tot_kill + SME_KILLED))
                [ "$QUIET" -eq 1 ] || printf '  SCORED    %s  generated=%s killed=%s survived=%s invalid=%s score=%s%%\n' \
                    "$_f" "$SME_GENERATED" "$SME_KILLED" "$SME_SURVIVED" "$SME_INVALID" "$SME_SCORE_PCT"
                [ "$QUIET" -eq 1 ] || [ -z "$SME_SURVIVORS" ] || printf '            survivors:%s\n' "$SME_SURVIVORS"
                ;;
            NO_MUTANTS)
                _unscored=$((_unscored + 1))
                [ "$QUIET" -eq 1 ] || printf '  UNSCORED  %s  (no valid mutant on the changed lines)\n' "$_f"
                ;;
            BASELINE_RED)
                _untrusted=$((_untrusted + 1))
                printf '  UNTRUSTED %s  BASELINE_RED — the kill command already fails on the UNMUTATED source, so every mutant would score a free kill (rc=%s)\n' "$_f" "$_sc_rc"
                ;;
            KILLER_BLIND)
                _untrusted=$((_untrusted + 1))
                printf '  UNTRUSTED %s  KILLER_BLIND — the catastrophic sentinel mutant SURVIVED, so this kill command cannot detect anything; a 0%% here would measure the instrument, not the tests (rc=%s)\n' "$_f" "$_sc_rc"
                ;;
            *)
                _untrusted=$((_untrusted + 1))
                printf '  UNTRUSTED %s  unexpected engine status %s (rc=%s)\n' "$_f" "$SME_STATUS" "$_sc_rc"
                ;;
        esac
    done

    printf 'REPORT\tthreshold=%s%%\tscored_files=%s\tunscored_files=%s\tuntrusted_files=%s\tgenerated=%s\tkilled=%s\n' \
        "$_tv" "$_scored" "$_unscored" "$_untrusted" "$_tot_gen" "$_tot_kill"

    if [ "$_untrusted" -gt 0 ]; then
        verdict "TRUST" "FAIL" "$_untrusted file(s) produced a measurement that cannot be trusted — refusing rather than reporting a fabricated score"
        return 1
    fi

    if [ "$_tot_gen" -eq 0 ]; then
        verdict "SCOPE" "SKIP" "no scored mutant on the diff's changed lines ($_unscored unscored file(s)) — an honest gap, not a pass"
        return 0
    fi

    _pct=$(( (_tot_kill * 100) / _tot_gen ))
    if [ "$_pct" -lt "$_tv" ]; then
        verdict "SCORE" "FAIL" "mutation score ${_pct}% is BELOW the threshold ${_tv}% ($_tot_kill killed / $_tot_gen generated)"
        return 1
    fi
    verdict "SCORE" "PASS" "mutation score ${_pct}% meets the threshold ${_tv}% ($_tot_kill killed / $_tot_gen generated)"
    return 0
}

# ---------------------------------------------------------------------------
selftest() {
    _d=$(mktemp -d) || die "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -rf '$_d'" EXIT INT TERM
    _p=0
    _f=0

    mkdir -p "$_d/src"
    cat > "$_d/src/sut.sh" <<'EOS'
#!/bin/sh
n=$1
if [ "$n" -gt 10 ]; then
    echo big
else
    echo small
fi
exit 0
EOS
    cat > "$_d/strong.sh" <<'EOS'
#!/bin/sh
m=$1
o1=$(sh "$m" 15) || exit 1
[ "$o1" = "big" ] || exit 1
o2=$(sh "$m" 5) || exit 1
[ "$o2" = "small" ] || exit 1
o3=$(sh "$m" 11) || exit 1
[ "$o3" = "big" ] || exit 1
o4=$(sh "$m" 10) || exit 1
[ "$o4" = "small" ] || exit 1
sh "$m" 15 >/dev/null 2>&1 || exit 1
exit 0
EOS
    cat > "$_d/partial.sh" <<'EOS'
#!/bin/sh
m=$1
o1=$(sh "$m" 15) || exit 1
[ "$o1" = "big" ] || exit 1
exit 0
EOS
    cat > "$_d/blind.sh" <<'EOS'
#!/bin/sh
m=$1
sh "$m" 15 >/dev/null 2>&1
exit 0
EOS
    cat > "$_d/the.diff" <<'EOD'
--- a/src/sut.sh
+++ b/src/sut.sh
@@ -0,0 +1,8 @@
+#!/bin/sh
+n=$1
+if [ "$n" -gt 10 ]; then
+    echo big
+else
+    echo small
+fi
+exit 0
EOD
    # 70 is the FIXTURE threshold, chosen to sit BETWEEN the two suites'
    # MEASURED scores (strong=80%, partial=60%) so the two golden cases differ
    # by SUITE STRENGTH, not by where the threshold happens to fall. It is a
    # test fixture only and says nothing about the shipped threshold, which is
    # the operator's to set (§11.4.66).
    printf '70\n' > "$_d/thresh70.txt"
    printf 'OPERATOR_DECISION_PENDING\n' > "$_d/thresh_pending.txt"
    printf 'src/sut.sh\tsh %s/strong.sh {mutant}\n'  "$_d" > "$_d/map_strong.tsv"
    printf 'src/sut.sh\tsh %s/partial.sh {mutant}\n' "$_d" > "$_d/map_partial.tsv"
    printf 'src/sut.sh\tsh %s/blind.sh {mutant}\n'   "$_d" > "$_d/map_blind.tsv"
    : > "$_d/map_empty.tsv"

    _ci=0
    # _case <name> <want-rc> <map> <threshold-file> [<required-substring>]
    # The optional substring matters: an exit code alone cannot distinguish
    # "refused because the score was low" from "refused because the instrument
    # was blind", and those are different facts. The blind-control case asserts
    # the REASON, so stripping the engine's sentinel check breaks it.
    _case() {
        _n=$1; _want=$2; _map=$3; _th=$4; _need=${5:-}
        _ci=$((_ci + 1))
        _cwd="$_d/wd$_ci"
        ( cd "$_d" && run_gate "$_d/the.diff" "$_th" "$_map" "$_cwd" ) > "$_d/o" 2>&1
        _got=$?
        cp "$_d/o" "$_d/log$_ci.txt"
        rm -rf "$_cwd"
        _ok=1
        [ "$_got" -eq "$_want" ] || _ok=0
        if [ -n "$_need" ]; then
            grep -q -- "$_need" "$_d/o"
            _gr=$?
            [ "$_gr" -eq 0 ] || _ok=0
        fi
        if [ "$_ok" -eq 1 ]; then
            printf 'SELFTEST\tPASS\t%s (rc=%s)\n' "$_n" "$_got"
            _p=$((_p + 1))
        else
            printf 'SELFTEST\tFAIL\t%s (want rc=%s got rc=%s; required text %s)\n' "$_n" "$_want" "$_got" "${_need:-none}"
            sed 's/^/      | /' "$_d/o"
            _f=$((_f + 1))
        fi
    }

    _case "golden-FALSE strong suite (measured 80%) must NOT fire at 70%" 0 "$_d/map_strong.tsv"  "$_d/thresh70.txt" "meets the threshold"
    _case "golden-TRUE partial suite (measured 60%) must REFUSE at 70%" 1 "$_d/map_partial.tsv" "$_d/thresh70.txt" "is BELOW the threshold"
    _case "control: blind kill command must REFUSE *as KILLER_BLIND*, never as a 0% score" 1 "$_d/map_blind.tsv" "$_d/thresh70.txt" "KILLER_BLIND"
    _case "unset threshold SKIPs (never a false-positive refusal)" 0 "$_d/map_partial.tsv" "$_d/thresh_pending.txt"
    _case "unmapped file is UNSCORED, not a fabricated pass/fail" 0 "$_d/map_empty.tsv" "$_d/thresh70.txt"

    printf 'SELFTEST\tSUMMARY\tpass=%d fail=%d\n' "$_p" "$_f"
    [ "$_f" -eq 0 ] || return 1
    return 0
}

if [ "$SELFTEST" -eq 1 ]; then
    selftest
    rc=$?
    exit "$rc"
fi

[ -n "$DIFF_FILE" ] || die "--diff is required (or --selftest)"

if [ -z "$WORKDIR" ]; then
    WORKDIR=$(mktemp -d) || die "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -rf '$WORKDIR'" EXIT INT TERM
fi

run_gate "$DIFF_FILE" "$THRESH_FILE" "$MAP_FILE" "$WORKDIR"
rc=$?
exit "$rc"
