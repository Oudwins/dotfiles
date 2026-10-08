{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "cli-proxy-api";
  version = "8.0.20";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    tag = "v${version}";
    hash = "sha256-RXCEHPDGUO8sPs/WuGriMhGobnzYKAZsZSx2Olk2JF8=";
  };

  vendorHash = "sha256-r3yWkdMcM40G9jV7MxW/qNv3E9WrHavFilW24quEf+8=";
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
