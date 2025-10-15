#!/bin/bash
# 1-Allow-Run.command — Prepare DragTranscribe bundle for first use (quiet & targeted)
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s\n' "$*"; }

qxattr() {
  local p="$1"
  [ -e "$p" ] || return 0
  xattr -dr com.apple.quarantine "$p" 2>/dev/null || true
}

log "🔐 Clearing quarantine attributes…"

# Top-level bundle items
qxattr "$BUNDLE_DIR/"
qxattr "$BUNDLE_DIR/DragTranscribe.app"
qxattr "$BUNDLE_DIR/bin"
qxattr "$BUNDLE_DIR/models"
qxattr "$BUNDLE_DIR/1-Allow-Run.command"
qxattr "$BUNDLE_DIR/2-Download-Model.command"
qxattr "$BUNDLE_DIR/Transcribe.command"

# Bin folder contents (tools, scripts)
if [ -d "$BUNDLE_DIR/bin" ]; then
  find "$BUNDLE_DIR/bin" -type f -exec xattr -dr com.apple.quarantine {} \; 2>/dev/null || true
fi

log "🧰 Setting execute permissions…"

# Top-level commands
for cmd in "$BUNDLE_DIR/1-Allow-Run.command" \
           "$BUNDLE_DIR/2-Download-Model.command" \
           "$BUNDLE_DIR/Transcribe.command"; do
  [ -f "$cmd" ] && chmod +x "$cmd" && log "✅ chmod +x $(basename "$cmd")"
done

# All .sh files in bin/
if [ -d "$BUNDLE_DIR/bin" ]; then
  find "$BUNDLE_DIR/bin" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  [ -f "$BUNDLE_DIR/bin/ffmpeg" ] && chmod +x "$BUNDLE_DIR/bin/ffmpeg" && log "✅ chmod +x bin/ffmpeg"
  [ -f "$BUNDLE_DIR/bin/whisper-cli" ] && chmod +x "$BUNDLE_DIR/bin/whisper-cli" && log "✅ chmod +x bin/whisper-cli"
fi

log "✅ DragTranscribe bundle is now ready to use."

/usr/bin/osascript -e 'display notification "Bundle is ready to use." with title "DragTranscribe Setup"'
/usr/bin/osascript -e 'display dialog "✅ All set! You can now run DragTranscribe.app" buttons {"OK"} with icon note giving up after 10'
