{
  config,
  configLib,
  pkgs,
  lib,
  ...
}:
let
  # COULDNT GET THIS TO WORK.
  # The issue is that wordpress redirects to localhost when I enable https. Tried changing the wp-config.php but no luck.
  # This is because nginx + apache server don't seem to play well and wordpress is shit and doesn't respect the nginx headers config
  # My next ideas are
  # - This -> https://github.com/evertramos/docker-wordpress/tree/main
  #   - Basically try to replicate this to see if I can get it to work. First try exclusively through docker compose.
  #   - Then I can see if I can get it to work with having nginx with nix. If not maybe also dockerize nginx and try that
  # - or this -> https://github.com/mjstealey/wordpress-nginx-docker
  # - Try the server automation / nginx automation
  #   - https://github.com/evertramos/server-automation
  #   - https://github.com/evertramos/nginx-proxy-automation/tree/main
  #   - https://www.youtube.com/watch?v=V360BeEU9_M&list=PLLET0MJVt0Ud2czqkzmMk8083UPns5bHH&index=10
  #   - already have a module for this but not tested
  # -  Try dokploy
  # - Look at this ->
  # - https://github.com/gioamato/stateless-wordpress
  # - https://www.reddit.com/r/docker/comments/tj8qp2/comment/i1jhp7w/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
  # Look at what the nix code for wordpress does
  # - https://carlosvaz.com/posts/setting-up-a-wordpress-website-on-nixos/

  cfgs = lib.filterAttrs (_: value: value.enable) config.my.wordpress_sites;

  # TODO
  # BACKUPS!
  # - Basically just the mysql db and wp data folder
  # Email server
in
{

  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    ./ssl.nix
  ];

  options.my.wordpress_sites = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "";
          domains = lib.mkOption {
            type = lib.types.listOf lib.types.str;
          };
          environmentFiles = lib.mkOption {
            type = lib.types.listOf lib.types.path;
          };

          wpContainerTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
          };
          mysqlContainerTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
          };

          redisContainerTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
          };

        };
      }
    );
    default = { };
  };

  #lib.foldl' lib.recursiveMerge {} attrSets;

  config = lib.mkIf (cfgs != { }) (
    let
      # Docker configuration
      docker = config.virtualisation.oci-containers.backend;
      dockerBin = "${pkgs.${docker}}/bin/${docker}";

      # Generate lists for all configuration pieces
      activationScripts = lib.mapAttrsToList (name: _: {
        ${"mkNetwork_${name}"} = ''
          ${dockerBin} network inspect network_${name} >/dev/null 2>&1 || ${dockerBin} network create network_${name} --subnet ${configLib.networking.docker.getSubnet "network_${name}"}
        '';
      }) cfgs;

      users = lib.mapAttrsToList (name: _: {
        ${"wordpress_${name}"} = {
          uid = configLib.users.genId "wordpress_${name}";
          isSystemUser = true;
          group = "wordpress_${name}";
        };
        ${"db_${name}"} = {
          uid = configLib.users.genId "db_${name}";
          isSystemUser = true;
          group = "db_${name}";
        };
      }) cfgs;

      groups = lib.mapAttrsToList (name: _: {
        ${"wordpress_${name}"} = {
          gid = configLib.users.genId "wordpress_${name}";
        };
        ${"db_${name}"} = {
          gid = configLib.users.genId "db_${name}";
        };
      }) cfgs;

      tmpfilesRules = lib.mapAttrsToList (
        name: _:
        let
          dataDir = "${config.my.services.baseDataDir}/wordpress-${name}";
          wpDataDir = "${dataDir}/wordpress";
          mysqlDataDir = "${dataDir}/mysql";
          redisDataDir = "${dataDir}/redis";
          wordpressUserName = "wordpress_${name}";
          dbUserName = "db_${name}";
        in
        [
          "d ${dataDir} 0777 root root -"
          "d ${wpDataDir} 0775 ${wordpressUserName} ${wordpressUserName} -"
          "d ${mysqlDataDir} 0775 ${dbUserName} ${dbUserName} -"
          "d ${redisDataDir} 0775 ${wordpressUserName} ${wordpressUserName} -"
        ]
      ) cfgs;

      containers = lib.mapAttrsToList (
        name: cfg:
        let
          networkName = "network_${name}";
          wordpressUserName = "wordpress_${name}";
          wordpressUserID = configLib.users.genId wordpressUserName;
          dbUserName = "db_${name}";
          dbUserID = configLib.users.genId dbUserName;
          dataDir = "${config.my.services.baseDataDir}/wordpress-${name}";
          wpDataDir = "${dataDir}/wordpress";
          mysqlDataDir = "${dataDir}/mysql";
          redisDataDir = "${dataDir}/redis";
          wordpressPort = configLib.networking.getPort name;
          domain = builtins.head cfg.domains;
          domainWithProtocol = "https://${domain}";
        in
        {
          "${name}_wordpress" = {
            image = "wordpress:${cfg.wpContainerTag}";
            autoStart = true;
            serviceName = "${name}_wordpress";
            user = "${toString wordpressUserID}:${toString wordpressUserID}";
            environment = {
              WORDPRESS_DB_HOST = "${name}_mysql:3306";
              WORDPRESS_REDIS_HOST = "${name}_redis:6379";
              # Ensure WordPress builds URLs using the external reverse-proxy domain, not localhost
              # But adding this variables not working for some reason.
              WORDPRESS_CONFIG_EXTRA = ''
                define('WP_HOME', '${domainWithProtocol}');
                define('WP_SITEURL', '${domainWithProtocol}');
              '';
            };
            environmentFiles = cfg.environmentFiles;
            volumes = [
              "${wpDataDir}:/var/www/html"
            ];
            networks = [ networkName ];
            dependsOn = [ "${name}_mysql" ];
            ports = [
              "${toString wordpressPort}:${toString 80}"
            ];
          };

          "${name}_mysql" = {
            image = "mysql:${cfg.mysqlContainerTag}";
            autoStart = true;
            serviceName = "${name}_mysql";
            user = "${toString dbUserID}:${toString dbUserID}";
            environmentFiles = cfg.environmentFiles;
            volumes = [
              "${mysqlDataDir}:/var/lib/mysql"
            ];
            networks = [ networkName ];
          };

          "${name}_redis" = {
            image = "redis:${cfg.redisContainerTag}";
            user = "${toString wordpressUserID}:${toString wordpressUserID}";
            volumes = [
              "${redisDataDir}:/data"
            ];
            autoStart = true;
            serviceName = "${name}_redis";
            networks = [ networkName ];
          };
        }
      ) cfgs;

      sslCerts = lib.mapAttrsToList (
        _: cfg:
        lib.listToAttrs (
          builtins.map (domain: {
            name = domain;
            value = {
              domain = domain;
            };
          }) cfg.domains
        )
      ) cfgs;

      virtualHosts = lib.mapAttrsToList (
        name: cfg:
        let
          wordpressPort = configLib.networking.getPort name;
        in
        lib.listToAttrs (
          builtins.map (domain: {
            name = domain;
            value = {
              useACMEHost = domain;
              addSSL = true;
              locations."/" = {
                proxyPass = "http://localhost:${toString wordpressPort}";
                proxyWebsockets = true; # Enable if needed
              };

              # extraConfig = ''
              #   proxy_set_header Host $host;
              #   proxy_set_header X-Real-IP $remote_addr;
              #   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              #   proxy_set_header X-Forwarded-Proto $scheme;
              #   proxy_set_header X-Forwarded-Host $host;
              #   proxy_set_header X-Forwarded-Port $server_port;
              # '';
              # try_files $uri $uri/ =404; # redirect /bla to /bla/
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Host $host;
                proxy_set_header X-Forwarded-Port $server_port;
                proxy_redirect off;
              '';

            };
          }) cfg.domains
        )
      ) cfgs;
    in
    {
      # Generate all system activation scripts at once
      system.activationScripts = lib.mkMerge activationScripts;

      # Generate all users at once
      users.users = lib.mkMerge users;

      # Generate all groups at once
      users.groups = lib.mkMerge groups;

      # Generate all tmpfile rules at once
      systemd.tmpfiles.rules = lib.concatLists tmpfilesRules;

      # Generate all containers at once
      virtualisation.oci-containers.containers = lib.mkMerge containers;

      # # Generate all SSL certificates at once
      security.acme.certs = lib.mkMerge sslCerts;

      # Generate all virtual hosts at once
      services.nginx.virtualHosts = lib.mkMerge virtualHosts;
    }
  );
}
