{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  user = "freshrss";
  # data -> "/var/lib/freshrss"
  domain = "${config.my.services.freshrss.subdomain}.${config.my.server.location}.${config.my.domain}";
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/containers")
  ];

  # Add extensions to freshRSS
  # https://discourse.nixos.org/t/how-can-i-add-extensions-to-freshrss-on-nixos/28971
  # TODO -> backups
  # https://freshrss.github.io/FreshRSS/en/admins/05_Backup.html
  # import & export feeds
  # https://freshrss.github.io/FreshRSS/en/users/04_Subscriptions.html#import-and-export
  # https://github.com/FreshRSS/FreshRSS/blob/edge/cli/README.md

  services.freshrss = {
    enable = true;
    inherit user;
    baseUrl = "https://${domain}";
    authType = "none";
    #defaultUser = config.my.username;
    # passwordFile = sops
    # database -> sqlite
    #webserver = "nginx"; # this is default
    virtualHost = domain;

  };

  services.nginx.virtualHosts."${domain}" = {
    #enableACME = true;
    #forceSSL = true;
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
  };

  # Full text RSS
  # https://github.com/fkie/fivefilters-full-text-rss-docker/tree/master
  # https://github.com/heussd/fivefilters-full-text-rss-docker
  # TODO -> backups of these feeds also!

  systemd.tmpfiles.rules =
    let
      user = "root";
      group = "root";
      dataDir = "${config.my.services.baseDataDir}/full-text-rss";
    in
    [
      #Type Path                      Mode UID     GID      Age Argument
      "d    ${dataDir}            0777 ${user} ${group} -   -"
    ];

  virtualisation.oci-containers.containers = {
    fullfeedrss = {
      image = "heussd/fivefilters-full-text-rss:latest";
      environment = {
        FTR_ADMIN_PASSWORD = ""; # empty for no password
      };
      volumes = [
        "${config.my.services.baseDataDir}/full-text-rss:/var/www/html/cache/rss"
      ];
      ports = [
        "48080:80"
      ];
    };
  };

  services.nginx.virtualHosts."${config.my.services.rssfeeds.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:48080";
        proxyWebsockets = true; # Enable if needed
      };
    };

  my.dashboard.services.freshrss = {
    label = "FreshRSS";
    description = "RSS reader";
    url = "https://${config.my.services.freshrss.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "freshrss";
  };
}
