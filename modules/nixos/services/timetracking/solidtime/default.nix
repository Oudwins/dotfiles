{
  config,
  configLib,
  lib,
  pkgs,
  ...
}@args:
let
  #######################################
  # WORKING!!!
  # Based on: https://github.com/solidtime-io/self-hosting-examples/tree/main/1-docker-with-database
  # docs: https://docs.solidtime.io/self-hosting/guides/docker
  #
  # Useful commands:
  # docker exec solidtime_scheduler php artisan self-host:generate-keys # generates the secrets for auth on the app
  # docker exec solidtime_scheduler php artisan migrate --force # migrates the db
  # docker exec solidtime_scheduler php artisan admin:user:create "tmx tmx" "tm@tristanmayo.com" --verify-email # creates an admin user
  # WHY IS IT DOWN?:
  # - The docker network was removed by docker prune. Verify with: sudo docker network ls | grep solidtime_network
  #######################################
  port = 8888;
  dbPort = 5432;
  serviceName = "solidtime";
  host = "${config.my.services.solidtime.subdomain}.${config.my.server.location}.${config.my.domain}";
  # Tags: https://hub.docker.com/r/solidtime/solidtime/tags
  tag = "0.10.0";
  image = "solidtime/solidtime:${tag}";
  dataDir = "${config.my.services.baseDataDir}/solidtime";

  environmentVariables = {
    #########################################################
    # .env variables
    #########################################################
    APP_DOMAIN = "${host}";
    FORWARD_APP_PORT = "${toString port}";
    FORWARD_DB_PORT = "${toString dbPort}";

    #########################################################
    # laravel.env variables
    #########################################################
    APP_ENABLE_REGISTRATION = "false"; # default
    APP_NAME = serviceName;
    VITE_APP_NAME = serviceName;
    APP_ENV = "production";
    APP_DEBUG = "false";
    APP_URL = "https://${host}";
    APP_FORCE_HTTPS = "false";
    TRUSTED_PROXIES = "0.0.0.0/0,2000:0:0:0:0:0:0:0/3";

    # Authentication - THESE ARE INSIDE SOPS SECRETS
    # APP_KEY="";
    # PASSPORT_PRIVATE_KEY="";
    # PASSPORT_PUBLIC_KEY="";
    SUPER_ADMINS = ""; # THIS ONE ISNT BC NOT SURE WHAT IT IS

    # Logging
    LOG_CHANNEL = "stderr_daily";
    LOG_LEVEL = "debug";

    # Database
    DB_CONNECTION = "pgsql";
    DB_HOST = "${serviceName}_db";
    DB_PORT = "5432";
    DB_SSLMODE = "require";
    DB_DATABASE = serviceName;
    DB_USERNAME = serviceName;
    # DB_PASSWORD comes from my.solidtime.environmentFile

    # Mail
    MAIL_MAILER = "smtp";
    MAIL_HOST = "";
    MAIL_PORT = "";
    MAIL_ENCRYPTION = "tls";
    MAIL_FROM_ADDRESS = "no-reply@your-domain.com";
    MAIL_FROM_NAME = serviceName;
    MAIL_USERNAME = "";
    MAIL_PASSWORD = "";

    # Queue
    QUEUE_CONNECTION = "database";

    # File storage
    FILESYSTEM_DISK = "local";
    PUBLIC_FILESYSTEM_DISK = "public";

    # Services
    GOTENBERG_URL = "http://${serviceName}_gotenberg:3000";
  };

  networkName = "${serviceName}_network";
  user = "1000";
  group = "100";
in
{

  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    (configLib.relativeToRoot "modules/nixos/services/containers")
    ./backup.nix
  ];

  options.my.solidtime = {
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Env file for the app containers: APP_KEY, PASSPORT_PRIVATE_KEY, PASSPORT_PUBLIC_KEY and DB_PASSWORD.";
    };
    dbEnvironmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Env file for the database container: POSTGRES_PASSWORD and PGPASSWORD.";
    };
  };

  config = {

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0777 ${user} ${group} -"
    # "d ${dataDir}/storage 0777 ${user} ${group} -"
    "d ${dataDir}/logs 0777 ${user} ${group} -"
    "d ${dataDir}/storage_app 0777 ${user} ${group} -"
  ];

  systemd.services."${serviceName}-network" = {
    description = "Create Docker network for ${serviceName}";
    after = [
      "docker.service"
      "docker.socket"
    ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script =
      let
        docker = config.virtualisation.oci-containers.backend;
        dockerBin = "${pkgs.${docker}}/bin/${docker}";
      in
      ''
        ${dockerBin} network inspect ${networkName} >/dev/null 2>&1 || ${dockerBin} network create ${networkName} --subnet 172.20.0.0/16
      '';
  };

  systemd.services."${serviceName}_app" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  systemd.services."${serviceName}_scheduler" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  systemd.services."${serviceName}_queue" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  systemd.services."${serviceName}_db" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  systemd.services."${serviceName}_gotenberg" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  virtualisation.oci-containers.containers = {
    solidtime_app = {
      image = image;
      user = "${user}:${group}";
      autoStart = true;
      serviceName = "${serviceName}_app";
      ports = [
        "${toString port}:8000"
      ];
      volumes = [
        # "${dataDir}/storage:/var/www/html/storage"
        "${dataDir}/logs:/var/www/html/storage/logs"
        "${dataDir}/storage_app:/var/www/html/storage/app"
      ];
      environment = {
        CONTAINER_MODE = "http";
        # VERY IMPORTANT THIS IS NOT SET TO TRUE. OTHERWISE ON CONTAINER RESTART WILL NUKE THE DB!
        # AUTO_DB_MIGRATE = "true"; # Automatically ensures DB has all the right tables and shit on container startup
      }
      // environmentVariables;
      environmentFiles = [
        config.my.solidtime.environmentFile
      ];
      networks = [ networkName ];
      dependsOn = [ "${serviceName}_db" ];
    };

    solidtime_scheduler = {
      image = image;
      user = "${user}:${group}";
      autoStart = true;
      serviceName = "${serviceName}_scheduler";
      volumes = [
        # "${dataDir}/storage:/var/www/html/storage"
        "${dataDir}/logs:/var/www/html/storage/logs"
        "${dataDir}/storage_app:/var/www/html/storage/app"
      ];

      environment = {
        CONTAINER_MODE = "scheduler";
      }
      // environmentVariables;
      environmentFiles = [
        config.my.solidtime.environmentFile
      ];
      networks = [ networkName ];
      dependsOn = [ "${serviceName}_db" ];
    };

    solidtime_queue = {
      image = image;
      user = "${user}:${group}";
      autoStart = true;
      serviceName = "${serviceName}_queue";
      volumes = [
        # "${dataDir}/storage:/var/www/html/storage"
        "${dataDir}/logs:/var/www/html/storage/logs"
        "${dataDir}/storage_app:/var/www/html/storage/app"
      ];

      environment = {
        CONTAINER_MODE = "worker";
        WORKER_COMMAND = "php /var/www/html/artisan queue:work";
      }
      // environmentVariables;

      environmentFiles = [
        config.my.solidtime.environmentFile
      ];

      networks = [ networkName ];
      dependsOn = [ "${serviceName}_db" ];
    };

    solidtime_db = {
      image = "postgres:15";
      autoStart = true;
      serviceName = "${serviceName}_db";
      volumes = [
        "${dataDir}/db:/var/lib/postgresql/data"
      ];
      environment = {
        POSTGRES_DB = serviceName;
        POSTGRES_USER = serviceName;
      };
      environmentFiles = [ config.my.solidtime.dbEnvironmentFile ];
      networks = [ networkName ];
    };

    solidtime_gotenberg = {
      image = "gotenberg/gotenberg:8";
      autoStart = true;
      serviceName = "${serviceName}_gotenberg";
      networks = [ networkName ];
    };
  };

  # Set up SSL + Domain
  services.nginx.virtualHosts."${host}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true; # Enable if needed
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
      '';
    };
  };

  my.dashboard.services.solidtime = {
    label = "Solidtime";
    description = "Time tracking";
    url = "https://${host}";
    category = "apps";
    icon = "solidtime";
  };
  };
}
