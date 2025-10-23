#!/usr/bin/env bash
# transcribe.sh — Batch-or-single transcription with whisper-cli + smart auto/override.
# Uses ONLY ffmpeg (no ffprobe) and samples a mid-video window for language detection.
#
# GUI hints supported:
#   --language <code> | WHISPER_LANG
#   --translate | --auto-translate | WHISPER_TASK in {translate,auto,transcribe} | WHISPER_TRANSLATE=1
#
# Behavior:
#   - Manual en  -> transcribe (EN→EN)
#   - Manual !en -> translate to EN
#   - Auto       -> detect; transcribe if EN, else translate to EN
#
# Bundle expectations:
#   ./bin/ffmpeg, ./bin/whisper-cli, ./models/ggml-large-v2.bin (or ggml-small.en.bin)

set -euo pipefail

# ---------- Cleanup ----------
TMP_FILES=()
cleanup_all() {
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f:-}" && -f "$f" ]] && rm -f "$f" || true
  done
}
trap cleanup_all EXIT INT TERM

# ---------- Paths / Tools ----------
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$BIN_DIR/.." && pwd)"
export PATH="$BIN_DIR:$PATH"
export WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"

: "${MODEL_DIR:="$BUNDLE_DIR/models"}"
if [[ -z "${MODEL_LARGE_V2:-}" ]]; then
  if [[ -f "$MODEL_DIR/ggml-large-v2.bin" ]]; then
    export MODEL_LARGE_V2="$MODEL_DIR/ggml-large-v2.bin"
  elif [[ -f "$MODEL_DIR/ggml-small.en.bin" ]]; then
    export MODEL_LARGE_V2="$MODEL_DIR/ggml-small.en.bin"
  else
    echo "Error: No model found in $MODEL_DIR" >&2
    echo "Expected one of: ggml-large-v2.bin or ggml-small.en.bin" >&2
    exit 1
  fi
fi

# ---------- Threads ----------
if command -v sysctl >/dev/null 2>&1; then
  DEFAULT_THREADS="$(sysctl -n hw.ncpu)"
else
  DEFAULT_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi
WCLI_THREADS="${WCLI_THREADS:-$DEFAULT_THREADS}"

# ---------- Detection window config (override via env) ----------
DETECT_WINDOW_SEC="${DETECT_WINDOW_SEC:-25}"  # length of detection clip
DETECT_FROM="${DETECT_FROM:-mid}"             # 'mid' | 'start' | <seconds>

# ---------- Args ----------
LANG_OVERRIDE=""     # final input-language ('' => auto)
TASK="default"       # default|translate|auto|transcribe

while getopts ":l:" opt; do
  case "$opt" in
    l) LANG_OVERRIDE="$(printf '%s' "$OPTARG" | tr '[:upper:]' '[:lower:]')" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

pending_lang=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --language) shift; pending_lang="${1:-}"; [[ -z "$pending_lang" ]] && { echo "Error: --language requires a value" >&2; exit 1; }
                LANG_OVERRIDE="$(printf '%s' "$pending_lang" | tr '[:upper:]' '[:lower:]')" ;;
    --translate) TASK="translate" ;;
    --auto-translate) TASK="auto" ;;
    -*) : ;;  # ignore unknown flags
    *) if [[ -z "${TARGET_PATH:-}" ]]; then TARGET_PATH="$1"; fi ;;
  esac
  shift || true
done
TARGET_PATH="${TARGET_PATH:-"$BUNDLE_DIR/video"}"

# Env overrides from GUI
if [[ "$TASK" == "default" ]]; then
  case "${WHISPER_TASK:-}" in
    translate) TASK="translate" ;;
    auto)      TASK="auto" ;;
    transcribe) TASK="transcribe" ;;
    *) [[ "${WHISPER_TRANSLATE:-}" == "1" ]] && TASK="translate" ;;
  esac
fi
if [[ -z "$LANG_OVERRIDE" && -n "${WHISPER_LANG:-}" ]]; then
  LANG_OVERRIDE="$(printf '%s' "$WHISPER_LANG" | tr '[:upper:]' '[:lower:]')"
fi

# ---------- Tool sanity ----------
if ! command -v "$WHISPER_BIN" >/dev/null 2>&1; then
  echo "Error: '$WHISPER_BIN' not found in PATH. Expected in $BIN_DIR" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: 'ffmpeg' not found in PATH. Expected in $BIN_DIR" >&2
  exit 1
fi

# ---------- Helpers ----------
is_video_file() {
  local lc; lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in *.mp4|*.mov|*.m4v|*.mkv|*.webm|*.avi) return 0 ;; *) return 1 ;; esac
}

should_skip_file() {
  local base; base="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in *_subbed.mp4|*_subbed.mov|*_subbed.m4v|*_subbed.mkv|*_subbed.webm|*_subbed.avi) return 0 ;; *) return 1 ;; esac
}

# Parse duration (seconds.float) using ONLY ffmpeg output
ffmpeg_duration_sec() {
  # prints seconds as integer (rounded) or empty if not found
  local media="$1"
  local d line
  # ffmpeg prints "Duration: HH:MM:SS.xx"
  line="$(ffmpeg -hide_banner -i "$media" 2>&1 | sed -n 's/.*Duration: \([0-9][0-9]:[0-9][0-9]:[0-9][0-9]\)\.\([0-9][0-9]\).*/\1.\2/p' | head -n1)"
  [[ -z "$line" ]] && return 0
  # Convert HH:MM:SS.xx -> integer seconds
  awk -v ts="$line" 'BEGIN{
    split(ts, a, /[:.]/); # a[1]=HH a[2]=MM a[3]=SS a[4]=centis
    h=a[1]+0; m=a[2]+0; s=a[3]+0; c=a[4]+0;
    tot = h*3600 + m*60 + s + (c/100.0);
    printf "%.0f\n", tot;
  }'
}

detect_lang_on_wav() {
  # Print: "<lang> <prob>"
  local wav="$1"
  "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -dl -f "$wav" -t "$WCLI_THREADS" 2>&1 \
    | sed -n 's/.*auto-detected language: \([a-z][a-z]\) (p = \([0-9.]*\)).*/\1 \2/p' \
    | tail -n1
}

detect_lang_window() {
  # Args: <source wav> <start_seconds> <window_seconds>
  local src_wav="$1"; local start="$2"; local win="$3"
  local out_wav="/tmp/detect_${start}_$$.wav"
  TMP_FILES+=("$out_wav")
  if ! ffmpeg -hide_banner -loglevel error -y \
        -ss "$start" -t "$win" -i "$src_wav" \
        -acodec pcm_s16le -ar 16000 -ac 1 "$out_wav"; then
    return 1
  fi
  detect_lang_on_wav "$out_wav"
}

detect_lang_mid() {
  # Decide a start time via ffmpeg-parsed duration; fallback to start
  local src_wav="$1"
  local dur_int start
  dur_int="$(ffmpeg_duration_sec "$src_wav" || true)"
  if [[ -z "$dur_int" || "$dur_int" -le 0 ]]; then
    # unknown duration — sample from start
    detect_lang_window "$src_wav" 0 "$DETECT_WINDOW_SEC"
    return
  fi

  case "$DETECT_FROM" in
    mid)   start=$(( dur_int/2 - DETECT_WINDOW_SEC/2 )) ;;
    start) start=0 ;;
    *)
      if [[ "$DETECT_FROM" =~ ^[0-9]+$ ]]; then
        start="$DETECT_FROM"
      else
        start=$(( dur_int/2 - DETECT_WINDOW_SEC/2 ))
      fi
      ;;
  esac
  (( start < 0 )) && start=0
  if (( start + DETECT_WINDOW_SEC > dur_int )); then
    start=$(( dur_int > DETECT_WINDOW_SEC ? dur_int - DETECT_WINDOW_SEC : 0 ))
  fi

  detect_lang_window "$src_wav" "$start" "$DETECT_WINDOW_SEC"
}

# ---------- Core per-file ----------
process_one() {
  local VIDEO_FILE="$1"
  if [[ ! -f "$VIDEO_FILE" ]]; then echo "Skip (not a regular file): $VIDEO_FILE"; return 0; fi
  if should_skip_file "$VIDEO_FILE"; then echo "Skip (_subbed file): $(basename "$VIDEO_FILE")"; return 0; fi
  if ! is_video_file "$VIDEO_FILE"; then echo "Skip (not a recognized video): $(basename "$VIDEO_FILE")"; return 0; fi

  local FULLDIR BASENAME STEM OUTPUT_SRT SUBBED_OUTPUT
  FULLDIR="$(cd "$(dirname "$VIDEO_FILE")" && pwd)"
  BASENAME="$(basename "$VIDEO_FILE")"
  STEM="${BASENAME%.*}"
  OUTPUT_SRT="$FULLDIR/$STEM.srt"
  SUBBED_OUTPUT="$FULLDIR/${STEM}_subbed.mp4"

  if [[ -f "$OUTPUT_SRT" ]]; then echo "Skip (SRT exists): $BASENAME"; return 0; fi
  echo "==> Processing: $BASENAME"

  # Extract WAV
  local TEMP_AUDIO OUT_PREFIX TEMP_SRT
  TEMP_AUDIO="/tmp/${STEM}_$$.wav"
  OUT_PREFIX="/tmp/${STEM}_$$"
  TEMP_SRT="${OUT_PREFIX}.srt"
  rm -f "$TEMP_AUDIO" "$TEMP_SRT"
  TMP_FILES+=("$TEMP_AUDIO" "$TEMP_SRT")
  trap 'rm -f "$TEMP_AUDIO" "$TEMP_SRT"' RETURN

  echo "Extracting audio -> '$TEMP_AUDIO' ..."
  if ! ffmpeg -hide_banner -loglevel error -y -i "$VIDEO_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$TEMP_AUDIO"; then
    echo "Error: ffmpeg failed to extract audio: $BASENAME" >&2
    return 2
  fi

  # Determine language/task
  local DET_LANG="" DET_PROB=""
  local EFFECTIVE_TASK="$TASK"

  if [[ -n "$LANG_OVERRIDE" ]]; then
    DET_LANG="$LANG_OVERRIDE"
    echo "Forcing language: $DET_LANG"
    if [[ "$EFFECTIVE_TASK" == "default" ]]; then
      [[ "$DET_LANG" == "en" ]] && EFFECTIVE_TASK="transcribe" || EFFECTIVE_TASK="translate"
    fi
  else
    echo "Auto-detecting language (mid-window ${DETECT_WINDOW_SEC}s) ..."
    read DET_LANG DET_PROB < <(detect_lang_mid "$TEMP_AUDIO" || true)
    if [[ -z "${DET_LANG:-}" ]]; then
      echo "Mid detection inconclusive; retrying from start ..." >&2
      read DET_LANG DET_PROB < <(detect_lang_window "$TEMP_AUDIO" 0 "$DETECT_WINDOW_SEC" || true)
    fi
    if [[ -z "${DET_LANG:-}" ]]; then
      echo "Warn: detection still inconclusive; defaulting to translate -> English." >&2
      DET_LANG="auto"
    else
      echo "Detected language: $DET_LANG (p=${DET_PROB:-?})"
    fi
    if [[ "$EFFECTIVE_TASK" == "default" || "$EFFECTIVE_TASK" == "auto" ]]; then
      [[ "$DET_LANG" == "en" ]] && EFFECTIVE_TASK="transcribe" || EFFECTIVE_TASK="translate"
    fi
  fi

  # Run whisper-cli
  local status=0
  if [[ "$EFFECTIVE_TASK" == "transcribe" ]]; then
    echo "Transcribing English -> '$OUTPUT_SRT' ..."
    "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -l en -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
  else
    # translate to English
    if [[ "$DET_LANG" == "auto" || -z "$DET_LANG" ]]; then
      echo "Translating (auto) -> English -> '$OUTPUT_SRT' ..."
      "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -tr -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
    else
      echo "Translating from '$DET_LANG' -> English -> '$OUTPUT_SRT' ..."
      "$WHISPER_BIN" -m "$MODEL_LARGE_V2" -f "$TEMP_AUDIO" -l "$DET_LANG" -tr -osrt -of "$OUT_PREFIX" -t "$WCLI_THREADS" || status=$?
    fi
  fi

  if [[ $status -ne 0 ]]; then
    echo "Error: whisper-cli failed for $BASENAME (exit $status)." >&2
    return $status
  fi

  # Move SRT into place
  if [[ -f "$TEMP_SRT" ]]; then
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
if [[ -d "$TARGET_PATH" ]]; then
  echo "Scanning directory: $TARGET_PATH"
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    if should_skip_file "$f"; then echo "Skip (_subbed file): $(basename "$f")"; skipped=$((skipped+1)); continue; fi
    if ! is_video_file "$f"; then continue; fi
    stem="${f%.*}"; srt="${stem}.srt"
    if [[ -f "$srt" ]]; then echo "Skip (SRT exists): $(basename "$f")"; skipped=$((skipped+1)); continue; fi
    if process_one "$f"; then processed=$((processed+1)); else failed=$((failed+1)); fi
  done < <(find "$TARGET_PATH" -type f -print0)
else
  if should_skip_file "$TARGET_PATH"; then
    echo "Skip (_subbed file): $(basename "$TARGET_PATH")"; skipped=$((skipped+1))
  elif ! is_video_file "$TARGET_PATH"; then
    echo "Error: Not a recognized video file: $TARGET_PATH" >&2; exit 1
  else
    stem="${TARGET_PATH%.*}"; srt="${stem}.srt"
    if [[ -f "$srt" ]]; then
      echo "Skip (SRT exists): $(basename "$TARGET_PATH")"; skipped=$((skipped+1))
    else
      if process_one "$TARGET_PATH"; then processed=$((processed+1)); else failed=$((failed+1)); fi
    fi
  fi
fi

echo
echo "Summary: processed=$processed  skipped=$skipped  failed=$failed"
exit $(( failed > 0 ))
