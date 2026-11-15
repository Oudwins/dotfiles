{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.40.2";
  sources = {
    aarch64-darwin = {
      platform = "darwin_arm64";
      hash = "adac8658d42488a5e3ae016923fbedf5098253d4751288decb2c561a9f26d3ae";
    };
    x86_64-darwin = {
      platform = "darwin_amd64";
      hash = "9bd6db1be5efbb01cab1545b5b2ba02771534175d888e24fc88c4718b7266e3d";
    };
    x86_64-linux = {
      platform = "linux_amd64";
      hash = "6d8a12f4055e5b0244f79c0c6aa5415c2988b91f5b16a2c0b92b5897b8bae76b";
    };
    aarch64-linux = {
      platform = "linux_arm64";
      hash = "db50a468df833f8ae358412e3790c83e1a689dd07272c76f634afb258d9f5827";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "agent-vault";
  inherit version;
  src = fetchurl {
    url = "https://github.com/Infisical/agent-vault/releases/download/v${version}/agent-vault_${version}_${source.platform}.tar.gz";
    sha256 = source.hash;
  };
  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 agent-vault $out/bin/agent-vault
    runHook postInstall
  '';
  meta = {
    description = "Credential broker and HTTP proxy for agents";
    homepage = "https://github.com/Infisical/agent-vault";
    license = lib.licenses.mit;
    mainProgram = "agent-vault";
    platforms = builtins.attrNames sources;
  };
}
