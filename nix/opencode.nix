let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "opencode";
  version = "1.18.31";
  src = pkgs.fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v1.18.31/opencode-linux-x64.tar.gz";
    sha256 = "e9312be75ed803b7415fc2aeabda1f4fe938912a39673762dc0c38c0e11ebde4";
  };
  sourceRoot = ".";
  nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.makeWrapper];
  buildInputs = [pkgs.stdenv.cc.cc.lib pkgs.zlib];
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    wrapProgram $out/bin/opencode --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.ripgrep]}
    runHook postInstall
  '';
}
