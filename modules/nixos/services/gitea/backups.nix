{
  config,
  pkgs,
  lib,
  ...
}:
# For more info see restic-backup.nix
# ! Trigger backup restore
# sudo ${serviceName}-restore
let
  serviceName = lib.last (lib.splitString "/" (builtins.toString ./.)); # Parent directory name
  userName = config.users.users.gitea.name;
  groupName = config.users.users.gitea.group;
  dataDir = "${config.my.services.baseDataDir}/gitea";
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir}/backup 700 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = userName;
    healthchecks.enable = true;

    extraConfig = {
      # nothing is needed here because gitea handles the dumps itself
      backupPrepareCommand = '''';
      paths = [ "${dataDir}/dump" ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      # TODO write this script
      text = '''';
    })
  ];
}
