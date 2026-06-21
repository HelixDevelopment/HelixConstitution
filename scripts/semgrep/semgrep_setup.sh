#!/bin/sh
# semgrep_setup.sh — Helix Universal semgrep install/build integration script.
#
# Installs semgrep via pip --user (fast path) or builds from the cloned
# submodule source when the OCaml toolchain is available. POSIX-sh compliant
# per §11.4.67.
#
# A consumer project that incorporates this constitution submodule invokes
# this script to ensure semgrep is on PATH before running the validation
# or scan gates. Intended to be called from setup.sh or once-per-session
# by the operator/conductor.
#
# Functions:
#   semgrep_setup_check()        — returns 0 if semgrep is on PATH
#   semgrep_setup_install()      — pip install --user if not present
#   semgrep_setup_build()        — build from submodule source (OCaml)
#
# Usage:
#   . <constitution>/scripts/semgrep/semgrep_setup.sh
#   semgrep_setup_check
#   semgrep_setup_install        # or semgrep_setup_build
#
# Anti-bluff (§107): after each installation path, verifies semgrep --version
# reports a non-empty version string. A successful pip install followed by an
# absent or broken binary is a bluff caught by the post-install check.
#
# Exit codes:
#   0 — semgrep is installed and on PATH
#   1 — installation attempted but binary not found (bluff caught)
#   2 — environment problem (pip missing, network unreachable, OCaml missing)
#
# Dependencies: python3, pip3 (for install path); ocaml, opam (for build path)
# Cross-references: semgrep_validate.sh, docs/semgrep/Status.md
# Last verified: 2026-06-21

set -u

# ---------- state ----------
SEMGREP_DIR="${SEMGREP_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONST_ROOT="$(cd "${SEMGREP_DIR}/../.." && pwd)"
STATUS_DOC="${CONST_ROOT}/docs/semgrep/Status.md"
SEMGREP_SUBMODULE_PATH="${CONST_ROOT}/submodules/semgrep"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "${STATUS_DOC}")"
mkdir -p "$(dirname "${STATUS_DOC}")/../.semgrep"

# ---------- helpers ----------

# Log an event to the semgrep Status.md event ledger.
semgrep_log_event() {
    _event="$1"
    _detail="$2"
    {
        echo ""
        echo "## ${TS} — ${_event}"
        echo ""
        echo "${_detail}"
    } >> "${STATUS_DOC}"
}

# ---------- public functions ----------

# semgrep_setup_check — returns 0 if semgrep is on PATH and functional.
semgrep_setup_check() {
    if command -v semgrep >/dev/null 2>&1; then
        _version="$(semgrep --version 2>/dev/null | head -1)"
        if [ -n "${_version}" ]; then
            return 0
        fi
    fi
    return 1
}

# semgrep_setup_install — install semgrep via pip --user.
# Falls back to pip3 if python3 -m pip not available.
semgrep_setup_install() {
    echo "[semgrep_setup] Checking pip availability..."

    _pip_cmd=""

    if python3 -m pip --version >/dev/null 2>&1; then
        _pip_cmd="python3 -m pip"
    elif command -v pip3 >/dev/null 2>&1; then
        _pip_cmd="pip3"
    elif command -v pip >/dev/null 2>&1; then
        _pip_cmd="pip"
    else
        echo "ERROR: pip not found. Install python3-pip first." >&2
        semgrep_log_event "semgrep setup FAILED" \
            "- error: pip not available"
        return 2
    fi

    echo "[semgrep_setup] Installing semgrep via ${_pip_cmd} install --user..."
    ${_pip_cmd} install --user semgrep 2>&1 || {
        _exit=$?
        echo "ERROR: pip install failed (exit ${_exit})." >&2
        semgrep_log_event "semgrep pip install FAILED" \
            "- exit code: ${_exit}"
        return 2
    }

    # Re-check PATH — pip --user installs to ~/.local/bin
    _recheck_paths="${HOME}/.local/bin /usr/local/bin ${HOME}/.cargo/bin"

    for _dir in ${_recheck_paths}; do
        if [ -x "${_dir}/semgrep" ]; then
            if ! echo "${PATH}" | grep -q "${_dir}"; then
                export PATH="${_dir}:${PATH}"
            fi
            break
        fi
    done

    # Anti-bluff: verify binary works
    if semgrep_setup_check; then
        _v="$(semgrep --version 2>/dev/null | head -1)"
        echo "[semgrep_setup] SUCCESS: semgrep ${_v} installed."
        semgrep_log_event "semgrep pip install SUCCEEDED" \
            "- version: ${_v}"
        return 0
    else
        echo "ERROR: pip install succeeded but semgrep binary not found." >&2
        echo "       Check PATH or run 'python3 -m semgrep --version'." >&2
        semgrep_log_event "semgrep pip install FAILED (bluff caught)" \
            "- pip exit 0 but semgrep not on PATH"
        return 1
    fi
}

# semgrep_setup_build — build semgrep from submodule source (OCaml).
# Requires ocaml, opam, make, gcc.
semgrep_setup_build() {
    echo "[semgrep_setup] Checking OCaml toolchain..."

    _missing=""
    for _cmd in ocaml opam make gcc; do
        if ! command -v "${_cmd}" >/dev/null 2>&1; then
            _missing="${_missing} ${_cmd}"
        fi
    done

    if [ -n "${_missing}" ]; then
        echo "ERROR: missing OCaml build dependencies:${_missing}" >&2
        echo "       Install them first or use 'semgrep_setup_install' (pip)." >&2
        semgrep_log_event "semgrep build FAILED" \
            "- missing deps:${_missing}"
        return 2
    fi

    # Check if submodule exists; if not, suggest cloning
    if [ ! -d "${SEMGREP_SUBMODULE_PATH}" ]; then
        echo "[semgrep_setup] Submodule not found at ${SEMGREP_SUBMODULE_PATH}."
        echo "       Cloning semgrep source..."
        mkdir -p "$(dirname "${SEMGREP_SUBMODULE_PATH}")"
        git clone --depth 1 git@github.com:semgrep/semgrep.git \
            "${SEMGREP_SUBMODULE_PATH}" 2>&1 || {
            _exit=$?
            echo "ERROR: git clone failed (exit ${_exit})." >&2
            semgrep_log_event "semgrep clone FAILED" \
                "- git clone exit: ${_exit}"
            return 2
        }
    fi

    cd "${SEMGREP_SUBMODULE_PATH}" || return 2

    echo "[semgrep_setup] Building semgrep from source..."
    echo "       This may take a while (OCaml compilation)."

    # Initialize opam if not already
    if ! command -v opam >/dev/null 2>&1 || ! opam list >/dev/null 2>&1; then
        opam init --disable-sandboxing --yes 2>&1 || {
            echo "ERROR: opam init failed." >&2
            return 2
        }
    fi

    eval "$(opam env)" 2>/dev/null

    # Run the build (semgrep uses 'make' or 'make install')
    # The exact build command depends on the semgrep version.
    # Fall back to pip if OCaml build path is not supported by this source layout.
    if [ -f "Makefile" ]; then
        make 2>&1 || {
            echo "ERROR: make failed." >&2
            echo "Falling back to pip install..." >&2
            cd /tmp || return 2
            semgrep_setup_install
            return $?
        }
    else
        echo "[semgrep_setup] No Makefile found in source. Falling back to pip..."
        cd /tmp || return 2
        semgrep_setup_install
        return $?
    fi

    # Anti-bluff: verify binary works
    if semgrep_setup_check; then
        _v="$(semgrep --version 2>/dev/null | head -1)"
        echo "[semgrep_setup] SUCCESS: semgrep ${_v} built and installed."
        semgrep_log_event "semgrep build SUCCEEDED" \
            "- version: ${_v} (built from source)"
        return 0
    else
        echo "ERROR: build completed but semgrep binary not found." >&2
        semgrep_log_event "semgrep build FAILED (bluff caught)" \
            "- make succeeded but semgrep not on PATH"
        return 1
    fi
}

# ---------- main ----------
# When invoked directly (not sourced), run the install path.
case "$(basename "$0" 2>/dev/null)" in
    semgrep_setup.sh)
        if semgrep_setup_check; then
            echo "semgrep already installed: $(semgrep --version 2>/dev/null | head -1)"
            exit 0
        fi
        semgrep_setup_install
        exit $?
        ;;
    *)
        # Sourced — do nothing, just provide functions
        ;;
esac
