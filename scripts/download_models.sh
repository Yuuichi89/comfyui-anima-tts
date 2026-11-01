#!/bin/bash
# Laedt fehlende Modelle nach /workspace/models. Vorhandene Dateien werden uebersprungen,
# laeuft also bei jedem Start in Sekunden durch, sobald alles da ist.
set -u

M=/workspace/models
echo "=== Modell-Check $(date '+%F %T')"

# dl <url> <ziel> [bearer-token]
# Ein abgebrochener Download (.part, z. B. nach Pod-Neustart) wird beim naechsten Lauf fortgesetzt.
dl() {
    # Die Zieldatei entsteht erst nach erfolgreichem Download (aus .part), auch leere Dateien zaehlen
    if [ -e "$2" ]; then echo "vorhanden: $2"; return 0; fi
    mkdir -p "$(dirname "$2")"
    if [ -s "$2.part" ]; then
        echo "setze fort: $2 ($(du -h "$2.part" | cut -f1) vorhanden)"
    else
        echo "lade: $2"
    fi
    local auth=() rc attempt
    [ -n "${3:-}" ] && auth=(-H "Authorization: Bearer $3")
    # Abgerissene Verbindungen (z. B. curl 18/56/92 bei grossen HF-Dateien) gleich weiterladen
    for attempt in 1 2 3 4 5; do
        curl -fsSL --retry 3 -C - "${auth[@]}" -o "$2.part" "$1"
        rc=$?
        # 33: Server kann keine Teil-Downloads -> von vorn
        if [ "$rc" = 33 ]; then
            rm -f "$2.part"
            curl -fsSL --retry 3 "${auth[@]}" -o "$2.part" "$1"
            rc=$?
        fi
        [ "$rc" = 0 ] && break
        # 22: HTTP-Fehler (404, 401 ...) - erneut versuchen hilft nicht
        [ "$rc" = 22 ] && break
        [ "$attempt" = 5 ] && break
        echo "Abbruch (curl $rc), Versuch $attempt/5 - setze in 10 s fort: $2"
        sleep 10
    done
    if [ "$rc" = 0 ]; then
        mv "$2.part" "$2"
    else
        echo "FEHLER (curl $rc) beim Download, Teil bleibt fuer den naechsten Versuch: $1"
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

# hf_repo <repo> <zielordner>: alle Dateien eines Hugging-Face-Repos per dl() laden.
# Statt snapshot_download: huggingface_hub >= 1.x setzt abgebrochene Downloads nicht fort und
# laesst bei jedem Abbruch eine neue .incomplete-Datei liegen.
hf_repo() {
    local repo=$1 dir=$2 files f
    # Reste frueherer snapshot_download-Laeufe
    rm -f "$dir"/.cache/huggingface/download/*.incomplete
    files=$(curl -fsSL --retry 3 ${HF_TOKEN:+-H "Authorization: Bearer $HF_TOKEN"} \
        "https://huggingface.co/api/models/$repo/revision/main" \
        | grep -o '"rfilename":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$files" ]; then
        echo "FEHLER: Dateiliste von $repo nicht abrufbar"
        return 1
    fi
    for f in $files; do
        dl "https://huggingface.co/$repo/resolve/main/$f" "$dir/$f" "${HF_TOKEN:-}"
    done
    echo "$repo: $(echo "$files" | wc -l) Dateien in $dir"
}

# MOSS-TTS 8B (16 GB) + Audio-Tokenizer (6.7 GB, braucht jede Sprachausgabe) vorab laden, sonst
# passiert das beim ersten speak. Die uebrigen TTS-Modelle (z. B. SoundEffect v2, 11 GB) laedt
# die Suite bei Bedarf selbst nach models/TTS.
if [ "${DOWNLOAD_MOSS_8B:-1}" = "1" ]; then
    hf_repo OpenMOSS-Team/MOSS-TTS-v1.5 "$M/TTS/moss_tts/MOSS-TTS-v1.5"
    hf_repo OpenMOSS-Team/MOSS-Audio-Tokenizer "$M/TTS/moss_tts/MOSS-Audio-Tokenizer"
fi

echo "=== Modell-Check fertig $(date '+%F %T')"
