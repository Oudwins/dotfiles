{ config, inputs, lib, pkgs, ... }:

let
  sshKeyFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
  executorToken = config.sops.secrets."executor/token".path;
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    defaultSopsFile = ../../../secrets/home.yaml;
    age.sshKeyPaths = [ sshKeyFile ];
    secrets."executor/token" = { };
  };

  home.sessionVariables.SOPS_AGE_KEY_CMD =
    "${lib.getExe pkgs.ssh-to-age} -private-key -i ${lib.escapeShellArg sshKeyFile}";

  services.executor.authTokenFile = executorToken;
}
