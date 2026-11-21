{ config, lib, ... }:

let
  ifTheyExist = groups:
    builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
  passwordSecretName = "users/${config.my.username}/hashed_password";
  pubKeys = lib.filesystem.listFilesRecursive ./keys;
in {
  config = {
    # Because this happens before users are available. No owners can be set for these files so the passwords must be hashed
    # see: https://youtu.be/gdxlc5a6ne0?si=rEc8JMt141I5qWaH&t=255
    # create hash with: printf '%s' 'your-password-here' | nix shell nixpkgs#whois -c mkpasswd -m yescrypt -s
    sops.secrets."${passwordSecretName}".neededForUsers = true;

    users.mutableUsers = false;
    users.users.${config.my.username} = {
      home = "/home/${config.my.username}";
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."${passwordSecretName}".path;

      # Only add groups that exist on the current host.
      extraGroups = [ "wheel" ] ++ ifTheyExist [
        "audio"
        "video"
        "docker"
        "podman"
        "git"
        "networkmanager"
        "libvirtd"
        "transmission"
        "paperless"
        "freshrss"
      ];

      openssh.authorizedKeys.keys = map builtins.readFile pubKeys;
    };

    systemd.tmpfiles.rules = let
      user = config.users.users.${config.my.username}.name;
      group = config.users.users.${config.my.username}.group;
    in [
      # Otherwise tmpfiles creates ~/.ssh as root for the sockets directory.
      "d /home/${config.my.username}/.ssh 0700 ${user} ${group} -"
      "d /home/${config.my.username}/.ssh/sockets 0750 ${user} ${group} -"
    ];
  };
}
