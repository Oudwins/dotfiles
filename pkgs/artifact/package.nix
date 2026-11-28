{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "artifact";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./main.go
      ./claude.go
      ./main_test.go
    ];
  };

  vendorHash = null;

  meta = {
    description = "Publishes files such as HTML reports at a URL, to S3 or Claude Artifacts, and serves the S3 uploads";
    mainProgram = "artifact";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
