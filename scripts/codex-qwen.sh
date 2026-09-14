#!/usr/bin/env bash
# Launch Codex CLI against the local Qwen model, with its sandbox and approval prompts.
# All Codex flags pass through, e.g.:  codex-qwen -s read-only   |  codex-qwen exec "task"
set -euo pipefail
qwen_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
export PORT="${PORT:-8080}"
if ! command -v codex >/dev/null; then
  printf 'codex is not installed. On NixOS: nix profile add nixpkgs#codex\n' >&2
  exit 1
fi
case "${1:-}" in
  --help|-h|--version|-V|login|logout|debug|completion) ;;
  *) "$qwen_dir/scripts/ensure-model.sh" ;;
esac
exec codex --profile qwen "$@"
