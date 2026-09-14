#!/usr/bin/env bash
# One-shot setup with Nix and the drivers for the configured hardware backend:
# builds llama.cpp, downloads the model, prepares OpenCode locally,
# installs the Codex configuration, and adds commands to the user's Nix profile.
# Pass --client on a box that uses a model host over SSH (no CUDA or weights).
# Safe to rerun; reuse runtimes and weights, and refresh the profile commands.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"

step() { printf '\n==> %s\n' "$*"; }

client_only=false
case "${1:-}" in
  '') ;;
  --client)
    [[ $# == 1 ]] || { printf 'Usage: %s [--client]\n' "$0" >&2; exit 2; }
    client_only=true
    ;;
  *) printf 'Usage: %s [--client]\n' "$0" >&2; exit 2 ;;
esac

if ! "$client_only"; then
  step "llama.cpp for the configured hardware (the first build can take a while)"
  ./scripts/ensure-runtime.sh server

  step "Model weights (16.5 GB)"
  ./scripts/download-model.sh
fi

step "OpenCode runtime (pinned binary)"
./scripts/ensure-runtime.sh client

if ! "$client_only"; then
  step "Codex profile (~/.codex/qwen.config.toml)"
  mkdir -p ~/.codex
  touch ~/.codex/config.toml
  if ! grep -q '^\[model_providers\.llamacpp\]' ~/.codex/config.toml; then
    cat codex/provider.toml >> ~/.codex/config.toml
    echo "added llamacpp provider to ~/.codex/config.toml"
  fi
  cp codex/qwen.config.toml ~/.codex/qwen.config.toml
  command -v codex >/dev/null || echo "note: codex is not installed; install it with: nix profile add nixpkgs#codex"
fi

step "Commands on PATH (user Nix profile)"
./scripts/install-profile.sh

if "$client_only"; then
  printf '\nClient ready. Run qwen --host USER@MODEL_HOST from your project.\n'
  exit 0
fi

cat <<MSG

Ready. Next:
  qwen                   start OpenCode on the local model
  codex-qwen             start Codex on the local model
  ./scripts/powercap.sh   apply the optional configured NVIDIA power cap (sudo)
The model server starts automatically on first use and stays loaded; stop it with:
  qwen shutdown
To load it without opening chat:
  qwen load
MSG
