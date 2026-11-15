{
  config,
  pkgs,
  lib,
  ...
}:
let
  # This does not backup the RSA key, attachments or sends
  serviceName = "vaultwarden";
  userName = config.users.users.${serviceName}.name;
  groupName = config.users.users.${serviceName}.group;
  dataDir = "${config.my.services.baseDataDir}/bitwarden_rs"; # not sure why its different than service name but that is what it is
  backupDir = "${dataDir}/restic-backups";
in
{
  systemd.tmpfiles.rules = [ "d ${backupDir} 700 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        systemctl stop ${serviceName}
        ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3 ".dump" > ${backupDir}/db.sqlite3.dump
        # ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3-shm ".dump" > ${backupDir}/db.sqlite3-shm.dump
        # ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3-wal ".dump" > ${backupDir}/db.sqlite3-wal.dump

        systemctl start ${serviceName}
      '';
      paths = [ backupDir ];
    };
  };

  environment.systemPackages = [
    pkgs.sqlite # required for the db commands
    (pkgs.writeShellApplication {
      # Not sure about this. Might not work. Unsure if the directories are correct
      name = "${serviceName}-restore";
      text = ''
        sudo systemctl stop ${serviceName}

        # Restore the latest backup
        restic-${serviceName} restore --target / latest

        # Remove any WAL files and the existing database
        sudo rm -f ${dataDir}/db.sqlite3*

        # Move the restored backup to the correct location
        ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3 < ${backupDir}/db.sqlite3.dump
        ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3-shm < ${backupDir}/db.sqlite3-shm.dump
        ${pkgs.sqlite}/bin/sqlite3 ${dataDir}/db.sqlite3-wal < ${backupDir}/db.sqlite3-wal.dump

        # Change permissions on new dbs
        sudo chown ${userName}:${groupName} ${dataDir}/db.sqlite3*
        sudo chown ${userName}:${groupName} ${dataDir}/db.sqlite3-shm*
        sudo chown ${userName}:${groupName} ${dataDir}/db.sqlite3-wal*

        # Start vaultwarden back up
        sudo systemctl start ${serviceName}
      '';
    })
  ];
}
