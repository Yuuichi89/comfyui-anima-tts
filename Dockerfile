# ComfyUI fuer RunPod: Anima-Bilder + TTS-Audio-Suite (MOSS-TTS, Soundeffekte, ASR).
# Code und Python-Umgebung liegen im Image (schneller Start); Modelle, Ausgaben und Stimmen
# auf dem RunPod-Volume /workspace (siehe scripts/start.sh).
FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev build-essential \
        git curl ca-certificates openssh-server \
        ffmpeg libsndfile1 libsamplerate0 libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && python3.12 -m venv /opt/venv \
    && pip install --upgrade pip

# torch 2.10 / cu128: mit TTS-Suite und ComfyUI 0.42 getestet (Treiber >= 570)
ARG TORCH_VERSION=2.10.0
ARG TORCHVISION_VERSION=0.25.0
RUN pip install torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCH_VERSION} \
        --index-url https://download.pytorch.org/whl/cu128

# ComfyUI-Release mit Anima-Unterstuetzung
ARG COMFYUI_REF=v0.42.1
RUN git clone https://github.com/comfyanonymous/ComfyUI /opt/ComfyUI \
    && git -C /opt/ComfyUI checkout -q ${COMFYUI_REF} \
    && pip install -r /opt/ComfyUI/requirements.txt

# ComfyUI_essentials: RemBGSession+/ImageRemoveBackground+ fuer remove_background
ARG ESSENTIALS_REF=9d9f4bedfc9f
RUN git clone https://github.com/cubiq/ComfyUI_essentials /opt/ComfyUI/custom_nodes/ComfyUI_essentials \
    && git -C /opt/ComfyUI/custom_nodes/ComfyUI_essentials checkout -q ${ESSENTIALS_REF} \
    && pip install -r /opt/ComfyUI/custom_nodes/ComfyUI_essentials/requirements.txt onnxruntime-gpu

# TTS-Audio-Suite. install.py laesst ein vorhandenes torch >= 2.6 in Ruhe, solange kein
# nvidia-smi gefunden wird (beim Bauen ohne GPU der Fall).
ARG TTS_SUITE_REF=f7693bc1965a
ENV SUITE=/opt/ComfyUI/custom_nodes/TTS-Audio-Suite
RUN git clone https://github.com/diodiogod/TTS-Audio-Suite ${SUITE} \
    && git -C ${SUITE} checkout -q ${TTS_SUITE_REF} \
    && cd ${SUITE} && python install.py \
    # Qwen3-TTS braucht onnxruntime in der Shared Runtime, install.py installiert es dort nicht
    && ${SUITE}/runtimes/shared_legacy_t4/bin/python -m pip install onnxruntime

# MOSS-TTS 1.7B laeuft sonst nur mit transformers <= 5.2 (siehe patches/)
COPY patches/ /opt/patches/
RUN python /opt/patches/moss_tts_transformers_compat.py \
        ${SUITE}/engines/moss_tts/impl/local_transformer/modeling_moss_tts.py

# Mit diesem Stand getestet (MOSS 8B + gepatchtes 1.7B, Qwen3, ChatterBox, Granite)
ARG TRANSFORMERS_VERSION=5.20.1
RUN pip install transformers==${TRANSFORMERS_VERSION} \
    && python -c "import torch, transformers; print('torch', torch.__version__, '| transformers', transformers.__version__)"

COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

ENV HF_HOME=/workspace/cache/huggingface
EXPOSE 8188 22
CMD ["/opt/scripts/start.sh"]
