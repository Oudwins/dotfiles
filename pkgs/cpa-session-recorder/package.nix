{
  lib,
  stdenv,
  buildGoModule,
}:

let
  # CLIProxyAPI loads plugins by file name, which must equal the plugin ID.
  file = "session-recorder${stdenv.hostPlatform.extensions.sharedLibrary}";
in
buildGoModule {
  pname = "cpa-session-recorder";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (f: f.hasExt "go" || f.name == "go.mod" || f.name == "go.sum") ./.;
  };

  vendorHash = "sha256-g+yaVIx4jxpAQ/+WrGKxhVeliYx7nLQe/zsGpxV4Fn4=";

  buildPhase = ''
    runHook preBuild
    go build -buildmode=c-shared -trimpath -ldflags "-s -w" -o ${file} .
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    go test ./...
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 ${file} "$out/lib/${file}"
    runHook postInstall
  '';

  meta = {
    description = "CLIProxyAPI plugin that records usage and request/response bodies into ClickHouse";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
