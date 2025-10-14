#!/bin/bash
# download_model.sh — Download ggml-large-v2.bin model into the bundle's models/ directory
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$BIN_DIR/.." && pwd)"
MODEL_DIR="$BUNDLE_DIR/models"
MODEL_FILE="$MODEL_DIR/ggml-large-v2.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin"

echo "📦 Model directory: $MODEL_DIR"
mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_FILE" ]; then
    echo "✅ Model already exists at: $MODEL_FILE"
    exit 0
fi

echo "🌐 Downloading ggml-large-v2.bin (~2.9 GB) ..."
curl -L -o "$MODEL_FILE" "$MODEL_URL"

echo "✅ Download complete: $MODEL_FILE"
