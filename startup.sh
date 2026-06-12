#!/bin/bash
set -e

echo "=== Updating ComfyUI ==="
cd /app
if git stash 2>/dev/null && git pull 2>/dev/null; then
    git stash pop 2>/dev/null || true
    echo "ComfyUI updated successfully."
else
    git stash pop 2>/dev/null || true
    echo "WARNING: Could not update ComfyUI (image may have local XPU patches). Continuing with existing version."
fi

echo "=== Installing ComfyUI-Manager ==="
if [ ! -d /app/custom_nodes/ComfyUI-Manager ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git /app/custom_nodes/ComfyUI-Manager
else
    echo "ComfyUI-Manager already present, updating..."
    (cd /app/custom_nodes/ComfyUI-Manager && git pull 2>/dev/null) || true
fi

echo "=== Downloading missing model files ==="

# The mmproj is the vision projector only — it cannot encode text.
# The actual CLIP/text encoder for Qwen Image Edit is the full Qwen2.5-VL-7B LLM.
# CLIPLoaderGGUF with qwen_image type needs the full LLM GGUF in models/clip/.
CLIP_LLM="/app/models/clip/qwen2.5-vl-7b-instruct-q4_k_m.gguf"
if [ ! -f "$CLIP_LLM" ]; then
    echo "Downloading Qwen2.5-VL-7B text model (CLIP/LLM, ~4.5GB)..."
    wget -q --show-progress -O "$CLIP_LLM" \
        "https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf" \
        || echo "WARNING: Could not download LLM GGUF. Place it manually at $CLIP_LLM"
fi

MMPROJ="/app/models/clip/Qwen2.5-VL-7B-Instruct-mmproj-BF16.gguf"
if [ ! -f "$MMPROJ" ]; then
    echo "Downloading Qwen2.5-VL mmproj (vision projector, ~500MB)..."
    # HuggingFace requires auth — set HF_TOKEN env var or pass via docker-compose
    HF_AUTH=""
    if [ -n "$HF_TOKEN" ]; then
        HF_AUTH="--header=Authorization: Bearer $HF_TOKEN"
    fi
    wget -q --show-progress $HF_AUTH -O "$MMPROJ" \
        "https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-mmproj-BF16.gguf" \
        || echo "WARNING: Could not download mmproj (may need HF_TOKEN). Place it manually at $MMPROJ"
fi

echo "=== Installing Python packages ==="
/app/venv/bin/pip install --quiet \
    uv \
    omegaconf \
    diffusers \
    transformers \
    accelerate \
    "gguf>=0.13.0" \
    sentencepiece \
    protobuf

echo "=== Installing custom node requirements ==="
for req in /app/custom_nodes/*/requirements.txt; do
    echo "  -> $req"
    /app/venv/bin/pip install --quiet -r "$req" 2>/dev/null || \
        echo "WARNING: Some requirements from $req could not be installed"
done

echo "=== Starting ComfyUI ==="
cd /app
exec /app/venv/bin/python main.py ${CLI_ARGS}
