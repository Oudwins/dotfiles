{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "mcp-auth-proxy";
  version = "0-unstable-2026-10-14-stdio";

  src = fetchFromGitHub {
    owner = "Oudwins";
    repo = "mcp-auth-proxy";
    rev = "28e62a2ff3973b5680ea9adc40713f514eac23fb";
    hash = "sha256-L9pEzoLBE0peH/WzfjIsIKMcU49CLoT+ZUsH9gsaemE=";
  };

  vendorHash = "sha256-LsLZmSEKUEwbSXpiwXc+ureGTzXGcT3667P6tVhBXqU=";
  subPackages = [ "cmd/mcp-auth-proxy" ];
  ldflags = [
    "-s"
    "-w"
    "-X main.version=0-unstable-2026-10-14-stdio"
  ];

  meta = {
    description = "Local auth proxy that injects short-lived credentials into MCP streamable HTTP requests";
    homepage = "https://github.com/Oudwins/mcp-auth-proxy";
    mainProgram = "mcp-auth-proxy";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
