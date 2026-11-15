{ config, configLib, lib, pkgs, ... }:

let
  port = 5230;
  serviceName = "memos";
  host =
    "${config.my.services.memos.subdomain}.${config.my.server.location}.${config.my.domain}";
  dataDir = "${config.my.services.baseDataDir}/${serviceName}";
  networkName = "${serviceName}_network";
  docker = config.virtualisation.oci-containers.backend;
  dockerBin = "${pkgs.${docker}}/bin/${docker}";
in {
  imports = [
    ./backup.nix
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  options.my.memos.environmentFile = lib.mkOption {
    type = lib.types.path;
    description = "Env file with POSTGRES_PASSWORD and MEMOS_DSN, read by both containers.";
  };

  config = {

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0777 root root -"
    "d ${dataDir}/app 0777 root root -"
    "d ${dataDir}/db 0777 root root -"
  ];

  systemd.services."${serviceName}-network" = {
    description = "Create Docker network for ${serviceName}";
    after = [ "docker.service" "docker.socket" ];
    requires = [ "docker.service" ];
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${dockerBin} network inspect ${networkName} >/dev/null 2>&1 || ${dockerBin} network create ${networkName} --subnet 172.21.0.0/16
    '';
  };

  systemd.services."${serviceName}" = {
    after = [ "${serviceName}_db.service" ];
    requires = [ "${serviceName}_db.service" ];
    preStart = ''
      for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
        if ${dockerBin} exec ${serviceName}_db pg_isready -U memos -d memos >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done

      echo "Timed out waiting for ${serviceName}_db to accept connections" >&2
      exit 1
    '';
  };

  systemd.services."${serviceName}_db" = {
    after = [ "${serviceName}-network.service" ];
    requires = [ "${serviceName}-network.service" ];
  };

  virtualisation.oci-containers.containers = {
    memos = {
      image = "neosmemo/memos:0.29.1";
      autoStart = true;
      serviceName = serviceName;
      ports = [ "${toString port}:5230" ];
      environment = {
        MEMOS_DRIVER = "postgres";
        MEMOS_INSTANCE_URL = "https://${host}";
      };
      environmentFiles = [ config.my.memos.environmentFile ];
      volumes = [ "${dataDir}/app:/var/opt/memos" ];
      networks = [ networkName ];
      dependsOn = [ "${serviceName}_db" ];
    };

    memos_db = {
      image = "postgres:15";
      autoStart = true;
      serviceName = "${serviceName}_db";
      environment = {
        POSTGRES_DB = "memos";
        POSTGRES_USER = "memos";
      };
      environmentFiles = [ config.my.memos.environmentFile ];
      volumes = [ "${dataDir}/db:/var/lib/postgresql/data" ];
      networks = [ networkName ];
    };
  };

  services.nginx.virtualHosts."${host}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  my.dashboard.services.memos = {
    label = "Memos";
    description = "Notes and knowledge base";
    url = "https://${host}";
    category = "apps";
    icon = "mdi-note-text";
  };
  };
}
