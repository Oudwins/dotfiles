# Shiori behind SSO: it logs in the account whose username is the Remote-User
# email nginx passes (accounts are not created automatically).
{ config, lib, ... }:

{
  imports = [ ../sso ];

  config = lib.mkIf (config.my.sso.enabledFor "shiori") {
    my.sso.proxy."${config.my.services.shiori.subdomain}.${config.my.server.location}.${config.my.domain}".service =
      "shiori";

    systemd.services.shiori.environment = {
      SHIORI_SSO_PROXY_AUTH_ENABLED = "true";
      SHIORI_SSO_PROXY_AUTH_TRUSTED = "127.0.0.1/32,::1/128";
    };
  };
}
