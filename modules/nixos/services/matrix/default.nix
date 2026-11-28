{ config, configLib, inputs, lib, pkgs, ... }:

let
  port = 6167;
  host = config.my.matrix.domain;
in
{
  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    (configLib.relativeToRoot "modules/nixos/services/dashboard")
    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
  ];

  options.my.matrix.domain = lib.mkOption {
    type = lib.types.str;
    default = "matrix.${config.my.server.location}.${config.my.domain}";
  };

  config = {
    nix.settings = {
      extra-substituters = [ "https://cache.tuwunel.chat" ];
      extra-trusted-public-keys = [
        "cache.tuwunel.chat-1:ZafUaXiRMozDa9N2SWim6EdzH0EEjWjwfvlTxXvcjLA="
      ];
    };

    sops.secrets."matrix/registration_token" = { };
    sops.templates."matrix-tuwunel.env" = {
      restartUnits = [ "tuwunel.service" ];
      content = ''
        TUWUNEL_REGISTRATION_TOKEN=${config.sops.placeholder."matrix/registration_token"}
      '';
    };

    services.matrix-tuwunel = {
      enable = true;
      package = inputs.tuwunel.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings.global = {
        address = [ "127.0.0.1" ];
        allow_registration = true;
        port = [ port ];
        server_name = host;
      };
    };

    systemd.services.tuwunel.serviceConfig.EnvironmentFile =
      config.sops.templates."matrix-tuwunel.env".path;

    services.nginx.virtualHosts."${host}" = {
      useACMEHost = host;
      addSSL = true;
      locations."/_matrix/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
    };

    security.acme.certs."${host}" = {
      domain = host;
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."cloudflare/cert_credentials".path;
    };

    my.dashboard.services.matrix = {
      label = "Matrix";
      description = "Matrix homeserver";
      url = "https://${host}";
      category = "apps";
      icon = "matrix";
    };
  };
}
