{ config, configLib, lib, pkgs, ... }:

let
  cfg = config.services.firecrawl;
  serviceName = "firecrawl";
  networkName = "${serviceName}_network";
  host =
    "${config.my.services.firecrawl.subdomain}.${config.my.server.location}.${config.my.domain}";
  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
  upstreamOpenapi = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/firecrawl/firecrawl-docs/a6563ef0771b5032825ca0e1583c9ae9abd84465/v1/api-reference/v2-openapi.json";
    hash = "sha256-t7PgLEEGPLSnCRPJ1WToX/6c7cNhnN4HsWRgef+ECaI=";
  };
  openapi = pkgs.runCommand "firecrawl-openapi.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '
      .info.title = "Firecrawl (Vela)"
      | .info.description = "OpenAPI specification for the self-hosted Firecrawl service on Vela."
      | .servers = [{ "url": "https://${host}/v2" }]
      | .paths |= with_entries(select(.key == "/scrape"
          or .key == "/search"
          or .key == "/map"
          or .key == "/crawl"
          or .key == "/crawl/active"
          or .key == "/crawl/{id}"
          or .key == "/crawl/{id}/errors"
          or .key == "/batch/scrape"
          or .key == "/batch/scrape/{id}"
          or .key == "/batch/scrape/{id}/errors"))
      | walk(if type == "object" then del(.security) else . end)
      | del(.components.securitySchemes)
    ' ${upstreamOpenapi} > $out
  '';
  networkDependency = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  options.services.firecrawl = {
    enable = lib.mkEnableOption "self-hosted Firecrawl";

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Env file with POSTGRES_PASSWORD, read by the API and Postgres containers.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Host port for the Firecrawl API.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/firecrawl";
      description = "Directory for persistent Firecrawl state.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for Firecrawl.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir}/postgres 0777 root root - -" ];

    systemd.services =
      lib.genAttrs [
        "${serviceName}-playwright"
        "${serviceName}-redis"
        "${serviceName}-rabbitmq"
        "${serviceName}-postgres"
      ]
        (_: networkDependency)
      // {
        "${serviceName}-network" = {
          description = "Create Docker network for ${serviceName}";
          after = [ "docker.service" "docker.socket" ];
          requires = [ "docker.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            ${dockerBin} network inspect ${networkName} >/dev/null 2>&1 || ${dockerBin} network create ${networkName} --subnet 172.22.0.0/16
          '';
        };

        "${serviceName}" = networkDependency // {
          after = networkDependency.after ++ [
            "${serviceName}-playwright.service"
            "${serviceName}-redis.service"
            "${serviceName}-rabbitmq.service"
            "${serviceName}-postgres.service"
          ];
          requires = networkDependency.requires ++ [
            "${serviceName}-playwright.service"
            "${serviceName}-redis.service"
            "${serviceName}-rabbitmq.service"
            "${serviceName}-postgres.service"
          ];
          preStart = ''
            for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
              if ${dockerBin} exec ${serviceName}-rabbitmq rabbitmq-diagnostics -q check_running >/dev/null 2>&1 \
                && ${dockerBin} exec ${serviceName}-postgres pg_isready -U postgres -d postgres >/dev/null 2>&1; then
                exit 0
              fi
              sleep 1
            done

            echo "Timed out waiting for Firecrawl dependencies" >&2
            exit 1
          '';
        };
      };

    virtualisation.oci-containers.containers = {
      firecrawl = {
        image = "ghcr.io/firecrawl/firecrawl@sha256:4749476b5def369906546e4dbe2c8e767559173635cac5d4a6b26e1ea42dbc46";
        autoStart = true;
        serviceName = serviceName;
        ports = [ "127.0.0.1:${toString cfg.port}:3002" ];
        cmd = [
          "node"
          "dist/src/harness.js"
          "--start-docker"
        ];
        environment = {
          HOST = "0.0.0.0";
          PORT = "3002";
          ENV = "local";
          REDIS_URL = "redis://${serviceName}-redis:6379";
          REDIS_RATE_LIMIT_URL = "redis://${serviceName}-redis:6379";
          PLAYWRIGHT_MICROSERVICE_URL = "http://${serviceName}-playwright:3000/scrape";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "postgres";
          POSTGRES_HOST = "${serviceName}-postgres";
          POSTGRES_PORT = "5432";
          NUQ_RABBITMQ_URL = "amqp://${serviceName}-rabbitmq:5672";
          USE_DB_AUTHENTICATION = "false";
          NUM_WORKERS_PER_QUEUE = "4";
          CRAWL_CONCURRENT_REQUESTS = "6";
          MAX_CONCURRENT_JOBS = "3";
          BROWSER_POOL_SIZE = "4";
        } // cfg.environment;
        environmentFiles = [ cfg.environmentFile ];
        networks = [ networkName ];
        dependsOn = [
          "${serviceName}-playwright"
          "${serviceName}-redis"
          "${serviceName}-rabbitmq"
          "${serviceName}-postgres"
        ];
        extraOptions = [
          "--cpus=4"
          "--memory=6g"
          "--memory-swap=6g"
          "--ulimit=nofile=65535:65535"
          ''--health-cmd=node -e "fetch('http://127.0.0.1:3002/v0/health/readiness').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"''
          "--health-interval=30s"
          "--health-timeout=5s"
          "--health-retries=5"
          "--health-start-period=60s"
        ];
      };

      firecrawl-playwright = {
        image = "ghcr.io/firecrawl/playwright-service@sha256:bd504f4f1068bbba36599bea38f4971d4d2e6b09a030a8b19baf0021ddbaedbc";
        autoStart = true;
        serviceName = "${serviceName}-playwright";
        environment = {
          PORT = "3000";
          MAX_CONCURRENT_PAGES = "6";
        };
        networks = [ networkName ];
        extraOptions = [
          "--cpus=2"
          "--memory=4g"
          "--memory-swap=4g"
          "--tmpfs=/tmp/.cache:noexec,nosuid,size=1g"
        ];
      };

      firecrawl-redis = {
        image = "redis:alpine";
        autoStart = true;
        serviceName = "${serviceName}-redis";
        cmd = [
          "redis-server"
          "--bind"
          "0.0.0.0"
        ];
        networks = [ networkName ];
      };

      firecrawl-rabbitmq = {
        image = "rabbitmq:3-management";
        autoStart = true;
        serviceName = "${serviceName}-rabbitmq";
        cmd = [ "rabbitmq-server" ];
        networks = [ networkName ];
      };

      firecrawl-postgres = {
        image = "ghcr.io/firecrawl/nuq-postgres@sha256:4ca6718b2cef40404b046db5cd37ae45db3e44d1a5750c80522f3587a5b193d5";
        autoStart = true;
        serviceName = "${serviceName}-postgres";
        environment = {
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "postgres";
        };
        environmentFiles = [ cfg.environmentFile ];
        volumes = [ "${cfg.dataDir}/postgres:/var/lib/postgresql/data" ];
        networks = [ networkName ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.nginx.virtualHosts."${host}" = {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."= /openapi.json" = {
        alias = openapi;
        extraConfig = "default_type application/json;";
      };
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          client_max_body_size 10m;
          proxy_read_timeout 300s;
        '';
      };
    };
  };
}
