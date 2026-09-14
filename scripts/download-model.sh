#!/usr/bin/env bash
# Resume interrupted downloads; publish the model only after checking its size.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
model_file=models/Qwen3.8-27B-UD-Q4_K_M.gguf
model_url=https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_M.gguf
model_size=16464440224
complete() { [[ -f "$1" && "$(stat -c %s "$1")" -eq "$model_size" ]]; }
complete "$model_file" && exit 0

mkdir -p models
# Concurrent launchers must not write to the same partial download.
exec 9>models/.download.lock
flock 9
complete "$model_file" && exit 0
printf 'Downloading Qwen weights (16.5 GB); interrupted downloads resume on the next launch.\n' >&2
if ! complete "$model_file.part"; then
  curl --fail --location --continue-at - --retry 5 --retry-delay 5 \
    --progress-bar --output "$model_file.part" "$model_url"
fi
if ! complete "$model_file.part"; then
  printf 'Model download size mismatch; expected %s bytes. Rerun to resume.\n' "$model_size" >&2
  exit 1
fi
mv "$model_file.part" "$model_file"
