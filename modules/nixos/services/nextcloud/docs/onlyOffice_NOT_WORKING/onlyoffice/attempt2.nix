{
  config,
  lib,
  pkgs,
  ...
}:
let
  jsonSecret = "test_secret";
in
{
  # this is adapted from docker file found in:
  #  https://github.com/ONLYOFFICE/Docker-DocumentServer
  virtualisation.oci-containers = {
    backend = "docker";

    containers = {
      # PostgreSQL Database
      onlyoffice-postgresql = {
        image = "postgres:15";
        autoStart = true;

        environment = {
          POSTGRES_DB = "onlyoffice";
          POSTGRES_USER = "onlyoffice";
          POSTGRES_HOST_AUTH_METHOD = "trust";
        };

        volumes = [
          "postgresql_data:/var/lib/postgresql"
        ];

        extraOptions = [
          "--health-cmd=pg_isready -U onlyoffice"
          "--health-interval=10s"
          "--health-retries=3"
          "--health-start-period=10s"
          "--health-timeout=10s"
          "--restart=always"
        ];
      };

      # RabbitMQ Message Queue
      onlyoffice-rabbitmq = {
        image = "rabbitmq:3";
        autoStart = true;

        extraOptions = [
          "--health-cmd=rabbitmq-diagnostics status"
          "--health-interval=10s"
          "--health-retries=3"
          "--health-start-period=10s"
          "--health-timeout=10s"
          "--restart=always"
        ];
      };

      # OnlyOffice Document Server
      onlyoffice-documentserver = {
        image = "onlyoffice/documentserver";
        autoStart = true;

        environment = {
          DB_TYPE = "postgres";
          DB_HOST = "onlyoffice-postgresql";
          DB_PORT = "5432";
          DB_NAME = "onlyoffice";
          DB_USER = "onlyoffice";
          AMQP_URI = "amqp://guest:guest@onlyoffice-rabbitmq";
          # Uncomment and modify these for JWT validation
          JWT_ENABLED = "true";
          JWT_SECRET = jsonSecret;
          JWT_HEADER = "Authorization";
          JWT_IN_BODY = "true";
        };

        ports = [
          "89:80" # changed ports here to avoid conflicts
          "449:443"
        ];

        volumes = [
          "/var/www/onlyoffice/Data"
          "/var/log/onlyoffice"
          "/var/lib/onlyoffice/documentserver/App_Data/cache/files"
          "/var/www/onlyoffice/documentserver-example/public/files"
          "/usr/share/fonts"
        ];

        dependsOn = [
          "onlyoffice-postgresql"
          "onlyoffice-rabbitmq"
        ];

        extraOptions = [
          "--health-cmd=curl -f http://localhost:8000/info/info.json"
          "--health-interval=30s"
          "--health-retries=5"
          "--health-start-period=60s"
          "--health-timeout=10s"
          "--stdin-open"
          "--restart=always"
          "--stop-timeout=60"
        ];
      };
    };
  };

  # Ensure curl is available for health checks
  environment.systemPackages = with pkgs; [
    curl
  ];

  # Create systemd services to ensure proper startup order and dependencies
  systemd.services = {
    "docker-onlyoffice-postgresql" = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    "docker-onlyoffice-rabbitmq" = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    "docker-onlyoffice-documentserver" = {
      wants = [
        "network-online.target"
        "docker-onlyoffice-postgresql.service"
        "docker-onlyoffice-rabbitmq.service"
      ];
      after = [
        "network-online.target"
        "docker-onlyoffice-postgresql.service"
        "docker-onlyoffice-rabbitmq.service"
      ];
      wantedBy = [ "multi-user.target" ];
    };
  };

  services.nginx.virtualHosts."${"onlyoffice"}.${config.my.server.location}.${config.my.domain}" = {
    #enableACME = true;
    #forceSSL = true;
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;

    # OnlyOffice specific settings
    extraConfig = ''
      client_max_body_size 100m;
    '';

    locations."/" = {
      proxyPass = "http://localhost:89";
      proxyWebsockets = true;

      # Essential headers for OnlyOffice
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # Timeouts for document processing
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffer settings for large documents
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };

    # Special handling for websocket connections (if needed)
    locations."/ws" = {
      proxyPass = "http://localhost:89/ws";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
