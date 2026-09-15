{ pkgs, revision ? "dirty" }:
let
  # Keep NVIDIA's tested driver/toolkit integration and native sm_86/sm_120a
  # kernels. Nix verifies this base and constructs the final layered image.
  base = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/ggml-org/llama.cpp";
    imageDigest = "sha256:1b843bc7b23cacb8f99a94e2feac569352ef1fb8b47ce97e8cbdf57a4df1ab30";
    sha256 = "sha256-BNcgqVOuyTrw6g9AB2pBGu7jP6zR3zFOp0uZ9+bjSQo=";
    finalImageName = "llama-cpp-cuda";
    finalImageTag = "pinned";
    arch = "amd64";
  };

  source = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q4_K_M.gguf";
    sha256 = "322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482";
  };

  # Separate Nix outputs ensure each GGUF shard gets its own Docker layer.
  # Nothing in these outputs references the original, unsplit 16.5 GB download.
  shards = pkgs.runCommand "qwen3.8-27b-shards" {
    outputs = [ "out" "part1" "part2" "part3" "part4" "part5" ];
    nativeBuildInputs = [ pkgs.llama-cpp ];
  } ''
    test "$(stat -c %s ${source})" -eq 16464440224
    mkdir split "$out"
    llama-gguf-split --split-max-size 4G ${source} split/qwen
    test "$(find split -name '*.gguf' | wc -l)" -eq 5
    for n in 1 2 3 4 5; do
      output=part$n
      shard=$(printf 'qwen-%05d-of-00005.gguf' "$n")
      test "$(stat -c %s "split/$shard")" -lt 5000000000
      mkdir -p "''${!output}/models"
      mv "split/$shard" "''${!output}/models/"
    done
  '';

  makeImage = withModel: pkgs.dockerTools.buildLayeredImage {
    name = "local_agent";
    tag = if withModel then "latest" else "runtime-check";
    fromImage = base;
    maxLayers = 125;
    contents = pkgs.lib.optionals withModel [
      shards.part1 shards.part2 shards.part3 shards.part4 shards.part5
    ];
    extraCommands = ''
      mkdir -p usr/local/bin usr/share/licenses/qwen
      cp ${../docker/entrypoint.sh} usr/local/bin/local-agent-server
      chmod 755 usr/local/bin/local-agent-server
      cp ${../docker/MODEL-LICENSE} usr/share/licenses/qwen/MODEL-LICENSE
      cp ${../docker/MODEL-NOTICE} usr/share/licenses/qwen/MODEL-NOTICE
    '';
    config = {
      Entrypoint = [ "/usr/local/bin/local-agent-server" ];
      WorkingDir = "/app";
      Env = [
        "LOCAL_AGENT_GPU_PROFILE=rtx3090"
        "LLAMA_ARG_MODEL=/models/qwen-00001-of-00005.gguf"
        "LLAMA_ARG_ALIAS=qwen3.8-27b"
        "LLAMA_ARG_HOST=127.0.0.1"
        "LLAMA_ARG_PORT=8080"
      ];
      ExposedPorts."8080/tcp" = { };
      Healthcheck = {
        Test = [ "CMD-SHELL" "curl --fail --silent http://127.0.0.1:$LLAMA_ARG_PORT/health || exit 1" ];
        Interval = 30000000000;
        Timeout = 5000000000;
        StartPeriod = 300000000000;
        Retries = 3;
      };
      Labels = {
        "org.opencontainers.image.source" = "https://github.com/jgoppert/local_agent";
        "org.opencontainers.image.revision" = revision;
        "org.opencontainers.image.title" = "local_agent Qwen model server";
        "org.opencontainers.image.description" = "Qwen3.8-27B Q4_K_M with CUDA, built by a Nix flake";
      };
    };
  };
in {
  runtime = makeImage false;
  model = makeImage true;
}
