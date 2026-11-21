# Serves this server's CLIProxyAPI to other machines at
# https://llmproxy.<location>.<domain>. The proxy itself stays on loopback;
# workstations point at it with
#   agents.llmproxy.address = "https://llmproxy.<location>.<domain>";
# The management API and panel are not exposed; use them over SSH.
{
  config,
  configLib,
  lib,
  ...
}:

let
  host = "${config.my.services.llmproxy.subdomain}.${config.my.server.location}.${config.my.domain}";
in
{
  imports = [
    (configLib.relativeToRoot "modules/shared/cli-proxy-api")
    (configLib.relativeToRoot "modules/nixos/services/nginx")
  ];

  services.cli-proxy-api = {
    enable = true;
    # Servers have no Stow tree, so use the tracked file directly.
    configFile = lib.mkDefault "${configLib.relativeToRoot "home-files/tmx/.cli-proxy-api/config.yaml"}";
    # The SOPS file is encrypted to the master key, which servers hold.
    sshKeyFile = lib.mkDefault config.my.networking.sshMasterKeyPath;
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.nginx.virtualHosts.${host} = {
    useACMEHost = "${config.my.server.location}.${config.my.domain}";
    forceSSL = true;
    # Agents resend the whole conversation on every turn.
    extraConfig = ''
      client_max_body_size 256m;
    '';
    locations = {
      "/" = {
        # Port from home-files/tmx/.cli-proxy-api/config.yaml.
        proxyPass = "http://127.0.0.1:8317";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
      "/management".return = "403";
      "/v0/management".return = "403";
      "/v8/management".return = "403";
      "/v0/resource/plugins/".return = "403";
    };
  };
}
