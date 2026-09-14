#!/usr/bin/env bash
# Serve Qwen with hardware/inference settings from config.toml and local overrides.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
source ./scripts/read-config.sh
./scripts/ensure-runtime.sh server
./scripts/download-model.sh
exec ./llama-cpp/bin/llama-server \
  -m models/Qwen3.8-27B-UD-Q4_K_M.gguf \
  -ngl "$QWEN_CFG_GPU_LAYERS" \
  -c "${CTX:-$QWEN_CFG_CONTEXT}" \
  -fa "$QWEN_CFG_FLASH_ATTENTION" -ctk "$QWEN_CFG_CACHE_TYPE" -ctv "$QWEN_CFG_CACHE_TYPE" \
  --reasoning-effort "${REASONING:-$QWEN_CFG_REASONING}" \
  --spec-type "$QWEN_CFG_SPECULATION" --spec-draft-n-max "$QWEN_CFG_DRAFT_TOKENS" \
  -n "$QWEN_CFG_MAX_TOKENS" --parallel "$QWEN_CFG_PARALLEL" --threads "$QWEN_CFG_THREADS" \
  --host 127.0.0.1 --port "${PORT:-8080}" \
  "$@"
