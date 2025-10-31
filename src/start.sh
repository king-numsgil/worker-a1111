#!/usr/bin/env bash
set -euo pipefail

echo "Worker Initiated"

# Where to place the model file for A1111
MODEL_PATH="${MODEL_PATH:-/model.safetensors}"
MODEL_DIR="$(dirname "$MODEL_PATH")"
mkdir -p "$MODEL_DIR"

need_download=false
if [[ ! -f "$MODEL_PATH" ]]; then
  need_download=true
fi

# Build a download URL from env:
# Prefer explicit MODEL_URL; otherwise use CivitAI MODEL_VERSION_ID
DOWNLOAD_URL=""
AUTH_HEADER=()

if [[ -n "${MODEL_URL:-}" ]]; then
  DOWNLOAD_URL="$MODEL_URL"
elif [[ -n "${MODEL_VERSION_ID:-}" ]]; then
  # CivitAI versioned download
  DOWNLOAD_URL="https://civitai.com/api/download/models/${MODEL_VERSION_ID}"
  # Add auth if token provided (recommended)
  if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
    AUTH_HEADER=( -H "Authorization: Bearer ${CIVITAI_TOKEN}" )
  else
    echo "Warning: MODEL_VERSION_ID set but CIVITAI_TOKEN is empty. Public-only downloads may fail."
  fi
fi

if $need_download; then
  if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "Error: No model present at ${MODEL_PATH} and no DOWNLOAD_URL could be derived."
    echo "Set either MODEL_URL or MODEL_VERSION_ID (+ CIVITAI_TOKEN for private models)."
    exit 1
  fi

  echo "Downloading model to ${MODEL_PATH} ..."
  # Try curl first (better errors), then wget as fallback.
  set +e
  curl -fL --retry 5 --retry-delay 2 "${AUTH_HEADER[@]}" \
       "$DOWNLOAD_URL" -o "$MODEL_PATH"
  CURL_RC=$?
  set -e

  if [[ $CURL_RC -ne 0 ]]; then
    echo "curl failed (rc=${CURL_RC}); falling back to wget..."
    wget --quiet --tries=3 --content-disposition \
      ${CIVITAI_TOKEN:+--header="Authorization: Bearer ${CIVITAI_TOKEN}"} \
      "$DOWNLOAD_URL" -O "$MODEL_PATH"
  fi

  # Basic sanity check
  if [[ ! -s "$MODEL_PATH" ]]; then
    echo "Error: model download produced an empty file at ${MODEL_PATH}"
    exit 2
  fi

  echo "Model download complete: $(ls -lh "$MODEL_PATH")"
else
  echo "Model already present at ${MODEL_PATH}; skipping download."
fi

# Optional: verify extension to help A1111 not choke on wrong files
case "$MODEL_PATH" in
  *.safetensors|*.ckpt) : ;;
  *)
    echo "Warning: MODEL_PATH does not end with .safetensors or .ckpt (${MODEL_PATH})"
    ;;
esac

# Start A1111 API (headless)
echo "Starting WebUI API"
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [[ -n "$TCMALLOC" ]]; then
  export LD_PRELOAD="${TCMALLOC}"
fi
export PYTHONUNBUFFERED=true

python /stable-diffusion-webui/webui.py \
  --xformers \
  --no-half-vae \
  --skip-python-version-check \
  --skip-torch-cuda-test \
  --skip-install \
  --ckpt "$MODEL_PATH" \
  --opt-sdp-attention \
  --disable-safe-unpickle \
  --port 3000 \
  --api \
  --nowebui \
  --skip-version-check \
  --no-hashing \
  --no-download-sd-model &

echo "Starting RunPod Handler"
python -u /handler.py
