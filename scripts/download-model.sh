#!/usr/bin/env bash
# Resume interrupted downloads; publish the model only after checking its size.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
source ./scripts/model-options.sh
while (( $# )); do
  case "$1" in
    --model|-m|--model=*|--list-models) local_agent_model_option "$@"; shift "$LOCAL_AGENT_MODEL_SHIFT" ;;
    *) printf 'Usage: %s [--model NAME] [--list-models]\n' "$0" >&2; exit 2 ;;
  esac
done
source ./scripts/read-config.sh
model_file="$LOCAL_AGENT_CFG_MODEL_FILE"
model_url="$LOCAL_AGENT_CFG_MODEL_URL"
model_size="$LOCAL_AGENT_CFG_MODEL_SIZE"
complete() { [[ -f "$1" && "$(stat -c %s "$1")" -eq "$model_size" ]]; }
complete "$model_file" && exit 0

mkdir -p models
# Concurrent launchers must not write to the same partial download.
exec 9>"$model_file.lock"
flock 9
complete "$model_file" && exit 0
printf 'Downloading %s (%s bytes); interrupted downloads resume on the next launch.\n' "$LOCAL_AGENT_CFG_MODEL_NAME" "$model_size" >&2
if ! complete "$model_file.part"; then
  curl --fail --location --continue-at - --retry 5 --retry-delay 5 \
    --progress-bar --output "$model_file.part" "$model_url"
fi
if ! complete "$model_file.part"; then
  printf 'Model download size mismatch; expected %s bytes. Rerun to resume.\n' "$model_size" >&2
  exit 1
fi
mv "$model_file.part" "$model_file"
