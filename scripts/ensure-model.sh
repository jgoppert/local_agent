#!/usr/bin/env bash
# Make sure llama-server is up on $PORT, starting it as a transient user service if needed.
set -euo pipefail
repo_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
PORT="${PORT:-8080}"
source "$repo_dir/scripts/model-options.sh"
while (( $# )); do
  case "$1" in
    --model|-m|--model=*|--list-models) local_agent_model_option "$@"; shift "$LOCAL_AGENT_MODEL_SHIFT" ;;
    *) printf 'Usage: %s [--model NAME]\n' "$0" >&2; exit 2 ;;
  esac
done
source "$repo_dir/scripts/read-config.sh"
export LOCAL_AGENT_MODEL="$LOCAL_AGENT_CFG_MODEL_ID"
health() { curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null; }
check_model() {
  local response matches
  response=$(curl --silent --fail --max-time 5 "http://127.0.0.1:$PORT/v1/models") || return
  matches=$(LOCAL_AGENT_SERVER_MODELS="$response" nix eval --impure --json --file "$repo_dir/nix/server-matches.nix") || return
  if [[ "$matches" != true ]]; then
    printf 'The server on port %s is not serving %s. Run local_agent shutdown on the model host, then retry with --model %s.\n' "$PORT" "$LOCAL_AGENT_MODEL" "$LOCAL_AGENT_MODEL" >&2
    return 1
  fi
}

# Serialize startup so two callers selecting different models cannot both succeed.
mkdir -p "$repo_dir/models"
exec 8>"$repo_dir/models/.server.lock"
flock 8
if health; then check_model; exit; fi
# Prepare outside the service readiness timeout: a first download/build can be long.
"$repo_dir/scripts/ensure-runtime.sh" server
"$repo_dir/scripts/download-model.sh"
printf 'Starting local model %s...\n' "$LOCAL_AGENT_MODEL" >&2
service=local_agent-model
# A pre-rename service can finish loading without a second server taking its port.
if systemctl --user is-active --quiet qwen-model.service; then service=qwen-model; fi
if ! systemctl --user is-active --quiet "$service.service"; then
  systemd-run --user --unit=local_agent-model --collect \
    --property="WorkingDirectory=$repo_dir" \
    --setenv="PORT=$PORT" --setenv="CTX=${CTX:-}" \
    --setenv="REASONING=${REASONING:-}" --setenv="LOCAL_AGENT_CONFIG=${LOCAL_AGENT_CONFIG:-}" \
    --setenv="LOCAL_AGENT_MODEL=$LOCAL_AGENT_MODEL" \
    "$repo_dir/scripts/run.sh"
fi
for ((attempt = 0; attempt < 180; attempt++)); do
  if health; then check_model; exit; fi
  if ! systemctl --user is-active --quiet "$service.service"; then break; fi
  sleep 1
done
printf 'The model did not become ready. Check: journalctl --user -u %s -n 40\n' "$service" >&2
exit 1
