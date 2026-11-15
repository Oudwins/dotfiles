{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:
let
  baseUrl = "https://${config.my.services.ntfy.subdomain}.${config.my.server.location}.${config.my.domain}";
  localHostDomain = "localhost:8111";
in
{
  # WARNING COULDN"T GET THIS TO WORK. MAYBE I CAN TAKE A LOOK AT THIS LATER: https://github.com/SebastianStork/nixos-config/blob/main/modules/system/services/ntfy.nix
  sops.secrets."ntfy/password" = {
    owner = "nginx";
  };
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = baseUrl;
      listen-http = "localhost:8111";
      behind-proxy = true;
      enable-login = true;
      auth-default-access = "read-write";
    };
  };

  services.nginx.virtualHosts."${baseUrl}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://${localHostDomain}";
      proxyWebsockets = true;
    };
  };

}
