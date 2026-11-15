{ config, pkgs, lib, ... }:
# ! Configure Dashboard
# Configure icons:
# - https://gethomepage.dev/configs/services/#icons
# From: 
# - https://selfh.st/icons/
let
  services = builtins.attrValues config.my.dashboard.services;
  servicesByCategory = lib.groupBy (service: service.category) services;
  port = 1111;
in {
  services.homepage-dashboard = {

    # These options were already present in my configuration.

    enable = config.my.dashboard.enable;
    listenPort = port;

    # package = pkgs.unstable.homepage-dashboard;

    # The following options were what I planned to add.

    # https://gethomepage.dev/latest/configs/settings/

    settings = {
      target = "_blank"; # Possible options include _blank, _self, and _top
      theme = "dark";
      color = "stone";
      # layout = {
      #   apps = {
      #     style = "row";
      #     columns = 4;
      #   };
      # };
    };

    # https://gethomepage.dev/latest/configs/bookmarks/

    # bookmarks = [ ];

    # https://gethomepage.dev/latest/configs/services/

    services = lib.mapAttrsToList (category: services: {
      ${category} = map (service: {
        ${service.label} = {
          description = service.description;
          href = service.url;
          icon = service.icon;
        };
      }) services;
    }) servicesByCategory;

    # https://gethomepage.dev/latest/configs/service-widgets/

    # widgets = [ ];

    # https://gethomepage.dev/latest/configs/kubernetes/

    # kubernetes = { };

    # https://gethomepage.dev/latest/configs/docker/

    # docker = { };

    # https://gethomepage.dev/latest/configs/custom-css-js/
    # customJS = "";
    # customCSS = "";
  };

  services.nginx.virtualHosts."${config.my.server.location}.${config.my.domain}" =
    {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
      };
    };

}
