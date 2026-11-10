{
  lib,
  buildGoModule,
  makeWrapper,
  google-cloud-sdk,
  agent-vault,
}:

buildGoModule {
  pname = "agent-vault-service";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./main.go
      ./main_test.go
    ];
  };

  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/agent-vault-service --prefix PATH : ${
      lib.makeBinPath [
        agent-vault
        google-cloud-sdk
      ]
    }
  '';

  meta = {
    description = "Runs and provisions Agent Vault, serving configured credentials over its OAuth refresh protocol";
    mainProgram = "agent-vault-service";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
