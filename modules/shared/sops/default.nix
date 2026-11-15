# Workstation sops-nix settings. The host names its own file:
#   sops.defaultSopsFile = configLib.secretFile "sops/hosts/<name>.yaml";
{ ... }:

{
  sops = {
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_master_key" ];
      generateKey = true;
    };
  };
}
