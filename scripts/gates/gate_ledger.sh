#!/usr/bin/env bash
# gate_ledger.sh — §11.4.227(A) named-gate LEDGER + monotone-decrease ratchet.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.227(A) requires every `CM-*`-class token NAMED in the governance
# corpus to be, at every build, either IMPLEMENTED (the token appears
# STRUCTURALLY inside a real executable gate site — never a prose carrier,
# §11.4.201(7)(a)) or covered by a REGISTERED DEFERRAL row pointing at a
# tracked follow-up item. Tokens satisfying NEITHER are "UNIMPLEMENTED" —
# legal silent debt is CLOSED: the unimplemented COUNT is a checked-in,
# MONOTONE-DECREASING ratchet (day-one baseline = the count measured at
# landing, so the ledger is GREEN on arrival and can only shrink from there —
# the §11.4.135-ratchet pattern applied to gate custody instead of test
# coverage). A gate NAME that vanishes from the corpus without an explicit
# removal citation FAILs (closes the delete-the-name-to-lower-the-count
# gaming channel; a genuine repeal, e.g. the §11.4.166 precedent, stays legal
# via the citation).
#
# Per §11.4.227(A): "an anchor's done state is its SEAM landing, not its
# TEXT landing" — this tool measures the SEAM (does an executable gate site
# exist / is the debt registered), never the prose.
#
# ── Structure-not-substring (§11.4.201(7)(a)) ───────────────────────────────
# An "implementation" is the gate's literal CM- token found INSIDE an
# executable `*.sh` file under the implementation tree (every real gate site
# in this corpus assigns its own name to a `GATE=` variable or an echoed
# string — a load-bearing, structural occurrence, not a passing mention).
# A `*.md` file (or any non-`.sh` file) that merely MENTIONS the token is a
# CARRIER and MUST NOT count as an implementation. A `*_mutation_test.sh`
# sibling that references the SAME token as the gate it tests is likewise
# excluded from counting as the implementation site (it is the gate's own
# §1.1 mutation harness, not the gate) — only a NON-mutation-test `.sh` hit
# counts as IMPLEMENTED.
#
# ── The `--` footgun this tool avoids (§11.4.201(7)(c) — the path is part of
#     the instrument) ─────────────────────────────────────────────────────
# `grep -rlE --include='*.sh' -- "$g" "$IMPL"` MUST keep every OPTION
# (`--include=...`) BEFORE the `--` end-of-options marker. Reordering so `--`
# precedes `--include` silently turns `--include` into a FILENAME argument
# and the include-filter stops matching real gate sites — the exact class of
# confident-wrong-answer-without-crashing this project's own §11.4.201(7)(c)
# anchor describes (first caught inside this tool's SOL-05 proof-of-concept
# ancestor's own RED->GREEN loop).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   gate_ledger.sh generate <impl-dir> <deferrals-tsv> <corpus-file> [<corpus-file> ...]
#       -> emits a ledger TSV on stdout: `<gate>\t<STATUS>\t<evidence>`
#          STATUS in {IMPLEMENTED, DEFERRED, UNIMPLEMENTED}.
#
#   gate_ledger.sh check <ledger-file> <baseline-file> <prev-names-file> [<removals-tsv>]
#       -> ratchet + vanished-name checks; prints a summary line; exit 0/1/2.
#
#   gate_ledger.sh selfcheck <scratch-impl-dir>
#       -> control-needle + golden-good/golden-bad/deferred self-test of this
#          tool itself (§11.4.201(7)(b) — a null result is not evidence until
#          the instrument is proven to see).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   <impl-dir>       tree scanned recursively for `*.sh` gate sites (this
#                    project's canonical scan root is `constitution/scripts`
#                    — gate implementations are NOT confined to
#                    `scripts/gates/`; several live under `scripts/hooks/`,
#                    `scripts/multitrack/`, `scripts/doc_integrity/wire/`,
#                    `scripts/helix_code/`, and `scripts/`, so a scan
#                    confined to `scripts/gates/` alone would UNDER-COUNT
#                    implementations and inflate the unimplemented figure —
#                    a false-FAIL of the exact §11.4.201(1) class this
#                    project forbids).
#   <deferrals-tsv>  `<gate>\t<tracked-item-id>[\t<note>]` rows, one per
#                    registered deferral. May be empty (header-only or
#                    zero-byte) — an empty registry is a HONEST statement
#                    that no deferral has yet been registered, not a defect.
#   <corpus-file>    one or more governance files to extract `CM-*` tokens
#                    from. This project's canonical corpus is
#                    `constitution/Constitution.md` — the anchor's own
#                    source-of-truth location per every existing
#                    `cm_covenant_*_propagation.sh` gate's documented
#                    convention; the four mirror files (CLAUDE/AGENTS/QWEN/
#                    GEMINI.md) restate the SAME anchors and are the concern
#                    of the SEPARATE anchor-block-integrity gates
#                    (§11.4.227(B)), not this ledger.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   generate: TSV ledger on stdout.
#   check:    per-violation lines + `LEDGER: unimplemented=N baseline=B fails=F`
#             summary; exit 1 if fails>0.
#   selfcheck: SELFCHECK-FAIL lines + exit 2/1 on any self-test failure;
#              `SELFCHECK: PASS ...` + exit 0 when the instrument is proven
#              sound.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). `selfcheck` creates + removes its own `mktemp -d`
#   scratch tree; it never touches the caller-supplied `<impl-dir>`.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX grep + sed + awk + cut + sort. Parses clean under `bash -n`
#   (§11.4.67).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   §11.4.227(A) (this ledger's mandate), §11.4.201(7)(a)/(b)/(c) (structure-
#   not-substring, control needle, the-path-is-part-of-the-instrument),
#   §11.4.135 (the monotone-decrease-ratchet pattern this reuses),
#   §11.4.6 (no-guessing — an unresolvable file is BLIND, exit 2, never a
#   guessed zero), §11.4.66/§11.4.122 (brownfield-adoption + exclusion
#   decisions stay operator-owned DATA, never invented by this tool), §1.1
#   (paired mutation — name a new gate with no implementation and no
#   deferral -> `check` FAILs; register its deferral -> `check` PASSes).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   generate: 0 on a non-empty ledger; 2 on BLIND (unreadable input / zero
#             tokens extracted from a non-empty corpus — the corpus needs a
#             control needle before an empty extraction is trusted).
#   check:    0 — ratchet holds, no vanished-name violation.
#             1 — ratchet exceeded and/or a vanished name lacks a citation.
#             2 — BLIND (an input file could not be read).
#   selfcheck: 0 — PASS; 1 — a golden fixture misclassified; 2 — the
#              control needle itself failed (the instrument is BLIND).
#
# Classification: universal (§11.4.17) — no project-specific literal; the
# consuming project supplies its own impl-dir / deferrals-tsv / corpus paths
# and baseline snapshot as DATA per §11.4.35.

set -u

SELF="$0"
TOOL="gate_ledger.sh"

usage() {
    sed -n '1,70p' "$SELF" | sed 's/^# \{0,1\}//'
}

MODE="${1:-}"
if [ -z "$MODE" ]; then
    usage >&2
    exit 2
fi
shift

# extract_names: reads corpus bytes on stdin, prints one CM-* token per line,
# de-duplicated, sorted. Trailing punctuation (a token immediately followed
# by `.`/`,`/`:`/`;`/`)` in prose, e.g. "... per CM-EXAMPLE-GATE.") is
# stripped so the SAME gate is not double-counted under two spellings.
extract_names() {
    grep -ohE 'CM-[A-Z0-9][A-Z0-9-]*' | sed -E 's/[-.,:;)]+$//' | sort -u
}

case "$MODE" in
generate)
    IMPL="${1:?generate: <impl-dir> required}"; shift
    DEF="${1:?generate: <deferrals-tsv> required}"; shift
    if [ "$#" -lt 1 ]; then
        echo "${TOOL}: generate requires >=1 <corpus-file>" >&2
        exit 2
    fi
    for f in "$@"; do
        [ -r "$f" ] || { echo "BLIND: cannot read corpus file $f" >&2; exit 2; }
    done
    [ -d "$IMPL" ] || { echo "BLIND: impl-dir $IMPL absent" >&2; exit 2; }
    [ -r "$DEF" ] || { echo "BLIND: deferrals-tsv $DEF absent" >&2; exit 2; }

    names="$(cat -- "$@" | extract_names)"
    if [ -z "$names" ]; then
        echo "BLIND-OR-EMPTY: zero CM- tokens extracted from corpus [$*] — needle the corpus (or the extractor) before trusting this as a real absence, §11.4.201(7)(b)" >&2
        exit 2
    fi

    while IFS= read -r g; do
        [ -n "$g" ] || continue
        # STRUCTURE match: options precede `--` (§11.4.201(7)(c)); real gate
        # sites are recursively discovered anywhere under IMPL (not confined
        # to a single subdirectory, per the ── Inputs ── note above).
        #
        # BOUNDARY-ANCHORED, never a bare substring (§11.4.201(7)(a) applied
        # to THIS tool's own instrument, not only to the corpus): a bare
        # `grep -E -- "$g"` would let a SHORTER gate name false-match as a
        # SUBSTRING of a longer one that shares its prefix. Forensic FACT
        # (found LIVE while generating this tool's own first real-corpus
        # ledger): the corpus occasionally cites several sibling propagation
        # gates compactly as one slash-joined literal (a single anchor-number
        # of the form NNN, joined to its siblings MMM/PPP/... by `/`, all
        # sharing one `-PROPAGATION` suffix at the end of the group). The
        # token extractor legitimately stops at the `/` (outside the
        # `[A-Z0-9-]` class), so it emits a spurious bare `CM-COVENANT-114-
        # <NNN>` token for the FIRST member of the group — missing its own
        # `-PROPAGATION` suffix. Without boundary anchoring that spurious
        # bare token would then substring-match INSIDE the real gate site's
        # `GATE="CM-COVENANT-114-<NNN>-PROPAGATION"` assignment line and be
        # misclassified IMPLEMENTED. The boundary class `[^A-Z0-9-]` on both
        # sides (or start/end of line) requires the matched token NOT be
        # immediately followed/preceded by more
        # `[A-Z0-9-]` characters, so the spurious bare `CM-COVENANT-114-<NNN>`
        # can never match inside its own strictly-longer, correctly-suffixed
        # `CM-COVENANT-114-<NNN>-PROPAGATION` sibling.
        hits="$(grep -rlE --include='*.sh' -- "(^|[^A-Z0-9-])${g}([^A-Z0-9-]|\$)" "$IMPL" 2>/dev/null | grep -v '_mutation_test\.sh$')"
        hit="$(printf '%s\n' "$hits" | head -1)"
        if [ -n "$hit" ]; then
            printf '%s\tIMPLEMENTED\t%s\n' "$g" "$hit"
            continue
        fi
        if [ -s "$DEF" ] && cut -f1 "$DEF" | grep -qx -- "$g"; then
            tracked="$(awk -F'\t' -v g="$g" '$1==g{print $2; exit}' "$DEF")"
            printf '%s\tDEFERRED\t%s\n' "$g" "${tracked:-UNKNOWN-TRACKED-ITEM}"
            continue
        fi
        printf '%s\tUNIMPLEMENTED\t-\n' "$g"
    done <<< "$names"
    ;;

check)
    LEDGER="${1:?check: <ledger-file> required}"
    BASE="${2:?check: <baseline-file> required}"
    PREV="${3:?check: <prev-names-file> required}"
    REM="${4:-}"
    for f in "$LEDGER" "$BASE" "$PREV"; do
        [ -r "$f" ] || { echo "BLIND: cannot read $f" >&2; exit 2; }
    done

    fails=0

    count="$(awk -F'\t' '$2=="UNIMPLEMENTED"{n++} END{print n+0}' "$LEDGER")"
    baseline_raw="$(cat -- "$BASE")"
    baseline="$(printf '%s' "$baseline_raw" | tr -d '[:space:]')"
    if ! printf '%s' "$baseline" | grep -qE '^[0-9]+$'; then
        echo "LEDGER-FAIL: baseline file $BASE does not contain a bare non-negative integer (got: '${baseline_raw}')"
        fails=$((fails + 1))
        baseline=0
    fi

    if [ "$count" -gt "$baseline" ]; then
        echo "LEDGER-FAIL: ratchet violated — unimplemented=${count} exceeds checked-in baseline=${baseline} (a CM-* gate was named with neither an implementation nor a registered deferral; land the gate, register its deferral against a tracked item, or this is a §11.4.227(A) violation)"
        fails=$((fails + 1))
    fi

    while IFS= read -r g; do
        [ -n "$g" ] || continue
        if ! cut -f1 "$LEDGER" | grep -qx -- "$g"; then
            cited=0
            if [ -n "$REM" ] && [ -r "$REM" ]; then
                if cut -f1 "$REM" | grep -qx -- "$g"; then
                    cited=1
                fi
            fi
            if [ "$cited" -eq 0 ]; then
                echo "LEDGER-FAIL: gate ${g} vanished from the corpus with no removal citation in ${REM:-<none supplied>} (silent deletion would game the monotone-decrease ratchet — cite the removal, e.g. a §11.4.166-class repeal, or restore the gate)"
                fails=$((fails + 1))
            fi
        fi
    done < "$PREV"

    echo "LEDGER: unimplemented=${count} baseline=${baseline} fails=${fails}"
    [ "$fails" -eq 0 ] || exit 1
    exit 0
    ;;

selfcheck)
    IMPL_UNUSED="${1:-}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    # ── control needle (§11.4.201(7)(b)) ────────────────────────────────────
    # A synthetic corpus with exactly one known-present gate token MUST be
    # extracted before any zero-extraction result elsewhere is trusted as a
    # true absence rather than a blind instrument.
    needle_corpus="$tmp/needle_corpus.md"
    printf 'Prose citing gate `CM-NEEDLE-CONTROL-TEST` inside a sentence, never a block-start.\n' > "$needle_corpus"
    needle_names="$(extract_names < "$needle_corpus")"
    if ! printf '%s\n' "$needle_names" | grep -qx 'CM-NEEDLE-CONTROL-TEST'; then
        echo "SELFCHECK-FAIL: control needle CM-NEEDLE-CONTROL-TEST was NOT extracted — the token extractor itself is BLIND" >&2
        exit 2
    fi

    # ── golden-good: a real .sh implementation classifies IMPLEMENTED ───────
    good_impl="$tmp/impl_good"; mkdir -p "$good_impl"
    cat > "$good_impl/cm_selftest_good.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-GOOD"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$good_impl/cm_selftest_good.sh"
    good_def="$tmp/deferrals_empty_good.tsv"; : > "$good_def"
    good_corpus="$tmp/good_corpus.md"
    printf 'Gate `CM-SELFTEST-GOOD` protects the good path.\n' > "$good_corpus"
    good_out="$("$SELF" generate "$good_impl" "$good_def" "$good_corpus")"
    if ! printf '%s\n' "$good_out" | grep -qE '^CM-SELFTEST-GOOD[[:space:]]+IMPLEMENTED'; then
        echo "SELFCHECK-FAIL: golden-good gate CM-SELFTEST-GOOD (real .sh site present) was NOT classified IMPLEMENTED" >&2
        printf '%s\n' "$good_out" >&2
        exit 1
    fi

    # ── golden-bad: a prose-only CARRIER (a .md mentioning the token, no
    #    real .sh site) MUST classify UNIMPLEMENTED, never IMPLEMENTED —
    #    proves structure-not-substring (§11.4.201(7)(a)) actually holds.
    bad_impl="$tmp/impl_bad"; mkdir -p "$bad_impl"
    printf 'CM-SELFTEST-BAD is mentioned here, in a doc, never in an executable script.\n' > "$bad_impl/prose_carrier.md"
    bad_def="$tmp/deferrals_empty_bad.tsv"; : > "$bad_def"
    bad_corpus="$tmp/bad_corpus.md"
    printf 'Gate `CM-SELFTEST-BAD` protects the bad path.\n' > "$bad_corpus"
    bad_out="$("$SELF" generate "$bad_impl" "$bad_def" "$bad_corpus")"
    if ! printf '%s\n' "$bad_out" | grep -qE '^CM-SELFTEST-BAD[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: golden-bad gate CM-SELFTEST-BAD (prose-only carrier, zero real .sh sites) was NOT classified UNIMPLEMENTED — a carrier is being counted as an implementation (§11.4.201(7)(a) violated)" >&2
        printf '%s\n' "$bad_out" >&2
        exit 1
    fi

    # ── negative control: a mutation-test-only reference (no real impl)
    #    MUST ALSO classify UNIMPLEMENTED — the mutation harness is not the
    #    gate.
    mut_impl="$tmp/impl_mutonly"; mkdir -p "$mut_impl"
    cat > "$mut_impl/cm_selftest_mutonly_mutation_test.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-MUTONLY"
echo "mutation test for $GATE"
SH
    chmod +x "$mut_impl/cm_selftest_mutonly_mutation_test.sh"
    mut_def="$tmp/deferrals_empty_mut.tsv"; : > "$mut_def"
    mut_corpus="$tmp/mut_corpus.md"
    printf 'Gate `CM-SELFTEST-MUTONLY` protects the mutation-only path.\n' > "$mut_corpus"
    mut_out="$("$SELF" generate "$mut_impl" "$mut_def" "$mut_corpus")"
    if ! printf '%s\n' "$mut_out" | grep -qE '^CM-SELFTEST-MUTONLY[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a gate present ONLY inside its own *_mutation_test.sh (no real implementation) was NOT classified UNIMPLEMENTED" >&2
        printf '%s\n' "$mut_out" >&2
        exit 1
    fi

    # ── deferred classification: a registered deferral (no impl) -> DEFERRED
    defr_impl="$tmp/impl_defr"; mkdir -p "$defr_impl"
    defr_def="$tmp/deferrals_one.tsv"
    printf 'CM-SELFTEST-DEFERRED\tTRACKED-ITEM-EXAMPLE-123\n' > "$defr_def"
    defr_corpus="$tmp/defr_corpus.md"
    printf 'Gate `CM-SELFTEST-DEFERRED` protects the deferred path.\n' > "$defr_corpus"
    defr_out="$("$SELF" generate "$defr_impl" "$defr_def" "$defr_corpus")"
    if ! printf '%s\n' "$defr_out" | grep -qE '^CM-SELFTEST-DEFERRED[[:space:]]+DEFERRED'; then
        echo "SELFCHECK-FAIL: a gate with a registered deferral (no implementation) was NOT classified DEFERRED" >&2
        printf '%s\n' "$defr_out" >&2
        exit 1
    fi

    # ── check-mode golden-true/golden-false ─────────────────────────────────
    # golden-TRUE: ratchet holds (count == baseline), no vanished name -> PASS
    ck_ledger="$tmp/ck_ledger.tsv"
    printf 'CM-A\tUNIMPLEMENTED\t-\nCM-B\tIMPLEMENTED\t/x\n' > "$ck_ledger"
    ck_base="$tmp/ck_baseline.txt"; printf '1\n' > "$ck_base"
    ck_prev="$tmp/ck_prev.txt"; printf 'CM-A\nCM-B\n' > "$ck_prev"
    if ! "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-TRUE check fixture (count==baseline, no vanished name) did NOT pass — false-positive refusal (§11.4.201(1))" >&2
        exit 1
    fi

    # golden-FALSE (ratchet exceeded): baseline=0, one UNIMPLEMENTED -> FAIL
    ck_base2="$tmp/ck_baseline2.txt"; printf '0\n' > "$ck_base2"
    if "$SELF" check "$ck_ledger" "$ck_base2" "$ck_prev" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-FALSE check fixture (ratchet exceeded) PASSED — the ratchet is not load-bearing" >&2
        exit 1
    fi

    # golden-FALSE (vanished name, no citation): prev names CM-A, CM-B, CM-C
    # but the ledger + no removals file only has CM-A/CM-B -> FAIL
    ck_prev2="$tmp/ck_prev2.txt"; printf 'CM-A\nCM-B\nCM-C\n' > "$ck_prev2"
    if "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev2" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-FALSE check fixture (vanished name CM-C, no removal citation) PASSED" >&2
        exit 1
    fi

    # golden-TRUE (vanished name WITH citation) -> PASS
    ck_removals="$tmp/ck_removals.tsv"; printf 'CM-C\trepealed-example\n' > "$ck_removals"
    if ! "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev2" "$ck_removals" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-TRUE check fixture (vanished name WITH a removal citation) did NOT pass" >&2
        exit 1
    fi

    echo "SELFCHECK: PASS — control needle sees; golden-good IMPLEMENTED; golden-bad prose-carrier UNIMPLEMENTED; mutation-test-only reference UNIMPLEMENTED; registered-deferral DEFERRED; check-mode ratchet + vanished-name golden-TRUE/golden-FALSE pairs all correct"
    exit 0
    ;;

*)
    usage >&2
    exit 2
    ;;
esac
