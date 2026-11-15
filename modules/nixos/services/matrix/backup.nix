{ config, configLib, pkgs, ... }:

let
  backupDir = "/var/lib/matrix-backup";
in
{
  imports = [ (configLib.relativeToRoot "modules/nixos/core/restic-backup.nix") ];

  systemd.tmpfiles.rules = [ "d ${backupDir} 0700 root root -" ];

  my.resticBackup.matrix = {
    enable = true;
    extraConfig = {
      timerConfig = {
        OnCalendar = "04:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
      # Snapshot both databases while stopped, then restart before uploading.
      backupPrepareCommand = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        export PATH=${pkgs.coreutils}/bin:${pkgs.systemd}/bin

        trap 'systemctl start tuwunel.service mautrix-whatsapp.service' EXIT
        systemctl stop mautrix-whatsapp.service tuwunel.service

        rm -rf ${backupDir}/tuwunel ${backupDir}/whatsapp
        cp -a --reflink=auto ${config.services.matrix-tuwunel.settings.global.database_path}. ${backupDir}/tuwunel
        cp -a --reflink=auto /var/lib/mautrix-whatsapp ${backupDir}/whatsapp
        cp ${config.sops.templates."mautrix-whatsapp-registration.yaml".path} \
          ${backupDir}/whatsapp-registration.yaml
        cp ${config.sops.templates."mautrix-whatsapp-double-puppet.yaml".path} \
          ${backupDir}/double-puppet.yaml
      '';
      paths = [
        "${backupDir}/tuwunel"
        "${backupDir}/whatsapp"
        "${backupDir}/whatsapp-registration.yaml"
        "${backupDir}/double-puppet.yaml"
      ];
    };
  };
}
