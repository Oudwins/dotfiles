{
  config,
  configLib,
  pkgs,
  ...
}@args:
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];
  # THIS FILE ENSURES THAT WHATEVER INSTANCE OF NC RUNS ON THIS SERVER CAN BE ACCESSED FROM cloud.domain.com
  # It generates another certificate for that specific subdomain & proxies the requests using nginx to the localhost service (bit of a hack but it works)
  # Docs
  # https://go-acme.github.io/lego/dns/cloudflare/
  security.acme = {
    acceptTerms = true;
    defaults.email = "${config.my.email}";
    certs."${config.my.services.nextcloud.subdomain}.${config.my.domain}" = {
      domain = "${config.my.services.nextcloud.subdomain}.${config.my.domain}";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."cloudflare/cert_credentials".path;
      dnsPropagationCheck = true;
    };
  };

  # Warning this does NOT work with recommended proxy settings. If you need those enabled you should use the solution below which just redirects to the local domain
  services.nginx.virtualHosts."${config.my.services.nextcloud.subdomain}.${config.my.domain}" = {
    #enableACME = true;
    #forceSSL = true;
    useACMEHost = "${config.my.services.nextcloud.subdomain}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "https://${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}";
      proxyWebsockets = true;
    };
  };

  # services.nginx.virtualHosts."${config.my.services.nextcloud.subdomain}.${config.my.domain}" = {
  #   useACMEHost = "${config.my.services.nextcloud.subdomain}.${config.my.domain}";
  #   addSSL = true;
  #   # Simple redirect to the local domain
  #   locations."/" = {
  #     return = "301 https://${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}$request_uri";
  #   };
  # };
}
