{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

let
  port = 5984;
  user = "sofadb";
in
{

  imports = [
    ./backup.nix
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  services.couchdb = {
    enable = true;
    adminUser = user;
    adminPass = user;
    inherit port;
    extraConfig = {
      chttpd.enable_cors = true;
      cors = {
        origins = "http://localhost,https://localhost,capacitor://localhost,ionic://localhost";
        credentials = "true";
        methods = "GET, PUT, POST, HEAD, DELETE, OPTIONS";
        headers = "accept, authorization, content-type, origin, referer, x-requested-with, if-match, if-none-match";
        exposed_headers = "location, etag";
      };
      log.level = "info";
    };
  };

  services.nginx.virtualHosts."${config.my.services.couchdb.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      #enableACME = true;
      #forceSSL = true;
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
      };
    };

  my.dashboard.services.couchdb = {
    label = "CouchDB";
    description = "Database";
    url = "https://${config.my.services.couchdb.subdomain}.${config.my.server.location}.${config.my.domain}/_utils";
    category = "system";
    icon = "couchdb";
  };
}
