{
  writeShellApplication,
  python3,
  google-cloud-sdk,
  agent-vault,
}:

writeShellApplication {
  name = "agent-vault-service";
  runtimeInputs = [
    agent-vault
    (python3.withPackages (packages: [ packages.aiohttp ]))
    google-cloud-sdk
  ];
  text = ''
    exec python ${./service.py} "$@"
  '';
}
