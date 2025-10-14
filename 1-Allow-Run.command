#!/bin/bash
# Allow-Run.command — Prepare bundle for first use (quiet & targeted)
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s\n' "$*"; }
qxattr() {
  local p="$1"
  [ -e "$p" ] || return 0
  xattr -dr com.apple.quarantine "$p" 2>/dev/null || true
}

log "🔐 Clearing quarantine on known artifacts…"
qxattr "$BUNDLE_DIR/dist/DragTranscribe.app"
qxattr "/Applications/DragTranscribe.app"
qxattr "$BUNDLE_DIR/bin"
qxattr "$BUNDLE_DIR/models"
qxattr "$BUNDLE_DIR/1-Allow-Run.command"
qxattr "$BUNDLE_DIR/2-Download-Model.command"
qxattr "$BUNDLE_DIR/Transcribe.command"

log "🧰 Making scripts/tools executable…"
for cmd in "$BUNDLE_DIR/2-Download-Model.command" "$BUNDLE_DIR/Transcribe.command"; do
  [ -f "$cmd" ] && chmod +x "$cmd" && log "✅ chmod +x $(basename "$cmd")"
done

find "$BUNDLE_DIR" -type f -name "*.sh" -exec chmod +x {} \;

[ -f "$BUNDLE_DIR/bin/ffmpeg" ] && chmod +x "$BUNDLE_DIR/bin/ffmpeg" && log "✅ chmod +x bin/ffmpeg"
[ -f "$BUNDLE_DIR/bin/whisper-cli" ] && chmod +x "$BUNDLE_DIR/bin/whisper-cli" && log "✅ chmod +x bin/whisper-cli"

log "✅ Bundle is now runnable: $BUNDLE_DIR"
/usr/bin/osascript -e 'display notification "Bundle is ready to use." with title "DragTranscribe Setup"'
/usr/bin/osascript -e 'display dialog "✅ All set! You can now run DragTranscribe." buttons {"OK"} with icon note giving up after 10'
