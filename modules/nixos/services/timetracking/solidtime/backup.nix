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
  dataDir = "${config.my.services.baseDataDir}/${serviceName}";

  containerName = "${serviceName}_db";
  databaseName = serviceName;

  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir}/backup 700 root root -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        ${dockerBin} exec ${containerName} pg_dump -U ${databaseName} -d ${databaseName} -Fc > ${dataDir}/backup/db.dump
      '';
      paths = [ "${dataDir}/backup" ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        sudo restic-${serviceName} restore --target / latest
        sudo systemctl stop ${serviceName}_app ${serviceName}_scheduler ${serviceName}_queue
        ${dockerBin} exec -i ${containerName} pg_restore -U ${databaseName} -d ${databaseName} -Fc < ${dataDir}/backup/db.dump
        sudo systemctl start ${serviceName}_app ${serviceName}_scheduler ${serviceName}_queue
      '';
    })
  ];
}
