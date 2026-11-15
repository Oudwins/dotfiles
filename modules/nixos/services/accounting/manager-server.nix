{ config, configLib, pkgs, lib, ... }:

let
  # Capture host's pkgs for use inside container
  hostPkgs = pkgs;
  # Container name based on host: facc for faker, tacc for tubby
  containerName = "${config.my.server.location}b";
  # These are ONLY used for the host<->container veth link created by
  # `privateNetwork = true;` (they are not "public" IPs).
  #
  # Why hardcode? It gives the host a stable address to reach the container
  # (e.g. for the host nginx reverse-proxy below), instead of a changing/dynamic
  # address.
  #
  # You can override these via `my.accounting.containerHostIP` and
  # `my.accounting.containerIP`.
  managerPort = 7979;
  baseDir = "/var/lib/manager-server";
  appDir = "${baseDir}/app";
  # Tailscale hostname for the container (used for certs)
  tailscaleHostname = containerName;
in {

  imports = [
    (configLib.relativeToRoot "modules/nixos/services/nginx")
    (configLib.relativeToRoot "modules/nixos/services/ssl/cloudflare")
    (configLib.relativeToRoot "modules/nixos/core/tailscale.nix")
  ];

  # Dedicated user on host for bind mount ownership
  users.users.manager = {
    isSystemUser = true;
    group = "manager";
    extraGroups = [ "wheel" ];
    home = baseDir;
    description = "Manager.io service user";
  };
  users.groups.manager = { };

  # Create data directories on the host for bind mount
  systemd.tmpfiles.rules = [
    "d ${baseDir} 750 manager manager -"
    "d ${appDir} 750 manager manager -"
  ];

  # Manager.io server
  systemd.services.manager-server = {
    description = "Manager.io Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "tailscaled.service" ];
    serviceConfig = {
      ExecStart =
        "${hostPkgs.manager-server}/bin/ManagerServer --urls http://*:${
          toString managerPort
        } --path ${appDir}";
      Restart = "always";
      RestartSec = 5;
      User = "manager";
      Group = "manager";
      WorkingDirectory = "/var/lib/manager-server";
    };
  };

  # Nginx proxy on the host to terminate SSL and forward to container
  services.nginx.virtualHosts."${config.my.services.manager.subdomain}.${config.my.server.location}.${config.my.domain}" =
    {
      useACMEHost = "${config.my.server.location}.${config.my.domain}";
      addSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString managerPort}";
        proxyWebsockets = true;
      };
    };

  # Dashboard entry
  my.dashboard.services.manager = {
    label = "Manager.io";
    description = "Accounting software";
    url =
      "https://${config.my.services.manager.subdomain}.${config.my.server.location}.${config.my.domain}";
    category = "apps";
    icon = "mdi-calculator";
  };
}
