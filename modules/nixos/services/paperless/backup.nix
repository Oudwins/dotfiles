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
  userName = config.users.users.paperless.name;
  groupName = config.users.users.paperless.group;
  dataDir = "${config.my.services.baseDataDir}/paperless";
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir}/backup 700 ${userName} ${groupName} -" ];

  my.resticBackup.${serviceName} = {
    enable = true;
    user = userName;
    healthchecks.enable = true;

    extraConfig = {
      backupPrepareCommand = ''
        ${lib.getExe config.services.paperless.manage} document_exporter ${dataDir}/backup ${
          lib.concatStringsSep " " [
            "--compare-checksums"
            "--delete"
            "--split-manifest"
            "--use-filename-format"
            "--no-progress-bar"
          ]
        }
      '';
      paths = [ "${dataDir}/backup" ];
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${serviceName}-restore";
      text = ''
        sudo -u ${userName} restic-${serviceName} restore --target / latest
        sudo -u ${userName} ${lib.getExe config.services.paperless.manage} document_importer ${dataDir}/backup
      '';
    })
  ];
}
