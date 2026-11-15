{ config, pkgs, lib, ... }:
let
  # ai generated. Review first
  serviceName = "immich";
  immichCfg = config.services.immich;
  immichUser = immichCfg.user;
  mediaLocation = immichCfg.mediaLocation;
  backupDir = "${config.my.services.baseDataDir}/${serviceName}-restic-backups";
  dbDumpFile = "${backupDir}/db.dump";
  dbConnectionString = if lib.hasPrefix "/" immichCfg.database.host then
    "postgresql:///${immichCfg.database.name}?host=${immichCfg.database.host}"
  else
    "postgresql://${immichCfg.database.user}@${immichCfg.database.host}:${
      toString immichCfg.database.port
    }/${immichCfg.database.name}";
in {
  systemd.tmpfiles.rules = [ "d ${backupDir} 770 root ${immichCfg.group} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        set -euo pipefail

        install -d -m 770 -o root -g ${immichCfg.group} ${backupDir}
        rm -f ${dbDumpFile}
      '' + lib.optionalString (immichCfg.secretsFile != null) ''
        set -a
        . ${immichCfg.secretsFile}
        set +a
        if [ -n "''${DB_PASSWORD:-}" ]; then
          export PGPASSWORD="$DB_PASSWORD"
        fi
      '' + ''
        ${pkgs.util-linux}/bin/runuser -u ${immichUser} -- \
          ${lib.getExe' config.services.postgresql.package "pg_dump"} \
            --dbname=${lib.escapeShellArg dbConnectionString} \
            --format=custom \
            --file=${lib.escapeShellArg dbDumpFile}
      '';

      paths = [ mediaLocation backupDir ];

      exclude = [
        "${mediaLocation}/backups"
        "${mediaLocation}/thumbs"
        "${mediaLocation}/encoded-video"
      ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        set -euo pipefail

        sudo systemctl stop immich-server || true
        sudo systemctl stop immich-machine-learning || true

        sudo restic-${serviceName} restore --target / latest
      '' + lib.optionalString (immichCfg.secretsFile != null) ''
        set -a
        . ${immichCfg.secretsFile}
        set +a
        if [ -n "''${DB_PASSWORD:-}" ]; then
          export PGPASSWORD="$DB_PASSWORD"
        fi
      '' + ''
        sudo ${pkgs.util-linux}/bin/runuser -u ${immichUser} -- \
          ${lib.getExe' config.services.postgresql.package "pg_restore"} \
            --clean \
            --if-exists \
            --single-transaction \
            --dbname=${lib.escapeShellArg dbConnectionString} \
            ${lib.escapeShellArg dbDumpFile}

        sudo systemctl start immich-server
        sudo systemctl start immich-machine-learning || true
      '';
    })
  ];
}
