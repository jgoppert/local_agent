#!/usr/bin/env bash
# Serve the selected model with hardware/inference settings from TOML.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
source ./scripts/model-options.sh
while (( $# )); do
  case "$1" in
    --model|-m|--model=*|--list-models) local_agent_model_option "$@"; shift "$LOCAL_AGENT_MODEL_SHIFT" ;;
    --) shift; break ;;
    *) break ;;
  esac
done
source ./scripts/read-config.sh
export LOCAL_AGENT_MODEL="$LOCAL_AGENT_CFG_MODEL_ID"
./scripts/ensure-runtime.sh server
./scripts/download-model.sh
exec ./llama-cpp/bin/llama-server \
  -m "$LOCAL_AGENT_CFG_MODEL_FILE" --alias "$LOCAL_AGENT_CFG_MODEL_ID" \
  -ngl "$LOCAL_AGENT_CFG_GPU_LAYERS" \
  -c "$LOCAL_AGENT_CFG_CONTEXT" \
  -fa "$LOCAL_AGENT_CFG_FLASH_ATTENTION" -ctk "$LOCAL_AGENT_CFG_CACHE_TYPE" -ctv "$LOCAL_AGENT_CFG_CACHE_TYPE" \
  --reasoning-effort "$LOCAL_AGENT_CFG_REASONING" \
  --spec-type "$LOCAL_AGENT_CFG_SPECULATION" --spec-draft-n-max "$LOCAL_AGENT_CFG_DRAFT_TOKENS" \
  -n "$LOCAL_AGENT_CFG_MAX_TOKENS" --parallel "$LOCAL_AGENT_CFG_PARALLEL" --threads "$LOCAL_AGENT_CFG_THREADS" \
  --host 127.0.0.1 --port "${PORT:-8080}" \
  "$@"
