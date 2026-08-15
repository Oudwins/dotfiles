{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

let
  version = "1.5.40";
  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha512-YpauyrLrsRMjkYgkTSue5EqRThlaUr2n3Y3NrSwov8ZTM+vCpVEy0TGmwStWuPbH8c5O3bxEPcuhvYppVKpMVA==";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha512-anqq/E6OajthonkAoVvFXfCCmckgASVn1tnmnsYaO/+mnNPp5vLNsewlFakYogC7dYej9HE3CATUL6IqWVbQmg==";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha512-FKc4LDJRYFUpRiECVRf0xd2Q40QtGw7Vwc780gADtIDX4UiAHL++MAONO0A0/j/mL7KG0AjeT/Lpi+m08x/kHg==";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha512-oUSJ9fgO/up2/Bh13BVFWBiDlYozyCGTir/mZ8T5rU+l1Knn+OXEsPD+nCZx2E+2Mdn6aZiiYEXXVU/CsUzisw==";
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
