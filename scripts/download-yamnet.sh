#!/bin/bash
# Download YAMNet Core ML model from Hugging Face
set -euo pipefail

MODEL_DIR="$HOME/.yt-subtitles/models"
MODEL_PKG="$MODEL_DIR/yamnet.mlpackage"
BASE_URL="https://huggingface.co/Yehor/YAMNet-CoreML/resolve/main"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_PKG/Manifest.json" ]; then
    echo "YAMNet model already exists at $MODEL_PKG"
    exit 0
fi

echo "Downloading YAMNet Core ML model..."
mkdir -p "$MODEL_PKG/Data/com.apple.CoreML"
mkdir -p "$MODEL_PKG/Data/com.apple.CoreML/weights"

curl -L -o "$MODEL_PKG/Manifest.json" "$BASE_URL/YAMNet.mlpackage/Manifest.json"
curl -L -o "$MODEL_PKG/Data/com.apple.CoreML/model.mlmodel" "$BASE_URL/YAMNet.mlpackage/Data/com.apple.CoreML/model.mlmodel"
curl -L -o "$MODEL_PKG/Data/com.apple.CoreML/weights/weight.bin" "$BASE_URL/YAMNet.mlpackage/Data/com.apple.CoreML/weights/weight.bin"

echo "Downloaded YAMNet model to $MODEL_PKG"
