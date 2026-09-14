#!/usr/bin/env bash
# Build only the runtime needed on this machine; clients do not need CUDA.
set -euo pipefail
cd "$(dirname "$(dirname "$(readlink -f "$0")")")"
case "${1:-}" in
  client) binary=.opencode-runtime/bin/opencode; expression=opencode; link=.opencode-runtime ;;
  server) binary=llama-cpp/bin/llama-server; expression=llama-cpp; link=llama-cpp ;;
  *) printf 'Usage: %s client|server\n' "$0" >&2; exit 2 ;;
esac
[[ "$1" == client && -x "$binary" ]] && exit 0
if ! command -v nix >/dev/null; then
  printf 'Nix is required to install the %s runtime. See README.md for prerequisites.\n' "$1" >&2
  exit 1
fi
# Re-evaluate the server derivation so backend/architecture changes replace an
# existing runtime. Nix reuses the build when its inputs have not changed.
if [[ "$1" == server && -x "$binary" ]]; then
  desired=$(nix eval --impure --raw --file ./nix/llama-cpp.nix --apply 'drv: drv.outPath')
  [[ "$(readlink -f "$link")" == "$desired" ]] && exit 0
fi
printf 'Preparing %s runtime with Nix...\n' "$1" >&2
nix build --impure --file "./nix/$expression.nix" --out-link "$link"
