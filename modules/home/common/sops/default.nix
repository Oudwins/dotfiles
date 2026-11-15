# The user names its own sops file, e.g. users/tmx/home.nix:
#   sops.defaultSopsFile = configLib.secretFile "sops/users/tmx.yaml";
{ config, inputs, lib, pkgs, ... }:

let
  sshKeyFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    age.sshKeyPaths = [ sshKeyFile ];
  };

  home.sessionVariables.SOPS_AGE_KEY_CMD =
    "${lib.getExe pkgs.ssh-to-age} -private-key -i ${lib.escapeShellArg sshKeyFile}";
}
