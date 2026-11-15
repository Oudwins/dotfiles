{
  config,
  pkgs,
  lib,
  dataDir,
  ...
}:
# For more info see restic-backup.nix
# ! Trigger backup restore
# sudo ${serviceName}-restore
let
  serviceName = lib.last (lib.splitString "/" (builtins.toString ./.)); # Parent directory name
  userName = config.users.users.nextcloud.name;
  groupName = config.users.users.nextcloud.group;
  dataDir = "${config.my.services.baseDataDir}/nextcloud";
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir}/backup 700 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = userName;
    healthchecks.enable = true;
    # nextcloud-occ needs the same credentials as nextcloud's own units
    loadCredentials = config.systemd.services.nextcloud-cron.serviceConfig.LoadCredential;
    cleanupCommand = ''
      ${lib.getExe' config.services.nextcloud.occ "nextcloud-occ"} maintenance:mode --off
    '';

    extraConfig = {
      backupPrepareCommand = ''
        ${lib.getExe' config.services.nextcloud.occ "nextcloud-occ"} maintenance:mode --on
        ${lib.getExe' config.services.postgresql.package "pg_dump"} nextcloud --format=custom --file=${dataDir}/backup/db.dump
      '';
      paths = [
        "${dataDir}/data"
        "${dataDir}/config/config.php"
        "${dataDir}/backup"
      ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        sudo -u ${userName} ${lib.getExe' config.services.nextcloud.occ "nextcloud-occ"} maintenance:mode --on
        sudo -u ${userName} restic-${serviceName} restore --target / latest
        sudo -u ${userName} pg_restore --clean --if-exists --dbname nextcloud ${dataDir}/backup/db.dump
        sudo -u ${userName} ${lib.getExe' config.services.nextcloud.occ "nextcloud-occ"} maintenance:mode --off
      '';
    })
  ];
}
