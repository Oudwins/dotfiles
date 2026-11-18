# Env files holding the SMTP password (my.smtp.passwordFile), for services that
# only read it from an environment variable. Each one is written at boot to
# /run/smtp-env-<name>/env and loaded by the listed units.
{ config, lib, ... }:

let
  cfg = config.my.smtp;
in
{
  options.my.smtp.envFiles = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            variable = lib.mkOption { type = lib.types.str; };
            units = lib.mkOption { type = lib.types.listOf lib.types.str; };
            path = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "/run/smtp-env-${name}/env";
            };
          };
        }
      )
    );
  };

  config.systemd.services = lib.mkMerge (
    lib.mapAttrsToList (
      name: env:
      let
        unit = "smtp-env-${name}.service";
      in
      {
        "smtp-env-${name}" = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "smtp-env-${name}";
            RuntimeDirectoryMode = "0700";
            LoadCredential = "password:${cfg.passwordFile}";
          };
          script = ''
            umask 077
            printf '%s=%s\n' ${env.variable} "$(cat "$CREDENTIALS_DIRECTORY/password")" > "$RUNTIME_DIRECTORY/env"
          '';
        };
      }
      // lib.genAttrs env.units (_: {
        requires = [ unit ];
        after = [ unit ];
        serviceConfig.EnvironmentFile = [ env.path ];
      })
    ) cfg.envFiles
  );
}
