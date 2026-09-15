#!/usr/bin/env bash
# Cap GPU power to keep temperatures down during inference. Resets on reboot.
# NVIDIA only. Usage: ./scripts/powercap.sh [watts] (default from config.toml).
set -euo pipefail
repo_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
source "$repo_dir/scripts/read-config.sh"
if [[ "$LOCAL_AGENT_CFG_BACKEND" != cuda ]]; then
  printf 'The power-cap helper applies only to the CUDA/NVIDIA backend.\n' >&2
  exit 1
fi
watts="${1:-$LOCAL_AGENT_CFG_POWER_WATTS}"
if [[ ! "$watts" =~ ^[0-9]+$ ]]; then
  printf 'Power cap must be a nonnegative integer in watts.\n' >&2; exit 2
fi
if [[ "$watts" == 0 ]]; then
  printf 'Power cap disabled; no GPU settings changed.\n'; exit 0
fi
sudo nvidia-smi -pm 1 >/dev/null
sudo nvidia-smi -pl "$watts" >/dev/null
nvidia-smi --query-gpu=name,power.limit,temperature.gpu --format=csv,noheader
