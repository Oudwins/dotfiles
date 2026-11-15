{
  config,
  pkgs,
  ...
}:

let
  serviceName = "memos";
  dataDir = "${config.my.services.baseDataDir}/${serviceName}";
  backupDir = "${dataDir}/backup";
  containerName = "${serviceName}_db";
  databaseName = serviceName;
  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
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

        ${dockerBin} exec ${containerName} pg_dump -U ${databaseName} -d ${databaseName} -Fc > ${backupDir}/db.dump
      '';
      paths = [ backupDir ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        set -euo pipefail

        ${dockerBin} stop ${serviceName} || true
        sudo restic-${serviceName} restore --target / latest
        ${dockerBin} exec -i ${containerName} pg_restore -U ${databaseName} -d ${databaseName} -Fc < ${backupDir}/db.dump
        ${dockerBin} start ${serviceName}
      '';
    })
  ];
}
