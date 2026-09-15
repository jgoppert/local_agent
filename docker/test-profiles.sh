#!/usr/bin/env bash
# Exercise the real image entrypoint with a mock server; no GPU or model required.
set -euo pipefail
image=${1:-local_agent:check}
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
cat > "$test_dir/llama-server" <<'SH'
#!/bin/sh
env | sort
printf 'ARG=%s\n' "$@"
SH
chmod 755 "$test_dir/llama-server"

run() {
    docker run --rm --network none \
        --mount "type=bind,src=$test_dir/llama-server,dst=/app/llama-server,readonly" "$@"
}
has() { grep -Fxq -- "$2" <<< "$1" || { printf 'Missing: %s\n' "$2" >&2; exit 1; }; }

defaults=$(run "$image")
has "$defaults" LOCAL_AGENT_GPU_PROFILE=rtx3090
has "$defaults" LLAMA_ARG_CTX_SIZE=32768
has "$defaults" LLAMA_ARG_BATCH=2048
has "$defaults" LLAMA_ARG_UBATCH=512
has "$defaults" LLAMA_ARG_CACHE_TYPE_K=q8_0
has "$defaults" LLAMA_ARG_CACHE_TYPE_V=q8_0
has "$defaults" LLAMA_ARG_SPEC_TYPE=draft-mtp
has "$defaults" LLAMA_ARG_N_GPU_LAYERS=all

blackwell=$(run -e LOCAL_AGENT_GPU_PROFILE=rtx-pro-6000-blackwell "$image")
has "$blackwell" LLAMA_ARG_CTX_SIZE=131072
has "$blackwell" LLAMA_ARG_BATCH=4096
has "$blackwell" LLAMA_ARG_UBATCH=1024
has "$blackwell" LLAMA_ARG_CACHE_TYPE_K=f16
has "$blackwell" LLAMA_ARG_CACHE_TYPE_V=f16
has "$blackwell" LLAMA_ARG_FLASH_ATTN=on
has "$blackwell" LLAMA_ARG_SPEC_TYPE=draft-mtp

overrides=$(run -e LOCAL_AGENT_GPU_PROFILE=rtx-pro-6000-blackwell \
    -e LLAMA_ARG_CTX_SIZE=8192 -e LLAMA_ARG_UBATCH=256 \
    -e LLAMA_ARG_CACHE_TYPE_K=q8_0 -e LLAMA_ARG_SPEC_TYPE=none \
    -e LLAMA_ARG_N_GPU_LAYERS=0 "$image" --alias 'name with spaces')
has "$overrides" LLAMA_ARG_CTX_SIZE=8192
has "$overrides" LLAMA_ARG_UBATCH=256
has "$overrides" LLAMA_ARG_CACHE_TYPE_K=q8_0
has "$overrides" LLAMA_ARG_SPEC_TYPE=none
has "$overrides" LLAMA_ARG_N_GPU_LAYERS=0
has "$overrides" ARG=--alias
has "$overrides" 'ARG=name with spaces'

status=0
run -e LOCAL_AGENT_GPU_PROFILE=invalid "$image" > "$test_dir/error" 2>&1 || status=$?
[[ "$status" == 2 ]] || { printf 'Invalid profile returned %s, expected 2\n' "$status" >&2; exit 1; }
grep -q 'Unknown LOCAL_AGENT_GPU_PROFILE' "$test_dir/error"
printf 'All container profile checks passed.\n'
