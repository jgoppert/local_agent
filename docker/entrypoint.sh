#!/bin/sh
# Set profile defaults without overriding explicit llama.cpp environment settings.
set -eu

case "${LOCAL_AGENT_GPU_PROFILE:-rtx3090}" in
    rtx3090)
        : "${LLAMA_ARG_CTX_SIZE:=32768}"
        : "${LLAMA_ARG_BATCH:=2048}"
        : "${LLAMA_ARG_UBATCH:=512}"
        : "${LLAMA_ARG_CACHE_TYPE_K:=q8_0}"
        : "${LLAMA_ARG_CACHE_TYPE_V:=q8_0}"
        ;;
    rtx-pro-6000-blackwell)
        # Use the 96 GB card's headroom for context and larger prompt batches.
        : "${LLAMA_ARG_CTX_SIZE:=131072}"
        : "${LLAMA_ARG_BATCH:=4096}"
        : "${LLAMA_ARG_UBATCH:=1024}"
        : "${LLAMA_ARG_CACHE_TYPE_K:=f16}"
        : "${LLAMA_ARG_CACHE_TYPE_V:=f16}"
        ;;
    *)
        printf 'Unknown LOCAL_AGENT_GPU_PROFILE: %s\nChoose rtx3090 or rtx-pro-6000-blackwell.\n' \
            "$LOCAL_AGENT_GPU_PROFILE" >&2
        exit 2
        ;;
esac

: "${LLAMA_ARG_N_GPU_LAYERS:=all}"
: "${LLAMA_ARG_THREADS:=8}"
: "${LLAMA_ARG_N_PARALLEL:=1}"
: "${LLAMA_ARG_FLASH_ATTN:=on}"
: "${LLAMA_ARG_REASONING_EFFORT:=low}"
: "${LLAMA_ARG_SPEC_TYPE:=draft-mtp}"
: "${LLAMA_ARG_SPEC_DRAFT_N_MAX:=3}"
: "${LLAMA_ARG_N_PREDICT:=4096}"

export LLAMA_ARG_CTX_SIZE LLAMA_ARG_BATCH LLAMA_ARG_UBATCH
export LLAMA_ARG_CACHE_TYPE_K LLAMA_ARG_CACHE_TYPE_V LLAMA_ARG_N_GPU_LAYERS
export LLAMA_ARG_THREADS LLAMA_ARG_N_PARALLEL LLAMA_ARG_FLASH_ATTN
export LLAMA_ARG_REASONING_EFFORT LLAMA_ARG_SPEC_TYPE LLAMA_ARG_SPEC_DRAFT_N_MAX LLAMA_ARG_N_PREDICT

exec /app/llama-server "$@"
