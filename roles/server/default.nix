{ config, pkgs, lib, configLib, ... }@args: {
  imports = [
    (configLib.relativeToRoot "roles/server/security.nix")
    (configLib.relativeToRoot "users/root/nixos.nix")
  ];

  # this should probably be moved somewhere else so its available for non server hosts
  options.my.server.enable =
    lib.mkEnableOption "If the current host is a server";
  options.my.server.location = lib.mkOption {
    # t = tubby = main
    # f = faker = faker -> testing vm for tubby
    # iss = VM in cloud
    type = lib.types.enum [ "t" "f" "iss" "iss-dev" "vela" "vela-dev" "r" ];
  };
  config = {
    my.server.enable = true;

    # Rotate logs to avoid filling up the disk
    services.logrotate.enable = true;
  };
}
