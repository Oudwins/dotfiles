{ config, inputs, ... }:

let
  executorToken = config.sops.secrets."executor/token".path;
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    defaultSopsFile = ../../../secrets/home.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    secrets."executor/token" = { };
  };

  services.executor.authTokenFile = executorToken;

  home.sessionVariables.EXECUTOR_MCP_TOKEN = "$(cat ${executorToken} 2>/dev/null)";
}
