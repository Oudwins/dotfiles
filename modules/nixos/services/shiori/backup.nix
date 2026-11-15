{
  pkgs,
  ...
}:

let
  serviceName = "shiori";
  dataDir = "/var/lib/${serviceName}";
  backupDir = "${dataDir}/restic-backups";
in
{
  systemd.tmpfiles.rules = [ "d ${backupDir} 700 root root -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        set -euo pipefail

        systemctl stop ${serviceName}
        trap 'systemctl start ${serviceName}' EXIT
        ${pkgs.rsync}/bin/rsync \
          -a \
          --delete \
          --exclude '/restic-backups' \
          ${dataDir}/ \
          ${backupDir}/
      '';
      paths = [ backupDir ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      runtimeInputs = [ pkgs.rsync ];
      text = ''
        set -euo pipefail

        sudo systemctl stop ${serviceName}
        sudo restic-${serviceName} restore --target / latest
        sudo rsync \
          -a \
          --delete \
          --exclude '/restic-backups' \
          ${backupDir}/ \
          ${dataDir}/
        sudo systemctl start ${serviceName}
      '';
    })
  ];
}
