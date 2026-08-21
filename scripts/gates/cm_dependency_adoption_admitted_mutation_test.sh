#!/bin/sh
# =============================================================================
# cm_dependency_adoption_admitted_mutation_test.sh — paired §1.1 mutation for
# CM-DEPENDENCY-ADOPTION-ADMITTED (T233).
#
# MUTATION (behavioural): remove the FR-021 sweep precondition from dr_adopt, so
# a missing or empty wiring-sweep result is silently treated as "no findings".
# That is the false-null this feature exists to close, re-introduced on purpose:
# an unread instrument and a clean tree return the identical quiet zero.
#
# NAMED FLIP : DAA-A5-SWEEP-PRECONDITION  (PASS -> FAIL)
# SURGICAL   : DAA-A2 (UNVERIFIED refused), DAA-A4 (covering rule named) and
#              DAA-A6 (admissible dependency still admitted) must STAY PASS —
#              the mutation must be shown to remove ONE precondition, not to
#              break adoption generally.
# =============================================================================

set -u
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib/gate_mutation_harness.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

mutate_drop_sweep_precondition() {  # <copy>
    awk '
      /if \[ -z "\$SWEEP" \] \|\| \[ ! -s "\$SWEEP" \]; then/ {
          print "    if false; then   # MUTATED: FR-021 sweep precondition removed (missing result read as no findings)"
          next
      }
      { print }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

gm_init "$SELF_DIR/cm_dependency_adoption_admitted.sh" \
        --gaps "$SELF_DIR/uncovered_capability_gaps.tsv" \
        --sweep "$SELF_DIR/wiring_sweep_result.tsv"
gm_mutate_target "$SELF_DIR/lib/dependency_register.sh"
gm_pair mutate_drop_sweep_precondition \
        DAA-A5-SWEEP-PRECONDITION \
        DAA-A2-UNVERIFIED-REFUSED DAA-A4-GAP-UNMAPPED-NAMES-RULE DAA-A6-MAPPED-ADMITTED
gm_report
exit $?
