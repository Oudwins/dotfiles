{
  config,
  pkgs,
  ...
}@args:
let
  # 1. Bookmarks manager
  # 2. default username:password = shiori:gopher
  # 3. has extension that only works on firefox
  # 4. This is default deploy with sqlite db couldn't get postgres to work

  # decided to use sqlite instead
  #   # Construct the local PostgreSQL URL
  #   user = "shiori";

  port = 58181;

in
{
  imports = [
    ./backup.nix
    ./sso.nix
  ];

  # The host sets services.shiori.environmentFile to a sops env file with
  # SHIORI_HTTP_SECRET_KEY.
  services.shiori = {
    enable = true;
    inherit port;
  };

  # Set up SSL + Domain
  services.nginx.virtualHosts."${config.my.services.shiori.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString port}";
        proxyWebsockets = true; # Enable if needed
      };
    };

  my.dashboard.services.shiori = {
    label = "Shiori";
    description = "Bookmark manager";
    url = "https://${config.my.services.shiori.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "shiori";
  };
}
