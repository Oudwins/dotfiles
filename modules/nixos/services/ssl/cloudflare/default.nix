{
  config,
  configLib,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];
  sops.secrets."cloudflare/cert_credentials" = {
    owner = "root";
  };
  # Docs
  # https://go-acme.github.io/lego/dns/cloudflare/
  security.acme = {
    acceptTerms = true;
    defaults.email = "${config.my.email}";
    certs."${config.my.server.location}.${config.my.domain}" = {
      domain = "${config.my.server.location}.${config.my.domain}";
      extraDomainNames = [ "*.${config.my.server.location}.${config.my.domain}" ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."cloudflare/cert_credentials".path;
      dnsPropagationCheck = true;
    };
  };
}
