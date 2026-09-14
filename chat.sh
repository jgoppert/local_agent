#!/usr/bin/env bash
# Run the coding assistant here, with either a local model or an SSH model host.
set -euo pipefail
qwen_dir="$(dirname "$(readlink -f "$0")")"
export PORT="${PORT:-8080}"
host="${QWEN_HOST:-}"
export QWEN_REMOTE_DIR="${QWEN_REMOTE_DIR:-}"
export QWEN_LOCAL_PORT="${QWEN_LOCAL_PORT:-18080}"

# Wrapper options precede OpenCode arguments. Remaining arguments pass through.
while (( $# )); do
  case "$1" in
    --host|--remote-dir|--local-port)
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        printf '%s needs a value.\n' "$1" >&2; exit 2
      fi
      case "$1" in
        --host) host="$2" ;;
        --remote-dir) export QWEN_REMOTE_DIR="$2" ;;
        --local-port) export QWEN_LOCAL_PORT="$2" ;;
      esac
      shift 2
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

for port in "$PORT" "$QWEN_LOCAL_PORT"; do
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    printf 'Invalid port: %s (expected 1-65535).\n' "$port" >&2; exit 2
  fi
done

# Model controls work even when the chat CLI has not been installed.
case "${1:-}" in
  load|start|shutdown|stop|unload)
    if (( $# != 1 )); then
      printf 'Usage: %s %s\n' "$0" "$1" >&2
      exit 2
    fi
    if [[ -n "$host" ]]; then
      exec "$qwen_dir/scripts/remote-chat.sh" "$host" "$@"
    fi
    case "$1" in
      load|start)
        "$qwen_dir/scripts/ensure-model.sh"
        printf 'Qwen is loaded and ready at http://127.0.0.1:%s\n' "$PORT"
        exit 0
        ;;
      *) exec "$qwen_dir/scripts/shutdown.sh" ;;
    esac
    ;;
  --help|-h)
    cat <<HELP
Usage: $0 [--host USER@HOST] [--remote-dir DIR] [--local-port PORT] [OpenCode args]

Chat and tools run in the caller's working directory. --host sends model
requests over SSH to the model host, which is started automatically.
The first local launch installs the runtime and downloads missing weights.

  $0 load                 Load the model without opening chat
  $0 shutdown             Stop the server and release its memory
  $0 --host gpu           Chat here using the model on gpu
  $0 --host gpu load      Load the model on gpu
  $0 --host gpu shutdown  Stop the model on gpu (affects all clients)

Environment defaults:
  QWEN_HOST         Model host; unset means this machine
  QWEN_REMOTE_DIR   Optional checkout override (default: qwen on remote PATH)
  PORT              Model server port (default: 8080)
  QWEN_LOCAL_PORT    Local SSH tunnel port (default: 18080)
  QWEN_CONFIG        Optional absolute TOML override path on this machine
Hardware defaults are in config.toml; config.local.toml overrides them locally.
Put wrapper options before any OpenCode arguments. SSH config aliases work.

HELP
    [[ -x "$qwen_dir/.opencode-runtime/bin/opencode" ]] || exit 0
    ;;
esac

export OPENCODE_CONFIG="$qwen_dir/opencode.json"
export OPENCODE_ENABLE_EXA=1
export OPENCODE_WEBSEARCH_PROVIDER=exa

"$qwen_dir/scripts/ensure-runtime.sh" client

# Help and administrative CLI commands do not need the model loaded.
case "${1:-}" in
  --help|-h|--version|-v|debug|models|session|auth|export|import|completion) ;;
  *)
    if [[ -n "$host" ]]; then
      exec "$qwen_dir/scripts/remote-chat.sh" "$host" "$@"
    fi
    "$qwen_dir/scripts/ensure-model.sh"
    ;;
esac

exec "$qwen_dir/.opencode-runtime/bin/opencode" "$@"
