{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

let
  version = "1.6.10";
  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha512-rPuEL8ibW7k6jkAa714wAiiw3YGWtQ4btMmCSDdLGzEIBj2FoBNjOu76okIF10H3fYbrituss0VeX5KEPFbv/w==";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha512-KA7sGlSV/3uXL5ZOv8YJd1HBoYR3DPDxQlVcsxzF+jdLjvDTKrl+n2eQ3imzlYMwps80AqDHk+rcFg8zEJXI7w==";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha512-SyzZsunGUhgwZoFEiWVqEIPV3h25SHKToWLrwId3p7FJqGuP/9ixMeOeXZ1CIS9j2kCws3F5iSUi3DQQ/6uxdw==";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha512-njvy/LzUWlVdDXuKTTGX6NCKhDpKdRjMf2T7KqumaZd2A7ZqXoIl65qeAyklFU+kkalLS6QW1Xs3lSSj+nfAPw==";
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
