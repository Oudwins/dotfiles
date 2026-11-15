{ config, configLib, lib, ... }:

let
  cfg = config.services.executor;
  host = "${config.my.services.executor.subdomain}.${config.my.server.location}.${config.my.domain}";
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  options.services.executor = {
    enable = lib.mkEnableOption "self-hosted Executor";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/rhyssullivan/executor-selfhost:latest";
      description = "OCI image to run for the self-hosted Executor server.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/executor";
      description = "Directory mounted at /data for Executor state.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4788;
      description = "Host port for the self-hosted Executor server.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for the Executor container.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description =
        "Environment files for optional self-hosted Executor settings.";
    };

  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 root root - -" ];

    virtualisation.oci-containers.containers.executor = {
      image = cfg.image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:4788" ];
      volumes = [ "${cfg.dataDir}:/data" ];
      environment = cfg.environment // {
        EXECUTOR_WEB_BASE_URL = "https://${host}";
      };
      environmentFiles = cfg.environmentFiles;
      extraOptions = [
        "--dns=100.100.100.100"
        ''--health-cmd=bun -e "fetch('http://127.0.0.1:4788/api/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"''
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=20s"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.nginx.virtualHosts."${host}" = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
