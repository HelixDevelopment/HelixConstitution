#!/usr/bin/env bash
# =============================================================================
# multitrack_config.sh — per-host multi-track drive config loader + detection
#                         + protect-guard library (§11.4.167 / §11.4.111 /
#                         §11.4.10 / §11.4.133).
# -----------------------------------------------------------------------------
# Purpose:
#   Sourceable POSIX-sh library that (a) resolves the current host, (b) loads
#   its per-host YAML drive<->track map (config/multitrack/<hostname>.yaml),
#   (c) detects LIVE drives at runtime matched by STABLE SERIAL (never by
#   /dev/nvmeXn1 enumeration index — §11.4.111), (d) exposes a HARD
#   protect-guard that refuses any drive whose serial is protected OR whose
#   parent disk carries a /, /boot, or /home mountpoint (belt-and-suspenders),
#   and (e) computes the dynamic track->drive->mount plan (1 drive = system
#   only; 2 = system + 1 track; N = system + N-1 tracks, in `tracks` order).
#
# Usage (sourced):
#   . scripts/multitrack/multitrack_config.sh
#   MT_HOST=$(mt_resolve_host)
#   cfg=$(mt_config_file "$MT_HOST") || { echo "no config for $MT_HOST"; exit 1; }
#   mt_load_config "$cfg"          # sets MT_* variables in the caller shell
#   mt_detect_drives               # prints  SERIAL|DEV|MOUNTS|HASCHILD  lines
#   mt_plan                        # prints  TRACK ...  +  TRACKS_READY=<n>
#   mt_protect_guard "$dev" "$serial" "$mounts"  # 0 = SAFE, 1 = PROTECTED
#
# Inputs:
#   config/multitrack/<hostname>.yaml    (schema_version: 1)
#   Env override MT_CONFIG_DIR           (default: <repo>/config/multitrack)
#   Env override MT_FIXTURE_DRIVES       (newline list of SERIAL|DEV|MOUNTS|HASCHILD
#                                         lines; when set, replaces live lsblk —
#                                         the deterministic test seam, no root/hw)
#
# Outputs:
#   MT_HOSTNAME MT_MACHINE_ID MT_PROTECTED_SERIALS MT_TRACK_COUNT
#   MT_TRACK_<i>_ID/_SERIAL/_MOUNT/_ROLE/_FS  (i = 1..MT_TRACK_COUNT)
#
# Side-effects:  NONE. Every function here is read-only. All destructive work
#   lives in multitrack_drive_prep.sh behind --apply + root + confirm.
#
# Dependencies:  awk, lsblk (real mode only), hostname OR /etc/machine-id.
#
# Cross-references:
#   docs/scripts/multitrack_drive_prep.md
#   docs/guides/MULTITRACK_DRIVE_PREP.md  (§ user guide)
#   config/multitrack/<host>.yaml    (seeded per-host map)
#   §11.4.111 resolve-by-stable-name-not-index · §11.4.10 credentials ·
#   §11.4.133 target/hardware safety · §11.4.167 feature work-stream lifecycle
# =============================================================================

# --- repo root resolution (works whether sourced from repo root or elsewhere) -
mt__self_dir() {
    # POSIX-ish dirname of this sourced file
    d=${MT_SELF:-$0}
    case "$d" in
        */*) printf '%s\n' "${d%/*}" ;;
        *)   printf '%s\n' "." ;;
    esac
}

mt_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then
        printf '%s\n' "$MT_REPO_ROOT"
        return 0
    fi
    # scripts/multitrack/ -> ../../  == repo root
    sd=$(mt__self_dir)
    ( cd "$sd/../.." 2>/dev/null && pwd )
}

mt_config_dir() {
    if [ -n "${MT_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$MT_CONFIG_DIR"
    else
        printf '%s/config/multitrack\n' "$(mt_repo_root)"
    fi
}

# --- host resolution: hostname first, /etc/machine-id as disambiguator --------
mt_resolve_host() {
    h=""
    if command -v hostname >/dev/null 2>&1; then
        h=$(hostname 2>/dev/null | cut -d. -f1)
    fi
    if [ -z "$h" ] && [ -r /etc/hostname ]; then
        h=$(cut -d. -f1 < /etc/hostname 2>/dev/null)
    fi
    if [ -z "$h" ]; then
        # last resort: machine-id (config filename may be machine-id-keyed)
        [ -r /etc/machine-id ] && h=$(cut -c1-16 < /etc/machine-id)
    fi
    printf '%s\n' "$h"
}

# --- config file path (error clearly if the host has no config) ---------------
mt_config_file() {
    host=${1:-$(mt_resolve_host)}
    dir=$(mt_config_dir)
    f="$dir/$host.yaml"
    if [ -r "$f" ]; then
        printf '%s\n' "$f"
        return 0
    fi
    # machine-id fallback filename
    if [ -r /etc/machine-id ]; then
        mid=$(cut -c1-16 < /etc/machine-id)
        f2="$dir/$mid.yaml"
        if [ -r "$f2" ]; then
            printf '%s\n' "$f2"
            return 0
        fi
    fi
    printf 'mt_config_file: no per-host config for host=%s in %s (looked for %s)\n' \
        "$host" "$dir" "$f" >&2
    return 1
}

# --- YAML -> shell assignments (focused parser for schema_version: 1) ---------
# Emits eval-able MT_* lines. Section-gated so device_pool `- id:` / `adb_serial:`
# never leak into the tracks list.
mt__parse_awk() {
    awk '
    function strip(v){
        sub(/[ \t]*#.*$/,"",v)            # drop inline comment
        gsub(/^[ \t]+|[ \t]+$/,"",v)      # trim
        gsub(/^"|"$/,"",v)                # drop surrounding double quotes
        return v
    }
    BEGIN{ section=""; tc=0; prot="" }
    {
        line=$0
        # blank / pure-comment line
        t=line; sub(/^[ \t]*/,"",t)
        if (t=="" || t ~ /^#/) next
        # indent of first non-space
        m=match(line,/[^ ]/); indent=(m>0)?m-1:0
        # top-level key toggles the active section
        if (indent==0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            ci=index(line,":"); section=substr(line,1,ci-1); next
        }
        # left-trim, detect "- " list-item prefix
        lt=line; sub(/^[ \t]+/,"",lt)
        isitem=0
        if (lt ~ /^- /) { sub(/^- /,"",lt); isitem=1 }
        ci=index(lt,":"); if (ci==0) next
        k=substr(lt,1,ci-1); gsub(/[ \t]/,"",k)
        v=strip(substr(lt,ci+1))
        if (section=="host") {
            if (k=="hostname")   printf "MT_HOSTNAME=%c%s%c\n", 39, v, 39
            if (k=="machine_id") printf "MT_MACHINE_ID=%c%s%c\n", 39, v, 39
        } else if (section=="protected_drives") {
            if (isitem && k=="serial") prot=(prot==""?v:prot" "v)
        } else if (section=="tracks") {
            if (isitem && k=="id") {
                tc++
                printf "MT_TRACK_%d_ID=%c%s%c\n", tc, 39, v, 39
            } else if (tc>0) {
                if (k=="drive_serial") printf "MT_TRACK_%d_SERIAL=%c%s%c\n", tc, 39, v, 39
                if (k=="mount")        printf "MT_TRACK_%d_MOUNT=%c%s%c\n", tc, 39, v, 39
                if (k=="role")         printf "MT_TRACK_%d_ROLE=%c%s%c\n", tc, 39, v, 39
                if (k=="fs")           printf "MT_TRACK_%d_FS=%c%s%c\n", tc, 39, v, 39
                if (k=="branch")         printf "MT_TRACK_%d_BRANCH=%c%s%c\n", tc, 39, v, 39
                if (k=="branch_pattern") printf "MT_TRACK_%d_BRANCH=%c%s%c\n", tc, 39, v, 39
            }
        }
        # host/protected/tracks only; device_pool + lease_policy ignored
    }
    END{
        printf "MT_PROTECTED_SERIALS=%c%s%c\n", 39, prot, 39
        printf "MT_TRACK_COUNT=%c%d%c\n", 39, tc, 39
    }
    ' "$1"
}

mt_load_config() {
    cfg=$1
    [ -r "$cfg" ] || { echo "mt_load_config: unreadable $cfg" >&2; return 1; }
    # clear any prior track vars so a re-load never leaves stale indices
    i=1
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        unset "MT_TRACK_${i}_ID" "MT_TRACK_${i}_SERIAL" "MT_TRACK_${i}_MOUNT" \
              "MT_TRACK_${i}_ROLE" "MT_TRACK_${i}_FS" "MT_TRACK_${i}_BRANCH" 2>/dev/null || true
        i=$((i + 1))
    done
    MT_HOSTNAME=""; MT_MACHINE_ID=""; MT_PROTECTED_SERIALS=""; MT_TRACK_COUNT=0
    eval "$(mt__parse_awk "$cfg")"
    export MT_HOSTNAME MT_MACHINE_ID MT_PROTECTED_SERIALS MT_TRACK_COUNT
    return 0
}

# --- device_pool + lease_policy parser (REM-02 device-lock; §11.4.119) ---------
# ADDITIVE + independent of mt__parse_awk: mt_load_config's output is unchanged
# (REM-08 loader untouched). Emits MT_DEVICE_COUNT + MT_DEVICE_<i>_ID/_ADB/
# _MODEL/_CAPS and MT_LEASE_<key>. Inline YAML flow-lists ["a","b"] are split to
# space-joined tokens. Section-gated so tracks/protected never leak in.
mt__parse_pool_awk() {
    awk '
    function strip(v){
        sub(/[ \t]*#.*$/,"",v)
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        gsub(/^"|"$/,"",v)
        return v
    }
    function flowlist(v,   n,arr,i,out,tok){
        gsub(/^\[|\]$/,"",v)
        n=split(v,arr,",")
        out=""
        for(i=1;i<=n;i++){
            tok=arr[i]
            gsub(/^[ \t]+|[ \t]+$/,"",tok)
            gsub(/^"|"$/,"",tok)
            gsub(/^[ \t]+|[ \t]+$/,"",tok)
            if(tok!="") out=(out==""?tok:out" "tok)
        }
        return out
    }
    BEGIN{ section=""; dc=0 }
    {
        line=$0
        t=line; sub(/^[ \t]*/,"",t)
        if (t=="" || t ~ /^#/) next
        m=match(line,/[^ ]/); indent=(m>0)?m-1:0
        if (indent==0 && line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
            ci=index(line,":"); section=substr(line,1,ci-1); next
        }
        lt=line; sub(/^[ \t]+/,"",lt)
        isitem=0
        if (lt ~ /^- /) { sub(/^- /,"",lt); isitem=1 }
        ci=index(lt,":"); if (ci==0) next
        k=substr(lt,1,ci-1); gsub(/[ \t]/,"",k)
        v=strip(substr(lt,ci+1))
        if (section=="device_pool") {
            if (isitem && k=="id") {
                dc++
                printf "MT_DEVICE_%d_ID=%c%s%c\n", dc, 39, v, 39
            } else if (dc>0) {
                if (k=="adb_serial")   printf "MT_DEVICE_%d_ADB=%c%s%c\n", dc, 39, v, 39
                if (k=="model")        printf "MT_DEVICE_%d_MODEL=%c%s%c\n", dc, 39, v, 39
                if (k=="capabilities") printf "MT_DEVICE_%d_CAPS=%c%s%c\n", dc, 39, flowlist(v), 39
            }
        } else if (section=="lease_policy") {
            gsub(/[^A-Za-z0-9_]/,"_",k)
            printf "MT_LEASE_%s=%c%s%c\n", k, 39, flowlist(v), 39
        }
    }
    END{ printf "MT_DEVICE_COUNT=%c%d%c\n", 39, dc, 39 }
    ' "$1"
}

# Loads MT_DEVICE_* + MT_LEASE_* into the caller shell. Safe to call alongside
# mt_load_config (disjoint variable namespaces).
mt_load_pool() {
    cfg=$1
    [ -r "$cfg" ] || { echo "mt_load_pool: unreadable $cfg" >&2; return 1; }
    i=1
    while [ "$i" -le "${MT_DEVICE_COUNT:-0}" ]; do
        unset "MT_DEVICE_${i}_ID" "MT_DEVICE_${i}_ADB" "MT_DEVICE_${i}_MODEL" \
              "MT_DEVICE_${i}_CAPS" 2>/dev/null || true
        i=$((i + 1))
    done
    MT_DEVICE_COUNT=0
    eval "$(mt__parse_pool_awk "$cfg")"
    export MT_DEVICE_COUNT
    return 0
}

# --- LIVE drive detection, matched by STABLE SERIAL (§11.4.111) ---------------
# Output line format:  SERIAL|DEV|MOUNTS|HASCHILD
#   SERIAL   = disk serial (stable id; NEVER the nvmeX ordinal)
#   DEV      = /dev/<name>
#   MOUNTS   = comma-joined mountpoints of the disk AND its partitions
#   HASCHILD = 1 if the disk has partitions/children, else 0
mt_detect_drives() {
    if [ -n "${MT_FIXTURE_DRIVES:-}" ]; then
        # deterministic test seam — no root, no hardware
        printf '%s\n' "$MT_FIXTURE_DRIVES"
        return 0
    fi
    command -v lsblk >/dev/null 2>&1 || { echo "mt_detect_drives: lsblk missing" >&2; return 1; }
    # -P = key="value" pairs, one disk per line: a serial-less disk can NOT
    # column-shift and corrupt the parse of the NEXT disk (§11.4.111 LOW fix).
    # -d = whole disks only; -n no header; explicit column order NAME,TYPE,SERIAL.
    lsblk -dno NAME,TYPE,SERIAL -P 2>/dev/null | while IFS= read -r line; do
        name=$(printf   '%s\n' "$line" | sed -n 's/.*NAME="\([^"]*\)".*/\1/p')
        type=$(printf   '%s\n' "$line" | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
        serial=$(printf '%s\n' "$line" | sed -n 's/.*SERIAL="\([^"]*\)".*/\1/p')
        [ "$type" = "disk" ] || continue
        [ -n "$name" ] || continue
        dev="/dev/$name"
        mounts=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -v '^[[:space:]]*$' | paste -sd, - 2>/dev/null)
        rows=$(lsblk -no NAME "$dev" 2>/dev/null | grep -c .)
        haschild=0
        [ "${rows:-1}" -gt 1 ] && haschild=1
        printf '%s|%s|%s|%s\n' "$serial" "$dev" "$mounts" "$haschild"
    done
}

# --- fail-closed live readers (used by the destructive re-guard path) ---------
# Sentinel meaning "the mount list could NOT be read". The guard fails CLOSED on
# it — DISTINCT from a genuinely-empty mount string (which is allowed). §11.4.133
: "${MT_MOUNTS_UNREADABLE:=__MT_MOUNTS_UNREADABLE__}"

# Read a whole-disk's mountpoints (disk + partitions), comma-joined, on stdout.
#   return 0 = read OK (stdout may be empty for a genuinely-empty disk)
#   return 1 = COULD NOT read (lsblk missing / not a block device / lsblk error)
#              -> caller MUST treat as UNREADABLE and fail CLOSED (§11.4.133).
mt_read_disk_mounts() {
    _dev=$1
    command -v lsblk >/dev/null 2>&1 || return 1
    [ -b "$_dev" ] || return 1
    _raw=$(lsblk -no MOUNTPOINT "$_dev" 2>/dev/null) || return 1
    printf '%s' "$_raw" | grep -v '^[[:space:]]*$' | paste -sd, -
    return 0
}

# Print $dev's CURRENT live serial on stdout (empty if unknown/unreadable).
mt_live_serial() {
    _d=$1
    command -v lsblk >/dev/null 2>&1 || return 0
    lsblk -dno SERIAL "$_d" 2>/dev/null | head -n1 | tr -d '[:space:]'
}

# --- protect-guard primitives -------------------------------------------------
mt_serial_protected() {
    # 0 = serial IS in protected_drives (EXACT match, not substring)
    s=$1
    [ -n "$s" ] || return 1
    # §11.4.111 LOW: disable globbing so a serial containing a shell metachar
    # can't glob-expand during the (still IFS-word-split) loop; restore the
    # caller's prior noglob state afterwards.
    case $- in *f*) _mt_hadf=1 ;; *) _mt_hadf=0 ;; esac
    set -f
    _mt_rc=1
    for p in $MT_PROTECTED_SERIALS; do
        if [ "$p" = "$s" ]; then _mt_rc=0; break; fi
    done
    [ "$_mt_hadf" = 1 ] || set +f
    return "$_mt_rc"
}

mt_mounts_protected() {
    # 0 = the mount set contains a system mountpoint (/, /boot*, /home*)
    mounts=$1
    case ",$mounts," in
        *,/,*)          return 0 ;;   # exact root
        *,/boot*)       return 0 ;;
        *,/home*)       return 0 ;;
    esac
    # also catch a mount that is exactly "/" as the whole field
    [ "$mounts" = "/" ] && return 0
    return 1
}

# HARD protect-guard — call before EVERY destructive step. 0 = SAFE, 1 = REFUSE.
mt_protect_guard() {
    dev=$1; serial=$2; mounts=$3
    # >>MT_MUT_EMPTY_SERIAL (paired §1.1 mutation target — do not remove marker)
    # Fail CLOSED on an unidentifiable target: a safety guard must NEVER ALLOW a
    # disk it cannot positively identify by serial (§11.4.133 / §11.4.111) —
    # independent of the mount check.
    if [ -z "$serial" ]; then
        printf 'REFUSE: %s has EMPTY/unknown serial — cannot positively identify (fail-closed §11.4.133) — NOT touching\n' \
            "$dev" >&2
        return 1
    fi
    # <<MT_MUT_EMPTY_SERIAL
    # Fail CLOSED when the live mount list could not be read (DISTINCT from a
    # genuinely-empty mount set): we cannot verify it is not a system disk.
    if [ "$mounts" = "${MT_MOUNTS_UNREADABLE:-__MT_MOUNTS_UNREADABLE__}" ]; then
        printf 'REFUSE: %s mount list UNREADABLE — cannot verify not-a-system-disk (fail-closed §11.4.133) — NOT touching\n' \
            "$dev" >&2
        return 1
    fi
    if mt_serial_protected "$serial"; then
        printf 'REFUSE: %s serial=%s is in protected_drives (§11.4.133) — NOT touching\n' \
            "$dev" "$serial" >&2
        return 1
    fi
    if mt_mounts_protected "$mounts"; then
        printf 'REFUSE: %s carries a system mountpoint [%s] (belt-and-suspenders) — NOT touching\n' \
            "$dev" "$mounts" >&2
        return 1
    fi
    return 0
}

# Interactive per-drive serial confirmation — the §11.4.133 HUMAN GATE. Reads the
# operator's typed serial from the CONTROLLING TERMINAL (/dev/tty), NEVER from
# stdin — so it truly prompts the keyboard even when the caller's stdin is a pipe
# / here-doc (the illusory-confirmation bug this fixes). 0 = confirmed
# (typed == serial); 1 = mismatch / aborted / no-tty / unknown-serial (fail-closed).
#   $1 dev  $2 serial  $3 assume_yes(0|1)
mt_confirm_serial() {
    _dev=$1; _serial=$2; _yes=${3:-0}
    [ -n "$_serial" ] || return 1
    if [ "$_yes" = "1" ]; then
        printf '    [--yes] auto-confirming %s with serial %s\n' "$_dev" "$_serial"
        return 0
    fi
    if [ ! -c /dev/tty ] || [ ! -r /dev/tty ]; then
        printf '    >> no controlling terminal (/dev/tty) — cannot confirm %s (fail-closed)\n' "$_dev" >&2
        return 1
    fi
    printf '    CONFIRM prep of %s by typing its serial (%s): ' "$_dev" "$_serial" > /dev/tty
    IFS= read -r _ans < /dev/tty || _ans=""
    # >>MT_MUT_CONFIRM (paired §1.1 mutation target — do not remove this marker)
    [ "$_ans" = "$_serial" ] || return 1
    # <<MT_MUT_CONFIRM
    return 0
}

# §11.4.111 TOCTOU guard — re-resolve $dev's LIVE serial and require it to STILL
# equal the plan-time serial AND not be protected. 0 = same non-protected drive;
# 1 = node reassigned / serial changed / now-protected / unreadable (fail-closed).
#   $1 dev  $2 expected(plan-time) serial
mt_verify_live_serial() {
    _dev=$1; _expect=$2
    [ -n "$_expect" ] || return 1
    _cur=$(mt_live_serial "$_dev")
    # >>MT_MUT_TOCTOU (paired §1.1 mutation target — do not remove this marker)
    if [ -z "$_cur" ] || [ "$_cur" != "$_expect" ]; then
        printf 'REFUSE: %s live serial [%s] != plan serial [%s] — node reassigned (§11.4.111) — NOT touching\n' \
            "$_dev" "$_cur" "$_expect" >&2
        return 1
    fi
    if mt_serial_protected "$_cur"; then
        printf 'REFUSE: %s live serial [%s] is PROTECTED at execute time (§11.4.133) — NOT touching\n' \
            "$_dev" "$_cur" >&2
        return 1
    fi
    # <<MT_MUT_TOCTOU
    return 0
}

# --- dynamic track -> live-drive plan -----------------------------------------
# Binds each config track to its declared serial IF that serial is live AND
# passes the protect-guard AND the disk is empty. Emits one TRACK line per
# config track + a UNASSIGNED line per live non-protected serial not in config,
# then TRACKS_READY=<count>.
mt_plan() {
    drives=$(mt_detect_drives)
    ready=0
    i=1
    matched_serials=" "
    while [ "$i" -le "$MT_TRACK_COUNT" ]; do
        eval "tid=\${MT_TRACK_${i}_ID:-}"
        eval "tserial=\${MT_TRACK_${i}_SERIAL:-}"
        eval "tmount=\${MT_TRACK_${i}_MOUNT:-}"
        eval "trole=\${MT_TRACK_${i}_ROLE:-}"
        line=$(printf '%s\n' "$drives" | awk -F'|' -v s="$tserial" '$1==s{print; exit}')
        if [ -z "$line" ]; then
            printf 'TRACK %s SERIAL=%s DEV=- MOUNT=%s ROLE=%s STATUS=ABSENT\n' \
                "$tid" "$tserial" "$tmount" "$trole"
        else
            dev=$(printf '%s' "$line" | cut -d'|' -f2)
            mounts=$(printf '%s' "$line" | cut -d'|' -f3)
            haschild=$(printf '%s' "$line" | cut -d'|' -f4)
            matched_serials="$matched_serials$tserial "
            if ! mt_protect_guard "$dev" "$tserial" "$mounts" 2>/dev/null; then
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=PROTECTED-CONFLICT\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
            elif [ "$haschild" = "1" ] || [ -n "$mounts" ]; then
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=NON-EMPTY\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
            else
                printf 'TRACK %s SERIAL=%s DEV=%s MOUNT=%s ROLE=%s STATUS=READY\n' \
                    "$tid" "$tserial" "$dev" "$tmount" "$trole"
                ready=$((ready + 1))
            fi
        fi
        i=$((i + 1))
    done
    # live non-protected serials that are not any declared track drive
    printf '%s\n' "$drives" | while IFS='|' read -r s dev mounts haschild; do
        [ -n "$s" ] || continue
        case "$matched_serials" in *" $s "*) continue ;; esac
        if mt_serial_protected "$s"; then
            printf 'DRIVE %s DEV=%s STATUS=PROTECTED\n' "$s" "$dev"
        elif mt_mounts_protected "$mounts"; then
            printf 'DRIVE %s DEV=%s STATUS=PROTECTED-BY-MOUNT MOUNTS=%s\n' "$s" "$dev" "$mounts"
        else
            printf 'DRIVE %s DEV=%s STATUS=UNASSIGNED-CANDIDATE\n' "$s" "$dev"
        fi
    done
    printf 'TRACKS_READY=%d\n' "$ready"
}
