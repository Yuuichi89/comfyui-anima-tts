# comfyui-anima-tts

Docker-Image fuer RunPod: ComfyUI mit Anima-Bildmodell und TTS-Audio-Suite (MOSS-TTS 8B,
MOSS SoundEffect v2, Qwen3-TTS, Granite ASR). Gedacht fuer die Steuerung per MCP-Server
ueber einen SSH-Tunnel.

Wird bei jedem Push auf `main` per GitHub Actions gebaut: `ghcr.io/yuuichi89/comfyui-anima-tts:latest`

## Inhalt

| | Version |
|---|---|
| Basis | `nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04`, Python 3.12 |
| torch | 2.10.0 (cu128) |
| ComfyUI | v0.42.1 |
| TTS-Audio-Suite | v5.10.4 + `onnxruntime` in der Shared Runtime + MOSS-Patch (`patches/`) |
| transformers | 5.20.1 |
| ComfyUI_essentials | fuer `remove_background` (rembg) |

## RunPod-Template

| Feld | Wert |
|---|---|
| Container Image | `ghcr.io/yuuichi89/comfyui-anima-tts:latest` |
| Container Disk | 20 GB |
| Volume | 80 GB, Mount Path `/workspace` |
| Ports | HTTP `8188`, TCP `22` |
| Env | `PUBLIC_KEY` = SSH-Public-Key, `CIVITAI_TOKEN` = `{{ RUNPOD_SECRET_... }}` |
| optional | `CIVITAI_MODELS` = eigene Civitai-Modellliste (siehe unten) |
| optional | `DOWNLOAD_MOSS_8B=0`, um MOSS 8B (16 GB) nicht vorab zu laden |

`CIVITAI_MODELS`: Leerzeichen-getrennte Eintraege `<ordner unter models>/<dateiname>=<modelVersionId>`,
z. B. `diffusion_models/mein_modell.safetensors=1234567 loras/meine_lora.safetensors=7654321`.
Ohne die Variable gilt die Standardliste in `scripts/download_models.sh`.

Kein Token gehoert ins Image oder in dieses Repo.

## Auf dem Pod

- Modelle, Stimmen (`models/voices`), Ausgaben und Logs liegen unter `/workspace`
- Logs: `/workspace/logs/comfyui.log`, `/workspace/logs/download_models.log`
- ComfyUI neu starten: `/opt/scripts/restart_comfyui.sh`
- Lokal: `REMOTE_PORT=8188 ./tunnel.sh <IP> <PORT>` (aus `comfyui-mcp`)
