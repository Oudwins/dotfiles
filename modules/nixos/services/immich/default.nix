{ config, configLib, lib, pkgs, ... }:

let
  port = 2283; # default
  user = "immich";
  # TODO Update to immich v2. Means updating the flake. Its in unstable
in {

  imports = [
    # ./backup.nix
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  services.immich = {
    enable = true;
    inherit port;
    redis.enable = true;
    accelerationDevices = null; # let immich use any device for acceleration
    package = pkgs.unstable.immich;
  };

  users.users.immich.extraGroups =
    lib.mkIf config.my.hardwareAcceleration.enable
    config.my.hardwareAcceleration.groups;

  services.nginx.virtualHosts."${config.my.services.immich.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
        recommendedProxySettings = true;
        extraConfig = ''
          client_max_body_size 50000M;
          proxy_read_timeout   600s;
          proxy_send_timeout   600s;
          send_timeout         600s;
        '';

      };
    };

  my.dashboard.services.immich = {
    label = "Immich";
    description = "Photo and Video Manager";
    url =
      "https://${config.my.services.immich.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "immich";
  };
}
