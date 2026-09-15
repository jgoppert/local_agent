#!/usr/bin/env bash
# One-shot setup with Nix and the drivers for the configured hardware backend:
# builds llama.cpp, downloads the model, prepares OpenCode locally,
# and adds the launcher to the user's Nix profile.
# Pass --client on a box that uses a model host over SSH (no CUDA or weights).
# Safe to rerun; reuse runtimes and weights, and refresh the profile commands.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"

step() { printf '\n==> %s\n' "$*"; }

client_only=false
source ./scripts/model-options.sh
while (( $# )); do
  case "$1" in
    --client) client_only=true; shift ;;
    --model|-m|--model=*|--list-models) local_agent_model_option "$@"; shift "$LOCAL_AGENT_MODEL_SHIFT" ;;
    *) printf 'Usage: %s [--client] [--model NAME] [--list-models]\n' "$0" >&2; exit 2 ;;
  esac
done

if ! "$client_only"; then
  step "llama.cpp for the configured hardware (the first build can take a while)"
  ./scripts/ensure-runtime.sh server

  step "Selected model weights"
  ./scripts/download-model.sh
fi

step "OpenCode runtime (pinned binary)"
./scripts/ensure-runtime.sh client

step "Commands on PATH (user Nix profile)"
./scripts/install-profile.sh

if "$client_only"; then
  printf '\nClient ready. Run local_agent --host USER@MODEL_HOST from your project.\n'
  exit 0
fi

cat <<MSG

Ready. Next:
  local_agent                  start OpenCode on the local model
  ./scripts/powercap.sh         apply the optional configured NVIDIA power cap (sudo)
The model server starts automatically on first use and stays loaded; stop it with:
  local_agent shutdown
To load it without opening chat:
  local_agent load
MSG
