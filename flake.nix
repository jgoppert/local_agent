{
  description = "local_agent Qwen container with RTX 3090 and Blackwell profiles";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02f5696b0e6097e589076d886b317b83ff0437d7";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      images = import ./nix/container.nix {
        inherit pkgs;
        revision = self.rev or "dirty";
      };
    in {
      packages.${system} = {
        default = images.model;
        dockerImage = images.model;
        dockerRuntime = images.runtime;
        skopeo = pkgs.skopeo;
      };
      checks.${system}.container-scripts = pkgs.runCommand "check-container-scripts" {
        nativeBuildInputs = [ pkgs.shellcheck ];
      } ''
        shellcheck ${./docker/entrypoint.sh} ${./docker/test-profiles.sh} ${./docker/test-offline.sh}
        touch $out
      '';
    };
}
