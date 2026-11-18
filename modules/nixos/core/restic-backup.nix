{
  config,
  pkgs,
  lib,
  ...
}:
# ! Trigger these backups mannually for testing
# mybackup = service name generally
# sudo systemctl start restic-backups-mybackup.service
# sudo systemctl status restic-backups-mybackup.service
# sudo journalctl -u restic-backups-mybackup.service
# ! Trigger Restore (generally)
# sudo ${serviceName}-restore
let
  cfg = lib.filterAttrs (_: value: value.enable) config.my.resticBackup;

  healthchecksEnable = (lib.filterAttrs (_: value: value.healthchecks.enable) cfg) != { };
  repositoryTemplateName = name: "restic-repository-${name}";
in
{
  options.my.resticBackup = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "";
          user = lib.mkOption {
            type = lib.types.str;
            default = config.users.users.root.name;
          };
          healthchecks.enable = lib.mkEnableOption "";
          # systemd LoadCredential entries ("id:/path") made available to the job via
          # $CREDENTIALS_DIRECTORY, so it can read secrets without running as root
          loadCredentials = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          # Runs after the job succeeds or fails, as its own unit with the same user and
          # credentials. Use instead of backupCleanupCommand (ExecStopPost), which runs
          # after systemd has already removed the credentials.
          cleanupCommand = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
          };
          extraConfig = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      }
    );
    default = { };
  };

  config = lib.mkIf (cfg != { }) {
    systemd.tmpfiles.rules =
      (lib.optionals (!config.my.sops.enable) [
        "z /run/secrets/restic/environment 440 root ${config.users.groups.backup.name} -"
        "z /run/secrets/restic/password 440 root ${config.users.groups.backup.name} -"
        "z /run/secrets/healthchecks-ping-key 440 root ${config.users.groups.backup.name} -"
      ] ++ lib.mapAttrsToList (
        name: _: "z /run/secrets/restic/repository-${name} 440 root ${config.users.groups.backup.name} -"
      ) cfg)
      ++ lib.mapAttrsToList (
        name: value: "d /var/cache/restic-backups-${name} 700 ${value.user} ${value.user} -"
      ) cfg;

    # adds users from the resticBackup.user option to the backup group
    users.groups.backup.members = builtins.filter (user: user != config.users.users.root.name) (
      lib.mapAttrsToList (_: value: value.user) cfg
    );

    sops.secrets = lib.optionalAttrs config.my.sops.enable (
      let
        resticPermissions = {
          mode = "440";
          group = config.users.groups.backup.name;
        };
      in
      {
        "restic/repo" = resticPermissions;
        "restic/environment" = resticPermissions;
        "restic/password" = resticPermissions;
        "healthchecks-ping-key" = lib.mkIf healthchecksEnable resticPermissions;
      }
    );

    sops.templates = lib.optionalAttrs config.my.sops.enable (
      lib.mapAttrs' (
        name: _:
        lib.nameValuePair (repositoryTemplateName name) {
          content = "${config.sops.placeholder."restic/repo"}/${config.networking.hostName}.${name}";
          mode = "0440";
          group = config.users.groups.backup.name;
        }
      ) cfg
    );

    services.restic.backups = lib.mapAttrs (
      name: value:
      {
        inherit (value) user;
        initialize = true;
        repositoryFile = if config.my.sops.enable
          then config.sops.templates.${repositoryTemplateName name}.path
          else "/run/secrets/restic/repository-${name}";
        environmentFile =
          config.sops.secrets."restic/environment".path or "/run/secrets/restic/environment";
        passwordFile = config.sops.secrets."restic/password".path or "/run/secrets/restic/password";
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
          "--keep-yearly 1"
        ];
      }
      // value.extraConfig
    ) cfg;

    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: value:
        # mkIf rather than filterAttrs: the attr names must not depend on option values
        lib.nameValuePair "restic-backups-${name}" {
          serviceConfig.LoadCredential = lib.mkIf (value.loadCredentials != [ ]) value.loadCredentials;
          onSuccess = lib.mkIf (value.cleanupCommand != null) [ "restic-backups-${name}-cleanup.service" ];
          onFailure = lib.mkIf (value.cleanupCommand != null) [ "restic-backups-${name}-cleanup.service" ];
        }
      ) cfg)
      (lib.mapAttrs' (
        name: value:
        lib.nameValuePair "restic-backups-${name}-cleanup" {
          script = value.cleanupCommand;
          serviceConfig = {
            Type = "oneshot";
            User = value.user;
            LoadCredential = lib.mkIf (value.loadCredentials != [ ]) value.loadCredentials;
          };
        }
      ) (lib.filterAttrs (_: value: value.cleanupCommand != null) cfg))
    ];

    # backup healthchecks. Not yet tested TODO
    # systemd.services = lib.mkMerge [
    #   (lib.mapAttrs'
    #     (
    #       name: _:
    #         lib.nameValuePair "restic-backups-${name}" {
    #           wants = [ "healthcheck-ping@${name}-backup_start.service" ];
    #           onSuccess = [ "healthcheck-ping@${name}-backup.service" ];
    #           onFailure = [ "healthcheck-ping@${name}-backup_fail.service" ];
    #         }
    #     )
    #     (lib.filterAttrs (_: value: value.healthchecks.enable) cfg))

    #   (lib.mkIf healthchecksEnable {
    #     "healthcheck-ping@" = {
    #       description = "Pings healthcheck (%i)";
    #       serviceConfig.Type = "oneshot";
    #       scriptArgs = "%i";
    #       script = ''
    #         ${lib.getExe pkgs.curl} -fsS -m 10 --retry 5  https://hc-ping.com/$(cat ${
    #           config.sops.secrets."healthchecks-ping-key".path or "/run/secrets/healthchecks-ping-key"
    #         })/$(echo $1 | tr _ /)
    #       '';
    #     };
    #   })
    # ];
  };
}
