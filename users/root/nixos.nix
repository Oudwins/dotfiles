{ config, lib, ... }:
let
  username = "root";
  passwordSecretName = "users/${username}/hashed_password";
  pubKeys = builtins.filter (path: lib.hasSuffix ".pub" (toString path))
    (lib.filesystem.listFilesRecursive ./keys);
in {
  config = {
    sops.secrets."${passwordSecretName}".neededForUsers = true;

    users.mutableUsers = false;
    users.users.${username} = {
      hashedPasswordFile = config.sops.secrets."${passwordSecretName}".path;
      openssh.authorizedKeys.keys = map builtins.readFile pubKeys;
    };
  };
}
