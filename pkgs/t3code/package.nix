{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# The t3 CLI and server from the Oudwins/t3code fork, matching the desktop app.
# It is a Node single-executable app, so patching or stripping would break the
# embedded bundle; NixOS runs it through nix-ld (enabled by roles/agents.nix).
stdenvNoCC.mkDerivation rec {
  pname = "t3code";
  version = "0.1.23";
  src = fetchurl {
    url = "https://github.com/Oudwins/t3code/releases/download/v${version}/t3-${version}-linux-x64.tar.gz";
    hash = "sha256-RulSk4Z1OxS5Nvkyi3zS4fSPXghM3R1Z3MD9/KW9XnU=";
  };
  dontBuild = true;
  dontFixup = true;
  # The binary finds client/, lib/ and node_modules/ next to itself.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -r . $out/lib/t3code
    ln -s $out/lib/t3code/t3 $out/bin/t3
    runHook postInstall
  '';
  meta = {
    description = "T3 Code server and CLI";
    homepage = "https://github.com/Oudwins/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [ "x86_64-linux" ];
  };
}
