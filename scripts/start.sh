#!/bin/bash
# Container-Start: Volume vorbereiten, SSH, Modell-Downloads im Hintergrund, ComfyUI.
set -u

W=/workspace
COMFY=/opt/ComfyUI
mkdir -p "$W/models" "$W/output" "$W/input" "$W/user" "$W/logs" "$W/cache"

# Modelle liegen auf dem Volume: Standard-Unterordner einmalig anlegen, dann verlinken
if [ ! -L "$COMFY/models" ]; then
    cp -rn "$COMFY/models/." "$W/models/" 2>/dev/null
    rm -rf "$COMFY/models"
    ln -s "$W/models" "$COMFY/models"
fi

# SSH: Schluessel aus der RunPod-Variable PUBLIC_KEY
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    grep -qxF "$PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
ssh-keygen -A >/dev/null
mkdir -p /run/sshd
/usr/sbin/sshd

# Fehlende Modelle nachladen; ComfyUI liest die Modellordner bei jeder Anfrage neu ein
/opt/scripts/download_models.sh >> "$W/logs/download_models.log" 2>&1 &

# ComfyUI in einer Schleife: nach Absturz oder `restart_comfyui.sh` startet es neu,
# der Container (und damit SSH) bleibt erreichbar
cd "$COMFY"
while true; do
    echo "=== ComfyUI-Start $(date '+%F %T')" >> "$W/logs/comfyui.log"
    python main.py --listen 0.0.0.0 --port 8188 --disable-cuda-malloc \
        --input-directory "$W/input" --output-directory "$W/output" --user-directory "$W/user" \
        >> "$W/logs/comfyui.log" 2>&1 &
    echo $! > /run/comfyui.pid
    wait $!
    sleep 3
done
