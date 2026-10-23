# comfyui-anima-tts

Docker-Image fuer RunPod: ComfyUI mit Anima-Bildmodell, ACE-Step 1.5 (Musik) und TTS-Audio-Suite
(MOSS-TTS 8B, MOSS SoundEffect v2, Qwen3-TTS, Granite ASR). Gedacht fuer die Steuerung per MCP-Server
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
| ACE-Step 1.5 Turbo | Musik, native ComfyUI-Nodes; Modelle aus `Comfy-Org/ace_step_1.5_ComfyUI_files` |

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
| optional | `DOWNLOAD_ACE_STEP=0`, um ACE-Step (ca. 10 GB) nicht zu laden |

`CIVITAI_MODELS`: Leerzeichen-getrennte Eintraege `<ordner unter models>/<dateiname>=<modelVersionId>`,
z. B. `diffusion_models/mein_modell.safetensors=1234567 loras/meine_lora.safetensors=7654321`.
Ohne die Variable gilt die Standardliste in `scripts/download_models.sh`.

Kein Token gehoert ins Image oder in dieses Repo.

## Auf dem Pod

- Modelle, Stimmen (`models/voices`), Ausgaben und Logs liegen unter `/workspace`
- Logs: `/workspace/logs/comfyui.log`, `/workspace/logs/download_models.log`
- ComfyUI neu starten: `/opt/scripts/restart_comfyui.sh`
- Lokal: `REMOTE_PORT=8188 ./tunnel.sh <IP> <PORT>` (aus `comfyui-mcp`)

## LoRA-Training (Anima 2.9B)

Nicht fest im Image, damit der Start schnell bleibt. Bei Bedarf einmal:

```
/opt/scripts/setup_trainer.sh
```

Richtet kohya sd-scripts (Fork `gazingstars123/sd-scripts`, Branch `anima-2.9b-support`, festgelegter
Commit) in `/workspace/lora/` ein, ~2 Minuten, venv ~1.6 GB. Die venv nutzt torch aus `/opt/venv` mit
(kein zweiter torch-Download), hat aber eigene Pakete wie transformers 4.x. Zweiter Aufruf tut nichts.
Training dann mit `/workspace/lora/venv/bin/accelerate launch ... anima_train_network.py
--network_module=networks.lora_anima --network_train_unet_only ...`. Getestet auf RTX 6000 Ada:
dim 32, AdamW8bit, ~1.2 s/Step bei 1024 px.

## Musik mit ACE-Step 1.5

Workflow wie die ComfyUI-Vorlage `audio_ace_step_1_5_split`: `UNETLoader` (`acestep_v1.5_turbo`) ->
`ModelSamplingAuraFlow` (shift 3), `DualCLIPLoader` (`qwen_0.6b_ace15` + `qwen_1.7b_ace15`, type `ace`),
`TextEncodeAceStepAudio1.5` (tags, lyrics, bpm, keyscale, Dauer), `EmptyAceStep1.5LatentAudio`,
`KSampler` (8 Schritte, cfg 1, euler/simple), `VAEDecodeAudio` mit `ace_1.5_vae`.
Fuer reine Instrumentalmusik `lyrics` = `[Instrumental]`.
