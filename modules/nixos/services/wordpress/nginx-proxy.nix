{
  config,
  configLib,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.nginxProxyAutomation;
  # AI GENERATED BASED ON https://github.com/evertramos/nginx-proxy-automation/tree/main
  # Not tried to see if it works.
  # Basically runs a few nginx containers and checks docker containers that have certain env variables set the configures the nginx container to proxy to those containers.
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  options.my.nginxProxyAutomation = {
    enable = lib.mkEnableOption "Enable nginx-proxy-automation stack (nginx + docker-gen + acme-companion)";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.my.services.baseDataDir}/nginx-proxy-automation";
      description = "Base directory for nginx-proxy-automation persistent data (conf.d, vhost.d, html, certs, htpasswd, acme.sh).";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "proxy";
      description = "External Docker network name used by the reverse proxy.";
    };

    # Bind IP and ports on the host
    bindIPv4 = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host IPv4 to bind published ports (use 0.0.0.0 for all).";
    };
    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 80;
      description = "Host HTTP port to publish.";
    };
    httpsPort = lib.mkOption {
      type = lib.types.int;
      default = 443;
      description = "Host HTTPS port to publish.";
    };

    # Images/tags
    nginxTag = lib.mkOption {
      type = lib.types.str;
      default = "stable-alpine";
      description = "nginx image tag (nginx:<tag>).";
    };
    dockerGenTag = lib.mkOption {
      type = lib.types.str;
      default = "0.7.7";
      description = "docker-gen image tag (nginxproxy/docker-gen:<tag>).";
    };
    acmeCompanionTag = lib.mkOption {
      type = lib.types.str;
      default = "2.1";
      description = "acme-companion image tag (nginxproxy/acme-companion:<tag>).";
    };

    # nginx-proxy and ACME tuning
    sslPolicy = lib.mkOption {
      type = lib.types.str;
      default = "Mozilla-Intermediate";
      description = "SSL policy passed to nginx-proxy (SSL_POLICY).";
    };
    defaultEmail = lib.mkOption {
      type = lib.types.str;
      default = "mail@yourdomain.tld";
      description = "Default email used by ACME companion (DEFAULT_EMAIL).";
    };
    defaultHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional DEFAULT_HOST for nginx-proxy (routes unmatched requests).";
    };
    enableIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set ENABLE_IPV6=\"true\" for nginx-proxy container.";
    };

    # Paths
    dockerSocketPath = lib.mkOption {
      type = lib.types.path;
      default = "/var/run/docker.sock";
      description = "Path to Docker socket (for docker-gen and acme-companion).";
    };
    nginxTemplatePath = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.dataDir}/nginx.tmpl";
      description = "Path to nginx.tmpl used by docker-gen. If missing, it will be fetched from upstream at activation.";
    };

    htmlIndexContent = lib.mkOption {
      type = lib.types.str;
      default = "nginx-proxy-automation is running";
      description = "Default /index.html content to place under html dir if missing (for quick smoke tests).";
    };

    # Optional extra environment for acme-companion (e.g., DNS-01)
    acmeEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for acme-companion (e.g., ACME_CHALLENGE, ACMESH_DNS_API_CONFIG via env file).";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      docker = config.virtualisation.oci-containers.backend;
      dockerBin = "${pkgs.${docker}}/bin/${docker}";

      # Canonical container names
      webName = "nginx-proxy-automation-web";
      genName = "nginx-proxy-automation-gen";
      leName = "nginx-proxy-automation-letsencrypt";

      confDir = "${cfg.dataDir}/conf.d";
      vhostDir = "${cfg.dataDir}/vhost.d";
      htmlDir = "${cfg.dataDir}/html";
      certsDir = "${cfg.dataDir}/certs";
      htpasswdDir = "${cfg.dataDir}/htpasswd";
      acmeDir = "${cfg.dataDir}/acme.sh";
    in
    {
      # Ensure external network exists
      system.activationScripts.mkProxyNetwork = ''
        ${dockerBin} network inspect ${cfg.networkName} >/dev/null 2>&1 || \
          ${dockerBin} network create ${cfg.networkName} --subnet ${configLib.networking.docker.getSubnet cfg.networkName}
      '';

      # Persistent dirs
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
        "d ${confDir} 0755 root root -"
        "d ${vhostDir} 0755 root root -"
        "d ${htmlDir} 0755 root root -"
        "d ${certsDir} 0755 root root -"
        "d ${htpasswdDir} 0755 root root -"
        "d ${acmeDir} 0755 root root -"
      ];

      # Seed upstream template and a simple index.html if missing
      system.activationScripts.seedNginxProxyAutomation =
        let
          curl = "${pkgs.curl}/bin/curl";
          upstreamTemplate = "https://raw.githubusercontent.com/evertramos/nginx-proxy-automation/main/nginx.tmpl";
        in
        ''
          set -eu
          if [ ! -s "${cfg.nginxTemplatePath}" ]; then
            echo "[nginx-proxy-automation] Fetching nginx.tmpl from upstream..."
            ${curl} -fsSL "${upstreamTemplate}" -o "${cfg.nginxTemplatePath}"
          fi
          if [ ! -s "${htmlDir}/index.html" ]; then
            echo "${cfg.htmlIndexContent}" > "${htmlDir}/index.html"
          fi
        '';

      # Containers
      virtualisation.oci-containers.containers = {
        ${webName} = {
          autoStart = true;
          serviceName = webName;
          image = "nginx:${cfg.nginxTag}";
          ports = [
            "${cfg.bindIPv4}:${toString cfg.httpPort}:80"
            "${cfg.bindIPv4}:${toString cfg.httpsPort}:443"
          ];
          volumes = [
            "${confDir}:/etc/nginx/conf.d"
            "${vhostDir}:/etc/nginx/vhost.d"
            "${htmlDir}:/usr/share/nginx/html"
            "${certsDir}:/etc/nginx/certs:ro"
            "${htpasswdDir}:/etc/nginx/htpasswd:ro"
          ];
          environment = {
            SSL_POLICY = cfg.sslPolicy;
          }
          // lib.optionalAttrs (cfg.defaultHost != null) { DEFAULT_HOST = cfg.defaultHost; }
          // lib.optionalAttrs cfg.enableIPv6 { ENABLE_IPV6 = "true"; };
          networks = [ cfg.networkName ];
          extraOptions = [
            "--restart=always"
            "--label=com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy=true"
            "--log-driver=json-file"
            "--log-opt=max-size=4m"
            "--log-opt=max-file=10"
          ];
        };

        ${genName} = {
          autoStart = true;
          serviceName = genName;
          image = "nginxproxy/docker-gen:${cfg.dockerGenTag}";
          cmd = [
            "-notify-sighup"
            webName
            "-watch"
            "-wait"
            "5s:30s"
            "/etc/docker-gen/templates/nginx.tmpl"
            "/etc/nginx/conf.d/default.conf"
          ];
          volumes = [
            "${confDir}:/etc/nginx/conf.d"
            "${vhostDir}:/etc/nginx/vhost.d"
            "${htmlDir}:/usr/share/nginx/html"
            "${certsDir}:/etc/nginx/certs:ro"
            "${htpasswdDir}:/etc/nginx/htpasswd:ro"
            "${cfg.dockerSocketPath}:/tmp/docker.sock:ro"
            "${cfg.nginxTemplatePath}:/etc/docker-gen/templates/nginx.tmpl:ro"
          ];
          networks = [ cfg.networkName ];
          dependsOn = [ webName ];
          extraOptions = [
            "--restart=always"
            "--log-driver=json-file"
            "--log-opt=max-size=2m"
            "--log-opt=max-file=10"
          ];
        };

        ${leName} = {
          autoStart = true;
          serviceName = leName;
          image = "nginxproxy/acme-companion:${cfg.acmeCompanionTag}";
          environment = {
            NGINX_DOCKER_GEN_CONTAINER = genName;
            NGINX_PROXY_CONTAINER = webName;
            DEFAULT_EMAIL = cfg.defaultEmail;
          }
          // cfg.acmeEnvironment;
          volumes = [
            "${confDir}:/etc/nginx/conf.d"
            "${vhostDir}:/etc/nginx/vhost.d"
            "${htmlDir}:/usr/share/nginx/html"
            "${certsDir}:/etc/nginx/certs:rw"
            "${acmeDir}:/etc/acme.sh"
            "${cfg.dockerSocketPath}:/var/run/docker.sock:ro"
          ];
          networks = [ cfg.networkName ];
          dependsOn = [
            genName
            webName
          ];
          extraOptions = [
            "--restart=always"
            "--log-driver=json-file"
            "--log-opt=max-size=2m"
            "--log-opt=max-file=10"
          ];
        };
      };
    }
  );
}
