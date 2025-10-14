#!/bin/bash
# Double-clickable helper to run the transcribe.sh script in bin/
set -euo pipefail

# Get the directory where this .command file lives
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BUNDLE_DIR"

# Run transcribe.sh from bin/
if [ -x "$BUNDLE_DIR/bin/transcribe.sh" ]; then
  /bin/bash "$BUNDLE_DIR/bin/transcribe.sh"
else
  echo "Error: $BUNDLE_DIR/bin/transcribe.sh not found or not executable"
  exit 1
fi

# Notify the user when finished
/usr/bin/osascript -e 'display notification "Transcription run finished." with title "Transcribe"'
