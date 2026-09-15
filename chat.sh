#!/usr/bin/env bash
# Run the coding assistant here, with either a local model or an SSH model host.
set -euo pipefail
repo_dir="$(dirname "$(readlink -f "$0")")"
source "$repo_dir/scripts/compat-env.sh"
export PORT="${PORT:-8080}"
host="${LOCAL_AGENT_HOST:-}"
export LOCAL_AGENT_REMOTE_DIR="${LOCAL_AGENT_REMOTE_DIR:-}"
export LOCAL_AGENT_LOCAL_PORT="${LOCAL_AGENT_LOCAL_PORT:-18080}"
source "$repo_dir/scripts/model-options.sh"
list_models=false

# Wrapper options precede client arguments. Remaining arguments pass through.
while (( $# )); do
  case "$1" in
    --model|-m|--model=*) local_agent_model_option "$@"; shift "$LOCAL_AGENT_MODEL_SHIFT" ;;
    --list-models) list_models=true; shift ;;
    --client|--client=*)
      printf 'local_agent runs OpenCode; --client is no longer supported.\n' >&2
      exit 2
      ;;
    --host|--remote-dir|--local-port)
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        printf '%s needs a value.\n' "$1" >&2; exit 2
      fi
      case "$1" in
        --host) host="$2" ;;
        --remote-dir) export LOCAL_AGENT_REMOTE_DIR="$2" ;;
        --local-port) export LOCAL_AGENT_LOCAL_PORT="$2" ;;
      esac
      shift 2
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if "$list_models"; then
  if [[ -n "$host" ]]; then
    exec "$repo_dir/scripts/remote-chat.sh" "$host" --list-models
  fi
  local_agent_model_option --list-models
fi

for port in "$PORT" "$LOCAL_AGENT_LOCAL_PORT"; do
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    printf 'Invalid port: %s (expected 1-65535).\n' "$port" >&2; exit 2
  fi
done

# Model controls work even when the chat CLI has not been installed.
case "${1:-}" in
  --print-client-config)
    # Used by SSH clients to obtain the host's selected model and limits.
    exec nix eval --impure --raw --file "$repo_dir/nix/client-config.nix"
    ;;
  load|start|shutdown|stop|unload)
    if (( $# != 1 )); then
      printf 'Usage: %s %s\n' "$0" "$1" >&2
      exit 2
    fi
    if [[ -n "$host" ]]; then
      exec "$repo_dir/scripts/remote-chat.sh" "$host" "$@"
    fi
    case "$1" in
      load|start)
        "$repo_dir/scripts/ensure-model.sh"
        printf 'Model is loaded and ready at http://127.0.0.1:%s\n' "$PORT"
        exit 0
        ;;
      *) exec "$repo_dir/scripts/shutdown.sh" ;;
    esac
    ;;
  --help|-h)
    cat <<HELP
Usage: $0 [--model NAME] [--host USER@HOST] [--remote-dir DIR] [--local-port PORT] [OpenCode args]

OpenCode and its tools run in the caller's working directory.
--host sends model requests over SSH to the model host.
The first local launch installs the runtime and downloads missing weights.

  $0 load                 Load the model without opening chat
  $0 shutdown             Stop the server and release its memory
  $0 --list-models        List available model names (also works with --host)
  $0 --model NAME         Chat using a model from models.toml
  $0 --model NAME load    Load a selected model without opening chat
  $0 --host gpu           Chat here using the model on gpu
  $0 --host gpu load      Load the model on gpu
  $0 --host gpu shutdown  Stop the model on gpu (affects all clients)

Environment defaults:
  LOCAL_AGENT_MODEL        Model name (default: model.default on the model host)
  LOCAL_AGENT_HOST         Model host; unset means this machine
  LOCAL_AGENT_REMOTE_DIR   Optional checkout override (default: local_agent on remote PATH)
  PORT                     Model server port (default: 8080)
  LOCAL_AGENT_LOCAL_PORT    Local SSH tunnel port (default: 18080)
  LOCAL_AGENT_CONFIG        Optional absolute TOML override path on this machine
The previous QWEN_* environment names are also accepted.
Models are in models.toml; hardware defaults are in config.toml.
config.local.toml can override settings and add models under [models.NAME].
Put wrapper options before any client arguments. SSH config aliases work.

HELP
    [[ -x "$repo_dir/.opencode-runtime/bin/opencode" ]] || exit 0
    ;;
esac

export OPENCODE_CONFIG="$repo_dir/opencode.json"
export OPENCODE_ENABLE_EXA=1
export OPENCODE_WEBSEARCH_PROVIDER=exa

"$repo_dir/scripts/ensure-runtime.sh" client

# Help and administrative CLI commands do not need the model loaded.
case "${1:-}" in
  --help|-h|--version|-v|debug|models|session|auth|export|import|completion) ;;
  *)
    if [[ -n "$host" ]]; then
      exec "$repo_dir/scripts/remote-chat.sh" "$host" "$@"
    fi
    "$repo_dir/scripts/ensure-model.sh"
    ;;
esac

OPENCODE_CONFIG_CONTENT=$(nix eval --impure --raw --file "$repo_dir/nix/client-config.nix")
export OPENCODE_CONFIG_CONTENT
exec "$repo_dir/.opencode-runtime/bin/opencode" "$@"
