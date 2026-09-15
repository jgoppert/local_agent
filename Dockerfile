# syntax=docker/dockerfile:1

# Upstream CUDA 12 server and CPU tools, pinned to immutable image digests.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:5268283a8d6510d167364f19aee93e98180d8eb0cac4b7edb20af7e3edf40c17 AS runtime

LABEL org.opencontainers.image.source="https://github.com/jgoppert/local_agent" \
      org.opencontainers.image.title="local_agent Qwen model server" \
      org.opencontainers.image.description="Qwen3.8-27B Q4_K_M weights with the llama.cpp CUDA server"

# The default profile matches config.toml; Blackwell tuning is opt-in.
# The pinned upstream build contains native sm_86 and sm_120a CUDA kernels.
ENV LOCAL_AGENT_GPU_PROFILE=rtx3090 \
    LLAMA_ARG_MODEL=/models/qwen-00001-of-00005.gguf \
    LLAMA_ARG_ALIAS=qwen3.8-27b \
    LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=8080

COPY docker/MODEL-LICENSE docker/MODEL-NOTICE /usr/share/licenses/qwen/
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/local-agent-server
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
    CMD curl --fail --silent "http://127.0.0.1:${LLAMA_ARG_PORT}/health" || exit 1
ENTRYPOINT ["/usr/local/bin/local-agent-server"]

FROM ghcr.io/ggml-org/llama.cpp:full@sha256:89814c1f5978e5523af2e7ab89ad86ba44930c041c0ce477ba31a74d86162b83 AS weights

# The exact artifact from models.toml, pinned independently of HF's moving main.
ARG MODEL_URL=https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q4_K_M.gguf
ARG MODEL_SHA256=322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482
RUN <<'SH'
set -eu
mkdir -p /models
curl --fail --location --retry 5 --retry-delay 5 --retry-all-errors \
    --output /tmp/model.gguf "$MODEL_URL"
printf '%s  /tmp/model.gguf\n' "$MODEL_SHA256" | sha256sum --check -
test "$(stat -c %s /tmp/model.gguf)" -eq 16464440224
/app/llama-gguf-split --split-max-size 4G /tmp/model.gguf /models/qwen
rm /tmp/model.gguf
test "$(find /models -name '*.gguf' | wc -l)" -eq 5
for shard in /models/*.gguf; do
    test "$(stat -c %s "$shard")" -lt 5000000000
done
chmod 644 /models/*.gguf
SH

FROM runtime AS model
# GHCR limits each layer to 10 GB. Each COPY must remain a separate layer.
# llama.cpp reads these GGUF shards directly; no first-run download or assembly.
COPY --from=weights /models/qwen-00001-of-00005.gguf /models/
COPY --from=weights /models/qwen-00002-of-00005.gguf /models/
COPY --from=weights /models/qwen-00003-of-00005.gguf /models/
COPY --from=weights /models/qwen-00004-of-00005.gguf /models/
COPY --from=weights /models/qwen-00005-of-00005.gguf /models/
RUN test "$(find /models -name '*.gguf' | wc -l)" -eq 5 && /app/llama-server --version
