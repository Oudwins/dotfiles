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
      # consistent copy of the live sqlite db; the raw files are excluded below
      backupPrepareCommand = ''
        ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/data/gitea.db ".backup '${dataDir}/backup/gitea.db'"
      '';
      paths = [
        "${dataDir}/repositories"
        "${dataDir}/data"
        "${dataDir}/custom"
        "${dataDir}/backup"
      ];
      exclude = [
        "${dataDir}/data/gitea.db*"
        "${dataDir}/data/indexers"
        "${dataDir}/data/queues"
        "${dataDir}/data/repo-archive"
      ];
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
