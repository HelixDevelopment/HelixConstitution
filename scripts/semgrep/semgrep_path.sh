#!/bin/sh
# semgrep_path.sh — Helix Universal semgrep PATH integration for .bashrc/.zshrc.
#
# Sources common directories that may contain semgrep into PATH if not
# already present. Designed to be sourced from the user's .bashrc or .zshrc
# so semgrep is available in every session.
#
# Source in .bashrc:
#   . <constitution>/scripts/semgrep/semgrep_path.sh
#
# Or with an absolute path:
#   [[ -f /path/to/constitution/scripts/semgrep/semgrep_path.sh ]] && \
#       . /path/to/constitution/scripts/semgrep/semgrep_path.sh
#
# POSIX-sh compliant per §11.4.67. Uses only portable shell constructs.
# Appends to PATH only once per directory (no duplicate entries).
# Does NOT require semgrep to already be installed — it just ensures
# common install locations are available.
#
# Cross-references: semgrep_setup.sh, semgrep_validate.sh
# Last verified: 2026-06-21

# List of directories to check for semgrep and other tools.
# Ordered by install-probability (most common first).
for _semgrep_path_dir in \
    "${HOME}/.local/bin" \
    "${HOME}/.cargo/bin" \
    "/usr/local/bin" \
    "/opt/homebrew/bin" \
    "${HOME}/bin"; do

    if [ -d "${_semgrep_path_dir}" ]; then
        # Only add if not already in PATH (portable check using case match)
        case ":${PATH}:" in
            *:"${_semgrep_path_dir}":*)
                # Already in PATH — skip
                ;;
            *)
                PATH="${_semgrep_path_dir}:${PATH}"
                ;;
        esac
    fi
done

# Export PATH for subshells. POSIX shells share the exported variable;
# this makes sure the change propagates.
export PATH
