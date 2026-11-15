{ config, lib, pkgs, ... }:

let
  serviceName = "mealie";
  dataDir = "${config.my.services.baseDataDir}/${serviceName}";
  mealieBackupDir = "${dataDir}/backups";
  backupDir = "${dataDir}/restic-backups";
  apiTokenFile = config.sops.secrets."mealie/api_token".path;
in {
  sops.secrets."mealie/api_token" = { };

  systemd.tmpfiles.rules = [ "d ${backupDir} 700 root root -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = "root";
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        set -euo pipefail

        token="$(tr -d '\n' < ${apiTokenFile})"

        ${lib.getExe pkgs.curl} \
          --fail \
          --silent \
          --show-error \
          --request POST \
          --header "Authorization: Bearer $token" \
          http://127.0.0.1:${
            toString config.services.mealie.port
          }/api/admin/backups \
          > /dev/null

        if [ ! -d ${mealieBackupDir} ]; then
          echo "Mealie backup directory does not exist: ${mealieBackupDir}" >&2
          exit 1
        fi

        ${pkgs.rsync}/bin/rsync \
          -a \
          --delete \
          --prune-empty-dirs \
          --include='*/' \
          --include='*.zip' \
          --exclude='*' \
          ${mealieBackupDir}/ \
          ${backupDir}/

        set -- ${backupDir}/*.zip
        if [ ! -e "$1" ]; then
          echo "No Mealie backup archives were staged in ${backupDir}" >&2
          exit 1
        fi
      '';
      paths = [ backupDir ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        restic-${serviceName} restore --target / latest

        # TODO: Upload a restored backup archive with POST /api/admin/backups/upload
        # and trigger POST /api/admin/backups/{file_name}/restore.
      '';
    })
  ];
}
