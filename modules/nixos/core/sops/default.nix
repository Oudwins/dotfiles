# sops-nix wiring shared by every server. Each host names its own sops files:
#   sops.defaultSopsFile = configLib.secretFile "sops/hosts/<name>.yaml";
{ config
, lib
, inputs
, ...
}:
{
  imports = [
    ./validate-structure.nix
    inputs.sops-nix.nixosModules.sops
  ];
  options.my.sops.enable = lib.mkEnableOption "";

  config = {
    my.sops.enable = true;
    sops = {
      age = {
        # automatically use ssh key to gen private age key
        sshKeyPaths = [
          "/etc/ssh/ssh_host_ed25519_key"
          config.my.networking.sshMasterKeyPath
        ];
      };
    };
  };
}
