# User profile commands pointing to the launchers in this checkout.
let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
  projectDir = toString ../.;
  launcher = name: script: pkgs.writeShellScriptBin name ''
    exec ${pkgs.bash}/bin/bash ${pkgs.lib.escapeShellArg "${projectDir}/${script}"} "$@"
  '';
in
pkgs.symlinkJoin {
  name = "qwen-tools";
  paths = [
    (launcher "qwen" "chat.sh")
    (launcher "codex-qwen" "scripts/codex-qwen.sh")
  ];
}
