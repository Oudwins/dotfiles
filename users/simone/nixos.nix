{ config, lib, ... }:
let
  username = "simone";
  passwordSecretName = "users/${username}/hashed_password";
  pubKeys = (lib.filesystem.listFilesRecursive ./keys) ++ [ ../tmx/keys/id_ed25519.pub ];
in {
  config = {
    sops.secrets."${passwordSecretName}".neededForUsers = true;

    users.mutableUsers = false;
    users.users.${username} = {
      home = "/home/${username}";
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."${passwordSecretName}".path;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = map builtins.readFile pubKeys;
    };

    nix.settings.trusted-users = [ username "root" ];

    security.sudo.extraRules = [{
      users = [ username ];
      commands = [{
        command = "ALL";
        options = [ "NOPASSWD" ];
      }];
    }];
  };
}
