#!/bin/bash
# gpuhub-Start, per /etc/autodl.sh bei jedem Instanz-Start: Datenplatte vorbereiten, fehlende Modelle
# im Hintergrund laden, ComfyUI in einer Schleife. Gegenstueck zu scripts/start.sh (RunPod);
# SSH stellt gpuhub selbst bereit.
#
# Einstellungen (CIVITAI_TOKEN, CIVITAI_MODELS, DOWNLOAD_MOSS_8B, DOWNLOAD_ACE_STEP, COMFYUI_PORT ...)
# kommen aus comfyui.env, siehe comfyui.env.example. Gelesen werden nacheinander
#   /root/autodl-fs/comfyui.env   Dateispeicher, gilt fuer alle Instanzen der Region
#   /workspace/comfyui.env        Datenplatte dieser Instanz, ueberschreibt
# Beide liegen nicht im gespeicherten Image.
set -u

W=/workspace            # Symlink auf die Datenplatte /root/autodl-tmp
COMFY=/opt/ComfyUI
export VIRTUAL_ENV=/opt/venv PATH=/opt/venv/bin:$PATH HF_HOME=$W/cache/huggingface PYTHONUNBUFFERED=1

# Nur eine Instanz dieses Skripts (Autostart + manueller Aufruf)
exec 9> /run/comfyui-start.lock
flock -n 9 || { echo "start.sh laeuft schon"; exit 0; }

# Die Datenplatte wird beim Boot eingehaengt; zur Sicherheit kurz darauf warten
for _ in $(seq 1 30); do
    mountpoint -q /root/autodl-tmp && break
    sleep 2
done

for f in /root/autodl-fs/comfyui.env "$W/comfyui.env"; do
    if [ -f "$f" ]; then
        set -a; . "$f"; set +a
        echo "Einstellungen gelesen: $f"
    fi
done

mkdir -p "$W/models" "$W/output" "$W/input" "$W/user" "$W/logs" "$W/cache"
# Standard-Unterordner (checkpoints, loras, ...) auf einer neuen Datenplatte anlegen
cp -rn /opt/ComfyUI-models-default/. "$W/models/" 2>/dev/null

# Fehlende Modelle nachladen; ComfyUI liest die Modellordner bei jeder Anfrage neu ein
/opt/scripts/download_models.sh >> "$W/logs/download_models.log" 2>&1 9>&- &

# Port 6006 ist bei gpuhub der "Custom Service"-Port; per SSH-Tunnel geht jeder Port
PORT="${COMFYUI_PORT:-6006}"
LISTEN="${COMFYUI_LISTEN:-0.0.0.0}"

# ComfyUI in einer Schleife: nach Absturz oder `restart_comfyui.sh` startet es neu
cd "$COMFY"
while true; do
    echo "=== ComfyUI-Start $(date '+%F %T') auf $LISTEN:$PORT" >> "$W/logs/comfyui.log"
    python main.py --listen "$LISTEN" --port "$PORT" --disable-cuda-malloc \
        --input-directory "$W/input" --output-directory "$W/output" --user-directory "$W/user" \
        >> "$W/logs/comfyui.log" 2>&1 9>&- &
    echo $! > /run/comfyui.pid
    wait $!
    sleep 3
done
