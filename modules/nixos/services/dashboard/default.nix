# Server dashboard: Glance listing every my.dashboard.services entry, served at
# the server's location domain.
{ config, ... }:

let
  host = "${config.my.server.location}.${config.my.domain}";
in
{
  imports = [ ../../../shared/dashboard ];

  services.glance = {
    enable = true;
    settings = config.my.dashboard.settings // {
      server.port = 1111;
    };
  };

  services.nginx.virtualHosts.${host} = {
    useACMEHost = host;
    addSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.glance.settings.server.port}";
      proxyWebsockets = true;
    };
  };
}
