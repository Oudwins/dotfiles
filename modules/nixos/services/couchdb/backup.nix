{
  config,
  pkgs,
  ...
}:

let
  serviceName = "couchdb";
  systemdService = serviceName;
  userName = config.services.couchdb.user;
  groupName = config.services.couchdb.group;
  dataDir = config.services.couchdb.databaseDir;
  backupDir = "${config.my.services.baseDataDir}/couchdb-backup";
in
{
  systemd.tmpfiles.rules = [ "d ${backupDir} 700 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;
    extraConfig = {
      backupPrepareCommand = ''
        systemctl stop ${systemdService} || true
        ${pkgs.rsync}/bin/rsync -a --delete ${dataDir}/ ${backupDir}/
        systemctl start ${systemdService}
      '';
      paths = [ backupDir ];
    };
  };

  environment.systemPackages = [
    pkgs.rsync
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        systemctl stop ${systemdService} || true
        restic-${serviceName} restore --target / latest
        ${pkgs.rsync}/bin/rsync -a --delete ${backupDir}/ ${dataDir}/
        chown -R ${userName}:${groupName} ${dataDir}/
        systemctl start ${systemdService}
      '';
    })
  ];
}
