{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "pr-review-server";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./main.go
    ];
  };

  vendorHash = null;

  meta = {
    description = "Serves pr-review-doc pages and proxies their GitHub review threads";
    mainProgram = "pr-review-server";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
