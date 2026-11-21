# Home-manager users on this host.
{ config, ... }:

let
  ageKeyFile = config.sops.secrets."users/tmx/age_key".path;
in
{
  home-manager.users.tmx =
    { lib, ... }:
    {
      imports = [
        ../../users/tmx/home.nix
        ../../modules/home/common
      ];

      sops.age = {
        keyFile = ageKeyFile;
        sshKeyPaths = lib.mkForce [ ];
      };

      services.t3code.enable = true;
    };
}
