#!/bin/bash
# macOS double-click launcher for downloading the Whisper model
cd "$(dirname "$0")/bin"
./download_model.sh
echo
echo "Press Return to close..."
read -r _
