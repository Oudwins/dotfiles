# RustFS, an S3-compatible object store, on loopback only. Buckets, users and
# their policies are created on every switch from services.rustfs.{buckets,users};
# removing one here leaves it in RustFS. The host sets services.rustfs.environmentFile
# with RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY (the root credentials).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.rustfs;
  json = pkgs.formats.json { };
  rc = lib.getExe pkgs.unstable.rustfs-cli;
  credential = name: "user-${name}";
in
{
  # The module is only in nixpkgs-unstable.
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/web-servers/rustfs.nix" ];

  options.services.rustfs = {
    buckets = lib.mkOption {
      default = { };
      description = "Buckets to create.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            # rc's canned "download" policy also lets anyone list the bucket.
            policy = lib.mkOption {
              type = lib.types.nullOr json.type;
              default = null;
              description = "Bucket policy document, e.g. granting anonymous s3:GetObject; null keeps the bucket private.";
            };
            lifecycle = lib.mkOption {
              type = lib.types.nullOr json.type;
              default = null;
              example = {
                Rules = [
                  {
                    ID = "expire";
                    Status = "Enabled";
                    Expiration.Days = 180;
                  }
                ];
              };
              description = "Lifecycle configuration, e.g. expiring objects some days after they were last written; null removes any rules.";
            };
          };
        }
      );
    };
    users = lib.mkOption {
      default = { };
      description = "Users to create, by access key, each with its own policy.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            secretKeyFile = lib.mkOption {
              type = lib.types.str;
              description = "File holding the user's secret key (at least 8 characters).";
            };
            policy = lib.mkOption {
              inherit (json) type;
              description = "IAM policy document attached to the user, as a policy of the same name.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    services.rustfs = {
      package = pkgs.unstable.rustfs;
      settings = {
        RUSTFS_ADDRESS = lib.mkDefault "127.0.0.1:9000";
        RUSTFS_CONSOLE_ADDRESS = lib.mkDefault "127.0.0.1:9001";
      };
    };

    environment.systemPackages = [ pkgs.unstable.rustfs-cli ];

    systemd.services.rustfs-provision = {
      description = "Create RustFS buckets, users and policies";
      after = [ "rustfs.service" ];
      requires = [ "rustfs.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RC_CONFIG_DIR = "/run/rustfs-provision";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        RuntimeDirectory = "rustfs-provision";
        UMask = "0077";
        EnvironmentFile = cfg.environmentFile;
        LoadCredential = lib.mapAttrsToList (
          name: user: "${credential name}:${user.secretKeyFile}"
        ) cfg.users;
      };
      # Secrets never appear in arguments, where other users could read them:
      # the alias is written by a shell builtin and passwords are read from files.
      script = ''
        printf 'schema_version = 1\n\n[[aliases]]\nname = "local"\nendpoint = "http://%s"\naccess_key = "%s"\nsecret_key = "%s"\n' \
          ${lib.escapeShellArg cfg.settings.RUSTFS_ADDRESS} "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" \
          > "$RC_CONFIG_DIR/config.toml"
        rc() { ${rc} --no-color --no-progress "$@"; }
        rc ready local --timeout 30 >/dev/null

        ${lib.concatStrings (
          lib.mapAttrsToList (name: bucket: ''
            rc bucket create --ignore-existing local/${name}
            ${
              if bucket.policy == null then
                "rc bucket anonymous set private local/${name}"
              else
                "rc bucket anonymous set-json ${json.generate "rustfs-bucket-${name}.json" bucket.policy} local/${name}"
            }
            ${
              if bucket.lifecycle == null then
                "rc bucket lifecycle rule remove --all local/${name}"
              else
                "rc bucket lifecycle rule import local/${name} ${json.generate "rustfs-lifecycle-${name}.json" bucket.lifecycle}"
            }
          '') cfg.buckets
        )}
        ${lib.concatStrings (
          lib.mapAttrsToList (name: user: ''
            rc admin policy create local ${name} ${json.generate "rustfs-policy-${name}.json" user.policy}
            if ! rc admin user info local ${name} >/dev/null 2>&1; then
              # Replaced by the real secret below before anything can use it.
              rc admin user add local ${name} "$(${pkgs.openssl}/bin/openssl rand -hex 24)"
            fi
            rc admin user passwd local ${name} --password-file "$CREDENTIALS_DIRECTORY/${credential name}"
            rc admin policy attach local ${name} --user ${name}
          '') cfg.users
        )}
      '';
    };
  };
}
