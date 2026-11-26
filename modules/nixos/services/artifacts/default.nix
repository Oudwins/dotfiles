# Files agents publish with `artifact publish` (pkgs/artifact): a RustFS bucket
# served read-only at artifacts.<location>.<domain>, whose /_upload/ goes to the
# upload server. Agent Vault's router adds the bearer token it checks, for agents
# on this or any other machine (roles/agents.nix, agents.artifacts). A
# directory's URL serves its index.html.
{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.artifacts;
  bucket = "artifacts";
  rustfs = config.services.rustfs.settings.RUSTFS_ADDRESS;
  host = "${config.my.services.artifacts.subdomain}.${config.my.server.location}.${config.my.domain}";
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/rustfs")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  options.services.artifacts = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "https://${host}";
      readOnly = true;
      description = "Where artifacts are served and uploaded; agents.artifacts uses it when its address is null.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8095;
      description = "Loopback port of the upload server.";
    };
    expireDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Days after its last upload that an artifact's file is deleted.";
    };
    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "File holding the bearer token uploads must carry; Agent Vault injects it.";
    };
    secretKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "File holding the secret key of the RustFS user the upload server writes as.";
    };
  };

  config = {
    services.rustfs = {
      enable = true;
      buckets.${bucket} = {
        # Anyone can read an object, but not list the bucket.
        policy = {
          Version = "2012-10-17";
          Statement = [
            {
              Effect = "Allow";
              Principal.AWS = [ "*" ];
              Action = [ "s3:GetObject" ];
              Resource = [ "arn:aws:s3:::${bucket}/*" ];
            }
          ];
        };
        # Each file is deleted this long after it was last uploaded; republishing
        # uploads every file again, so it restarts the clock.
        lifecycle.Rules = [
          {
            ID = "expire";
            Status = "Enabled";
            Expiration.Days = cfg.expireDays;
          }
        ];
      };
      # Write-only: uploads can't read, list or delete other artifacts.
      users.${bucket} = {
        inherit (cfg) secretKeyFile;
        policy = {
          Version = "2012-10-17";
          Statement = [
            {
              Effect = "Allow";
              Action = [
                "s3:PutObject"
                "s3:AbortMultipartUpload"
                "s3:ListMultipartUploadParts"
              ];
              Resource = [ "arn:aws:s3:::${bucket}/*" ];
            }
          ];
        };
      };
    };

    systemd.services.artifact-upload = {
      description = "Artifact upload server";
      after = [ "rustfs-provision.service" ];
      requires = [ "rustfs-provision.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe pkgs.artifact)
          "serve"
          "-listen"
          "127.0.0.1:${toString cfg.port}"
          "-endpoint"
          "http://${rustfs}"
          "-bucket"
          bucket
          "-access-key"
          bucket
          "-secret-key-file"
          "%d/secret-key"
          "-token-file"
          "%d/token"
        ];
        LoadCredential = [
          "secret-key:${cfg.secretKeyFile}"
          "token:${cfg.tokenFile}"
        ];
        DynamicUser = true;
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
    };

    # Anonymous reads straight from the bucket, which can't be listed.
    services.nginx.virtualHosts.${host} = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."= /".return = "404";
      # Artifact IDs can't start with "_", so this never shadows one. The
      # upload server checks the token and the size.
      locations."/_upload/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/";
        extraConfig = ''
          client_max_body_size 0;
        '';
      };
      locations."/" = {
        proxyPass = "http://${rustfs}";
        extraConfig = ''
          limit_except GET { deny all; }
          rewrite ^/(.*)/$ /${bucket}/$1/index.html break;
          rewrite ^/(.*)$ /${bucket}/$1 break;
        '';
      };
    };
  };
}
