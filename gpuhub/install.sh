#!/bin/bash
# Richtet ComfyUI (Anima + TTS-Audio-Suite + ACE-Step) auf einer gpuhub-Instanz ein - das
# Gegenstueck zum Dockerfile, weil gpuhub keine Images aus fremden Registries (ghcr) laden kann.
# Danach Instanz herunterfahren und in der Konsole "Save Image" -> neue Instanzen aus "My Images".
#
#   git clone https://github.com/Yuuichi89/comfyui-anima-tts /opt/comfyui-anima-tts
#   bash /opt/comfyui-anima-tts/gpuhub/install.sh
#
# Basis: ein gpuhub-PyTorch-Image mit Miniconda-Python 3.12 (Ubuntu 22.04). Dessen torch wird nicht
# angefasst; ComfyUI bekommt wie im Docker-Image eine eigene venv unter /opt/venv.
# Versionen kommen aus den ARG-Zeilen des Dockerfiles, damit RunPod und gpuhub gleich bleiben.
# Mehrfach ausfuehrbar: fertige Schritte (je Version) werden uebersprungen. Fuer ein Update
# erst `git -C /opt/comfyui-anima-tts pull`, dann dieses Skript erneut.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
COMFY=/opt/ComfyUI
SUITE=$COMFY/custom_nodes/TTS-Audio-Suite
ESSENTIALS=$COMFY/custom_nodes/ComfyUI_essentials
MODELS_DEFAULT=/opt/ComfyUI-models-default
STAMPS=/opt/.gpuhub-install
DATA_DISK=/root/autodl-tmp
BASE_PY="${BASE_PY:-/root/miniconda3/bin/python3.12}"

# Versionen aus dem Dockerfile (ARG NAME=wert)
while IFS='=' read -r name value; do
    declare "$name=$value"
done < <(sed -n 's/^ARG \([A-Z_]*\)=\([^ ]*\)$/\1=\2/p' "$REPO_DIR/Dockerfile")
for v in TORCH_VERSION TORCHVISION_VERSION COMFYUI_REF ESSENTIALS_REF TTS_SUITE_REF TRANSFORMERS_VERSION; do
    [ -n "${!v:-}" ] || { echo "ARG $v fehlt im Dockerfile"; exit 1; }
done

export DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1
export VIRTUAL_ENV=/opt/venv PATH=/opt/venv/bin:$PATH
export HF_HOME=/workspace/cache/huggingface

log() { echo; echo "=== $* ($(date '+%T'))"; }
# Schritt-Stempel: <name> <version>; laeuft der Schritt mit derselben Version schon, ueberspringen
done_step() { [ -f "$STAMPS/$1" ] && [ "$(cat "$STAMPS/$1")" = "$2" ]; }
mark_step() { mkdir -p "$STAMPS"; echo "$2" > "$STAMPS/$1"; }

# git-Checkout auf festen Stand; lokale Aenderungen an getrackten Dateien (Patches) werden verworfen
checkout() {
    local url=$1 dir=$2 ref=$3
    [ -d "$dir/.git" ] || git clone -q "$url" "$dir"
    git -C "$dir" checkout -q -- .
    git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null || git -C "$dir" fetch -q --tags origin
    git -C "$dir" checkout -q "$ref"
}

[ -x "$BASE_PY" ] || BASE_PY=$(command -v python3.12) || { echo "kein Python 3.12 gefunden (BASE_PY setzen)"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "bitte als root ausfuehren"; exit 1; }

log "Systempakete"
if ! done_step apt 1; then
    apt-get update -q
    apt-get install -y -q --no-install-recommends \
        git curl ca-certificates rsync build-essential \
        ffmpeg libsndfile1 libsamplerate0 libgl1 libglib2.0-0
    apt-get clean && rm -rf /var/lib/apt/lists/*
    mark_step apt 1
fi

# /workspace zeigt auf die Datenplatte: so laufen die Skripte aus scripts/ unveraendert
log "/workspace -> $DATA_DISK"
if [ -L /workspace ]; then
    :
elif [ -e /workspace ]; then
    echo "/workspace existiert und ist kein Symlink - bitte pruefen"; exit 1
else
    ln -s "$DATA_DISK" /workspace
fi

log "venv /opt/venv ($("$BASE_PY" -V))"
if [ ! -x /opt/venv/bin/python ]; then
    "$BASE_PY" -m venv /opt/venv
    pip install -q --upgrade pip
fi

log "torch $TORCH_VERSION (cu128)"
if ! done_step torch "$TORCH_VERSION/$TORCHVISION_VERSION"; then
    pip install torch=="$TORCH_VERSION" torchvision=="$TORCHVISION_VERSION" torchaudio=="$TORCH_VERSION" \
        --index-url https://download.pytorch.org/whl/cu128
    mark_step torch "$TORCH_VERSION/$TORCHVISION_VERSION"
fi

log "ComfyUI $COMFYUI_REF"
if ! done_step comfyui "$COMFYUI_REF"; then
    # models ist im Betrieb ein Symlink auf die Datenplatte; fuer den Checkout kurz zurueck
    if [ -L "$COMFY/models" ]; then
        rm "$COMFY/models"
    fi
    checkout https://github.com/comfyanonymous/ComfyUI "$COMFY" "$COMFYUI_REF"
    pip install -r "$COMFY/requirements.txt"
    mark_step comfyui "$COMFYUI_REF"
fi
# Standard-Unterordner von models/ merken (start.sh legt sie auf der Datenplatte an), dann verlinken
if [ ! -L "$COMFY/models" ]; then
    rm -rf "$MODELS_DEFAULT"
    mv "$COMFY/models" "$MODELS_DEFAULT"
    ln -s /workspace/models "$COMFY/models"
fi

log "ComfyUI_essentials $ESSENTIALS_REF"
if ! done_step essentials "$ESSENTIALS_REF"; then
    checkout https://github.com/cubiq/ComfyUI_essentials "$ESSENTIALS" "$ESSENTIALS_REF"
    pip install -r "$ESSENTIALS/requirements.txt" onnxruntime-gpu
    mark_step essentials "$ESSENTIALS_REF"
fi

# install.py behaelt das vorhandene torch >= 2.6 (mit GPU: torch.cuda verfuegbar -> keine Neuinstallation)
log "TTS-Audio-Suite $TTS_SUITE_REF"
if ! done_step tts_suite "$TTS_SUITE_REF"; then
    checkout https://github.com/diodiogod/TTS-Audio-Suite "$SUITE" "$TTS_SUITE_REF"
    (cd "$SUITE" && python install.py)
    # Qwen3-TTS braucht onnxruntime in der Shared Runtime, install.py installiert es dort nicht
    "$SUITE/runtimes/shared_legacy_t4/bin/python" -m pip install onnxruntime
    # MOSS-TTS 1.7B laeuft sonst nur mit transformers <= 5.2
    python "$REPO_DIR/patches/moss_tts_transformers_compat.py" \
        "$SUITE/engines/moss_tts/impl/local_transformer/modeling_moss_tts.py"
    mark_step tts_suite "$TTS_SUITE_REF"
fi

log "transformers $TRANSFORMERS_VERSION"
if ! done_step transformers "$TRANSFORMERS_VERSION/$TTS_SUITE_REF"; then
    pip install transformers=="$TRANSFORMERS_VERSION"
    mark_step transformers "$TRANSFORMERS_VERSION/$TTS_SUITE_REF"
fi

log "Skripte nach /opt/scripts, Autostart /etc/autodl.sh"
mkdir -p /opt/scripts/gpuhub
rsync -a "$REPO_DIR/scripts/" /opt/scripts/
rsync -a "$REPO_DIR/gpuhub/start.sh" "$REPO_DIR/gpuhub/comfyui.env.example" /opt/scripts/gpuhub/
chmod +x /opt/scripts/*.sh /opt/scripts/gpuhub/*.sh

# gpuhub fuehrt /etc/autodl.sh bei jedem Instanz-Start aus (Log: /tmp/autodl.sh.log).
# Eigene Zeilen dort bleiben erhalten, unsere wird nur einmal ergaenzt.
AUTOSTART='setsid /opt/scripts/gpuhub/start.sh > /tmp/comfyui-start.log 2>&1 < /dev/null &  # comfyui-anima-tts'
if [ ! -f /etc/autodl.sh ]; then
    printf '#!/bin/bash\n# Autostart, wird von gpuhub bei jedem Instanz-Start ausgefuehrt\n' > /etc/autodl.sh
fi
grep -qF '# comfyui-anima-tts' /etc/autodl.sh || echo "$AUTOSTART" >> /etc/autodl.sh
chmod +x /etc/autodl.sh

log "Pruefung"
python - <<'EOF'
import torch, torchaudio, transformers
print("torch", torch.__version__, "| CUDA", torch.version.cuda, "| GPU", torch.cuda.is_available(),
      "| torchaudio", torchaudio.__version__, "| transformers", transformers.__version__)
EOF
rm -rf /root/.cache/pip
du -sh /opt/venv "$COMFY" 2>/dev/null
df -h / | tail -1

echo
echo "Fertig. ComfyUI starten:  setsid /opt/scripts/gpuhub/start.sh > /tmp/comfyui-start.log 2>&1 < /dev/null &"
echo "Danach testen, Instanz herunterfahren und in der Konsole 'Save Image' waehlen."
