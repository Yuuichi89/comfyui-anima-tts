#!/bin/bash
# Startet ComfyUI neu (die Schleife in start.sh startet es nach dem Beenden wieder).
# SSH-Aufrufe kehren sofort zurueck, weil hier nichts im Hintergrund gestartet wird.
pid=$(cat /run/comfyui.pid 2>/dev/null) || { echo "keine PID-Datei"; exit 1; }
kill "$pid" && echo "ComfyUI (PID $pid) beendet, Neustart folgt"
