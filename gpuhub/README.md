# gpuhub.com

gpuhub kann keine Images aus fremden Registries (ghcr, Docker Hub) laden und hat kein Docker in der
Instanz. Stattdessen richtet `install.sh` eine Instanz so ein wie das Dockerfile; die fertige
Instanz wird in der Konsole als eigenes Image gespeichert. Versionen kommen aus den `ARG`-Zeilen des
Dockerfiles, Modell-Downloads, Neustart und LoRA-Trainer aus `scripts/` sind dieselben wie bei RunPod.

## Unterschiede zu RunPod

| | RunPod | gpuhub |
|---|---|---|
| Image | ghcr, per GitHub Actions | "Save Image" einer eingerichteten Instanz (nur Systemplatte, 30 GB) |
| Modelle, Ausgaben, Logs | Volume `/workspace` | Datenplatte `/root/autodl-tmp`, `/workspace` ist ein Symlink darauf |
| Start | `CMD /opt/scripts/start.sh` | `/etc/autodl.sh` (ruft gpuhub bei jedem Start auf) -> `/opt/scripts/gpuhub/start.sh` |
| Port | 8188 | 6006 (gpuhub "Custom Service"), per SSH-Tunnel |
| Einstellungen | RunPod-Env / Secrets | `comfyui.env` auf Dateispeicher oder Datenplatte (siehe `comfyui.env.example`) |
| SSH | `PUBLIC_KEY` | macht gpuhub selbst (Passwort oder Key in `/root/.ssh/authorized_keys`) |

Die Datenplatte und `/root/autodl-fs` landen nicht im Image. Ein Token gehoert deshalb in
`comfyui.env`, nie auf die Systemplatte.

## Image bauen (einmal bzw. pro Update)

1. Instanz mit einem PyTorch-Image (Python 3.12, Ubuntu 22.04) mieten. Eine GPU ist fuer die
   Einrichtung nicht noetig, schadet aber nicht (der Test am Ende nutzt sie).
2. Auf der Instanz:
   ```
   git clone https://github.com/Yuuichi89/comfyui-anima-tts /opt/comfyui-anima-tts
   bash /opt/comfyui-anima-tts/gpuhub/install.sh 2>&1 | tee /root/install.log
   ```
   Dauert ca. 15-20 Minuten, belegt ca. 15 GB der 30-GB-Systemplatte.
3. Testen: `setsid /opt/scripts/gpuhub/start.sh > /tmp/comfyui-start.log 2>&1 < /dev/null &`,
   dann `tail -f /root/autodl-tmp/logs/comfyui.log`.
4. Instanz herunterfahren -> More -> **Save Image**. Neue Instanzen: beim Erstellen unter
   "My Images" waehlen.

Update: Instanz aus dem gespeicherten Image starten, `git -C /opt/comfyui-anima-tts pull`,
`install.sh` erneut (fertige Schritte mit gleicher Version werden uebersprungen), neu speichern.

Vor dem Teilen des Images (Share) `/root/.ssh/authorized_keys` und `/root/.bash_history` leeren.

## Einstellungen

`comfyui.env.example` nach `/root/autodl-fs/comfyui.env` (gilt fuer alle Instanzen der Region, wenn
der Dateispeicher initialisiert ist) oder `/root/autodl-tmp/comfyui.env` kopieren, `chmod 600`,
`CIVITAI_TOKEN` eintragen. Gleiche Variablen wie bei RunPod (`CIVITAI_MODELS`, `DOWNLOAD_MOSS_8B`,
`DOWNLOAD_ACE_STEP`), dazu `COMFYUI_PORT` und `COMFYUI_LISTEN`.

Platz (gemessen): vorab geladen werden ca. 40 GB (Anima + Civitai 7, ACE-Step 9,5,
MOSS 8B + Audio-Tokenizer 23). Beim ersten Aufruf laedt die TTS-Suite selbst nach:
SoundEffect v2 11 GB, Granite-ASR 4,5 GB. Mit allem ca. 55 GB -> Datenplatte 80 GB waehlen oder
`DOWNLOAD_*=0` setzen. Erste Aufrufe auf neuer Datenplatte: `sound_effect` ca. 13 min,
`transcribe` ca. 4 min (Download); danach Sekunden.

## Auf der Instanz

- Logs: `/root/autodl-tmp/logs/comfyui.log`, `download_models.log`; Autostart: `/tmp/autodl.sh.log`,
  `/tmp/comfyui-start.log`
- ComfyUI neu starten: `/opt/scripts/restart_comfyui.sh`
- LoRA-Trainer: `/opt/scripts/setup_trainer.sh` (wie bei RunPod, landet in `/root/autodl-tmp/lora`)
- Lokal (aus `comfyui-mcp`): `REMOTE_PORT=6006 ./tunnel.sh connect.<region>.gpuhub.com <SSH-Port>`
- Grosse Downloads ohne GPU-Kosten: Instanz im "Non-GPU Mode" starten, Modelle laden lassen,
  danach mit GPU neu starten.
