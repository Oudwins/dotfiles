{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "mcp-auth-proxy";
  version = "0-unstable-2026-10-27-strategy-target";

  src = fetchFromGitHub {
    owner = "Oudwins";
    repo = "mcp-auth-proxy";
    rev = "039e0be798bedcbac978b4c90d4a780768bb202f";
    hash = "sha256-xVqt+Fj/6HHWTlEguanAAyLv1h3tuf8wDW3PyTyZ/bM=";
  };

  vendorHash = "sha256-LsLZmSEKUEwbSXpiwXc+ureGTzXGcT3667P6tVhBXqU=";
  subPackages = [ "cmd/mcp-auth-proxy" ];
  ldflags = [
    "-s"
    "-w"
    "-X main.version=0-unstable-2026-10-27-strategy-target"
  ];

  meta = {
    description = "Local auth proxy that injects short-lived credentials into MCP streamable HTTP requests";
    homepage = "https://github.com/Oudwins/mcp-auth-proxy";
    mainProgram = "mcp-auth-proxy";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
