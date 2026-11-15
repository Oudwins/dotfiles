{ lib, fetchurl, makeWrapper, stdenvNoCC, }:

let
  pname = "btca";
  version = "2.0.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash =
      "sha512-NnVCMCs9EPtVjJyB1sRa2T940eUVVtqulvktfYwMeI6THzCNo8w7OqhUyHnJ+SUWSF5WKUX4Dh1gyxdyd+/DLQ==";
  };

  binaryName = {
    x86_64-linux = "btca-linux-x64";
    aarch64-linux = "btca-linux-arm64";
    x86_64-darwin = "btca-darwin-x64";
    aarch64-darwin = "btca-darwin-arm64";
  }.${stdenvNoCC.hostPlatform.system} or (throw
    "Unsupported system for btca: ${stdenvNoCC.hostPlatform.system}");
in stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  sourceRoot = "package";

  installPhase = ''
    runHook preInstall

    install -Dm755 "dist/${binaryName}" "$out/libexec/${pname}/${pname}"
    install -Dm644 dist/tree-sitter-worker.js "$out/libexec/${pname}/tree-sitter-worker.js"
    install -Dm644 dist/tree-sitter.js "$out/libexec/${pname}/tree-sitter.js"
    install -Dm644 dist/tree-sitter.wasm "$out/libexec/${pname}/tree-sitter.wasm"

    makeWrapper "$out/libexec/${pname}/${pname}" "$out/bin/${pname}" \
      --set OTUI_TREE_SITTER_WORKER_PATH "$out/libexec/${pname}/tree-sitter-worker.js"

    runHook postInstall
  '';

  meta = {
    description =
      "CLI for asking questions about technologies using Better Context";
    homepage = "https://btca.dev";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms =
      [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
