{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

let
  version = "1.6.11";
  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha512-G2AABJVhsGiyqw1dAD700urT1RJ0MFg09dpVQSn20Nrue5ev91Cd0V32+4cTLufqRF9MNluPMEddhIEPhQoeMQ==";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha512-5gH+6Uq8b7T4nEFsYQRXGr8PvIgImPGsSiO/ThgPme8pEEGz9A7ERKD8NGKKPBjLwCt0z0JA9HROXvX0GRJeMA==";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha512-wuGN0QuCmUOwntG0jayHaNMWsP1n1XzB9e0TryZEYCbYqfWJXwNulqi4mb93UW+Ej3uKphLpifaVUWB5bllHrg==";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha512-GzSkw26qGL9Tyk1FfeRctEY9743e91OVhtL+czmnAEaNYS2O3cjFJPZrTDWTjl30kxnAVkjxX8zoVH7PV3T2Wg==";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "Executor does not support ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "executor";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/executor/-/executor-${version}-${source.suffix}.tgz";
    inherit (source) hash;
  };

  sourceRoot = "package";
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R bin $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Local-first MCP gateway and tool runtime";
    homepage = "https://executor.sh";
    license = lib.licenses.mit;
    mainProgram = "executor";
    platforms = builtins.attrNames sources;
  };
}
