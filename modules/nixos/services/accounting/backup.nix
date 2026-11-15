{
  config,
  pkgs,
  lib,
  ...
}:
# For more info see restic-backup.nix
# ! Trigger backup restore
# sudo manager-restore
let
  serviceName = "manager";
  userName = "manager";
  groupName = "manager";
  baseDir = "/var/lib/manager-server";
  appDir = "${baseDir}/app";
  backupDir = "${baseDir}/backup";
  systemdService = "manager-server";
in
{
  systemd.tmpfiles.rules = [ "d ${backupDir} 750 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        systemctl stop ${systemdService} || true
        # Copy app data to backup directory
        ${pkgs.rsync}/bin/rsync -a --delete ${appDir}/ ${backupDir}/
        # Restart the manager-server service
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
        # Stop the manager-server service
        sudo systemctl stop ${systemdService} || true

        # Restore the latest backup
        sudo restic-${serviceName} restore --target / latest

        # Copy restored files back to app directory
        sudo ${pkgs.rsync}/bin/rsync -a --delete ${backupDir}/ ${appDir}/

        # Fix ownership
        sudo chown -R ${userName}:${groupName} ${appDir}/

        # Start the manager-server service
        sudo systemctl start ${systemdService}
      '';
    })
  ];
}
