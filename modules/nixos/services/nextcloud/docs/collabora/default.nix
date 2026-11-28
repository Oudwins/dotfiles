{
  config,
  lib,
  pkgs,
  ...
}:
{
  # collabora-online is built on libreoffice
  nixpkgs.config.permittedInsecurePackages = [ "libreoffice-25.04.9-4" ];

  # This configuration is based on the one described in this post: https://diogotc.com/blog/collabora-nextcloud-nixos/#deploy-collabora-with-nixos
  services.collabora-online = {
    enable = true;
    port = 9980; # default
    settings = {
      # Rely on reverse proxy for SSL
      ssl = {
        enable = false;
        termination = true;
      };

      # Listen on loopback interface only, and accept requests from ::1
      net = {
        listen = "loopback";
        post_allow.host = [ "::1" ];
      };

      # Restrict loading documents from WOPI Host nextcloud.example.com
      storage.wopi = {
        "@allow" = true;
        host = [
          # we use two nextcloud subdomains. So allow both.
          "${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}"
          "${config.my.services.nextcloud.subdomain}.${config.my.domain}"
        ];
      };

      # Set FQDN of server
      server_name = "collabora.${config.my.server.location}.${config.my.domain}";
    };
  };

  services.nginx.virtualHosts."collabora.${config.my.server.location}.${config.my.domain}" = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    addSSL = true;
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.collabora-online.port}";
      proxyWebsockets = true; # Enable if needed
    };
  };

  systemd.services.nextcloud-config-collabora =
    let
      inherit (config.services.nextcloud) occ;

      wopi_url = "http://[::1]:${toString config.services.collabora-online.port}";
      public_wopi_url = "https://collabora.${config.my.server.location}.${config.my.domain}";
      wopi_allowlist = lib.concatStringsSep "," [
        "127.0.0.1"
        "::1"
      ];
    in
    {
      wantedBy = [ "multi-user.target" ];
      after = [
        "nextcloud-setup.service"
        "coolwsd.service"
      ];
      requires = [ "coolwsd.service" ];
      script = ''
        ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_url --value ${lib.escapeShellArg wopi_url}
        ${occ}/bin/nextcloud-occ config:app:set richdocuments public_wopi_url --value ${lib.escapeShellArg public_wopi_url}
        ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist --value ${lib.escapeShellArg wopi_allowlist}
        ${occ}/bin/nextcloud-occ richdocuments:setup
      '';
      serviceConfig = {
        Type = "oneshot";
      };
    };

  networking.hosts = {
    "127.0.0.1" = [
      "${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}"
      "collabora.${config.my.server.location}.${config.my.domain}"
    ];
    "::1" = [
      "${config.my.services.nextcloud.subdomain}.${config.my.server.location}.${config.my.domain}"
      "collabora.${config.my.server.location}.${config.my.domain}"
    ];
  };
}
