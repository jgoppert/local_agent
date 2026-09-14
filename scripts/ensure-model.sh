#!/usr/bin/env bash
# Make sure llama-server is up on $PORT, starting it as a transient user service if needed.
set -euo pipefail
qwen_dir="$(dirname "$(dirname "$(readlink -f "$0")")")"
PORT="${PORT:-8080}"
health() { curl --silent --fail --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null; }

if health; then exit 0; fi
# Prepare outside the service readiness timeout: a first download/build can be long.
"$qwen_dir/scripts/ensure-runtime.sh" server
"$qwen_dir/scripts/download-model.sh"
printf 'Starting local Qwen model...\n' >&2
if ! systemctl --user is-active --quiet qwen-model.service; then
  systemd-run --user --unit=qwen-model --collect \
    --property="WorkingDirectory=$qwen_dir" \
    --setenv="PORT=$PORT" --setenv="CTX=${CTX:-}" \
    --setenv="REASONING=${REASONING:-}" --setenv="QWEN_CONFIG=${QWEN_CONFIG:-}" \
    "$qwen_dir/scripts/run.sh"
fi
for ((attempt = 0; attempt < 180; attempt++)); do
  if health; then exit 0; fi
  if ! systemctl --user is-active --quiet qwen-model.service; then break; fi
  sleep 1
done
printf 'Qwen did not become ready. Check: journalctl --user -u qwen-model -n 40\n' >&2
exit 1
