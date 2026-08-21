#!/bin/sh
# =============================================================================
# cm_mechanism_observed_refusing_mutation_test.sh — paired §1.1 mutation for
# CM-MECHANISM-OBSERVED-REFUSING (T229).
#
# MUTATION (behavioural): remove the RESOLUTION check on first_refusal_ref, so
# a reference that points at nothing is accepted merely because the field is
# non-empty. Every literal string the gate matches on is left in place — the
# mutated gate still says "a pointer to no record is not a record", it just no
# longer checks.
#
# NAMED FLIP : MOR-A3-DANGLING-REF-REFUSED   (must go PASS -> FAIL)
# SURGICAL   : MOR-A1 (absent ref still refused) and MOR-A2 (observed mechanism
#              still admitted) must both STAY PASS, so the flip is attributable
#              to this mutation and not to the gate simply breaking.
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

mutate_drop_ref_resolution() {  # <copy>
    awk '
      /if \[ ! -s "\$_mor_p" \]; then/ {
          print "    if false; then   # MUTATED: first_refusal_ref resolution check removed"
          next
      }
      { print }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

gm_init "$SELF_DIR/cm_mechanism_observed_refusing.sh"
gm_mutate_target "$SELF_DIR/cm_mechanism_observed_refusing.sh"
gm_pair mutate_drop_ref_resolution \
        MOR-A3-DANGLING-REF-REFUSED \
        MOR-A1-UNOBSERVED-REFUSED MOR-A2-OBSERVED-ADMITTED
gm_report
exit $?
