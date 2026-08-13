#!/usr/bin/env bash
# SOL-10 — misunderstanding-layer mechanics: three decidable checks for the
# composition seams where honest components manufacture false beliefs.
#
#   stateblock : MU-1 — text encoding a MEASUREMENT gets a re-measurement trigger
#                (machine-derived block re-rendered + byte-compared, §11.4.205(4);
#                self-referencing blocks refused per the §11.4.205(5) fixpoint bug)
#   fence      : MU-2 — a verdict is citable only inside its declared fence
#                (§11.4.112(5) citation-fencing, mechanized)
#   seam       : MU-3 — a plan may only require a gate at the gate's DECLARED seam
#                (restatements move qualifiers; the declaration wins)
#
# SECURITY NOTE (integration, not POC): stateblock EXECUTES the embedded cmd.
# A consumer MUST allowlist the command vocabulary (read-only generators) before
# wiring this at a commit seam — an unconstrained cmd field is an injection seam.
set -u
MODE="${1:?stateblock|fence|seam}"; shift

case "$MODE" in
stateblock)
  DOC="${1:?doc}"
  [ -r "$DOC" ] || { echo "BLIND: cannot read $DOC"; exit 2; }
  base=$(basename "$DOC")
  n=0; findings=0
  # Extract blocks: begin-line carries cmd="..."; content until end marker.
  while IFS= read -r begin_line_no; do
    n=$((n+1))
    begin=$(sed -n "${begin_line_no}p" "$DOC")
    cmd=$(printf '%s' "$begin" | sed -n 's/.*cmd="\(.*\)".*/\1/p')
    if [ -z "$cmd" ]; then echo "DRIFT: block at line $begin_line_no has no cmd"; findings=$((findings+1)); continue; fi
    case "$cmd" in *"$base"*)
      echo "SELF-REF: block at line $begin_line_no derives from the document itself — a self-fingerprint is a permanent false-FAIL fixpoint (§11.4.205(5))"
      findings=$((findings+1)); continue;;
    esac
    end_line_no=$(awk -v s="$begin_line_no" 'NR>s && /<!-- machine:end -->/{print NR; exit}' "$DOC")
    if [ -z "$end_line_no" ]; then echo "DRIFT: unterminated block at line $begin_line_no"; findings=$((findings+1)); continue; fi
    recorded=$(sed -n "$((begin_line_no+1)),$((end_line_no-1))p" "$DOC")
    rendered=$(bash -c "$cmd" 2>/dev/null)
    if [ "$recorded" != "$rendered" ]; then
      echo "DRIFT: block at line $begin_line_no — recorded state no longer matches its generator"
      echo "  recorded: $(printf '%s' "$recorded" | head -1)"
      echo "  rendered: $(printf '%s' "$rendered" | head -1)"
      findings=$((findings+1))
    fi
  done < <(grep -n 'machine:begin' "$DOC" | cut -d: -f1)
  # Control needle: a doc claiming machine blocks but yielding zero extracted
  # blocks means the extractor (or the doc) is broken — never a silent pass.
  if [ "$n" -eq 0 ]; then
    if grep -q 'machine:' "$DOC"; then echo "BLIND: machine markers present but zero blocks extracted"; exit 2; fi
    echo "STATEBLOCK: no machine blocks declared (nothing to verify)"; exit 0
  fi
  echo "STATEBLOCK: blocks=$n findings=$findings"
  [ "$findings" -eq 0 ] || exit 1
  ;;
fence)
  REGF="${1:?registry}"; DIR="${2:?docs-dir}"
  [ -r "$REGF" ] || { echo "BLIND: cannot read $REGF"; exit 2; }
  [ -d "$DIR" ]  || { echo "BLIND: $DIR absent"; exit 2; }
  findings=0
  while IFS=$'\t' read -r vid fencelist; do
    [ -n "$vid" ] || continue
    while IFS= read -r hit; do
      rel="${hit#"$DIR"/}"
      okfile=0
      IFS=',' read -ra allowed <<< "$fencelist"
      for a in "${allowed[@]}"; do
        case "docs/$rel" in "$a") okfile=1;; esac
        case "$rel" in "${a#docs/}") okfile=1;; esac
      done
      if [ "$okfile" -eq 0 ]; then
        echo "FENCE-VIOLATION: verdict $vid cited in $rel outside its fence ($fencelist) — outside the fence means UNDECIDED, never inherited (§11.4.112(5))"
        findings=$((findings+1))
      fi
    done < <(grep -rl -- "$vid" "$DIR" 2>/dev/null)
  done < "$REGF"
  echo "FENCE: findings=$findings"
  [ "$findings" -eq 0 ] || exit 1
  ;;
seam)
  GREG="${1:?gate registry}"; PLAN="${2:?plan}"
  [ -r "$GREG" ] || { echo "BLIND: cannot read $GREG"; exit 2; }
  [ -r "$PLAN" ] || { echo "BLIND: cannot read $PLAN"; exit 2; }
  findings=0
  while IFS= read -r line; do
    case "$line" in REQUIRE\ *\ AT\ *) : ;; *) continue;; esac
    gid=$(printf '%s' "$line" | awk '{print $2}')
    seam=$(printf '%s' "$line" | awk '{print $4}')
    declared=$(awk -F'\t' -v g="$gid" '$1==g{print $2; exit}' "$GREG")
    if [ -z "$declared" ]; then
      echo "SEAM-MISMATCH: plan requires unregistered gate $gid — the declaration is the source of truth, a restatement cannot mint one"
      findings=$((findings+1))
    elif [ "$declared" != "$seam" ]; then
      echo "SEAM-MISMATCH: plan requires $gid at '$seam' but its declaration seats it at '$declared' — the restatement moved a load-bearing qualifier (MU-3)"
      findings=$((findings+1))
    fi
  done < "$PLAN"
  echo "SEAM: findings=$findings"
  [ "$findings" -eq 0 ] || exit 1
  ;;
*) echo "usage: mu_checks.sh stateblock|fence|seam ..."; exit 2;;
esac
