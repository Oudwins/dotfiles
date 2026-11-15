{
  lib,
  buildGo127Module,
  fetchFromGitHub,
}:

buildGo127Module rec {
  pname = "cli-proxy-api";
  version = "8.0.69";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    tag = "v${version}";
    hash = "sha256-SF3aSlhWMPEBu9q5vuKeSbdB4ew8CwyjyhcOQ5U/GUI=";
  };

  vendorHash = "sha256-02Qqrs9lQ0kE+Tnk/SWvlkLXGSh8RQPxRawFZogRYNc=";
  subPackages = [ "cmd/server" ];
  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
  ];

  postInstall = ''
    mv "$out/bin/server" "$out/bin/cli-proxy-api"
    install -Dm644 config.example.yaml "$out/share/cli-proxy-api/config.example.yaml"
  '';

  meta = {
    description = "OpenAI, Gemini and Claude compatible proxy for CLI subscriptions";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
