#!/usr/bin/env bash
# subagent_tier.sh — §11.4.141 Measure M2 model-tier resolver + bright-line enforcer.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Reads actions/subagent_tiering.yaml and, for a given subagent TASK CLASS,
# prints its model tier (mechanical | judgment) and the resolved model name, so a
# dispatcher can pick the model WITHOUT hardcoding. It MECHANICALLY ENFORCES the
# §11.4.141 bright line: it REFUSES (exit 1) any attempt to route a `judgment`-tier
# class to the mechanical model. That refusal is what makes "the cheap model never
# decides" real, and is the §1.1 paired-mutation seam (mutate the YAML to set a
# judgment class to mechanical → the `--assert-mechanical` check FAILs).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   subagent_tier.sh resolve <task-class>
#       → prints: "<tier> <model>" (e.g. "mechanical haiku" / "judgment inherit")
#   subagent_tier.sh model <task-class>
#       → prints just the resolved model name.
#   subagent_tier.sh assert-mechanical <task-class>
#       → exit 0 if the class is mechanical (safe to tier down);
#         exit 1 if it is judgment (REFUSE — would cross the bright line).
#   subagent_tier.sh list
#       → prints every class + tier from the registry.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   <task-class>             a name from actions/subagent_tiering.yaml `classes[]`.
#   $HELIX_SUBAGENT_TIERING  registry path override (default: the bundled YAML).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   resolve/model: the tier and/or model name on stdout.
#   assert-mechanical: exit code only (+ a one-line stderr verdict).
#   list: "class<TAB>tier<TAB>model" lines.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). No network, no device mutation, no commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   A YAML reader. Prefers python3 (robust); falls back to a constrained awk
#   parse of the flat `classes[]` rows. Parses clean under bash -n AND sh -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.141 (M2 — model tiering), §11.4.50 (cheap model never decides),
#   §11.4.102 / §11.4.125 / §11.4.7 (judgment-tier classes), §1.1 (mutate the
#   registry → assert-mechanical FAILs), §11.4.28 (decoupled registry), §11.4.67.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   resolve/model/list: 0 ok, 2 env/unknown-class.
#   assert-mechanical: 0 mechanical, 1 judgment (REFUSE), 2 env/unknown-class.
#
# Classification: universal (§11.4.17) — no project-specific data.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY="${HELIX_SUBAGENT_TIERING:-${CONST_ROOT}/actions/subagent_tiering.yaml}"

_die() { echo "subagent_tier: $*" >&2; exit 2; }
[ -f "$REGISTRY" ] || _die "registry not found: $REGISTRY"

# Parse the registry once into three echo-able facts via python3 (robust YAML)
# or an awk fallback. We deliberately keep the YAML FLAT (mechanical_model,
# judgment_model, classes[] of {name,tier}) so the awk fallback is reliable.
_parse_py() {
    python3 - "$REGISTRY" "$1" "$2" <<'PY' 2>/dev/null
import sys
reg, mode, cls = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
mech = "haiku"; judg = "inherit"; classes = {}
in_classes = False
for raw in open(reg, encoding="utf-8"):
    line = raw.rstrip("\n")
    s = line.strip()
    if s.startswith("#") or not s:
        continue
    if s.startswith("mechanical_model:"):
        mech = s.split(":", 1)[1].strip(); continue
    if s.startswith("judgment_model:"):
        judg = s.split(":", 1)[1].strip(); continue
    if s.startswith("classes:"):
        in_classes = True; continue
    if in_classes and s.startswith("-"):
        # row like:  - { name: code_search, tier: mechanical, desc: "..." }
        name = tier = None
        for part in s.lstrip("-").strip().strip("{}").split(","):
            if ":" not in part:
                continue
            k, v = part.split(":", 1)
            k = k.strip(); v = v.strip().strip('"')
            if k == "name": name = v
            elif k == "tier": tier = v
        if name and tier:
            classes[name] = tier
def model_for(tier): return mech if tier == "mechanical" else judg
if mode == "list":
    for n, t in classes.items():
        print(f"{n}\t{t}\t{model_for(t)}")
    sys.exit(0)
if cls not in classes:
    sys.stderr.write(f"unknown task-class '{cls}'\n"); sys.exit(2)
t = classes[cls]
if mode == "resolve": print(f"{t} {model_for(t)}")
elif mode == "model": print(model_for(t))
elif mode == "tier":  print(t)
sys.exit(0)
PY
}

_parse_awk() {
    # Fallback: same flat-YAML contract, awk only.
    local mode="$1" cls="${2:-}"
    awk -v MODE="$mode" -v CLS="$cls" '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        /^[ \t]*#/ { next }
        /^[ \t]*mechanical_model:/ { split($0,a,":"); mech=trim(a[2]); next }
        /^[ \t]*judgment_model:/   { split($0,a,":"); judg=trim(a[2]); next }
        /^[ \t]*classes:/          { inc=1; next }
        inc && /^[ \t]*-/ {
            line=$0; sub(/^[ \t]*-[ \t]*\{?/,"",line); sub(/\}[ \t]*$/,"",line)
            n=""; t=""
            nf=split(line,parts,",")
            for(i=1;i<=nf;i++){
                kv=parts[i]; ci=index(kv,":"); if(ci==0) continue
                k=trim(substr(kv,1,ci-1)); v=trim(substr(kv,ci+1)); gsub(/"/,"",v)
                if(k=="name") n=v; else if(k=="tier") t=v
            }
            if(n!=""&&t!=""){ cls_t[n]=t; order[++oc]=n }
        }
        function modelfor(tt){ return (tt=="mechanical")?mech:judg }
        END{
            if(MODE=="list"){
                for(i=1;i<=oc;i++){ nm=order[i]; print nm"\t"cls_t[nm]"\t"modelfor(cls_t[nm]) }
                exit 0
            }
            if(!(CLS in cls_t)){ print "unknown task-class \x27" CLS "\x27" > "/dev/stderr"; exit 2 }
            tt=cls_t[CLS]
            if(MODE=="resolve") print tt" "modelfor(tt)
            else if(MODE=="model") print modelfor(tt)
            else if(MODE=="tier")  print tt
            exit 0
        }
    ' "$REGISTRY"
}

_parse() {
    if command -v python3 >/dev/null 2>&1; then
        _parse_py "$@"
    else
        _parse_awk "$@"
    fi
}

main() {
    local sub="${1:-}"; [ $# -gt 0 ] && shift || true
    case "$sub" in
        resolve|model|tier)
            [ $# -ge 1 ] || _die "$sub: <task-class> required"
            local out rc
            out="$(_parse "$sub" "$1")"; rc=$?
            if [ $rc -ne 0 ] || [ -z "$out" ]; then
                echo "subagent_tier: $sub: unknown task-class '$1' (run 'subagent_tier.sh list')." >&2
                exit 2
            fi
            printf '%s\n' "$out"
            ;;
        list)
            _parse list "" || exit 2
            ;;
        assert-mechanical)
            [ $# -ge 1 ] || _die "assert-mechanical: <task-class> required"
            local tier; tier="$(_parse tier "$1")" || exit 2
            if [ "$tier" = "mechanical" ]; then
                echo "subagent_tier: '$1' is MECHANICAL — safe to tier down." >&2
                exit 0
            else
                echo "subagent_tier: REFUSE — '$1' is JUDGMENT tier; routing it to the cheap model crosses the §11.4.141 bright line (the cheap model never decides)." >&2
                exit 1
            fi
            ;;
        ""|-h|--help)
            sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
            ;;
        *) _die "unknown subcommand '$sub' (use: resolve | model | tier | assert-mechanical | list)" ;;
    esac
}

main "$@"
