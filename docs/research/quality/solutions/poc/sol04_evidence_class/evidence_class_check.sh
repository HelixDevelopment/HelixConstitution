#!/usr/bin/env bash
# SOL-04 — evidence-class-at-closure checker.
# The discriminator (ROOT_CAUSE §7, corpus-3 §5.3) as a refusing seam: a closure's
# evidence must be of the CLASS of the defect's layer, and the class is proven by
# MACHINE FIELDS in the evidence file, never by a bare label.
#
# Usage: evidence_class_check.sh <defect-layer> <evidence-file>
#   defect-layer ∈ {user-visible, runtime, artifact, source}
# Exit: 0 satisfied | 1 refused (WRONG-LAYER / SHAPE-INCOMPLETE / CLASS-INSUFFICIENT) | 2 blind
set -u
LAYER="${1:?defect layer}"; EV="${2:?evidence file}"

[ -r "$EV" ] || { echo "BLIND: cannot read evidence file $EV — unreadable evidence is not evidence"; exit 2; }

get() { sed -n "s/^$1: *//p" "$EV" | head -1; }

CLAIMED=$(get 'EVIDENCE-CLASS')
[ -n "$CLAIMED" ] || { echo "SHAPE-INCOMPLETE: no EVIDENCE-CLASS field"; exit 1; }

# Verify the CLAIMED class by its required machine fields (labels alone are bluffable).
verified=""
case "$CLAIMED" in
  runtime)
    FP=$(get 'TARGET_FINGERPRINT'); OBS=$(get 'RUNTIME_OBSERVABLE')
    if [ -z "$FP" ] || [ -z "$OBS" ]; then
      echo "SHAPE-INCOMPLETE: runtime class requires TARGET_FINGERPRINT + RUNTIME_OBSERVABLE"; exit 1
    fi
    # Anti-echo rule (PC-8): a source transcript wearing a runtime label. A
    # RUNTIME_OBSERVABLE that IS a grep transcript observes the source, not the runtime.
    case "$OBS" in
      grep:*|'source-grep'*)
        echo "WRONG-LAYER: RUNTIME_OBSERVABLE is a source-grep transcript — a grep can never observe a user-visible/runtime property (§11.4.115(F) evidence-class rule)"; exit 1;;
    esac
    verified="runtime";;
  artifact)
    AP=$(get 'ARTIFACT_PATH'); SH=$(get 'ARTIFACT_SHA256')
    { [ -n "$AP" ] && [ -n "$SH" ]; } || { echo "SHAPE-INCOMPLETE: artifact class requires ARTIFACT_PATH + ARTIFACT_SHA256"; exit 1; }
    verified="artifact";;
  source)
    SR=$(get 'SOURCE_REF')
    [ -n "$SR" ] || { echo "SHAPE-INCOMPLETE: source class requires SOURCE_REF"; exit 1; }
    verified="source";;
  *) echo "SHAPE-INCOMPLETE: unknown evidence class '$CLAIMED' (closed set: runtime|artifact|source)"; exit 1;;
esac

# Matching floor: rank source(1) < artifact(2) < runtime(3); the defect's layer
# sets the minimum class.
rank() { case "$1" in source) echo 1;; artifact) echo 2;; runtime) echo 3;; esac; }
case "$LAYER" in
  user-visible|runtime) need=3;;
  artifact)             need=2;;
  source)               need=1;;
  *) echo "BLIND: unknown defect layer '$LAYER'"; exit 2;;
esac
have=$(rank "$verified")
if [ "$have" -lt "$need" ]; then
  echo "CLASS-INSUFFICIENT: defect layer '$LAYER' requires evidence rank >= $need; '$verified' is rank $have"
  exit 1
fi
echo "CLASS-OK: defect layer '$LAYER' satisfied by verified '$verified' evidence ($EV)"
exit 0
