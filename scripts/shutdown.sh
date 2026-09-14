#!/usr/bin/env bash
# Stop the model service and any Qwen server launched directly from this checkout.
set -euo pipefail
qwen_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
model_file="$qwen_dir/models/Qwen3.8-27B-UD-Q4_K_M.gguf"

# A transient service disappears after stopping; repeated shutdowns are harmless.
load_state=$(systemctl --user show qwen-model.service --property=LoadState --value)
if [[ "$load_state" != not-found ]]; then
  printf 'Stopping Qwen model service...\n'
  systemctl --user stop qwen-model.service
fi

# Older/manual launches may not belong to the service. Match this user's server,
# working directory and model before signaling it, leaving other models alone.
is_local_server() {
  local pid="$1" i model
  local -a args=()
  [[ -O "/proc/$pid" ]] || return 1
  [[ "$(readlink "/proc/$pid/cwd" 2>/dev/null || true)" == "$qwen_dir" ]] || return 1
  [[ "$(readlink "/proc/$pid/exe" 2>/dev/null || true)" == */bin/llama-server ]] || return 1
  mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || return 1
  for ((i = 0; i + 1 < ${#args[@]}; i++)); do
    case "${args[i]}" in
      -m|--model)
        model="${args[i+1]}"
        [[ "$model" == /* ]] || model="$qwen_dir/$model"
        [[ "$model" -ef "$model_file" ]] && return 0
        ;;
    esac
  done
  return 1
}

pids=()
while read -r pid; do
  if is_local_server "$pid"; then
    pids+=("$pid")
    printf 'Stopping Qwen server (PID %s)...\n' "$pid"
    kill -TERM "$pid" 2>/dev/null || true
  fi
done < <(pgrep -u "$EUID" -x llama-server || true)

# Allow cleanup, then force termination if a server is stuck. Recheck identity
# each time so a recycled PID is not mistaken for the original server.
for ((attempt = 0; attempt < 30; attempt++)); do
  remaining=()
  for pid in "${pids[@]}"; do
    if is_local_server "$pid"; then remaining+=("$pid"); fi
  done
  pids=("${remaining[@]}")
  (( ${#pids[@]} )) || break
  sleep 1
done
for pid in "${pids[@]}"; do
  if is_local_server "$pid"; then
    printf 'Force-stopping Qwen server (PID %s)...\n' "$pid"
    kill -KILL "$pid" 2>/dev/null || true
  fi
done
for ((attempt = 0; attempt < 5; attempt++)); do
  remaining=()
  for pid in "${pids[@]}"; do
    if is_local_server "$pid"; then remaining+=("$pid"); fi
  done
  pids=("${remaining[@]}")
  (( ${#pids[@]} )) || break
  sleep 1
done
if (( ${#pids[@]} )); then
  printf 'Could not stop Qwen server PID(s): %s\n' "${pids[*]}" >&2
  exit 1
fi
printf 'Qwen is shut down; its model memory has been released.\n'
