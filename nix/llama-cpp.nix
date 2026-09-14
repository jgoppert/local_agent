# llama.cpp with the selected hardware backend; CUDA sm_86 is the default preset.
# The system nixpkgs may predate Qwen3.8 support, so this pin is independent of it.
let
  cfg = import ./config.nix;
  nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/02f5696b0e6097e589076d886b317b83ff0437d7";
  pkgs = import nixpkgs {
    system = builtins.currentSystem;
    config = {
      allowUnfree = true;
      cudaSupport = cfg.hardware.backend == "cuda";
      cudaCapabilities = cfg.hardware.cuda_capabilities;
    };
  };
in
pkgs.llama-cpp.override {
  cudaSupport = cfg.hardware.backend == "cuda";
  vulkanSupport = cfg.hardware.backend == "vulkan";
  rocmSupport = false;
  metalSupport = false;
}
