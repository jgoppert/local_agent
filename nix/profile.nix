# User profile commands pointing to the launchers in this checkout.
let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
  projectDir = toString ../.;
  launcher = name: script: pkgs.writeShellScriptBin name ''
    exec ${pkgs.bash}/bin/bash ${pkgs.lib.escapeShellArg "${projectDir}/${script}"} "$@"
  '';
in
pkgs.symlinkJoin {
  name = "local_agent-tools";
  paths = [
    (launcher "local_agent" "chat.sh")
    # Existing shells and scripts can keep using the previous OpenCode command.
    (launcher "qwen" "chat.sh")
  ];
}
