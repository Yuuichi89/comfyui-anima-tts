#!/bin/bash
# Laedt fehlende Modelle nach /workspace/models. Vorhandene Dateien werden uebersprungen,
# laeuft also bei jedem Start in Sekunden durch, sobald alles da ist.
set -u

M=/workspace/models
echo "=== Modell-Check $(date '+%F %T')"

# dl <url> <ziel> [bearer-token]
dl() {
    if [ -s "$2" ]; then echo "vorhanden: $2"; return 0; fi
    mkdir -p "$(dirname "$2")"
    echo "lade: $2"
    local auth=()
    [ -n "${3:-}" ] && auth=(-H "Authorization: Bearer $3")
    if curl -fsSL --retry 3 "${auth[@]}" -o "$2.part" "$1"; then
        mv "$2.part" "$2"
    else
        rm -f "$2.part"
        echo "FEHLER beim Download: $1"
    fi
}

# Anima: Text-Encoder + VAE (Hugging Face, ohne Token)
ANIMA=https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files
dl "$ANIMA/text_encoders/qwen_3_06b_base.safetensors" "$M/text_encoders/qwen_3_06b_base.safetensors"
dl "$ANIMA/vae/qwen_image_vae.safetensors" "$M/vae/qwen_image_vae.safetensors"

# Civitai: "<ordner>/<dateiname>=<modelVersionId>", Leerzeichen-getrennt; per RunPod-Env
# CIVITAI_MODELS ueberschreibbar. Token als RunPod-Secret CIVITAI_TOKEN.
DEFAULT_CIVITAI_MODELS="diffusion_models/miaomiaoHarem_29BBETA11_fp16.safetensors=3360028 loras/Turbo-ANIMA-v4-29B.safetensors=3410939"
if [ -n "${CIVITAI_TOKEN:-}" ]; then
    for entry in ${CIVITAI_MODELS:-$DEFAULT_CIVITAI_MODELS}; do
        dl "https://civitai.com/api/download/models/${entry##*=}" "$M/${entry%=*}" "$CIVITAI_TOKEN"
    done
else
    echo "CIVITAI_TOKEN fehlt - Civitai-Modelle uebersprungen"
fi

# ACE-Step 1.5 Turbo fuer Musik (ca. 10 GB; native ComfyUI-Nodes, Workflow siehe README).
if [ "${DOWNLOAD_ACE_STEP:-1}" = "1" ]; then
    ACE=https://huggingface.co/Comfy-Org/ace_step_1.5_ComfyUI_files/resolve/main/split_files
    dl "$ACE/diffusion_models/acestep_v1.5_turbo.safetensors" "$M/diffusion_models/acestep_v1.5_turbo.safetensors"
    dl "$ACE/text_encoders/qwen_0.6b_ace15.safetensors" "$M/text_encoders/qwen_0.6b_ace15.safetensors"
    dl "$ACE/text_encoders/qwen_1.7b_ace15.safetensors" "$M/text_encoders/qwen_1.7b_ace15.safetensors"
    dl "$ACE/vae/ace_1.5_vae.safetensors" "$M/vae/ace_1.5_vae.safetensors"
fi

# MOSS-TTS 8B (16 GB) vorab laden, sonst passiert das beim ersten speak.
# Die uebrigen TTS-Modelle laedt die Suite bei Bedarf selbst nach models/TTS.
if [ "${DOWNLOAD_MOSS_8B:-1}" = "1" ]; then
    python - <<'EOF'
from huggingface_hub import snapshot_download
path = snapshot_download("OpenMOSS-Team/MOSS-TTS-v1.5", local_dir="/workspace/models/TTS/moss_tts/MOSS-TTS-v1.5")
print("MOSS 8B bereit:", path)
EOF
fi

echo "=== Modell-Check fertig $(date '+%F %T')"
