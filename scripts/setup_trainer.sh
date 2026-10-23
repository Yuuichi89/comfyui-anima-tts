#!/bin/bash
# Richtet den LoRA-Trainer fuer Anima 2.9B ein (kohya sd-scripts, Fork mit 40-Block-Unterstuetzung).
# Nicht fest im Image, damit der Pod-Start schnell bleibt: bei Bedarf einmal aufrufen (~ein paar Minuten).
# Laeuft er schon, passiert nichts.
#
#   /opt/scripts/setup_trainer.sh
#
# Danach:  cd $TRAINER_DIR/sd-scripts && $TRAINER_DIR/venv/bin/accelerate launch ... anima_train_network.py ...
# Die venv nutzt torch/torchvision aus /opt/venv mit: eine .pth-Datei haengt dessen site-packages
# hinten an (--system-site-packages reicht nicht, das erbt nur das System-Python). Eigene Pakete des
# Trainers (z. B. transformers 4.x) liegen vorn und haben Vorrang vor denen von ComfyUI.
set -euo pipefail

TRAINER_DIR="${TRAINER_DIR:-/workspace/lora}"
SD_SCRIPTS_REPO="${SD_SCRIPTS_REPO:-https://github.com/gazingstars123/sd-scripts}"
# Branch anima-2.9b-support, mit diesem Stand getestet (erkennt 40 Bloecke)
SD_SCRIPTS_REF="${SD_SCRIPTS_REF:-45dddfccb704b6b0591f65d98f0d695c997b3115}"

SRC="$TRAINER_DIR/sd-scripts"
VENV="$TRAINER_DIR/venv"
STAMP="$VENV/.setup-$SD_SCRIPTS_REF"

if [ -f "$STAMP" ]; then
    echo "Trainer schon eingerichtet: $SRC ($SD_SCRIPTS_REF)"
    exit 0
fi

mkdir -p "$TRAINER_DIR"
if [ ! -d "$SRC/.git" ]; then
    git clone -q "$SD_SCRIPTS_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q "$SD_SCRIPTS_REF"

if [ ! -x "$VENV/bin/python" ]; then
    /opt/venv/bin/python -m venv "$VENV"
fi
SITE=$("$VENV/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
/opt/venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])' > "$SITE/opt_venv.pth"

# torch-Versionen aus /opt/venv festhalten, sonst zieht pip ein neueres torch (mehrere GB)
PINS=$(mktemp)
# ohne lokalen Versionsteil (+cu128): den kennt PyPI nicht, die installierte Version erfuellt ihn trotzdem
/opt/venv/bin/pip freeze | grep -E '^(torch|torchvision|torchaudio)==' | sed 's/+.*//' > "$PINS"
"$VENV/bin/pip" install -q --upgrade pip
(cd "$SRC" && "$VENV/bin/pip" install -q -c "$PINS" -r requirements.txt)
rm -f "$PINS"

"$VENV/bin/python" - <<'EOF'
import torch, accelerate, bitsandbytes
print("torch", torch.__version__, "| CUDA", torch.cuda.is_available(), "| accelerate", accelerate.__version__)
EOF
(cd "$SRC" && "$VENV/bin/python" anima_train_network.py --help > /dev/null)

touch "$STAMP"
echo "Trainer bereit: $SRC, venv $VENV"
