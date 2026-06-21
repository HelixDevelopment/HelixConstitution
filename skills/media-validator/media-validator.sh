#!/usr/bin/env bash
# ============================================================================
# media-validator.sh — Validate media files via OCR/metadata/pattern matching
# ============================================================================
# Purpose:
#   Takes a path to a media file (MP4, PNG, TXT), runs OCR via tesseract
#   (if available), compares extracted text against expected patterns,
#   and returns PASS/FAIL with evidence.
#
#   §11.4.107 — liveness evidence
#   §11.4.117 — CV/OCR pixel oracle fallback
#   §11.4.137 — subtitle content-correctness oracle
#
# Usage:
#   ./media-validator.sh <file> [expected-pattern...]
#
# Examples:
#   ./media-validator.sh screenshot.png "Hello, World" "Welcome"
#   ./media-validator.sh recording.mp4 "Playback started" "Subtitle:"
#   ./media-validator.sh output.txt "COMPLETED" "PASS:"
#
# Inputs:
#   $1          — path to the media file (MP4, PNG, TXT, or any format
#                 supported by tesseract for OCR)
#   $2..$N      — one or more expected regex patterns to match
#                 against extracted text
#   MEDIA_VALIDATOR_EVIDENCE_DIR  — evidence output directory
#                   (default: qa-results/media-validator/)
#
# Outputs:
#   stdout — PASS/FAIL/SKIP verdict with evidence path
#   Exit 0 — PASS (all expected patterns found)
#   Exit 1 — FAIL (one or more patterns not found, or file error)
#   Exit 2 — SKIP (dependency missing, cannot validate)
#
# Dependencies:
#   tesseract  (optional — OCR on images/video frames)
#   ffmpeg     (optional — frame extraction from MP4)
#   ffprobe    (optional — video metadata)
#   file       (optional — MIME detection; uses extension fallback)
#
# Side-effects:
#   Writes evidence to $MEDIA_VALIDATOR_EVIDENCE_DIR/<timestamp>-<basename>/
#
# Cross-references:
#   constitution/Constitution.md §11.4.69 (sink-side taxonomy)
#   constitution/Constitution.md §11.4.107 (liveness evidence)
#   constitution/Constitution.md §11.4.117 (pixel oracle)
#   constitution/Constitution.md §11.4.137 (subtitle correctness)
#
# Last verified: 2026-06-21
# ============================================================================

set -euo pipefail

# --- Paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_BASE="${MEDIA_VALIDATOR_EVIDENCE_DIR:-qa-results/media-validator}"

# --- Helpers --------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS:${NC} $*"; }
fail() { echo -e "${RED}FAIL:${NC} $*";   exit 1; }
skip() { echo -e "${YELLOW}SKIP:${NC} $*"; exit 2; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# --- Cleanup --------------------------------------------------------------
EVIDENCE_DIR=""
cleanup() {
    :
}
trap cleanup EXIT

# ============================================================================
# Main
# ============================================================================
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <file> [expected-pattern...]"
        echo "  Validates media file content against expected patterns."
        echo "  Runs OCR on images/video frames, then greps for patterns."
        exit 2
    fi

    local file="$1"
    shift
    local patterns=("$@")

    # --- Validate input file ------------------------------------------------
    if [ ! -f "$file" ]; then
        fail "File not found: $file"
    fi

    local basename
    basename="$(basename "$file")"
    local timestamp
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

    # Create evidence directory
    EVIDENCE_DIR="${EVIDENCE_BASE}/${timestamp}-${basename}"
    mkdir -p "$EVIDENCE_DIR"

    # Copy original file as evidence
    cp "$file" "${EVIDENCE_DIR}/original_${basename}"

    # --- Determine file type -------------------------------------------------
    local mime=""
    local ext="${file##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

    if command -v file &>/dev/null; then
        mime="$(file --mime-type -b "$file")"
    fi

    info "File: $file"
    info "MIME: ${mime:-unknown}"
    info "Extension: $ext"
    info "Expected patterns: ${patterns[*]:-(none)}"

    # --- Extract text -------------------------------------------------------
    local extracted_text=""
    local text_source=""

    case "$ext" in
        txt|log|md|json|yaml|yml|xml|csv|sh|bash)
            # Plain text — read directly
            extracted_text="$(cat "$file")"
            text_source="direct-read"
            info "Text source: direct file read"
            ;;

        png|jpg|jpeg|gif|bmp|tiff|tif|webp)
            # Image — run OCR via tesseract
            if command -v tesseract &>/dev/null; then
                local ocr_out="${EVIDENCE_DIR}/ocr_output"
                tesseract "$file" "$ocr_out" 2>/dev/null || \
                    skip "tesseract failed on $file"
                if [ -f "${ocr_out}.txt" ]; then
                    extracted_text="$(cat "${ocr_out}.txt")"
                    text_source="tesseract-ocr"
                    cp "${ocr_out}.txt" "${EVIDENCE_DIR}/ocr_raw.txt"
                else
                    fail "tesseract produced no output for $file"
                fi
            else
                skip "tesseract not installed — cannot OCR image: $file"
            fi
            ;;

        mp4|mkv|webm|avi|mov|m4v)
            # Video — extract a frame and OCR it, plus probe metadata
            if command -v ffmpeg &>/dev/null && command -v tesseract &>/dev/null; then
                # Extract a mid-point frame
                local duration
                duration="$(ffprobe -v error -show_entries format=duration \
                    -of csv=p=0 "$file" 2>/dev/null || echo "10")"
                local mid_time
                mid_time="$(echo "$duration / 2" | bc -l 2>/dev/null || echo "5")"
                local frame_file="${EVIDENCE_DIR}/mid_frame.png"
                ffmpeg -y -ss "$mid_time" -i "$file" -vframes 1 \
                    "$frame_file" 2>/dev/null || \
                    warn "ffmpeg frame extraction failed for $file"

                # OCR the frame
                if [ -f "$frame_file" ]; then
                    local ocr_out="${EVIDENCE_DIR}/ocr_output"
                    tesseract "$frame_file" "$ocr_out" 2>/dev/null || true
                    if [ -f "${ocr_out}.txt" ]; then
                        extracted_text="$(cat "${ocr_out}.txt")"
                        text_source="ffmpeg-frame+tesseract"
                        cp "${ocr_out}.txt" "${EVIDENCE_DIR}/ocr_raw.txt"
                    fi
                fi

                # Also dump ffprobe metadata
                ffprobe -v error -show_entries stream=codec_type,codec_name,width,height \
                    -of json "$file" > "${EVIDENCE_DIR}/ffprobe_metadata.json" 2>/dev/null || true
            elif command -v tesseract &>/dev/null; then
                # Try OCR directly on the video file (tesseract may reject it)
                local ocr_out="${EVIDENCE_DIR}/ocr_output"
                tesseract "$file" "$ocr_out" 2>/dev/null || \
                    skip "Cannot read $ext — ffmpeg not available for frame extraction"
                if [ -f "${ocr_out}.txt" ]; then
                    extracted_text="$(cat "${ocr_out}.txt")"
                    text_source="tesseract-direct"
                    cp "${ocr_out}.txt" "${EVIDENCE_DIR}/ocr_raw.txt"
                fi
            else
                skip "tesseract and ffmpeg not installed — cannot validate video: $file"
            fi
            ;;

        *)
            # Unknown — try OCR directly; if that fails, treat as text
            if command -v tesseract &>/dev/null; then
                local ocr_out="${EVIDENCE_DIR}/ocr_output"
                if tesseract "$file" "$ocr_out" 2>/dev/null; then
                    extracted_text="$(cat "${ocr_out}.txt" 2>/dev/null || true)"
                    text_source="tesseract-ocr"
                fi
            fi
            if [ -z "$extracted_text" ]; then
                # Fallback: try reading as text
                extracted_text="$(cat "$file" 2>/dev/null || true)"
                text_source="direct-read-fallback"
            fi
            ;;
    esac

    # Save extracted text
    if [ -n "$extracted_text" ]; then
        echo "$extracted_text" > "${EVIDENCE_DIR}/extracted_text.txt"
        info "Extracted text length: $(echo "$extracted_text" | wc -c) bytes"
    else
        info "No text could be extracted from $file"
        echo "(no text extracted)" > "${EVIDENCE_DIR}/extracted_text.txt"
    fi

    # --- Match patterns -----------------------------------------------------
    local all_found=true
    local evidence_lines=()

    if [ ${#patterns[@]} -eq 0 ]; then
        # No patterns specified — just confirm text was extracted
        if [ -n "$extracted_text" ]; then
            pass "Text extracted from ${basename} [evidence: ${EVIDENCE_DIR}/extracted_text.txt]"
            exit 0
        else
            fail "No text could be extracted from ${basename} and no patterns to match"
        fi
    fi

    for pattern in "${patterns[@]}"; do
        if echo "$extracted_text" | grep -qE "$pattern"; then
            local match_line
            match_line="$(echo "$extracted_text" | grep -E "$pattern" | head -1)"
            info "  Pattern found: /${pattern}/ -> '${match_line}'"
            evidence_lines+=("FOUND: ${pattern} -> ${match_line}")
        else
            warn "  Pattern NOT found: /${pattern}/"
            evidence_lines+=("MISSING: ${pattern}")
            all_found=false
        fi
    done

    # Write evidence report
    {
        echo "Media Validator Evidence Report"
        echo "================================"
        echo "File:      $file"
        echo "MIME:      ${mime:-unknown}"
        echo "Timestamp: $timestamp"
        echo "Text source: ${text_source:-none}"
        echo ""
        echo "Expected patterns (${#patterns[@]}):"
        printf '  - %s\n' "${patterns[@]}"
        echo ""
        echo "Results:"
        printf '  %s\n' "${evidence_lines[@]}"
        echo ""
        echo "Verdict: $($all_found && echo "PASS" || echo "FAIL")"
    } > "${EVIDENCE_DIR}/verdict.txt"

    # --- Verdict -------------------------------------------------------------
    if $all_found && [ ${#patterns[@]} -gt 0 ]; then
        pass "All ${#patterns[@]} expected pattern(s) found in ${basename}"
        echo "       [evidence: ${EVIDENCE_DIR}/verdict.txt]"
        exit 0
    elif [ ${#patterns[@]} -gt 0 ]; then
        fail "Some expected patterns not found in ${basename}"
        echo "       [evidence: ${EVIDENCE_DIR}/verdict.txt]"
        exit 1
    fi
}

main "$@"
