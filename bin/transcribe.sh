#!/bin/bash
# transcribe.sh — Batch-or-single transcription with whisper-cli.
# - FILE: transcribe that one file (unless it already has .srt or *_subbed.*).
# - DIR or no arg: scan for videos and transcribe only those WITHOUT a matching .srt,
#   skipping any filename containing "_subbed".
# Always embeds QuickTime-friendly soft subtitles into <name>_subbed.mp4 after creating .srt.
#
# Usage:
#   ./transcribe.sh [-l <lang>] [<file_or_dir>]
#   -l en     -> force English transcription
#   -l xx     -> force translation from <lang code> -> English
#
# Self-contained bundle expectations:
#   ./bin/ffmpeg, ./bin/whisper-cli, ./models/ggml-large-v2.bin (or ggml-small.en.bin)

set -euo pipefail

# ---------- Global quit-safe cleanup ----------
# We track all temp files created during this run and remove them on normal exit,
# Ctrl-C (SIGINT), or app-initiated termination (SIGTERM). Note: SIGKILL (-9) cannot be trapped.
TMP_FILES=()

cleanup_all() {
  for f in "${TMP_FILES[@]:-}"; do
    [ -n "${f:-}" ] && [ -f "$f" ] && rm -f "$f" || true
  done
}
trap cleanup_all EXIT INT TERM

# ---------- Locate bundle root & prefer bundled bin/ + models/ ----------
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$BIN_DIR/.." && pwd)"

export PATH="$BIN_DIR:$PATH"
export WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"

# Choose model
: "${MODEL_DIR:="$BUNDLE_DIR/models"}"
if [ -z "${MODEL_LARGE_V2:-}" ]; then
  if [ -f "$MODEL_DIR/ggml-large-v2.bin" ]; then
    export MODEL_LARGE_V2="$MODEL_DIR/ggml-large-v2.bin"
  elif [ -f "$MODEL_DIR/ggml-small.en.bin" ]; then
    export MODEL_LARGE_V2="$MODEL_DIR/ggml-small.en.bin"
  else
    echo "Error: No model found in $MODEL_DIR" >&2
    echo "Expected one of: ggml-large-v2.bin or ggml-small.en.bin" >&2
    exit 1
  fi
fi

# ---------- Args ----------
LANG_OVERRIDE=""
while getopts ":l:" opt; do
  case "$opt" in
    l) LANG_OVERRIDE="$(printf '%s' "$OPTARG" | tr '[:upper:]' '[:lower:]')" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

TARGET_PATH="${1:-"$BUNDLE_DIR/video"}"

# ---------- Sanity checks ----------
if ! command -v "$WHISPER_BIN" >/dev/null 2>&1; then
  echo "Error: '$WHISPER_BIN' not found in PATH. Expected in $BIN_DIR" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' not found in PATH. Expected in $BIN_DIR" >&2
  exit 1
fi

# ---------- Threads ----------
if command -v sysctl >/dev/null 2>&1; then
  DEFAULT_THREADS="$(sysctl -n hw.ncpu)"
else
  DEFAULT_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi
WCLI_THREADS="${WCLI_THREADS:-$DEFAULT_THREADS}"

# ---------- Helpers ----------
is_video_file() {
  local name_lc
  name_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name_lc" in
    *.mp4|*.mov|*.m4v|*.mkv|*.webm|*.avi) return 0 ;; *) return 1 ;;
  esac
}

should_skip_file() {
  local base_lc
  base_lc="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base_lc" in
    *_subbed.mp4|*_subbed.mov|*_subbed.m4v|*_subbed.mkv|*_subbed.webm|*_subbed.avi) return 0 ;; *) return 1 ;;
  esac
}

detect_lang_simple() {
  local wav="$1"
  "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -dl -f "$wav" -t "$WCLI_THREADS" 2>&1 \
    | sed -n 's/.*auto-detected language: \([a-z][a-z]\) (p = \([0-9.]*\)).*/\1 \2/p' | tail -n1
}

# ---------- Core per-file processor ----------
process_one() {
  local VIDEO_FILE="$1"

  if [ ! -f "$VIDEO_FILE" ]; then
    echo "Skip (not a regular file): $VIDEO_FILE"
    return 0
  fi
  if should_skip_file "$VIDEO_FILE"; then
    echo "Skip (_subbed file): $(basename "$VIDEO_FILE")"
    return 0
  fi
  if ! is_video_file "$VIDEO_FILE"; then
    echo "Skip (not a recognized video): $(basename "$VIDEO_FILE")"
    return 0
  fi

  local FULLDIR BASENAME STEM OUTPUT_SRT SUBBED_OUTPUT
  FULLDIR="$(cd "$(dirname "$VIDEO_FILE")" && pwd)"
  BASENAME="$(basename "$VIDEO_FILE")"
  STEM="${BASENAME%.*}"

  OUTPUT_SRT="$FULLDIR/$STEM.srt"
  SUBBED_OUTPUT="$FULLDIR/${STEM}_subbed.mp4"

  # Skip if .srt already exists
  if [ -f "$OUTPUT_SRT" ]; then
    echo "Skip (SRT exists): $BASENAME"
    return 0
  fi

  echo "==> Processing: $BASENAME"

  # Temp files (PID-suffixed) + pre-clean
  local TEMP_AUDIO OUT_PREFIX TEMP_SRT
  TEMP_AUDIO="/tmp/${STEM}_$$.wav"
  OUT_PREFIX="/tmp/${STEM}_$$"
  TEMP_SRT="${OUT_PREFIX}.srt"
  rm -f "$TEMP_AUDIO" "$TEMP_SRT"

  # Register temp files globally for quit-safe cleanup
  TMP_FILES+=("$TEMP_AUDIO" "$TEMP_SRT")

  # Function-local cleanup (runs when this function returns)
  trap 'rm -f "$TEMP_AUDIO" "$TEMP_SRT"' RETURN

  # Extract mono 16 kHz PCM
  echo "Extracting audio -> '$TEMP_AUDIO' ..."
  if ! ffmpeg -hide_banner -loglevel error -y -i "$VIDEO_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$TEMP_AUDIO"; then
    echo "Error: ffmpeg failed to extract audio: $BASENAME" >&2
    return 2
  fi

  # Language detect / override
  local DET_LANG="" DET_PROB=""
  if [ -n "$LANG_OVERRIDE" ]; then
    DET_LANG="$LANG_OVERRIDE"
    echo "Forcing language: $DET_LANG"
  else
    echo "Auto-detecting language ..."
    read DET_LANG DET_PROB < <(detect_lang_simple "$TEMP_AUDIO" || true)
    if [ -z "${DET_LANG:-}" ]; then
      echo "Warn: detection inconclusive; defaulting to translate -> English." >&2
      DET_LANG="auto"
    else
      echo "Detected language: $DET_LANG (p=${DET_PROB:-?})"
    fi
  fi

  # Transcribe vs translate
  local status=0
  if [ "$DET_LANG" = "en" ]; then
    echo "Transcribing English -> '$OUTPUT_SRT' ..."
    "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -l en -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
  else
    echo "Translating from '$DET_LANG' -> English -> '$OUTPUT_SRT' ..."
    if [ "$DET_LANG" = "auto" ]; then
      "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -tr -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
    else
      "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -l "$DET_LANG" -tr -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
    fi
  fi
  if [ $status -ne 0 ]; then
    echo "Error: whisper-cli failed for $BASENAME (exit $status)." >&2
    return $status
  fi

  # Move SRT into place
  if [ -f "$TEMP_SRT" ]; then
    mv -f "$TEMP_SRT" "$OUTPUT_SRT"
    echo "SRT created: $OUTPUT_SRT"
  else
    echo "Error: Expected SRT not found at $TEMP_SRT" >&2
    return 3
  fi

  # Embed QuickTime-friendly soft subtitles
  echo "Embedding soft subtitles into '$SUBBED_OUTPUT' ..."
  if ffmpeg -hide_banner -loglevel error \
       -i "$VIDEO_FILE" -i "$OUTPUT_SRT" \
       -c:v copy -c:a copy -c:s mov_text \
       -metadata:s:s:0 language=eng \
       -metadata:s:s:0 title="English" \
       "$SUBBED_OUTPUT"; then
    echo "✅ Subtitled file created: $SUBBED_OUTPUT"
  else
    echo "⚠️ Warning: failed to embed subtitles into video: $BASENAME" >&2
  fi

  return 0
}

# ---------- Batch or single ----------
processed=0; skipped=0; failed=0

if [ -d "$TARGET_PATH" ]; then
  echo "Scanning directory: $TARGET_PATH"
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    if should_skip_file "$f"; then
      echo "Skip (_subbed file): $(basename "$f")"; skipped=$((skipped+1)); continue; fi
    if ! is_video_file "$f"; then continue; fi
    stem="${f%.*}"; srt="${stem}.srt"
    if [ -f "$srt" ]; then
      echo "Skip (SRT exists): $(basename "$f")"; skipped=$((skipped+1)); continue; fi
    if process_one "$f"; then processed=$((processed+1)); else failed=$((failed+1)); fi
  done < <(find "$TARGET_PATH" -type f -print0)
else
  if should_skip_file "$TARGET_PATH"; then
    echo "Skip (_subbed file): $(basename "$TARGET_PATH")"; skipped=$((skipped+1))
  elif ! is_video_file "$TARGET_PATH"; then
    echo "Error: Not a recognized video file: $TARGET_PATH" >&2; exit 1
  else
    stem="${TARGET_PATH%.*}"; srt="${stem}.srt"
    if [ -f "$srt" ]; then
      echo "Skip (SRT exists): $(basename "$TARGET_PATH")"; skipped=$((skipped+1))
    else
      if process_one "$TARGET_PATH"; then processed=$((processed+1)); else failed=$((failed+1)); fi
    fi
  fi
fi

echo
echo "Summary: processed=$processed  skipped=$skipped  failed=$failed"
exit $(( failed > 0 ))
