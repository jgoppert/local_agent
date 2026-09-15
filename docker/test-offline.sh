#!/usr/bin/env bash
# A real inference check using only image contents, with all Docker networking off.
set -euo pipefail
image=${1:-local_agent:latest}
mode=${2:-gpu}
container="local-agent-offline-test-$$"
cleanup() {
    status=$?
    if (( status != 0 )); then docker logs --tail 60 "$container" >&2 || true; fi
    docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

options=(--gpus all)
case "$mode" in
    gpu) ;;
    --cpu)
        options=(--memory 32g
            -e LLAMA_ARG_N_GPU_LAYERS=0 -e LLAMA_ARG_CTX_SIZE=1024
            -e LLAMA_ARG_SPEC_TYPE=none -e LLAMA_ARG_FLASH_ATTN=auto
            -e LLAMA_ARG_CACHE_TYPE_K=f16 -e LLAMA_ARG_CACHE_TYPE_V=f16)
        ;;
    *) printf 'Usage: %s [IMAGE] [--cpu]\n' "$0" >&2; exit 2 ;;
esac

docker run -d --name "$container" --network none "${options[@]}" "$image" >/dev/null
ready=false
for ((attempt = 0; attempt < 120; attempt++)); do
    if docker exec "$container" curl --fail --silent --max-time 2 http://127.0.0.1:8080/health >/dev/null; then
        ready=true
        break
    fi
    if [[ $(docker inspect --format '{{.State.Running}}' "$container") != true ]]; then break; fi
    sleep 5
done
if [[ "$ready" != true ]]; then
    docker logs --tail 60 "$container" >&2
    printf 'Offline server failed to become ready.\n' >&2
    exit 1
fi

docker exec "$container" curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8080/v1/models | grep -q 'qwen3.8-27b'
# Embedded UI assets require Accept-Encoding: gzip (as sent by web browsers).
docker exec "$container" curl --compressed --fail --silent --show-error --max-time 10 --output /dev/null http://127.0.0.1:8080/
response=$(docker exec "$container" curl --fail --silent --show-error --max-time 180 \
    --header 'Content-Type: application/json' \
    --data '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"Reply with exactly OK."}],"max_tokens":16,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' \
    http://127.0.0.1:8080/v1/chat/completions)
grep -q '"choices"' <<< "$response"
grep -Eq '"completion_tokens"[[:space:]]*:[[:space:]]*[1-9]' <<< "$response"
printf '%s\nAll offline image checks passed (mode: %s).\n' "$response" "$mode"
