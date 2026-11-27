# Files agents publish with `artifact publish` (pkgs/artifact): a RustFS bucket
# served read-only at artifacts.<location>.<domain>, whose /_upload/ goes to the
# upload server. Agent Vault's router adds the bearer token it checks, for agents
# on this or any other machine (roles/agents.nix, agents.artifacts). A
# directory's URL serves its index.html.
#
# Unlike other modules, this one declares its own sops secrets: every host that
# runs it uses the same ones, from nix-secrets sops/shared/artifacts.yaml. The
# token there is also the one agents.artifacts has Agent Vault send.
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
  # Largest file accepted, in bytes; nginx and the upload server both enforce it.
  maxSize = 256 * 1024 * 1024;
  rustfs = config.services.rustfs.settings.RUSTFS_ADDRESS;
  secret = name: config.sops.secrets."artifacts/${name}".path;
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
  };

  config = {
    sops.secrets =
      lib.genAttrs [ "artifacts/rustfs-env" "artifacts/rustfs-secret-key" "artifacts/token" ]
        (_: {
          sopsFile = configLib.secretFile "sops/shared/artifacts.yaml";
        });

    services.rustfs = {
      enable = true;
      # RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY, the root credentials.
      environmentFile = secret "rustfs-env";
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
        secretKeyFile = secret "rustfs-secret-key";
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
          "-max-size"
          (toString maxSize)
        ];
        LoadCredential = [
          "secret-key:${secret "rustfs-secret-key"}"
          # The bearer token uploads must carry; Agent Vault injects it.
          "token:${secret "token"}"
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
      # Artifact IDs can't start with "_", so this never shadows one. Bodies
      # stream to the upload server, which rejects a missing token before
      # reading them.
      locations."/_upload/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/";
        extraConfig = ''
          client_max_body_size ${toString maxSize};
          proxy_request_buffering off;
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
