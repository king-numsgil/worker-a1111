# ---------------------------------------------------------------------------- #
#                        Single-stage runtime image                             #
# ---------------------------------------------------------------------------- #
FROM python:3.10.14-slim

ARG A1111_RELEASE=v1.9.3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1 \
    # runtime knobs (override these in RunPod Serverless env vars)
    MODEL_PATH="/model.safetensors" \
    MODEL_VERSION_ID="" \
    MODEL_URL=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Sys deps for A1111 + downloads (wget/curl/CA certs) + tcmalloc
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      fonts-dejavu-core rsync git jq moreutils aria2 wget curl \
      libgoogle-perftools-dev libtcmalloc-minimal4 \
      procps libgl1 libglib2.0-0 ca-certificates && \
    update-ca-certificates && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

# Clone A1111 and prep Python deps
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard ${A1111_RELEASE} && \
    pip install --no-cache-dir xformers && \
    pip install --no-cache-dir -r requirements_versions.txt && \
    # prepare_environment will install torch/torchvision and friends
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

# Your app deps
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# App code
COPY test_input.json .
ADD src .

# Startup script (handles model download at runtime)
RUN chmod +x /start.sh
CMD ["/start.sh"]
