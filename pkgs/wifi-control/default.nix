{ lib, buildGoModule }:

buildGoModule {
  pname = "wifi-control";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  vendorHash = null;
  env.CGO_ENABLED = 0;
  flags = [ "-trimpath" ];
  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Small web controller for ZTE H3600 Wi-Fi radios";
    mainProgram = "wifi-control";
    platforms = lib.platforms.linux;
  };
}
